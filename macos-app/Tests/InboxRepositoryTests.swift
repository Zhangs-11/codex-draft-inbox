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
            try manualRefreshQueuesBehindBackgroundSync()
            try selectsNewestPreviewRelease()
            try ignoresDraftAndOlderReleases()
            try comparesMultiDigitVersions()
            try checksForUpdatesOncePerDay()
            try decodesGitHubReleaseResponse()
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

    private static func manualRefreshQueuesBehindBackgroundSync() throws {
        var coordinator = RefreshCoordinator()

        try expect(coordinator.begin(queueIfBusy: false), "后台同步没有开始")
        try expect(!coordinator.begin(queueIfBusy: true), "手动刷新绕过了正在运行的同步")
        try expect(coordinator.finish(), "手动刷新没有排队")
        try expect(coordinator.begin(queueIfBusy: false), "排队的手动刷新没有补跑")
        try expect(!coordinator.finish(), "手动刷新被重复排队")
    }

    private static func selectsNewestPreviewRelease() throws {
        let releases = [
            release("v0.2.2"),
            release("v0.2.3", prerelease: true),
        ]

        let update = AppReleaseSelector.update(from: releases, currentVersion: "0.2.2")

        try expect(update?.tagName == "v0.2.3", "预发布版本没有被更新检查发现")
    }

    private static func ignoresDraftAndOlderReleases() throws {
        let releases = [
            release("v0.3.0", draft: true),
            release("not-a-version"),
            release("v0.2.2"),
        ]

        let update = AppReleaseSelector.update(from: releases, currentVersion: "0.2.2")

        try expect(update == nil, "草稿、非法或相同版本被误报为更新")
    }

    private static func comparesMultiDigitVersions() throws {
        try expect(AppVersion("0.10.0")! > AppVersion("0.9.9")!, "版本号被按字符串错误比较")
        try expect(AppVersion("v1.2")! == AppVersion("1.2.0")!, "省略的补丁版本没有按 0 处理")
    }

    private static func checksForUpdatesOncePerDay() throws {
        let now = Date(timeIntervalSince1970: 100_000)
        try expect(
            !AppReleaseSelector.shouldCheck(lastCheckedAt: now.addingTimeInterval(-23 * 60 * 60), now: now),
            "24 小时内重复触发了自动检查"
        )
        try expect(
            AppReleaseSelector.shouldCheck(lastCheckedAt: now.addingTimeInterval(-25 * 60 * 60), now: now),
            "超过 24 小时没有触发自动检查"
        )
    }

    private static func decodesGitHubReleaseResponse() throws {
        let json = """
        [{"tag_name":"v0.2.3","html_url":"https://github.com/example/releases/v0.2.3","draft":false,"prerelease":true}]
        """

        let releases = try JSONDecoder().decode([AppRelease].self, from: Data(json.utf8))

        try expect(releases.first?.displayVersion == "0.2.3", "GitHub Release 响应解析失败")
        try expect(releases.first?.prerelease == true, "预发布标记解析失败")
    }

    private static func release(
        _ tagName: String,
        draft: Bool = false,
        prerelease: Bool = false
    ) -> AppRelease {
        AppRelease(
            tagName: tagName,
            htmlURL: URL(string: "https://example.com/\(tagName)")!,
            draft: draft,
            prerelease: prerelease
        )
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
