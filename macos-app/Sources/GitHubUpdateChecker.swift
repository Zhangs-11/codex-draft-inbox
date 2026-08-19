import Foundation
import DraftInboxCore

protocol UpdateChecking: Sendable {
    func fetchReleases() async throws -> [AppRelease]
}

struct GitHubUpdateChecker: UpdateChecking {
    private let releasesURL = URL(
        string: "https://api.github.com/repos/Zhangs-11/codex-draft-inbox/releases?per_page=20"
    )!

    func fetchReleases() async throws -> [AppRelease] {
        var request = URLRequest(url: releasesURL)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Codex-Draft-Inbox", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.invalidResponse
        }
        return try JSONDecoder().decode([AppRelease].self, from: data)
    }

    private enum UpdateCheckError: Error {
        case invalidResponse
    }
}

enum UpdateCheckState: Equatable {
    case idle
    case available(AppRelease)
    case current(String)
    case failed
}
