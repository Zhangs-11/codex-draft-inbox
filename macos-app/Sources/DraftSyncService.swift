import Foundation

struct DraftSyncService {
    let scriptURL: URL

    static var bundled: DraftSyncService? {
        guard let url = Bundle.main.url(forResource: "draft_inbox", withExtension: "py") else {
            return nil
        }
        return DraftSyncService(scriptURL: url)
    }

    func synchronize() throws {
        try run(arguments: ["sync"])
    }

    func markHandled(threadID: String) throws {
        try run(arguments: ["clear", "--thread-id", threadID, "--manual"])
    }

    func saveClaudeDraft(threadID: String, text: String) throws {
        try run(arguments: ["set-claude-draft", "--thread-id", threadID, "--text", text])
    }

    private func run(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SyncError.failed(process.terminationStatus)
        }
    }

    private enum SyncError: Error {
        case failed(Int32)
    }
}
