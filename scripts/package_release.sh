#!/bin/sh
set -eu

PLUGIN_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
VERSION=${1:-$(plutil -extract CFBundleShortVersionString raw "$PLUGIN_ROOT/macos-app/AppResources/Info.plist")}
OUTPUT_ROOT=${2:-"$PLUGIN_ROOT/dist"}
ARCHIVE="$OUTPUT_ROOT/Codex-Draft-Inbox-v$VERSION-macos.zip"
PACKAGE_DIR=$(mktemp -d)
STAGING="$PACKAGE_DIR/Codex Draft Inbox v$VERSION"
trap 'rm -rf -- "$PACKAGE_DIR"' EXIT

APP_PATH=$(CODEX_DRAFT_INBOX_SKIP_BRAND_ASSETS=1 "$PLUGIN_ROOT/scripts/build_macos_app.sh")
install -d "$STAGING/scripts" "$OUTPUT_ROOT"
ditto "$APP_PATH" "$STAGING/Codex Draft Inbox.app"
install -m 755 "$PLUGIN_ROOT/scripts/install_release.sh" "$STAGING/scripts/install_release.sh"
install -m 755 "$PLUGIN_ROOT/scripts/uninstall.sh" "$STAGING/scripts/uninstall.sh"
install -m 644 "$PLUGIN_ROOT/scripts/install_claude_hooks.py" "$STAGING/scripts/install_claude_hooks.py"
install -m 644 "$PLUGIN_ROOT/README.md" "$STAGING/README.md"
install -m 644 "$PLUGIN_ROOT/LICENSE" "$STAGING/LICENSE"
ditto -c -k --sequesterRsrc --keepParent "$STAGING" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"

echo "$ARCHIVE"
