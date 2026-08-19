#!/bin/sh
set -eu

PLUGIN_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PACKAGE_ROOT="$PLUGIN_ROOT/macos-app"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/Library/Caches}/CodexDraftInbox"
SCRATCH_PATH="$CACHE_ROOT/swift-test"

swift build \
    --package-path "$PACKAGE_ROOT" \
    --scratch-path "$SCRATCH_PATH" \
    -c debug \
    --product CodexDraftInboxSelfTest

BIN_PATH=$(swift build \
    --package-path "$PACKAGE_ROOT" \
    --scratch-path "$SCRATCH_PATH" \
    -c debug \
    --show-bin-path)

"$BIN_PATH/CodexDraftInboxSelfTest"
