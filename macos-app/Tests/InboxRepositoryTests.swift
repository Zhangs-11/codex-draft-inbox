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
            try completionDetectorIgnoresInitialSnapshot()
            try completionDetectorEmitsRunningTransitionOnlyOnce()
            try completionDetectorCatchesFastNewCompletion()
            try completionDetectorCatchesNewTurnAfterPreviousCompletion()
            try completionDetectorIgnoresDraftChangesAfterCompletion()
            try completionDetectorIgnoresSyntheticGenerationRecovery()
            try completionUnreadRequiresCompletedStatus()
            try successfulTaskOpenDismissesPopover()
            try failedTaskOpenKeepsPopoverVisible()
            try resolvesConfiguredAndSystemLanguages()
            try providesCompleteChineseAndEnglishCopy()
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

    private static func completionDetectorIgnoresInitialSnapshot() throws {
        var detector = CompletionDetector()
        let completed = item(
            id: "already-completed",
            completedAt: "2026-08-19T09:00:00Z",
            status: "completed"
        )

        try expect(detector.detect(in: [completed]).isEmpty, "启动时把历史完成任务误报为新完成")
    }

    private static func completionDetectorEmitsRunningTransitionOnlyOnce() throws {
        var detector = CompletionDetector()
        let running = item(
            id: "thread-1",
            completedAt: "2026-08-19T09:00:00Z",
            status: "running"
        )
        let completed = item(
            id: "thread-1",
            completedAt: "2026-08-19T09:00:00Z",
            lastActivityAt: "2026-08-19T10:00:00Z",
            status: "completed"
        )
        _ = detector.detect(in: [running])

        try expect(
            detector.detect(in: [completed]).map(\.threadID) == ["thread-1"],
            "执行中变为已完成时没有产生完成事件"
        )
        try expect(detector.detect(in: [completed]).isEmpty, "同一个完成状态被重复提醒")
    }

    private static func completionDetectorCatchesFastNewCompletion() throws {
        var detector = CompletionDetector()
        _ = detector.detect(in: [])
        let completed = item(
            id: "fast-task",
            completedAt: "2026-08-19T09:00:00Z",
            status: "completed"
        )

        try expect(
            detector.detect(in: [completed]).map(\.threadID) == ["fast-task"],
            "轮询间隔内快速完成的新任务没有产生完成事件"
        )
    }

    private static func completionDetectorCatchesNewTurnAfterPreviousCompletion() throws {
        var detector = CompletionDetector()
        let first = item(
            id: "same-thread",
            completedAt: "2026-08-19T09:00:00Z",
            status: "completed",
            observationToken: "turn:turn-1:draft:first"
        )
        let second = item(
            id: "same-thread",
            completedAt: "2026-08-19T09:00:00Z",
            lastActivityAt: "2026-08-19T10:00:00Z",
            status: "completed",
            observationToken: "turn:turn-2:draft:second"
        )
        _ = detector.detect(in: [first])

        try expect(
            detector.detect(in: [second]).map(\.threadID) == ["same-thread"],
            "同一任务在轮询间隔内完成新 Turn 时没有产生完成事件"
        )
    }

    private static func completionDetectorIgnoresDraftChangesAfterCompletion() throws {
        var detector = CompletionDetector()
        let original = item(
            id: "same-turn",
            completedAt: "2026-08-19T09:00:00Z",
            status: "completed",
            observationToken: "turn:turn-1:draft:first"
        )
        let editedDraft = item(
            id: "same-turn",
            completedAt: "2026-08-19T09:00:00Z",
            status: "completed",
            observationToken: "turn:turn-1:draft:second"
        )
        _ = detector.detect(in: [original])

        try expect(
            detector.detect(in: [editedDraft]).isEmpty,
            "已完成任务只修改草稿时被误报为新完成"
        )
    }

    private static func completionDetectorIgnoresSyntheticGenerationRecovery() throws {
        var detector = CompletionDetector()
        let actual = item(
            id: "temporary-rollout-gap",
            completedAt: "2026-08-19T09:00:00Z",
            status: "completed",
            observationToken: "turn:turn-1:draft:first"
        )
        let fallback = item(
            id: "temporary-rollout-gap",
            completedAt: "2026-08-19T09:00:00Z",
            status: "completed",
            observationToken: "turn:unread:draft:first"
        )
        _ = detector.detect(in: [actual])

        try expect(
            detector.detect(in: [fallback]).isEmpty,
            "rollout 暂时不可读时使用未读兜底被误报为新完成"
        )
        try expect(
            detector.detect(in: [actual]).isEmpty,
            "rollout 恢复后同一 Turn 被误报为新完成"
        )
    }

    private static func completionUnreadRequiresCompletedStatus() throws {
        let running = item(
            id: "running-unread",
            completedAt: "2026-08-19T09:00:00Z",
            status: "running",
            completionUnread: true
        )
        let completed = item(
            id: "completed-unread",
            completedAt: "2026-08-19T09:00:00Z",
            status: "completed",
            completionUnread: true
        )

        try expect(!running.isCompletionUnread, "执行中的任务被显示为已完成未读")
        try expect(completed.isCompletionUnread, "已完成未读标识没有生效")
    }

    private static func successfulTaskOpenDismissesPopover() throws {
        var dismissCount = 0

        let opened = TaskOpenCoordinator.perform(
            open: { true },
            dismiss: { dismissCount += 1 }
        )

        try expect(opened, "成功打开任务却返回失败")
        try expect(dismissCount == 1, "成功打开任务后没有关闭弹窗")
    }

    private static func failedTaskOpenKeepsPopoverVisible() throws {
        var dismissCount = 0

        let opened = TaskOpenCoordinator.perform(
            open: { false },
            dismiss: { dismissCount += 1 }
        )

        try expect(!opened, "打开失败却返回成功")
        try expect(dismissCount == 0, "打开失败时错误关闭了弹窗")
    }

    private static func resolvesConfiguredAndSystemLanguages() throws {
        try expect(
            AppLanguage.system.resolved(preferredLanguages: ["zh-Hans-CN"]) == .simplifiedChinese,
            "中文系统没有解析为简体中文"
        )
        try expect(
            AppLanguage.system.resolved(preferredLanguages: ["en-US"]) == .english,
            "英文系统没有解析为英文"
        )
        try expect(
            AppLanguage.system.resolved(preferredLanguages: ["ja-JP"]) == .english,
            "其他系统语言没有回退为英文"
        )
        try expect(
            AppLanguage.simplifiedChinese.resolved(preferredLanguages: ["en-US"]) == .simplifiedChinese,
            "手动选择中文后仍然跟随系统"
        )
    }

    private static func providesCompleteChineseAndEnglishCopy() throws {
        let chinese = AppStrings(language: .simplifiedChinese)
        let english = AppStrings(language: .english)

        for key in AppTextKey.allCases {
            try expect(chinese.hasTranslation(for: key), "中文文案缺失：\(key)")
            try expect(english.hasTranslation(for: key), "英文文案缺失：\(key)")
        }
        try expect(chinese[.inboxTitle] == "会话待办", "中文标题不正确")
        try expect(english[.inboxTitle] == "Conversation Inbox", "英文标题不正确")
        try expect(english[.openTask] == "Open task", "英文操作文案不正确")
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

    private static func item(
        id: String,
        completedAt: String,
        lastActivityAt: String? = nil,
        status: String? = nil,
        observationToken: String? = nil,
        completionUnread: Bool? = nil
    ) -> PendingItem {
        PendingItem(
            threadID: id,
            title: "任务 \(id)",
            draft: "继续处理 \(id)",
            draftKey: "local:\(id)",
            completedAt: completedAt,
            lastActivityAt: lastActivityAt,
            status: status,
            observationToken: observationToken,
            completionUnread: completionUnread
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
