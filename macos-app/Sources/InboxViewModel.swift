import AppKit
import Combine
import DraftInboxCore
import Foundation

struct CompletionBatch {
    let id = UUID()
    let items: [PendingItem]
}

@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var items: [PendingItem] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var notificationDraftPreviewEnabled = false
    @Published private(set) var completionPopoverEnabled = true
    @Published private(set) var newlyCompletedThreadIDs: Set<String> = []
    @Published private(set) var completionBatch: CompletionBatch?
    @Published private(set) var isRefreshing = false
    @Published private(set) var updateCheckState: UpdateCheckState = .idle
    @Published private(set) var isCheckingForUpdates = false

    private let repository: InboxRepository
    private let syncService: DraftSyncService?
    private let updateChecker: any UpdateChecking
    private let currentVersion: String
    private let defaults: UserDefaults
    private var timer: Timer?
    private var updateTimer: Timer?
    private var refreshCoordinator = RefreshCoordinator()
    private var completionDetector = CompletionDetector()
    private var completionHighlightGeneration = 0
    private let lastUpdateCheckKey = "CodexDraftInbox.lastUpdateCheckAt"
    private let availableUpdateTagKey = "CodexDraftInbox.availableUpdateTag"
    private let availableUpdateURLKey = "CodexDraftInbox.availableUpdateURL"

    init(
        repository: InboxRepository = .live,
        syncService: DraftSyncService? = .bundled,
        updateChecker: any UpdateChecking = GitHubUpdateChecker(),
        currentVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0",
        defaults: UserDefaults = .standard,
        startsPolling: Bool = true
    ) {
        self.repository = repository
        self.syncService = syncService
        self.updateChecker = updateChecker
        self.currentVersion = currentVersion
        self.defaults = defaults
        reload()
        loadSettings()
        loadCachedUpdate()
        checkForUpdatesIfNeeded()
        if startsPolling {
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.synchronize() }
            }
            updateTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkForUpdatesIfNeeded() }
            }
        }
    }

    deinit {
        timer?.invalidate()
        updateTimer?.invalidate()
    }

    func reload() {
        do {
            let loadedItems = try repository.load()
            let completedItems = completionDetector.detect(in: loadedItems)
            items = loadedItems
            if !completedItems.isEmpty {
                registerCompletion(completedItems)
            }
            errorMessage = nil
        } catch {
            errorMessage = "待办文件暂时无法读取"
        }
    }

    private func registerCompletion(_ completedItems: [PendingItem]) {
        completionHighlightGeneration += 1
        let generation = completionHighlightGeneration
        newlyCompletedThreadIDs.formUnion(completedItems.map(\.threadID))
        completionBatch = CompletionBatch(items: completedItems)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, self.completionHighlightGeneration == generation else { return }
            self.newlyCompletedThreadIDs.removeAll()
        }
    }

    func refresh() {
        isRefreshing = true
        synchronize(queueIfBusy: true, showProgress: true)
    }

    func checkForUpdates() {
        performUpdateCheck(manual: true)
    }

    func openAvailableUpdate() {
        guard case let .available(release) = updateCheckState else { return }
        if !NSWorkspace.shared.open(release.htmlURL) {
            errorMessage = "无法打开更新页面"
        }
    }

    private func checkForUpdatesIfNeeded() {
        let lastCheckedAt = defaults.object(forKey: lastUpdateCheckKey) as? Date
        guard AppReleaseSelector.shouldCheck(lastCheckedAt: lastCheckedAt) else { return }
        performUpdateCheck(manual: false)
    }

    private func loadCachedUpdate() {
        guard let tagName = defaults.string(forKey: availableUpdateTagKey),
              let rawURL = defaults.string(forKey: availableUpdateURLKey),
              let htmlURL = URL(string: rawURL) else {
            return
        }
        let release = AppRelease(tagName: tagName, htmlURL: htmlURL)
        if AppReleaseSelector.update(from: [release], currentVersion: currentVersion) != nil {
            updateCheckState = .available(release)
        } else {
            clearCachedUpdate()
        }
    }

    private func cacheAvailableUpdate(_ release: AppRelease?) {
        guard let release else {
            clearCachedUpdate()
            return
        }
        defaults.set(release.tagName, forKey: availableUpdateTagKey)
        defaults.set(release.htmlURL.absoluteString, forKey: availableUpdateURLKey)
    }

    private func clearCachedUpdate() {
        defaults.removeObject(forKey: availableUpdateTagKey)
        defaults.removeObject(forKey: availableUpdateURLKey)
    }

    private func performUpdateCheck(manual: Bool) {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        let updateChecker = self.updateChecker
        let currentVersion = self.currentVersion
        Task.detached {
            do {
                let releases = try await updateChecker.fetchReleases()
                let available = AppReleaseSelector.update(
                    from: releases,
                    currentVersion: currentVersion
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.defaults.set(Date(), forKey: self.lastUpdateCheckKey)
                    self.cacheAvailableUpdate(available)
                    self.isCheckingForUpdates = false
                    self.updateCheckState = available.map(UpdateCheckState.available)
                        ?? (manual ? .current(currentVersion) : .idle)
                }
            } catch {
                if manual {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.isCheckingForUpdates = false
                        if case .available = self.updateCheckState {
                            return
                        }
                        self.updateCheckState = .failed
                    }
                } else {
                    await MainActor.run { [weak self] in
                        self?.isCheckingForUpdates = false
                    }
                }
            }
        }
    }

    private func synchronize(queueIfBusy: Bool = false, showProgress: Bool = false) {
        guard refreshCoordinator.begin(queueIfBusy: queueIfBusy) else {
            return
        }
        guard let syncService else {
            _ = refreshCoordinator.finish()
            isRefreshing = false
            reload()
            return
        }
        if showProgress {
            isRefreshing = true
        }
        Task.detached {
            let syncFailed: Bool
            do {
                try syncService.synchronize()
                syncFailed = false
            } catch {
                syncFailed = true
            }
            await MainActor.run { [weak self] in
                let shouldRefreshAgain = self?.refreshCoordinator.finish() == true
                self?.reload()
                if syncFailed {
                    self?.errorMessage = "同步失败，当前显示的是上次保存的待办"
                }
                if shouldRefreshAgain {
                    self?.synchronize(showProgress: true)
                } else {
                    self?.isRefreshing = false
                }
            }
        }
    }

    private func loadSettings() {
        guard let syncService else {
            synchronize()
            return
        }
        Task.detached {
            let settings = (try? syncService.settings())
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.notificationDraftPreviewEnabled = settings?.notificationDraftPreviewEnabled ?? false
                self.completionPopoverEnabled = settings?.completionPopoverEnabled ?? true
                self.synchronize()
            }
        }
    }

    func setNotificationDraftPreview(enabled: Bool) {
        guard let syncService else { return }
        Task.detached {
            do {
                try syncService.setNotificationDraftPreview(enabled: enabled)
                await MainActor.run { [weak self] in
                    self?.notificationDraftPreviewEnabled = enabled
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "通知隐私设置保存失败"
                }
            }
        }
    }

    func setCompletionPopover(enabled: Bool) {
        guard let syncService else { return }
        Task.detached {
            do {
                try syncService.setCompletionPopover(enabled: enabled)
                await MainActor.run { [weak self] in
                    self?.completionPopoverEnabled = enabled
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "完成提醒设置保存失败"
                }
            }
        }
    }

    @discardableResult
    func openTask(_ item: PendingItem) -> Bool {
        if item.source == "claude" {
            let opened = openClaudeSession(item)
            if opened {
                markRead(item)
            }
            return opened
        }
        guard let url = URL(string: "codex://threads/\(item.threadID)") else {
            errorMessage = "任务链接无效"
            return false
        }
        if NSWorkspace.shared.open(url) {
            refreshCodexReadStateSoon()
            return true
        } else {
            errorMessage = "Codex 没有接受任务链接"
            return false
        }
    }

    private func markRead(_ item: PendingItem) {
        guard item.source == "claude", item.isCompletionUnread, let syncService else { return }
        Task.detached {
            do {
                try syncService.markRead(threadID: item.threadID)
                await MainActor.run { [weak self] in self?.reload() }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "未读状态更新失败"
                }
            }
        }
    }

    private func refreshCodexReadStateSoon() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            self?.synchronize()
        }
    }

    func saveClaudeDraft(_ item: PendingItem, text: String) {
        guard let syncService else { return }
        Task.detached {
            do {
                try syncService.saveClaudeDraft(threadID: item.threadID, text: text)
                await MainActor.run { [weak self] in self?.reload() }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Claude 草稿保存失败"
                }
            }
        }
    }

    private func openClaudeSession(_ item: PendingItem) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        if item.status == "running" {
            process.arguments = ["-e", "tell application \"Terminal\" to activate"]
        } else {
            guard let sessionID = item.externalSessionID, !sessionID.isEmpty else {
                errorMessage = "缺少 Claude session ID"
                return false
            }
            let cwd = item.cwd?.isEmpty == false ? item.cwd! : FileManager.default.homeDirectoryForCurrentUser.path
            let command = "cd \(shellQuote(cwd)) && if command -v claude >/dev/null 2>&1; then claude --resume \(shellQuote(sessionID)); else echo '未找到 claude，请先安装 Claude Code 或检查 PATH'; fi"
            let script = "tell application \"Terminal\" to do script \(appleScriptQuote(command))\ntell application \"Terminal\" to activate"
            process.arguments = ["-e", script]
        }
        do {
            try process.run()
            return true
        } catch {
            errorMessage = "无法打开 Claude Code 会话"
            return false
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptQuote(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    func markHandled(_ item: PendingItem) {
        if let syncService {
            Task.detached {
                do {
                    try syncService.markHandled(threadID: item.threadID)
                    await MainActor.run { [weak self] in self?.reload() }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.errorMessage = "标记失败，请稍后再试"
                    }
                }
            }
            return
        }
        do {
            try repository.markHandled(threadID: item.threadID)
            reload()
        } catch {
            errorMessage = "标记失败，请稍后再试"
        }
    }
}
