#!/bin/sh
set -eu

PLUGIN_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PACKAGE_ROOT="$PLUGIN_ROOT/macos-app"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/Library/Caches}/CodexDraftInbox"
SCRATCH_PATH="$CACHE_ROOT/swift-build"
APP_PATH="$CACHE_ROOT/Codex Draft Inbox.app"

if [ "${CODEX_DRAFT_INBOX_UNIVERSAL:-0}" = "1" ]; then
    UNIVERSAL_BIN="$CACHE_ROOT/CodexDraftInbox-universal"
    for target_arch in arm64 x86_64; do
        arch_scratch="$SCRATCH_PATH-$target_arch"
        swift build \
            --package-path "$PACKAGE_ROOT" \
            --scratch-path "$arch_scratch" \
            -c release \
            --product CodexDraftInbox \
            --arch "$target_arch" >/dev/null
        arch_bin=$(swift build \
            --package-path "$PACKAGE_ROOT" \
            --scratch-path "$arch_scratch" \
            -c release \
            --show-bin-path \
            --arch "$target_arch")
        install -m 755 "$arch_bin/CodexDraftInbox" "$CACHE_ROOT/CodexDraftInbox-$target_arch"
    done
    lipo -create \
        "$CACHE_ROOT/CodexDraftInbox-arm64" \
        "$CACHE_ROOT/CodexDraftInbox-x86_64" \
        -output "$UNIVERSAL_BIN"
    EXECUTABLE_PATH="$UNIVERSAL_BIN"
else
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
    EXECUTABLE_PATH="$BIN_PATH/CodexDraftInbox"
fi

rm -rf -- "$APP_PATH"
install -d "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
install -m 755 "$EXECUTABLE_PATH" "$APP_PATH/Contents/MacOS/CodexDraftInbox"
install -m 644 "$PACKAGE_ROOT/AppResources/Info.plist" "$APP_PATH/Contents/Info.plist"
install -m 644 "$PLUGIN_ROOT/scripts/draft_inbox.py" "$APP_PATH/Contents/Resources/draft_inbox.py"
install -m 644 \
    "$PACKAGE_ROOT/AppResources/com.zhangshuo.codex-draft-inbox.plist" \
    "$APP_PATH/Contents/Resources/com.zhangshuo.codex-draft-inbox.plist"

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

if [ "${CODEX_DRAFT_INBOX_SKIP_BRAND_ASSETS:-0}" != "1" ]; then
    install_logo "codex-logo.png" \
        "$PACKAGE_ROOT/AppResources/codex-logo.png" \
        "/Applications/ChatGPT.app/Contents/Resources/icon-codex-dark-color.png" \
        "$HOME/Applications/ChatGPT.app/Contents/Resources/icon-codex-dark-color.png"
    install_logo "claude-logo.png" \
        "$PACKAGE_ROOT/AppResources/claude-logo.png" \
        "/Applications/Claude.app/Contents/Resources/ion-dist/images/claude_app_icon.png" \
        "$HOME/Applications/Claude.app/Contents/Resources/ion-dist/images/claude_app_icon.png"
fi
codesign --force --deep --sign - "$APP_PATH" >/dev/null

echo "$APP_PATH"
