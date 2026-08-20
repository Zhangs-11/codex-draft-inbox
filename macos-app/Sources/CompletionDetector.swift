public struct CompletionDetector {
    private var previousStatuses: [String: String]?

    public init() {}

    public mutating func detect(in items: [PendingItem]) -> [PendingItem] {
        let currentStatuses = Dictionary(
            uniqueKeysWithValues: items.map { ($0.threadID, $0.status ?? "") }
        )
        defer { previousStatuses = currentStatuses }
        guard let previousStatuses else { return [] }
        return items.filter { item in
            guard item.status == "completed" else { return false }
            let previousStatus = previousStatuses[item.threadID]
            return previousStatus == nil || previousStatus == "running" || previousStatus == "draft"
        }
    }
}
