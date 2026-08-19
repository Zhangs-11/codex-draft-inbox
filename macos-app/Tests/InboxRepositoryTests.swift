import DraftInboxCore
import Darwin
import Foundation

@main
struct InboxRepositorySelfTests {
    static func main() {
        do {
            try loadsNewestItemsFirst()
            try loadsLegacyItemsWithoutActivityTimestamp()
            try markHandledRemovesOnlySelectedItem()
            try missingStateIsEmpty()
            print("CodexDraftInbox self-test passed")
        } catch {
            fputs("CodexDraftInbox self-test failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func loadsNewestItemsFirst() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stateURL = directory.appendingPathComponent("pending.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let inbox = PendingInbox(
            version: 1,
            items: [
                "older": item(id: "older", completedAt: "2026-08-19T09:00:00Z"),
                "newer": item(
                    id: "newer",
                    completedAt: "2026-08-19T08:00:00Z",
                    lastActivityAt: "2026-08-19T10:00:00Z"
                ),
            ]
        )
        try JSONEncoder().encode(inbox).write(to: stateURL)

        let items = try InboxRepository(stateURL: stateURL).load()

        try expect(items.map(\.threadID) == ["newer", "older"], "待办没有按最近活动时间倒序排列")
    }

    private static func loadsLegacyItemsWithoutActivityTimestamp() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stateURL = directory.appendingPathComponent("pending.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = """
        {"version":1,"items":{"legacy":{"thread_id":"legacy","title":"旧待办","draft":"","completed_at":"2026-08-19T09:00:00Z"}}}
        """
        try Data(legacy.utf8).write(to: stateURL)

        let items = try InboxRepository(stateURL: stateURL).load()

        try expect(items.first?.threadID == "legacy", "旧版待办状态无法兼容读取")
    }

    private static func markHandledRemovesOnlySelectedItem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stateURL = directory.appendingPathComponent("pending.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let inbox = PendingInbox(
            version: 1,
            items: [
                "keep": item(id: "keep", completedAt: "2026-08-19T09:00:00Z"),
                "remove": item(id: "remove", completedAt: "2026-08-19T10:00:00Z"),
            ]
        )
        try JSONEncoder().encode(inbox).write(to: stateURL)
        let repository = InboxRepository(stateURL: stateURL)

        try repository.markHandled(threadID: "remove")

        try expect(try repository.load().map(\.threadID) == ["keep"], "标记已处理删除了错误的待办")
    }

    private static func missingStateIsEmpty() throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("pending.json")

        try expect(try InboxRepository(stateURL: stateURL).load() == [], "缺失状态文件时没有返回空列表")
    }

    private static func item(id: String, completedAt: String, lastActivityAt: String? = nil) -> PendingItem {
        PendingItem(
            threadID: id,
            title: "任务 \(id)",
            draft: "继续处理 \(id)",
            draftKey: "local:\(id)",
            completedAt: completedAt,
            lastActivityAt: lastActivityAt
        )
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else {
            throw SelfTestError.failed(message)
        }
    }

    private enum SelfTestError: Error {
        case failed(String)
    }
}
