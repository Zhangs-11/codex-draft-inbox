#!/bin/sh
set -eu

PLUGIN_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PACKAGE_ROOT="$PLUGIN_ROOT/macos-app"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/Library/Caches}/CodexDraftInbox"
SCRATCH_PATH="$CACHE_ROOT/swift-build"
APP_PATH="$CACHE_ROOT/Codex Draft Inbox.app"

swift build \
    --package-path "$PACKAGE_ROOT" \
    --scratch-path "$SCRATCH_PATH" \
    -c release \
    --product CodexDraftInbox >/dev/null

BIN_PATH=$(swift build \
    --package-path "$PACKAGE_ROOT" \
    --scratch-path "$SCRATCH_PATH" \
    -c release \
    --show-bin-path)

install -d "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
install -m 755 "$BIN_PATH/CodexDraftInbox" "$APP_PATH/Contents/MacOS/CodexDraftInbox"
install -m 644 "$PACKAGE_ROOT/AppResources/Info.plist" "$APP_PATH/Contents/Info.plist"
install -m 644 "$PLUGIN_ROOT/scripts/draft_inbox.py" "$APP_PATH/Contents/Resources/draft_inbox.py"

install_logo() {
    destination=$1
    shift
    for candidate in "$@"; do
        if [ -f "$candidate" ]; then
            install -m 644 "$candidate" "$APP_PATH/Contents/Resources/$destination"
            return
        fi
    done
}

install_logo "codex-logo.png" \
    "$PACKAGE_ROOT/AppResources/codex-logo.png" \
    "/Applications/ChatGPT.app/Contents/Resources/icon-codex-dark-color.png" \
    "$HOME/Applications/ChatGPT.app/Contents/Resources/icon-codex-dark-color.png"
install_logo "claude-logo.png" \
    "$PACKAGE_ROOT/AppResources/claude-logo.png" \
    "/Applications/Claude.app/Contents/Resources/ion-dist/images/claude_app_icon.png" \
    "$HOME/Applications/Claude.app/Contents/Resources/ion-dist/images/claude_app_icon.png"
codesign --force --deep --sign - "$APP_PATH" >/dev/null

echo "$APP_PATH"
