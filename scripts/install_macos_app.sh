#!/bin/sh
set -eu

PLUGIN_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CACHE_APP=$("$PLUGIN_ROOT/scripts/build_macos_app.sh")
INSTALL_ROOT="$HOME/Applications"
INSTALL_APP="$INSTALL_ROOT/Codex Draft Inbox.app"

install -d "$INSTALL_ROOT"
ditto "$CACHE_APP" "$INSTALL_APP"
"$PLUGIN_ROOT/scripts/configure_launch_agent.sh" "$INSTALL_APP"

echo "$INSTALL_APP"
