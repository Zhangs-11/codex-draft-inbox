public enum TaskOpenCoordinator {
    @discardableResult
    public static func perform(open: () -> Bool, dismiss: () -> Void) -> Bool {
        guard open() else { return false }
        dismiss()
        return true
    }
}
