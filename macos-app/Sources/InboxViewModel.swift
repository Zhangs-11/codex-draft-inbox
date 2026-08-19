import AppKit
import Combine
import DraftInboxCore
import Foundation

@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var items: [PendingItem] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var notificationDraftPreviewEnabled = false

    private let repository: InboxRepository
    private let syncService: DraftSyncService?
    private var timer: Timer?
    private var syncInFlight = false

    init(
        repository: InboxRepository = .live,
        syncService: DraftSyncService? = .bundled,
        startsPolling: Bool = true
    ) {
        self.repository = repository
        self.syncService = syncService
        reload()
        synchronize()
        loadSettings()
        if startsPolling {
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.synchronize() }
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func reload() {
        do {
            items = try repository.load()
            errorMessage = nil
        } catch {
            errorMessage = "待办文件暂时无法读取"
        }
    }

    func refresh() {
        synchronize()
    }

    private func synchronize() {
        guard !syncInFlight, let syncService else {
            reload()
            return
        }
        syncInFlight = true
        Task.detached {
            let syncFailed: Bool
            do {
                try syncService.synchronize()
                syncFailed = false
            } catch {
                syncFailed = true
            }
            await MainActor.run { [weak self] in
                self?.syncInFlight = false
                self?.reload()
                if syncFailed {
                    self?.errorMessage = "同步失败，当前显示的是上次保存的待办"
                }
            }
        }
    }

    private func loadSettings() {
        guard let syncService else { return }
        Task.detached {
            let enabled = (try? syncService.notificationDraftPreviewEnabled()) ?? false
            await MainActor.run { [weak self] in
                self?.notificationDraftPreviewEnabled = enabled
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

    func openTask(_ item: PendingItem) {
        if item.source == "claude" {
            openClaudeSession(item)
            return
        }
        guard let url = URL(string: "codex://threads/\(item.threadID)") else {
            errorMessage = "任务链接无效"
            return
        }
        if !NSWorkspace.shared.open(url) {
            errorMessage = "Codex 没有接受任务链接"
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

    private func openClaudeSession(_ item: PendingItem) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        if item.status == "running" {
            process.arguments = ["-e", "tell application \"Terminal\" to activate"]
        } else {
            guard let sessionID = item.externalSessionID, !sessionID.isEmpty else {
                errorMessage = "缺少 Claude session ID"
                return
            }
            let cwd = item.cwd?.isEmpty == false ? item.cwd! : FileManager.default.homeDirectoryForCurrentUser.path
            let command = "cd \(shellQuote(cwd)) && if command -v claude >/dev/null 2>&1; then claude --resume \(shellQuote(sessionID)); else echo '未找到 claude，请先安装 Claude Code 或检查 PATH'; fi"
            let script = "tell application \"Terminal\" to do script \(appleScriptQuote(command))\ntell application \"Terminal\" to activate"
            process.arguments = ["-e", script]
        }
        do {
            try process.run()
        } catch {
            errorMessage = "无法打开 Claude Code 会话"
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
