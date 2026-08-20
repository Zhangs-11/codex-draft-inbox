# Codex Draft Inbox

> 不自动发送消息，只把你还没处理的 Codex 与 Claude Code 会话留在菜单栏里。

Codex Draft Inbox 是一个本地优先的 Codex 插件和 macOS 菜单栏伴随应用。它把正在执行、已经完成以及仍有草稿的 Codex / Claude Code 会话集中到一个待办面板中，直到你明确点击“已处理”才移除。

它适合同时跑多个 Agent 任务的人：你可以先在某个 Codex 会话里写好下一句话，再去处理其他工作；任务完成后，菜单栏会保留会话标题、草稿和执行状态，避免“看过结果，却忘了回来继续”。

## 能做什么

- 统一展示 Codex 与 Claude Code 会话；构建时检测到官方 App 后，使用各自的 Logo 分组。
- 用户会话启动后立即进入待办；已绑定到真实 Codex 会话的非空草稿也一定展示。
- 卡片显示真实会话标题，下面显示当前草稿；没有草稿时显示等待处理提示。
- 会话标题跟随 Codex 侧栏名称，内部 subagent、exec 和未绑定临时草稿不会进入列表。
- 黄色状态条表示执行中或仅有草稿，绿色表示当前 Turn 已完成，红色表示执行失败，橙色表示已中止。
- Codex 与 Claude Code 混合按最近活动时间排序；任务刚完成时自动展开面板、置顶并短暂高亮。
- 已完成但尚未通过插件打开的任务显示“未读”；点击“打开任务 / 恢复会话”后取消标识。
- 已归档、已删除、不可见或暂时无法确认的 Codex 会话继续保留，并在标题旁显示标记。
- 按最后活动时间排序；旧待办产生新 Turn 或新草稿后会回到顶部。
- 点击“打开任务”跳回对应 Codex 会话，或在 Terminal 中恢复 Claude Code 会话。
- 只有点击“已处理”才移除；打开、读过、草稿变空或任务结束都不会自动清除。
- 通知默认隐藏草稿正文，可以在菜单栏面板底部主动开启预览。
- 登录 macOS 后自动启动。
- 手动刷新会显示加载状态；若后台同步正在运行，会排队补跑一次。
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
- macOS 13+ 的 `SMAppService.mainApp` 负责登录自启动；旧版 LaunchAgent 会在升级时停止并移出 `~/Library/LaunchAgents`。

## 适配环境

| 项目 | 要求 |
|---|---|
| 操作系统 | macOS 13 Ventura 或更高版本 |
| Codex | 支持 Plugins 与本地会话状态的 Codex 桌面客户端 / CLI |
| Claude Code | 可选；需要支持 `SessionStart`、`UserPromptSubmit`、`Stop`、`StopFailure` 和 `SessionEnd` hooks |
| Python | `/usr/bin/python3`，Python 3.9 或更高版本 |
| 构建工具 | Xcode Command Line Tools，包含 Swift 6 与 `codesign` |

菜单栏应用目前仅支持 macOS。Codex 的本地状态结构属于客户端实现细节，未来客户端升级后如果字段发生变化，本项目也可能需要同步适配。

构建脚本会从当前电脑已安装的 ChatGPT/Codex 与 Claude App 中读取对应 Logo，并复制进本地构建产物；仓库不重新分发第三方品牌素材。没有检测到对应 App 时，界面会使用通用应用图标，不影响待办功能。

## 安装

Codex 插件与菜单栏 App 是两个组件。Codex 插件通过 marketplace 安装；菜单栏 App 可以下载 GitHub Release，也可以从源码构建。

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

#### 使用 GitHub Release

从 [Releases](https://github.com/Zhangs-11/codex-draft-inbox/releases) 下载最新的 `Codex-Draft-Inbox-v<版本>-macos-universal.zip` 和同名 `.sha256` 文件。安装包同时包含 `arm64` 与 `x86_64`，可用于 Apple 芯片和 Intel Mac。先在下载目录校验（把 `<版本>` 替换为实际版本号）：

```bash
shasum -a 256 -c Codex-Draft-Inbox-v<版本>-macos-universal.zip.sha256
```

解压后运行：

```bash
cd "Codex Draft Inbox v<版本>"
./scripts/install_release.sh
```

同时接入 Claude Code：

```bash
./scripts/install_release.sh --with-claude
```

当前 Release 使用本地 ad-hoc 签名，属于开源预览版，并未经过 Apple Developer ID 公证。Universal Binary 已静态核对包含两个架构，并在 Apple 芯片 Mac 上完成安装验证；Intel 实机运行仍未验证。Release 不重新分发第三方 Logo，因此使用通用分组图标；从源码构建时才会尝试读取本机已安装 App 的官方图标。

#### 从源码构建

```bash
./scripts/install_macos_app.sh
```

脚本会完成以下操作：

- 构建并签名 `~/Applications/Codex Draft Inbox.app`；
- 通过 macOS `SMAppService` 注册登录自启动；
- 启动菜单栏应用。

如果缺少 Swift 工具链，先运行：

```bash
xcode-select --install
```

### 4. 从源码接入 Claude Code（可选）

先安装菜单栏应用，再执行：

```bash
/usr/bin/python3 ./scripts/install_claude_hooks.py
```

安装器只会更新 `~/.claude/settings.json` 中本项目使用的五类 Hook，并保留已有的其他设置和 Hook。重新启动 Claude Code 后生效。

## 使用方法

安装后，菜单栏会出现对话气泡图标和待办数量：

1. 在 Codex 或 Claude Code 中启动任务。
2. 切换去处理其他会话；需要时可提前在 Codex 输入框写好下一条草稿。
3. 点击菜单栏图标查看所有尚未处理的会话。
4. 点击“打开任务”回到原会话，结合上一轮结果继续处理。
5. 确认不再需要跟进后，点击“已处理”。

如果 Codex 会话后来被归档或删除，它仍会留在待办中并显示相应标记。已删除和不可见会话不能再打开，但仍可手动标记“已处理”。

Codex 中也可以直接询问“哪些会话还没处理”或要求打开、清理某个待办，插件内的 `draft-inbox` Skill 会读取同一份本地列表。

## Codex 与 Claude Code 的差异

| 能力 | Codex | Claude Code |
|---|---|---|
| 会话标题 | 读取 Codex 本地会话信息 | 使用最近一条已发送消息生成预览 |
| 未发送草稿 | 读取 Codex 客户端已有草稿 | 终端输入框不可读取，需要在菜单栏卡片中保存 |
| 执行状态 | 读取最近一个 Turn 的 rollout 状态 | 由 Claude Code 生命周期 Hook 同步 |
| 打开会话 | 使用 `codex://threads/<id>` | 已完成会话使用 `claude --resume <session-id>`；运行中只激活 Terminal |

## 状态与隐私

运行时文件保存在：

```text
~/.codex/draft-inbox/pending.json
~/.codex/draft-inbox/pending.json.bak
~/.codex/draft-inbox/observed.json
~/.codex/draft-inbox/claude.json
~/.codex/draft-inbox/settings.json
```

程序会只读访问 Codex 的本地草稿状态、会话 SQLite 数据库和 rollout 日志，以取得标题、真实会话 ID 和执行状态；不会写入 Codex 数据库。除每天检查一次新版本外，它不会连接外部服务；版本检查只访问 GitHub Releases API，不会上传待办、草稿或会话内容，也不会自动发送草稿。通知默认不显示草稿正文；开启“通知显示草稿”后，只显示截断后的预览。待办更新前会保留最后一份有效备份，主状态文件损坏时自动恢复。

## 更新

从 v0.2.3 开始，菜单栏 App 每 24 小时检查一次 GitHub Release。发现新版本后，面板顶部会显示升级提示；也可以点击底部的“检查更新”立即检查。App 只会打开对应的 GitHub Release 页面，不会静默下载或安装。

从 v0.2.4 开始，只有已经确认进入 Codex 用户会话表的任务，后续消失时才会标记为“已删除”；旧版遗留、从未成为真实会话的临时 ID 会自动清理。Claude Code 子代理和带有明确内部 worker 协议的自动化会话也不会进入待办。

从 v0.3.0 开始，Codex 和 Claude Code 使用统一单列并按最近活动时间全局排序。运行中的任务变为已完成时，菜单栏面板会自动展开且不抢键盘焦点，刚完成的卡片会短暂显示绿色动态高亮；点击桌面其他位置即可关闭。可以在面板底部关闭“完成时自动展开”。

从 v0.3.1 开始，自动展开期间会监听其他 App 或桌面的鼠标点击并主动关闭面板，不再只依赖 macOS 对 transient popover 的默认关闭行为。

从 v0.3.2 开始，插件会为新完成任务展示“未读”状态。Codex 直接跟随客户端原生蓝点，因此从侧栏或插件进入会话后都会同步为已读；Claude Code 没有对应字段，由插件在成功点击“恢复会话”后清除。查看自动弹窗不算已读，同一会话后续产生新任务并再次完成时会重新标记。失败和中止会显示独立状态，不会触发成功提醒；升级安装会等待旧进程退出并验证新版 App 已启动。

首次安装或从旧版 LaunchAgent 迁移时，macOS 可能显示一次登录项系统通知，因为菜单栏 App 会注册为登录后自动启动。这是 macOS 的透明性提示，应用无法静默关闭；迁移完成后的更新不会再创建新的 legacy 后台项目。

v0.2.2 及更早版本还没有更新检测，需要先手动下载新版 Release 并重新运行安装脚本；原有待办和设置会保留。更新提示检查的是菜单栏 App，Codex 插件仍需通过 marketplace 单独升级。从源码安装时可以执行：

```bash
git pull
codex plugin marketplace upgrade codex-draft-inbox
codex plugin add codex-draft-inbox@codex-draft-inbox
./scripts/install_macos_app.sh
```

如果使用 Claude Code，菜单栏 App 更新后 Hook 会继续指向 App 内置的同步脚本，无需重复安装。

## 卸载

默认卸载 App、登录项、旧版 LaunchAgent、Claude Hooks 和公开 marketplace 插件，但保留本地待办数据：

```bash
./scripts/uninstall.sh
```

同时删除 `~/.codex/draft-inbox/` 中的待办和设置：

```bash
./scripts/uninstall.sh --purge-data
```

卸载脚本只移除本项目写入的 Claude Hooks，并保留 `settings.json` 中的其他 Hook 和配置。

## 验证与开发

```bash
python3 -m unittest discover -s tests -v
python3 scripts/draft_inbox.py list --json
./scripts/test_macos_app.sh
```

GitHub Actions 会在 Python 3.9、Python 3.13 和 Swift 6 环境重复执行兼容测试。插件开发者还可以使用 Codex 自带的 `plugin-creator` Skill 校验插件清单。

## 已知限制

- 不支持 Windows 和 Linux 菜单栏。
- 无法读取 Claude Code 终端中尚未按回车的文本。
- 状态颜色表示最近一个 Turn 的运行状态，不代表你是否已经阅读。
- Codex 客户端本地状态结构升级后可能需要跟进适配。
- Claude Code 运行中的会话只能激活 Terminal，不能精确定位原终端窗口。
- 菜单栏空间不足时，macOS 可能临时隐藏图标；可按住 `Command` 将图标拖到更靠右的位置。
- 当前使用本地 ad-hoc 签名，不是经过 Apple Developer ID 公证的分发包；首次运行若被系统拦截，需要在“系统设置 → 隐私与安全性”中确认。

## License

[MIT](LICENSE)

本许可证只覆盖本仓库代码。OpenAI、Codex、Anthropic 与 Claude 的名称和标识归各自权利人所有；本项目与 OpenAI 或 Anthropic 没有官方隶属、赞助或背书关系。
