import AppKit
import Combine
import DraftInboxCore
import Foundation

@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var items: [PendingItem] = []
    @Published private(set) var errorMessage: String?

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
        if startsPolling {
            timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
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

    private func synchronize() {
        guard !syncInFlight, let syncService else {
            reload()
            return
        }
        syncInFlight = true
        Task.detached {
            try? syncService.synchronize()
            await MainActor.run { [weak self] in
                self?.syncInFlight = false
                self?.reload()
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
            let claude = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/claude").path
            let command = "cd \(shellQuote(cwd)) && \(shellQuote(claude)) --resume \(shellQuote(sessionID))"
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
                try? syncService.markHandled(threadID: item.threadID)
                await MainActor.run { [weak self] in self?.reload() }
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
