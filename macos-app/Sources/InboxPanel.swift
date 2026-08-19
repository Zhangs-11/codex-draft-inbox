import AppKit
import DraftInboxCore
import SwiftUI

struct InboxPanel: View {
    @ObservedObject var viewModel: InboxViewModel

    private let accent = Color(red: 0.89, green: 0.42, blue: 0.25)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)

            if viewModel.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        sourceSection(
                            title: "Codex",
                            logoName: "codex-logo",
                            color: Color(red: 0.31, green: 0.56, blue: 0.96),
                            items: codexItems
                        )
                        sourceSection(
                            title: "Claude Code",
                            logoName: "claude-logo",
                            color: accent,
                            items: claudeItems
                        )
                    }
                    .padding(12)
                }
            }

            if let message = viewModel.errorMessage {
                errorBanner(message)
            }

            Divider().opacity(0.55)
            notificationPrivacy
            Divider().opacity(0.55)
            footer
        }
        .frame(width: 410, height: 500)
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
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("刷新")
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

    private var codexItems: [PendingItem] {
        viewModel.items.filter { $0.source != "claude" }
    }

    private var claudeItems: [PendingItem] {
        viewModel.items.filter { $0.source == "claude" }
    }

    @ViewBuilder
    private func sourceSection(
        title: String,
        logoName: String,
        color: Color,
        items: [PendingItem]
    ) -> some View {
        if !items.isEmpty {
            HStack(spacing: 8) {
                SourceLogo(name: logoName)
                Text(title)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                Text("\(items.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.13), in: Capsule())
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)

            ForEach(items) { item in
                InboxRow(item: item, accent: accent) {
                    viewModel.openTask(item)
                } onHandled: {
                    viewModel.markHandled(item)
                } onSaveDraft: { text in
                    viewModel.saveClaudeDraft(item, text: text)
                }
            }
        }
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
        .frame(width: 27, height: 27)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct InboxRow: View {
    let item: PendingItem
    let accent: Color
    let onOpen: () -> Void
    let onHandled: () -> Void
    let onSaveDraft: (String) -> Void

    @State private var hovering = false

    private var statusColor: Color {
        if item.status == "completed" {
            return Color(red: 0.25, green: 0.78, blue: 0.43)
        }
        return Color(red: 0.96, green: 0.68, blue: 0.20)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Capsule()
                .fill(statusColor)
                .frame(width: 3)
                .padding(.vertical, 3)
                .padding(.trailing, 11)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
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
                        Text(statusText(item.status))
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
                .fill(Color(nsColor: .controlBackgroundColor).opacity(hovering ? 0.9 : 0.64))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovering ? 0.12 : 0.06), lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
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
