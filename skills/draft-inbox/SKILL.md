---
name: draft-inbox
description: 查看、跳转或清理 Codex 与 Claude Code 中尚未处理的会话和草稿待办。用户询问“哪些会话还没处理”“草稿待办”“Claude 待办”“刚才准备发什么”“跳转到待处理任务”或“标记草稿已处理”时使用。
---

# Codex / Claude 草稿待办

这个 Skill 只管理本地会话与草稿待办，不提交、不自动发送草稿。打开、读过或发送消息都不等于处理完成；只有用户明确要求标记已处理，待办才会清除。Codex 草稿来自客户端本地状态；Claude Code 草稿由菜单栏面板本地保存。

## 查看待办

将本 `SKILL.md` 向上两级目录作为 `<plugin-root>`，执行：

```bash
python3 <plugin-root>/scripts/draft_inbox.py list --json
```

按最后活动时间从新到旧展示任务名称、草稿原文、执行状态、会话可用性和任务 ID。`archived`、`deleted`、`unavailable`、`unknown` 分别说明会话已归档、已删除、不可见或暂时无法确认；这些状态不等于已经处理。不要读取或展示 `.codex-global-state.json` 中与这些待办无关的内容。

## 跳转任务

用户要求打开某个 Codex 待办时，从列表取精确 `thread_id`，调用 Codex 的任务导航工具跳转。Claude Code 待办由菜单栏 App 根据 `external_session_id` 恢复；若有多个候选且无法从名称唯一确定，只问用户选择哪一个，不要猜。

## 标记已处理

仅在用户明确要求时执行：

```bash
python3 <plugin-root>/scripts/draft_inbox.py clear --thread-id <thread_id> --manual
```

不要因为用户查看、打开、复制草稿、发送下一条消息或草稿变空而清除待办。只有用户明确点击或要求“已处理”时才使用 `--manual` 清除；同一对话启动新 Turn 或产生新草稿后可以再次进入待办。
