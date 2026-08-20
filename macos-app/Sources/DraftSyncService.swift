import DraftInboxCore
import Foundation

struct InboxSettings {
    let notificationDraftPreviewEnabled: Bool
    let completionPopoverEnabled: Bool
    let language: AppLanguage
}

struct DraftSyncService {
    let scriptURL: URL

    static var bundled: DraftSyncService? {
        guard let url = Bundle.main.url(forResource: "draft_inbox", withExtension: "py") else {
            return nil
        }
        return DraftSyncService(scriptURL: url)
    }

    func synchronize() throws {
        _ = try run(arguments: ["sync"])
    }

    func markHandled(threadID: String) throws {
        _ = try run(arguments: ["clear", "--thread-id", threadID, "--manual"])
    }

    func markRead(threadID: String) throws {
        _ = try run(arguments: ["mark-read", "--thread-id", threadID])
    }

    func saveClaudeDraft(threadID: String, text: String) throws {
        _ = try run(arguments: ["set-claude-draft", "--thread-id", threadID, "--text", text])
    }

    func settings() throws -> InboxSettings {
        let data = try run(arguments: ["settings", "--json"])
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return InboxSettings(
            notificationDraftPreviewEnabled: payload?["show_notification_draft_preview"] as? Bool ?? false,
            completionPopoverEnabled: payload?["show_completion_popover"] as? Bool ?? true,
            language: AppLanguage(rawValue: payload?["language"] as? String ?? "") ?? .system
        )
    }

    func setNotificationDraftPreview(enabled: Bool) throws {
        _ = try run(arguments: ["set-notification-preview", "--enabled", enabled ? "true" : "false"])
    }

    func setCompletionPopover(enabled: Bool) throws {
        _ = try run(arguments: ["set-completion-popover", "--enabled", enabled ? "true" : "false"])
    }

    func setLanguage(_ language: AppLanguage) throws {
        _ = try run(arguments: ["set-language", "--language", language.rawValue])
    }

    private func run(arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path] + arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let messageData = errors.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: messageData, encoding: .utf8) ?? ""
            throw SyncError.failed(process.terminationStatus, message)
        }
        return outputData
    }

    private enum SyncError: Error {
        case failed(Int32, String)
    }
}
