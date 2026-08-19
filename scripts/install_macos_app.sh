#!/bin/sh
set -eu

PLUGIN_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CACHE_APP=$("$PLUGIN_ROOT/scripts/build_macos_app.sh")
INSTALL_ROOT="$HOME/Applications"
INSTALL_APP="$INSTALL_ROOT/Codex Draft Inbox.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.zhangshuo.codex-draft-inbox.plist"
LABEL="com.zhangshuo.codex-draft-inbox"

install -d "$INSTALL_ROOT" "$HOME/Library/LaunchAgents"
ditto "$CACHE_APP" "$INSTALL_APP"
install -m 644 \
    "$PLUGIN_ROOT/macos-app/AppResources/com.zhangshuo.codex-draft-inbox.plist" \
    "$LAUNCH_AGENT"
plutil -insert ProgramArguments.0 \
    -string "$INSTALL_APP/Contents/MacOS/CodexDraftInbox" \
    "$LAUNCH_AGENT"

launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
if ! launchctl bootstrap "gui/$UID" "$LAUNCH_AGENT" >/dev/null 2>&1; then
    sleep 1
    launchctl bootstrap "gui/$UID" "$LAUNCH_AGENT"
fi

echo "$INSTALL_APP"
