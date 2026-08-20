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
PROCESS_NAME="${CODEX_DRAFT_INBOX_PROCESS_NAME:-CodexDraftInbox}"
PGREP_BIN="${CODEX_DRAFT_INBOX_PGREP:-/usr/bin/pgrep}"
PKILL_BIN="${CODEX_DRAFT_INBOX_PKILL:-/usr/bin/pkill}"
KILL_BIN="${CODEX_DRAFT_INBOX_KILL:-/bin/kill}"
OPEN_BIN="${CODEX_DRAFT_INBOX_OPEN:-/usr/bin/open}"
SLEEP_BIN="${CODEX_DRAFT_INBOX_SLEEP:-/bin/sleep}"

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

old_pids=$("$PGREP_BIN" -x "$PROCESS_NAME" 2>/dev/null || true)
if [ -n "$old_pids" ]; then
    "$PKILL_BIN" -x "$PROCESS_NAME" >/dev/null 2>&1 || true
    old_process_running=1
    wait_count=0
    while [ "$wait_count" -lt 40 ]; do
        old_process_running=0
        for old_pid in $old_pids; do
            if "$KILL_BIN" -0 "$old_pid" >/dev/null 2>&1; then
                old_process_running=1
                break
            fi
        done
        [ "$old_process_running" -eq 0 ] && break
        "$SLEEP_BIN" 0.1
        wait_count=$((wait_count + 1))
    done
    if [ "$old_process_running" -ne 0 ]; then
        echo "旧版 Codex Draft Inbox 未能退出，安装已停止。" >&2
        exit 1
    fi
fi

open_count=0
while [ "$open_count" -lt 5 ]; do
    if "$OPEN_BIN" -gja "$INSTALL_APP" >/dev/null 2>&1; then
        break
    fi
    open_count=$((open_count + 1))
    "$SLEEP_BIN" 0.25
done
if [ "$open_count" -ge 5 ]; then
    echo "Codex Draft Inbox 启动失败。" >&2
    exit 1
fi

verify_count=0
while [ "$verify_count" -lt 40 ]; do
    if "$PGREP_BIN" -x "$PROCESS_NAME" >/dev/null 2>&1; then
        exit 0
    fi
    "$SLEEP_BIN" 0.1
    verify_count=$((verify_count + 1))
done

echo "Codex Draft Inbox 启动后未检测到运行进程。" >&2
exit 1
