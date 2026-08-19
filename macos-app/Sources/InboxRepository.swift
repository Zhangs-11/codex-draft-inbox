import Darwin
import Foundation

public struct InboxRepository {
    public let stateURL: URL

    public init(stateURL: URL) {
        self.stateURL = stateURL
    }

    public static var live: InboxRepository {
        let environment = ProcessInfo.processInfo.environment
        let home = environment["CODEX_HOME"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return InboxRepository(
            stateURL: home
                .appendingPathComponent("draft-inbox", isDirectory: true)
                .appendingPathComponent("pending.json")
        )
    }

    public func load() throws -> [PendingItem] {
        let inbox = try loadFile()
        return inbox.items.values.sorted { $0.completedAt > $1.completedAt }
    }

    public func markHandled(threadID: String) throws {
        try withExclusiveLock {
            var inbox = try loadFile()
            guard inbox.items.removeValue(forKey: threadID) != nil else { return }
            try write(inbox)
        }
    }

    private func loadFile() throws -> PendingInbox {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: stateURL)
        return try JSONDecoder().decode(PendingInbox.self, from: data)
    }

    private func write(_ inbox: PendingInbox) throws {
        let directory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(inbox)
        data.append(0x0A)

        let temporaryURL = directory.appendingPathComponent("pending.\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: .atomic)
        guard Darwin.rename(temporaryURL.path, stateURL.path) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: temporaryURL)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    private func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        let directory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = URL(fileURLWithPath: stateURL.path + ".lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.lockf(descriptor, F_ULOCK, 0) }
        return try operation()
    }
}
