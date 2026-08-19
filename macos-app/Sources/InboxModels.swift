import Foundation

public struct PendingInbox: Codable, Equatable {
    public var version: Int
    public var items: [String: PendingItem]

    public static let empty = PendingInbox(version: 2, items: [:])

    public init(version: Int, items: [String: PendingItem]) {
        self.version = version
        self.items = items
    }
}

public struct PendingItem: Codable, Equatable, Identifiable {
    public let threadID: String
    public let title: String
    public let draft: String
    public let draftKey: String?
    public let completedAt: String
    public let lastActivityAt: String?
    public let status: String?
    public let lifecycle: String?
    public let observationToken: String?
    public let source: String?
    public let externalSessionID: String?
    public let cwd: String?

    public var id: String { threadID }

    public init(
        threadID: String,
        title: String,
        draft: String,
        draftKey: String?,
        completedAt: String,
        lastActivityAt: String? = nil,
        status: String? = nil,
        lifecycle: String? = nil,
        observationToken: String? = nil,
        source: String? = nil,
        externalSessionID: String? = nil,
        cwd: String? = nil
    ) {
        self.threadID = threadID
        self.title = title
        self.draft = draft
        self.draftKey = draftKey
        self.completedAt = completedAt
        self.lastActivityAt = lastActivityAt
        self.status = status
        self.lifecycle = lifecycle
        self.observationToken = observationToken
        self.source = source
        self.externalSessionID = externalSessionID
        self.cwd = cwd
    }

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case title
        case draft
        case draftKey = "draft_key"
        case completedAt = "completed_at"
        case lastActivityAt = "last_activity_at"
        case status
        case lifecycle
        case observationToken = "observation_token"
        case source
        case externalSessionID = "external_session_id"
        case cwd
    }

    public var effectiveActivityAt: String { lastActivityAt ?? completedAt }
}
