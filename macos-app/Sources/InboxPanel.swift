import AppKit
import DraftInboxCore
import SwiftUI

struct InboxPanel: View {
    @ObservedObject var viewModel: InboxViewModel
    let onDismiss: () -> Void

    private let accent = Color(red: 0.89, green: 0.42, blue: 0.25)
    private var strings: AppStrings { viewModel.strings }

    init(viewModel: InboxViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)

            updateBanner

            if viewModel.items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.items) { item in
                                InboxRow(
                                    item: item,
                                    accent: accent,
                                    isNewlyCompleted: viewModel.newlyCompletedThreadIDs.contains(item.threadID),
                                    strings: strings
                                ) {
                                    TaskOpenCoordinator.perform(
                                        open: { viewModel.openTask(item) },
                                        dismiss: onDismiss
                                    )
                                } onHandled: {
                                    viewModel.markHandled(item)
                                } onSaveDraft: { text in
                                    viewModel.saveClaudeDraft(item, text: text)
                                }
                                .id(item.threadID)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: viewModel.completionBatch?.id) { _ in
                        guard let threadID = viewModel.completionBatch?.items.first?.threadID else { return }
                        proxy.scrollTo(threadID, anchor: .top)
                    }
                }
            }

            if let message = viewModel.errorMessage {
                errorBanner(message)
            }

            Divider().opacity(0.55)
            reminderSettings
            Divider().opacity(0.55)
            footer
        }
        .frame(width: 410, height: 530)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(strings[.inboxTitle])
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(viewModel.items.isEmpty ? strings[.noPendingTasks] : strings[.pendingTasks])
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !viewModel.items.isEmpty {
                Text("\(viewModel.items.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.14), in: Capsule())
            }

            Button {
                viewModel.refresh()
            } label: {
                Group {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(strings[.refresh])
            .help(viewModel.isRefreshing ? strings[.refreshing] : strings[.refresh])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 5]))
                    .foregroundStyle(.tertiary)
                    .frame(width: 76, height: 76)
                Image(systemName: "checkmark")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                Text(strings[.allHandled])
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(strings[.emptyDescription])
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
            Spacer()
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.09))
    }

    private var footer: some View {
        HStack {
            Label(strings[.storedLocally], systemImage: "lock.fill")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                viewModel.checkForUpdates()
            } label: {
                if viewModel.isCheckingForUpdates {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 54)
                } else {
                    Text(strings[.checkUpdates])
                }
            }
            .disabled(viewModel.isCheckingForUpdates)
            .font(.system(size: 10.5, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Label(strings[.startsAtLogin], systemImage: "arrow.clockwise")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Button(strings[.quit]) {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 10.5, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var updateBanner: some View {
        switch viewModel.updateCheckState {
        case let .available(release):
            HStack(spacing: 9) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(strings[.updateAvailable]) v\(release.displayVersion)")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(strings[.updateDetails])
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(strings[.openUpdate]) {
                    viewModel.openAvailableUpdate()
                }
                .font(.system(size: 10.5, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.blue.opacity(0.09))
            Divider().opacity(0.55)
        case let .current(version):
            updateStatusBanner("\(strings[.latestVersion]) v\(version)", color: .green)
        case .failed:
            updateStatusBanner(strings[.updateCheckFailed], color: .orange)
        case .idle:
            EmptyView()
        }
    }

    private func updateStatusBanner(_ text: String, color: Color) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: color == .green ? "checkmark.circle.fill" : "wifi.exclamationmark")
                Text(text)
                Spacer()
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(color.opacity(0.08))
            Divider().opacity(0.55)
        }
    }

    private var reminderSettings: some View {
        VStack(spacing: 0) {
            languageSelection
            Divider().opacity(0.35)
            completionReminder
            Divider().opacity(0.35)
            notificationPrivacy
        }
    }

    private var languageSelection: some View {
        HStack(spacing: 10) {
            Label(strings[.language], systemImage: "globe")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Picker(
                strings[.language],
                selection: Binding(
                    get: { viewModel.appLanguage },
                    set: { viewModel.setLanguage($0) }
                )
            ) {
                Text(strings[.followSystem]).tag(AppLanguage.system)
                Text(strings[.simplifiedChinese]).tag(AppLanguage.simplifiedChinese)
                Text(strings[.english]).tag(AppLanguage.english)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var completionReminder: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label(strings[.autoOpenOnCompletion], systemImage: "bell.badge.fill")
                    .font(.system(size: 11, weight: .medium))
                Text(strings[.autoOpenDescription])
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle(
                strings[.autoOpenOnCompletion],
                isOn: Binding(
                    get: { viewModel.completionPopoverEnabled },
                    set: { viewModel.setCompletionPopover(enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var notificationPrivacy: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label(strings[.showDraftInNotifications], systemImage: "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 11, weight: .medium))
                Text(strings[.showDraftDescription])
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle(
                strings[.showDraftInNotifications],
                isOn: Binding(
                    get: { viewModel.notificationDraftPreviewEnabled },
                    set: { viewModel.setNotificationDraftPreview(enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct SourceLogo: View {
    let name: String

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(5)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct InboxRow: View {
    let item: PendingItem
    let accent: Color
    let isNewlyCompleted: Bool
    let strings: AppStrings
    let onOpen: () -> Void
    let onHandled: () -> Void
    let onSaveDraft: (String) -> Void

    @State private var hovering = false
    @State private var completionPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let completionColor = Color(red: 0.25, green: 0.78, blue: 0.43)

    private var statusColor: Color {
        switch item.status {
        case "completed":
            Color(red: 0.25, green: 0.78, blue: 0.43)
        case "failed":
            Color(red: 0.93, green: 0.30, blue: 0.28)
        case "aborted":
            Color(red: 0.96, green: 0.52, blue: 0.18)
        default:
            Color(red: 0.96, green: 0.68, blue: 0.20)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Capsule()
                .fill(statusColor)
                .frame(width: 3)
                .padding(.vertical, 3)
                .padding(.trailing, 11)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    SourceLogo(name: item.source == "claude" ? "claude-logo" : "codex-logo")
                        .help(item.source == "claude" ? "Claude Code" : "Codex")
                    Text(item.title)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if item.isCompletionUnread {
                        Label(strings[.unread], systemImage: "circle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Color(red: 0.31, green: 0.56, blue: 0.96))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Color(red: 0.31, green: 0.56, blue: 0.96).opacity(0.13),
                                in: Capsule()
                            )
                            .accessibilityLabel(strings[.unreadAccessibility])
                    }
                    if let lifecycle = lifecycleBadge {
                        Text(lifecycle.text)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(lifecycle.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(lifecycle.color.opacity(0.12), in: Capsule())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(isNewlyCompleted ? strings[.justCompleted] : statusText(item.status))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(statusColor)
                        Text(relativeTime(item.effectiveActivityAt))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                if item.source == "claude" {
                    ClaudeDraftEditor(initialText: item.draft, strings: strings, onSave: onSaveDraft)
                        .id("\(item.observationToken ?? ""):\(item.draft)")
                } else if item.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(strings[.noDraft])
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                } else {
                    Text(item.draft)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .lineSpacing(2.5)
                        .textSelection(.enabled)
                }

                HStack(spacing: 8) {
                    Button(action: onOpen) {
                        Label(openButtonTitle, systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryActionStyle(accent: accent))
                    .disabled(!canOpen)
                    .opacity(canOpen ? 1 : 0.48)

                    Button(action: onHandled) {
                        Label(strings[.handled], systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionStyle())
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isNewlyCompleted
                        ? completionColor.opacity(completionPulse ? 0.16 : 0.08)
                        : Color(nsColor: .controlBackgroundColor).opacity(hovering ? 0.9 : 0.64)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isNewlyCompleted
                        ? completionColor.opacity(completionPulse ? 0.82 : 0.38)
                        : Color.primary.opacity(hovering ? 0.12 : 0.06),
                    lineWidth: isNewlyCompleted ? 1.5 : 1
                )
        )
        .shadow(
            color: isNewlyCompleted ? completionColor.opacity(completionPulse ? 0.24 : 0.08) : .clear,
            radius: isNewlyCompleted ? 10 : 0
        )
        .scaleEffect(isNewlyCompleted && completionPulse ? 1.006 : 1)
        .onHover { hovering = $0 }
        .onAppear { updateCompletionPulse(isActive: isNewlyCompleted) }
        .onChange(of: isNewlyCompleted) { updateCompletionPulse(isActive: $0) }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    private func updateCompletionPulse(isActive: Bool) {
        guard isActive, !reduceMotion else {
            completionPulse = false
            return
        }
        completionPulse = false
        withAnimation(.easeInOut(duration: 0.65).repeatCount(3, autoreverses: true)) {
            completionPulse = true
        }
    }

    private func relativeTime(_ raw: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: raw) else { return strings[.now] }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: strings.localeIdentifier)
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func statusText(_ status: String?) -> String {
        switch status {
        case "running": strings[.statusRunning]
        case "draft": strings[.statusDraft]
        case "failed": strings[.statusFailed]
        case "aborted": strings[.statusAborted]
        default: strings[.statusCompleted]
        }
    }

    private var openButtonTitle: String {
        if item.lifecycle == "deleted" { return strings[.conversationDeleted] }
        if item.lifecycle == "unavailable" { return strings[.conversationUnavailable] }
        guard item.source == "claude" else { return strings[.openTask] }
        return item.status == "running" ? strings[.openTerminal] : strings[.resumeConversation]
    }

    private var canOpen: Bool {
        item.lifecycle != "deleted" && item.lifecycle != "unavailable"
    }

    private var lifecycleBadge: (text: String, color: Color)? {
        switch item.lifecycle {
        case "archived": (strings[.lifecycleArchived], Color.secondary)
        case "deleted": (strings[.lifecycleDeleted], Color.red)
        case "unavailable": (strings[.lifecycleUnavailable], Color.secondary)
        case "unknown": (strings[.lifecycleUnknown], Color.orange)
        default: nil
        }
    }
}

private struct ClaudeDraftEditor: View {
    @State private var text: String
    let strings: AppStrings
    let onSave: (String) -> Void

    init(initialText: String, strings: AppStrings, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: initialText)
        self.strings = strings
        self.onSave = onSave
    }

    var body: some View {
        HStack(spacing: 7) {
            TextField(strings[.claudeDraftPlaceholder], text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
                .onSubmit { onSave(text) }
            Button(strings[.save]) {
                onSave(text)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .buttonStyle(.borderless)
        }
    }
}

private struct PrimaryActionStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 7)
            .background(accent.opacity(configuration.isPressed ? 0.72 : 0.92), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct SecondaryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}
