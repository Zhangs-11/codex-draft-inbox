#!/bin/sh
set -eu

PACKAGE_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SOURCE_APP="$PACKAGE_ROOT/Codex Draft Inbox.app"
INSTALL_ROOT="$HOME/Applications"
INSTALL_APP="$INSTALL_ROOT/Codex Draft Inbox.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.zhangshuo.codex-draft-inbox.plist"
TEMPLATE="$SOURCE_APP/Contents/Resources/com.zhangshuo.codex-draft-inbox.plist"
LABEL="com.zhangshuo.codex-draft-inbox"
WITH_CLAUDE=0

if [ "${1:-}" = "--with-claude" ]; then
    WITH_CLAUDE=1
elif [ "$#" -gt 0 ]; then
    echo "用法：$0 [--with-claude]" >&2
    exit 2
fi

if [ ! -d "$SOURCE_APP" ] || [ ! -f "$TEMPLATE" ]; then
    echo "Release 包不完整：缺少菜单栏 App 或 LaunchAgent 模板。" >&2
    exit 1
fi

install -d "$INSTALL_ROOT" "$HOME/Library/LaunchAgents"
ditto "$SOURCE_APP" "$INSTALL_APP"
install -m 644 "$TEMPLATE" "$LAUNCH_AGENT"
plutil -insert ProgramArguments.0 \
    -string "$INSTALL_APP/Contents/MacOS/CodexDraftInbox" \
    "$LAUNCH_AGENT"

if [ "${CODEX_DRAFT_INBOX_SKIP_SYSTEM_COMMANDS:-0}" != "1" ]; then
    launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
    if ! launchctl bootstrap "gui/$UID" "$LAUNCH_AGENT" >/dev/null 2>&1; then
        sleep 1
        launchctl bootstrap "gui/$UID" "$LAUNCH_AGENT"
    fi
fi

if [ "$WITH_CLAUDE" -eq 1 ]; then
    /usr/bin/python3 "$PACKAGE_ROOT/scripts/install_claude_hooks.py"
fi

echo "已安装：$INSTALL_APP"
