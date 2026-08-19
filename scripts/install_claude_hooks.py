#!/usr/bin/env python3
"""Install the Claude Code hooks used by Codex Draft Inbox."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import tempfile
from pathlib import Path
from typing import Any


HOOK_EVENTS = ("SessionStart", "UserPromptSubmit", "Stop")


def _is_draft_inbox_hook(entry: Any) -> bool:
    if not isinstance(entry, dict):
        return False
    nested = entry.get("hooks")
    if not isinstance(nested, list):
        return False
    return any(
        isinstance(hook, dict)
        and "draft_inbox.py" in str(hook.get("command", ""))
        and "claude-event" in str(hook.get("command", ""))
        for hook in nested
    )


def install_hooks(settings_path: Path, script_path: Path) -> None:
    if not script_path.is_file():
        raise FileNotFoundError(f"同步脚本不存在：{script_path}")

    if settings_path.exists():
        payload = json.loads(settings_path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("Claude settings.json 顶层必须是 JSON object")
    else:
        payload = {}

    hooks = payload.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("Claude settings.json 中的 hooks 必须是 JSON object")

    command = f"/usr/bin/python3 {shlex.quote(str(script_path))} claude-event"
    registration = {
        "hooks": [
            {
                "type": "command",
                "command": command,
                "timeout": 5,
            }
        ]
    }

    for event in HOOK_EVENTS:
        existing = hooks.get(event, [])
        if not isinstance(existing, list):
            raise ValueError(f"Claude settings.json 中的 hooks.{event} 必须是 JSON array")
        hooks[event] = [entry for entry in existing if not _is_draft_inbox_hook(entry)]
        hooks[event].append(registration)

    settings_path.parent.mkdir(parents=True, exist_ok=True)
    mode = settings_path.stat().st_mode & 0o777 if settings_path.exists() else 0o600
    fd, temporary_name = tempfile.mkstemp(prefix="settings.", suffix=".tmp", dir=settings_path.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.chmod(temporary_path, mode)
        os.replace(temporary_path, settings_path)
    finally:
        temporary_path.unlink(missing_ok=True)


def uninstall_hooks(settings_path: Path) -> bool:
    if not settings_path.is_file():
        return False
    payload = json.loads(settings_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or not isinstance(payload.get("hooks"), dict):
        return False
    changed = False
    hooks = payload["hooks"]
    for event in HOOK_EVENTS:
        existing = hooks.get(event)
        if not isinstance(existing, list):
            continue
        filtered = [entry for entry in existing if not _is_draft_inbox_hook(entry)]
        if len(filtered) == len(existing):
            continue
        changed = True
        if filtered:
            hooks[event] = filtered
        else:
            hooks.pop(event, None)
    if not changed:
        return False

    mode = settings_path.stat().st_mode & 0o777
    fd, temporary_name = tempfile.mkstemp(prefix="settings.", suffix=".tmp", dir=settings_path.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.chmod(temporary_path, mode)
        os.replace(temporary_path, settings_path)
    finally:
        temporary_path.unlink(missing_ok=True)
    return True


def main() -> int:
    home = Path.home()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uninstall", action="store_true", help="移除本项目写入的 Claude Code hooks")
    parser.add_argument(
        "--settings-path",
        type=Path,
        default=home / ".claude" / "settings.json",
        help="Claude Code settings.json 路径",
    )
    parser.add_argument(
        "--script-path",
        type=Path,
        default=home
        / "Applications"
        / "Codex Draft Inbox.app"
        / "Contents"
        / "Resources"
        / "draft_inbox.py",
        help="已安装到菜单栏 App 内的同步脚本路径",
    )
    args = parser.parse_args()
    if args.uninstall:
        changed = uninstall_hooks(args.settings_path.expanduser())
        print("Claude Code hooks 已移除" if changed else "没有找到 Codex Draft Inbox hooks")
        return 0
    install_hooks(args.settings_path.expanduser(), args.script_path.expanduser())
    print(f"Claude Code hooks 已写入：{args.settings_path.expanduser()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
