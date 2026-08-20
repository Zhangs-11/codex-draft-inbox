import AppKit
import DraftInboxCore
import SwiftUI

struct InboxPanel: View {
    @ObservedObject var viewModel: InboxViewModel
    let onDismiss: () -> Void

    private let accent = Color(red: 0.89, green: 0.42, blue: 0.25)

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
                                    isNewlyCompleted: viewModel.newlyCompletedThreadIDs.contains(item.threadID)
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
                Text("会话待办")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(viewModel.items.isEmpty ? "没有等待你处理的任务" : "进行中，或等待你处理")
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
            .accessibilityLabel("刷新")
            .help(viewModel.isRefreshing ? "刷新中" : "刷新")
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
                Text("都处理完了")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("任务启动后会出现在这里。\n只有点“已处理”才会移除。")
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
            Label("本机保存", systemImage: "lock.fill")
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
                    Text("检查更新")
                }
            }
            .disabled(viewModel.isCheckingForUpdates)
            .font(.system(size: 10.5, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Label("登录自动启动", systemImage: "arrow.clockwise")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Button("退出") {
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
                    Text("菜单栏 App 有新版本 v\(release.displayVersion)")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("前往 GitHub 查看说明并下载")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("前往更新") {
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
            updateStatusBanner("已是最新版本 v\(version)", color: .green)
        case .failed:
            updateStatusBanner("检查更新失败，请稍后再试", color: .orange)
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
            completionReminder
            Divider().opacity(0.35)
            notificationPrivacy
        }
    }

    private var completionReminder: some View {
        HStack(spacing: 10) {
            Label("完成时自动展开", systemImage: "bell.badge.fill")
                .font(.system(size: 11, weight: .medium))
            Text("新完成任务会置顶并短暂高亮")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Toggle(
                "完成时自动展开",
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
            Label("通知显示草稿", systemImage: "rectangle.inset.filled.and.person.filled")
                .font(.system(size: 11, weight: .medium))
            Text("关闭时锁屏通知只显示待办提醒")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Toggle(
                "通知显示草稿",
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
                        Label("未读", systemImage: "circle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Color(red: 0.31, green: 0.56, blue: 0.96))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Color(red: 0.31, green: 0.56, blue: 0.96).opacity(0.13),
                                in: Capsule()
                            )
                            .accessibilityLabel("已完成但未读")
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
                        Text(isNewlyCompleted ? "刚刚完成" : statusText(item.status))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(statusColor)
                        Text(relativeTime(item.effectiveActivityAt))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                if item.source == "claude" {
                    ClaudeDraftEditor(initialText: item.draft, onSave: onSaveDraft)
                        .id("\(item.observationToken ?? ""):\(item.draft)")
                } else if item.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("暂无草稿，等待你处理")
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
                        Label("已处理", systemImage: "checkmark")
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
        guard let date = ISO8601DateFormatter().date(from: raw) else { return "刚刚" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func statusText(_ status: String?) -> String {
        switch status {
        case "running": "执行中"
        case "draft": "有草稿"
        case "failed": "执行失败"
        case "aborted": "已中止"
        default: "已完成"
        }
    }

    private var openButtonTitle: String {
        if item.lifecycle == "deleted" { return "会话已删除" }
        if item.lifecycle == "unavailable" { return "会话不可见" }
        guard item.source == "claude" else { return "打开任务" }
        return item.status == "running" ? "打开终端" : "恢复会话"
    }

    private var canOpen: Bool {
        item.lifecycle != "deleted" && item.lifecycle != "unavailable"
    }

    private var lifecycleBadge: (text: String, color: Color)? {
        switch item.lifecycle {
        case "archived": ("已归档", Color.secondary)
        case "deleted": ("已删除", Color.red)
        case "unavailable": ("不可见", Color.secondary)
        case "unknown": ("状态未知", Color.orange)
        default: nil
        }
    }
}

private struct ClaudeDraftEditor: View {
    @State private var text: String
    let onSave: (String) -> Void

    init(initialText: String, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: initialText)
        self.onSave = onSave
    }

    var body: some View {
        HStack(spacing: 7) {
            TextField("写下准备发给 Claude 的下一句话", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
                .onSubmit { onSave(text) }
            Button("保存") {
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
