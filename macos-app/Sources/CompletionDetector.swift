public struct CompletionDetector {
    private struct State {
        let status: String
        let completionGeneration: String?
    }

    private var previousStates: [String: State]?

    public init() {}

    public mutating func detect(in items: [PendingItem]) -> [PendingItem] {
        let currentStates = Dictionary(
            uniqueKeysWithValues: items.map {
                ($0.threadID, State(
                    status: $0.status ?? "",
                    completionGeneration: completionGeneration(for: $0)
                ))
            }
        )
        defer { previousStates = currentStates }
        guard let previousStates else { return [] }
        return items.filter { item in
            guard item.status == "completed" else { return false }
            guard let previous = previousStates[item.threadID] else { return true }
            guard previous.status == "completed" else { return true }
            guard let previousGeneration = previous.completionGeneration,
                  let currentGeneration = completionGeneration(for: item) else {
                return false
            }
            return currentGeneration != previousGeneration
        }
    }

    private func completionGeneration(for item: PendingItem) -> String? {
        guard let token = item.observationToken, !token.isEmpty else { return nil }
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        if item.source == "claude", parts.count >= 3, parts[0] == "claude" {
            return parts.prefix(3).joined(separator: ":")
        }
        if parts.count >= 2, parts[0] == "turn" {
            if parts[1] == "none" || parts[1] == "unread" || parts[1] == "unknown" {
                return nil
            }
            return parts.prefix(2).joined(separator: ":")
        }
        return token
    }
}
