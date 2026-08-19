#!/bin/sh
set -eu

PACKAGE_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SOURCE_APP="$PACKAGE_ROOT/Codex Draft Inbox.app"
INSTALL_ROOT="$HOME/Applications"
INSTALL_APP="$INSTALL_ROOT/Codex Draft Inbox.app"
WITH_CLAUDE=0

if [ "${1:-}" = "--with-claude" ]; then
    WITH_CLAUDE=1
elif [ "$#" -gt 0 ]; then
    echo "用法：$0 [--with-claude]" >&2
    exit 2
fi

if [ ! -d "$SOURCE_APP" ]; then
    echo "Release 包不完整：缺少菜单栏 App。" >&2
    exit 1
fi

install -d "$INSTALL_ROOT"
ditto "$SOURCE_APP" "$INSTALL_APP"
"$PACKAGE_ROOT/scripts/configure_launch_agent.sh" "$INSTALL_APP"

if [ "$WITH_CLAUDE" -eq 1 ]; then
    /usr/bin/python3 "$PACKAGE_ROOT/scripts/install_claude_hooks.py"
fi

echo "已安装：$INSTALL_APP"
