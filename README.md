# Codex Draft Inbox

> 不自动发送消息，只把你还没处理的 Codex 与 Claude Code 会话留在菜单栏里。

Codex Draft Inbox 是一个本地优先的 Codex 插件和 macOS 菜单栏伴随应用。它把正在执行、已经完成以及仍有草稿的 Codex / Claude Code 会话集中到一个待办面板中，直到你明确点击“已处理”才移除。

它适合同时跑多个 Agent 任务的人：你可以先在某个 Codex 会话里写好下一句话，再去处理其他工作；任务完成后，菜单栏会保留会话标题、草稿和执行状态，避免“看过结果，却忘了回来继续”。

## 能做什么

- 统一展示 Codex 与 Claude Code 会话；构建时检测到官方 App 后，使用各自的 Logo 分组。
- 会话启动后立即进入待办；有非空草稿的 Codex 会话也一定展示。
- 卡片显示真实会话标题，下面显示当前草稿；没有草稿时显示等待处理提示。
- 黄色状态条表示执行中或仅有草稿，绿色表示当前 Turn 已完成。
- 点击“打开任务”跳回对应 Codex 会话，或在 Terminal 中恢复 Claude Code 会话。
- 只有点击“已处理”才移除；打开、读过、草稿变空或任务结束都不会自动清除。
- 登录 macOS 后自动启动；异常退出会由 LaunchAgent 重新拉起。
- 所有状态保存在本机，不上传草稿，也不会自动发送任何消息。

## 它是什么

这不是嵌进 Codex 窗口的单一 UI 扩展，而是一套协同工作的本地组件：

```text
Codex hooks + 本地会话状态 ─┐
                             ├─ Python 同步引擎 ─ pending.json ─ macOS 菜单栏 App
Claude Code hooks ──────────┘                                  ├─ 打开任务
                                                                └─ 标记已处理
```

- `.codex-plugin/plugin.json`、`hooks.json` 和 `skills/` 组成 Codex 插件。
- `scripts/draft_inbox.py` 只读采集会话标题、草稿和最近一个 Turn 的状态，并维护本地待办。
- `macos-app/` 是 SwiftUI 编写的原生菜单栏应用。
- `~/Library/LaunchAgents/com.zhangshuo.codex-draft-inbox.plist` 负责登录自启动。

## 适配环境

| 项目 | 要求 |
|---|---|
| 操作系统 | macOS 13 Ventura 或更高版本 |
| Codex | 支持 Plugins 与本地会话状态的 Codex 桌面客户端 / CLI |
| Claude Code | 可选；需要支持 `SessionStart`、`UserPromptSubmit` 和 `Stop` hooks |
| Python | `/usr/bin/python3`，Python 3.9 或更高版本 |
| 构建工具 | Xcode Command Line Tools，包含 Swift 6 与 `codesign` |

菜单栏应用目前仅支持 macOS。Codex 的本地状态结构属于客户端实现细节，未来客户端升级后如果字段发生变化，本项目也可能需要同步适配。

构建脚本会从当前电脑已安装的 ChatGPT/Codex 与 Claude App 中读取对应 Logo，并复制进本地构建产物；仓库不重新分发第三方品牌素材。没有检测到对应 App 时，界面会使用通用应用图标，不影响待办功能。

## 安装

### 1. 克隆仓库

```bash
git clone https://github.com/Zhangs-11/codex-draft-inbox.git
cd codex-draft-inbox
```

### 2. 安装 Codex 插件

把仓库添加为 Codex marketplace，再安装插件：

```bash
codex plugin marketplace add Zhangs-11/codex-draft-inbox
codex plugin add codex-draft-inbox@codex-draft-inbox
```

安装或升级插件后，请新开一个 Codex 会话，让 Codex 重新加载 Skill 和 Hooks。

### 3. 安装菜单栏应用

```bash
./scripts/install_macos_app.sh
```

脚本会完成以下操作：

- 构建并签名 `~/Applications/Codex Draft Inbox.app`；
- 写入当前用户的 LaunchAgent；
- 启动菜单栏应用。

如果缺少 Swift 工具链，先运行：

```bash
xcode-select --install
```

### 4. 接入 Claude Code（可选）

先安装菜单栏应用，再执行：

```bash
/usr/bin/python3 ./scripts/install_claude_hooks.py
```

安装器只会更新 `~/.claude/settings.json` 中本项目使用的三类 Hook，并保留已有的其他设置和 Hook。重新启动 Claude Code 后生效。

## 使用方法

安装后，菜单栏会出现对话气泡图标和待办数量：

1. 在 Codex 或 Claude Code 中启动任务。
2. 切换去处理其他会话；需要时可提前在 Codex 输入框写好下一条草稿。
3. 点击菜单栏图标查看所有尚未处理的会话。
4. 点击“打开任务”回到原会话，结合上一轮结果继续处理。
5. 确认不再需要跟进后，点击“已处理”。

Codex 中也可以直接询问“哪些会话还没处理”或要求打开、清理某个待办，插件内的 `draft-inbox` Skill 会读取同一份本地列表。

## Codex 与 Claude Code 的差异

| 能力 | Codex | Claude Code |
|---|---|---|
| 会话标题 | 读取 Codex 本地会话信息 | 使用最近一条已发送消息生成预览 |
| 未发送草稿 | 读取 Codex 客户端已有草稿 | 终端输入框不可读取，需要在菜单栏卡片中保存 |
| 执行状态 | 读取最近一个 Turn 的 rollout 状态 | 由 Claude Code 生命周期 Hook 同步 |
| 打开会话 | 使用 `codex://threads/<id>` | 使用 `claude --resume <session-id>` |

## 状态与隐私

运行时文件保存在：

```text
~/.codex/draft-inbox/pending.json
~/.codex/draft-inbox/observed.json
~/.codex/draft-inbox/claude.json
```

程序会只读访问 Codex 的本地草稿状态、会话 SQLite 数据库和 rollout 日志，以取得标题、真实会话 ID 和执行状态；不会写入 Codex 数据库。它不会连接外部服务，也不会上传或自动发送草稿。macOS 通知只显示截断后的草稿预览。

## 更新

```bash
git pull
codex plugin marketplace upgrade codex-draft-inbox
codex plugin add codex-draft-inbox@codex-draft-inbox
./scripts/install_macos_app.sh
```

如果使用 Claude Code，菜单栏 App 更新后 Hook 会继续指向 App 内置的同步脚本，无需重复安装。

## 验证与开发

```bash
python3 -m unittest discover -s tests -v
python3 scripts/draft_inbox.py list --json
./scripts/test_macos_app.sh
```

插件开发者还可以使用 Codex 自带的 `plugin-creator` Skill 校验插件清单。

## 已知限制

- 不支持 Windows 和 Linux 菜单栏。
- 无法读取 Claude Code 终端中尚未按回车的文本。
- 状态颜色表示最近一个 Turn 的运行状态，不代表你是否已经阅读。
- Codex 客户端本地状态结构升级后可能需要跟进适配。
- 当前使用本地 ad-hoc 签名，不是经过 Apple Developer ID 公证的分发包；首次运行若被系统拦截，需要在“系统设置 → 隐私与安全性”中确认。

## License

[MIT](LICENSE)

本许可证只覆盖本仓库代码。OpenAI、Codex、Anthropic 与 Claude 的名称和标识归各自权利人所有；本项目与 OpenAI 或 Anthropic 没有官方隶属、赞助或背书关系。
