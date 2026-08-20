import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
struct CodexDraftInboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var viewModel = InboxViewModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var itemsSubscription: AnyCancellable?
    private var completionSubscription: AnyCancellable?
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handleLoginItemCommand() {
            NSApp.terminate(nil)
            return
        }
        registerLoginItemIfNeeded()
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "Codex / Claude 会话待办"
            button.setAccessibilityLabel("Codex / Claude 会话待办")
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 410, height: 530)
        popover.contentViewController = NSHostingController(rootView: InboxPanel(viewModel: viewModel))

        itemsSubscription = viewModel.$items.sink { [weak self] items in
            self?.updateStatusItem(count: items.count)
        }
        completionSubscription = viewModel.$completionBatch
            .compactMap { $0 }
            .debounce(for: .milliseconds(700), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.viewModel.completionPopoverEnabled else { return }
                self.showPopover(activating: false)
            }
        updateStatusItem(count: viewModel.items.count)

        if ProcessInfo.processInfo.environment["CODEX_DRAFT_INBOX_SHOW_ON_LAUNCH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showPreviewWindow()
            }
        }
    }

    private func handleLoginItemCommand() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--unregister-login-item") {
            try? SMAppService.mainApp.unregister()
            return true
        }
        if arguments.contains("--login-item-status") {
            print(SMAppService.mainApp.status.rawValue)
            return true
        }
        return false
    }

    private func registerLoginItemIfNeeded() {
        let service = SMAppService.mainApp
        guard service.status == .notRegistered else { return }
        try? service.register()
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover(activating: true)
    }

    private func showPopover(activating: Bool) {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        if activating {
            viewModel.refresh()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showPreviewWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 470),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex 草稿待办 · 验收预览"
        window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: InboxPanel(viewModel: viewModel))
        window.center()
        window.makeKeyAndOrderFront(nil)
        previewWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateStatusItem(count: Int) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: count == 0 ? "text.bubble" : "text.bubble.fill",
            accessibilityDescription: "Codex 草稿待办"
        )
        button.imagePosition = count == 0 ? .imageOnly : .imageLeading
        button.title = count == 0 ? "" : "\(count)"
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    }
}
