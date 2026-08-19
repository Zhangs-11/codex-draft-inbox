public struct RefreshCoordinator {
    public private(set) var isInFlight = false
    private var isQueued = false

    public init() {}

    public mutating func begin(queueIfBusy: Bool) -> Bool {
        if isInFlight {
            if queueIfBusy {
                isQueued = true
            }
            return false
        }
        isInFlight = true
        return true
    }

    public mutating func finish() -> Bool {
        isInFlight = false
        let shouldRunAgain = isQueued
        isQueued = false
        return shouldRunAgain
    }
}
