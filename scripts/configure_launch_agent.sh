#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "用法：$0 <已安装 App>" >&2
    exit 2
fi

INSTALL_APP=$1
LEGACY_LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.zhangshuo.codex-draft-inbox.plist"
LABEL="com.zhangshuo.codex-draft-inbox"
STATE_ROOT="${CODEX_HOME:-$HOME/.codex}/draft-inbox"
BACKUP="$STATE_ROOT/legacy-launch-agent.plist.bak"

if [ -f "$LEGACY_LAUNCH_AGENT" ]; then
    if [ "${CODEX_DRAFT_INBOX_SKIP_SYSTEM_COMMANDS:-0}" != "1" ]; then
        launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
    fi
    install -d "$STATE_ROOT"
    if [ -e "$BACKUP" ]; then
        BACKUP="$STATE_ROOT/legacy-launch-agent.$$.plist.bak"
    fi
    mv "$LEGACY_LAUNCH_AGENT" "$BACKUP"
fi

if [ "${CODEX_DRAFT_INBOX_SKIP_SYSTEM_COMMANDS:-0}" = "1" ]; then
    exit 0
fi

pkill -x CodexDraftInbox >/dev/null 2>&1 || true
open -gja "$INSTALL_APP"
