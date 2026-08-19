import Foundation

public struct AppRelease: Decodable, Equatable, Sendable {
    public let tagName: String
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool

    public init(tagName: String, htmlURL: URL, draft: Bool = false, prerelease: Bool = false) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.draft = draft
        self.prerelease = prerelease
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }

    public var displayVersion: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}

public struct AppVersion: Comparable, Equatable, Sendable {
    private let components: [Int]

    public init?(_ rawValue: String) {
        let normalized = rawValue.hasPrefix("v") ? String(rawValue.dropFirst()) : rawValue
        let core = normalized.split(separator: "-", maxSplits: 1).first.map(String.init) ?? normalized
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        var parsed = parts.map { Int($0)! }
        while parsed.count > 1 && parsed.last == 0 {
            parsed.removeLast()
        }
        components = parsed
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

public enum AppReleaseSelector {
    public static func update(
        from releases: [AppRelease],
        currentVersion: String
    ) -> AppRelease? {
        guard let current = AppVersion(currentVersion) else { return nil }
        return releases
            .filter { !$0.draft && AppVersion($0.tagName) != nil }
            .sorted {
                AppVersion($0.tagName)! > AppVersion($1.tagName)!
            }
            .first { AppVersion($0.tagName)! > current }
    }

    public static func shouldCheck(
        lastCheckedAt: Date?,
        now: Date = Date(),
        interval: TimeInterval = 24 * 60 * 60
    ) -> Bool {
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= interval || now < lastCheckedAt
    }
}
