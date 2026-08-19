#!/bin/sh
set -eu

PLUGIN_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
INSTALL_APP="$HOME/Applications/Codex Draft Inbox.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.zhangshuo.codex-draft-inbox.plist"
STATE_ROOT="${CODEX_HOME:-$HOME/.codex}/draft-inbox"
LABEL="com.zhangshuo.codex-draft-inbox"
PURGE_DATA=0

if [ "${1:-}" = "--purge-data" ]; then
    PURGE_DATA=1
elif [ "$#" -gt 0 ]; then
    echo "用法：$0 [--purge-data]" >&2
    exit 2
fi

if [ "${CODEX_DRAFT_INBOX_SKIP_SYSTEM_COMMANDS:-0}" != "1" ]; then
    if [ -x "$INSTALL_APP/Contents/MacOS/CodexDraftInbox" ]; then
        "$INSTALL_APP/Contents/MacOS/CodexDraftInbox" --unregister-login-item >/dev/null 2>&1 || true
    fi
    launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
    pkill -x CodexDraftInbox >/dev/null 2>&1 || true
fi

/usr/bin/python3 "$PLUGIN_ROOT/scripts/install_claude_hooks.py" --uninstall >/dev/null
rm -f -- "$LAUNCH_AGENT"
rm -rf -- "$INSTALL_APP"

if [ "${CODEX_DRAFT_INBOX_SKIP_SYSTEM_COMMANDS:-0}" != "1" ] && command -v codex >/dev/null 2>&1; then
    codex plugin remove codex-draft-inbox@codex-draft-inbox >/dev/null 2>&1 || true
    codex plugin marketplace remove codex-draft-inbox >/dev/null 2>&1 || true
fi

if [ "$PURGE_DATA" -eq 1 ]; then
    rm -rf -- "$STATE_ROOT"
    echo "已卸载 Codex Draft Inbox，并删除本地待办数据。"
else
    echo "已卸载 Codex Draft Inbox；本地待办数据保留在 ${STATE_ROOT}。"
fi
