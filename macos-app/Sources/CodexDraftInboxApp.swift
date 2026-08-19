import AppKit
import Combine
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
    private let viewModel = InboxViewModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var itemsSubscription: AnyCancellable?
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "Codex / Claude 会话待办"
            button.setAccessibilityLabel("Codex / Claude 会话待办")
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 410, height: 470)
        popover.contentViewController = NSHostingController(rootView: InboxPanel(viewModel: viewModel))

        itemsSubscription = viewModel.$items.sink { [weak self] items in
            self?.updateStatusItem(count: items.count)
        }
        updateStatusItem(count: viewModel.items.count)

        if ProcessInfo.processInfo.environment["CODEX_DRAFT_INBOX_SHOW_ON_LAUNCH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showPreviewWindow()
            }
        }
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        viewModel.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
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
