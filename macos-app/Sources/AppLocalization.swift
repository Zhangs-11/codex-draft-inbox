import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        let preferred = preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

public enum AppTextKey: String, CaseIterable {
    case inboxTitle
    case noPendingTasks
    case pendingTasks
    case refresh
    case refreshing
    case allHandled
    case emptyDescription
    case storedLocally
    case checkUpdates
    case startsAtLogin
    case quit
    case updateAvailable
    case updateDetails
    case openUpdate
    case latestVersion
    case updateCheckFailed
    case autoOpenOnCompletion
    case autoOpenDescription
    case showDraftInNotifications
    case showDraftDescription
    case language
    case followSystem
    case simplifiedChinese
    case english
    case unread
    case unreadAccessibility
    case justCompleted
    case noDraft
    case handled
    case now
    case statusRunning
    case statusDraft
    case statusFailed
    case statusAborted
    case statusCompleted
    case conversationDeleted
    case conversationUnavailable
    case openTask
    case openTerminal
    case resumeConversation
    case lifecycleArchived
    case lifecycleDeleted
    case lifecycleUnavailable
    case lifecycleUnknown
    case claudeDraftPlaceholder
    case save
    case menuTooltip
    case previewTitle
    case inboxReadError
    case updateOpenError
    case syncError
    case notificationSettingsError
    case completionSettingsError
    case languageSettingsError
    case taskLinkError
    case codexOpenError
    case unreadUpdateError
    case claudeDraftSaveError
    case missingClaudeSessionError
    case claudeNotFound
    case claudeOpenError
    case markHandledError
}

public struct AppStrings {
    public let language: AppLanguage

    public init(
        language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.language = language.resolved(preferredLanguages: preferredLanguages)
    }

    public subscript(key: AppTextKey) -> String {
        let values = language == .simplifiedChinese ? Self.chinese : Self.english
        return values[key] ?? key.rawValue
    }

    public func hasTranslation(for key: AppTextKey) -> Bool {
        let values = language == .simplifiedChinese ? Self.chinese : Self.english
        return values[key]?.isEmpty == false
    }

    public var localeIdentifier: String {
        language == .simplifiedChinese ? "zh_CN" : "en_US"
    }

    private static let chinese: [AppTextKey: String] = [
        .inboxTitle: "会话待办",
        .noPendingTasks: "没有等待你处理的任务",
        .pendingTasks: "进行中，或等待你处理",
        .refresh: "刷新",
        .refreshing: "刷新中",
        .allHandled: "都处理完了",
        .emptyDescription: "任务启动后会出现在这里。\n只有点“已处理”才会移除。",
        .storedLocally: "本机保存",
        .checkUpdates: "检查更新",
        .startsAtLogin: "登录自动启动",
        .quit: "退出",
        .updateAvailable: "菜单栏 App 有新版本",
        .updateDetails: "前往 GitHub 查看说明并下载",
        .openUpdate: "前往更新",
        .latestVersion: "已是最新版本",
        .updateCheckFailed: "检查更新失败，请稍后再试",
        .autoOpenOnCompletion: "完成时自动展开",
        .autoOpenDescription: "新完成任务会置顶并短暂高亮",
        .showDraftInNotifications: "通知显示草稿",
        .showDraftDescription: "关闭时锁屏通知只显示待办提醒",
        .language: "语言",
        .followSystem: "跟随系统",
        .simplifiedChinese: "简体中文",
        .english: "English",
        .unread: "未读",
        .unreadAccessibility: "已完成但未读",
        .justCompleted: "刚刚完成",
        .noDraft: "暂无草稿，等待你处理",
        .handled: "已处理",
        .now: "刚刚",
        .statusRunning: "执行中",
        .statusDraft: "有草稿",
        .statusFailed: "执行失败",
        .statusAborted: "已中止",
        .statusCompleted: "已完成",
        .conversationDeleted: "会话已删除",
        .conversationUnavailable: "会话不可见",
        .openTask: "打开任务",
        .openTerminal: "打开终端",
        .resumeConversation: "恢复会话",
        .lifecycleArchived: "已归档",
        .lifecycleDeleted: "已删除",
        .lifecycleUnavailable: "不可见",
        .lifecycleUnknown: "状态未知",
        .claudeDraftPlaceholder: "写下准备发给 Claude 的下一句话",
        .save: "保存",
        .menuTooltip: "Codex / Claude 会话待办",
        .previewTitle: "Codex 草稿待办 · 验收预览",
        .inboxReadError: "待办文件暂时无法读取",
        .updateOpenError: "无法打开更新页面",
        .syncError: "同步失败，当前显示的是上次保存的待办",
        .notificationSettingsError: "通知隐私设置保存失败",
        .completionSettingsError: "完成提醒设置保存失败",
        .languageSettingsError: "语言设置保存失败",
        .taskLinkError: "任务链接无效",
        .codexOpenError: "Codex 没有接受任务链接",
        .unreadUpdateError: "未读状态更新失败",
        .claudeDraftSaveError: "Claude 草稿保存失败",
        .missingClaudeSessionError: "缺少 Claude session ID",
        .claudeNotFound: "未找到 claude，请先安装 Claude Code 或检查 PATH",
        .claudeOpenError: "无法打开 Claude Code 会话",
        .markHandledError: "标记失败，请稍后再试",
    ]

    private static let english: [AppTextKey: String] = [
        .inboxTitle: "Conversation Inbox",
        .noPendingTasks: "No tasks are waiting for you",
        .pendingTasks: "Running or waiting for you",
        .refresh: "Refresh",
        .refreshing: "Refreshing",
        .allHandled: "All caught up",
        .emptyDescription: "Tasks appear here after they start.\nOnly “Handled” removes them.",
        .storedLocally: "Stored locally",
        .checkUpdates: "Check for updates",
        .startsAtLogin: "Starts at login",
        .quit: "Quit",
        .updateAvailable: "A new menu bar app version is available",
        .updateDetails: "View release notes and download on GitHub",
        .openUpdate: "View update",
        .latestVersion: "Latest version",
        .updateCheckFailed: "Update check failed. Try again later.",
        .autoOpenOnCompletion: "Show on completion",
        .autoOpenDescription: "New completions move to the top and briefly highlight",
        .showDraftInNotifications: "Show drafts in notifications",
        .showDraftDescription: "When off, lock-screen notifications hide draft text",
        .language: "Language",
        .followSystem: "Follow system",
        .simplifiedChinese: "Simplified Chinese",
        .english: "English",
        .unread: "Unread",
        .unreadAccessibility: "Completed and unread",
        .justCompleted: "Just completed",
        .noDraft: "No draft yet. Waiting for you.",
        .handled: "Handled",
        .now: "Now",
        .statusRunning: "Running",
        .statusDraft: "Draft saved",
        .statusFailed: "Failed",
        .statusAborted: "Aborted",
        .statusCompleted: "Completed",
        .conversationDeleted: "Conversation deleted",
        .conversationUnavailable: "Conversation unavailable",
        .openTask: "Open task",
        .openTerminal: "Open Terminal",
        .resumeConversation: "Resume conversation",
        .lifecycleArchived: "Archived",
        .lifecycleDeleted: "Deleted",
        .lifecycleUnavailable: "Unavailable",
        .lifecycleUnknown: "Status unknown",
        .claudeDraftPlaceholder: "Write the next message for Claude",
        .save: "Save",
        .menuTooltip: "Codex / Claude Conversation Inbox",
        .previewTitle: "Codex Draft Inbox · Preview",
        .inboxReadError: "The inbox file could not be read.",
        .updateOpenError: "The update page could not be opened.",
        .syncError: "Sync failed. Showing the last saved inbox.",
        .notificationSettingsError: "Notification privacy settings could not be saved.",
        .completionSettingsError: "Completion reminder settings could not be saved.",
        .languageSettingsError: "Language settings could not be saved.",
        .taskLinkError: "The task link is invalid.",
        .codexOpenError: "Codex did not accept the task link.",
        .unreadUpdateError: "The unread state could not be updated.",
        .claudeDraftSaveError: "The Claude draft could not be saved.",
        .missingClaudeSessionError: "The Claude session ID is missing.",
        .claudeNotFound: "Claude was not found. Install Claude Code or check PATH.",
        .claudeOpenError: "The Claude Code conversation could not be opened.",
        .markHandledError: "The task could not be marked as handled. Try again.",
    ]
}
