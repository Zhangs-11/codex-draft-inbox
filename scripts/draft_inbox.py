#!/usr/bin/env python3
"""Maintain the local Codex and Claude Code conversation inbox."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterator


STATE_VERSION = 2
NOTIFICATION_PREVIEW_LENGTH = 180
ROLLOUT_TAIL_LIMIT_BYTES = 2 * 1024 * 1024
TURN_EVENT_STATUSES = {
    "task_complete": "completed",
    "turn_aborted": "aborted",
    "turn_failed": "failed",
    "task_failed": "failed",
}
DEFAULT_SETTINGS = {
    "version": 1,
    "show_notification_draft_preview": False,
    "show_completion_popover": True,
    "language": "system",
}
SUPPORTED_LANGUAGES = {"system", "zh-Hans", "en"}
LOCALIZED_TEXT = {
    "zh-Hans": {
        "notification_title": "Codex 草稿待办",
        "draft_prefix": "草稿：{draft}",
        "task_completed": "任务已完成，等待你处理",
        "task_failed": "任务执行失败，等待你处理",
        "task_aborted": "任务已中止，等待你处理",
        "task_started": "任务已启动，等待你处理",
        "current_pending": "当前会话仍在待办中",
        "pending_count_one": "还有 {count} 个会话待办",
        "pending_count_many": "还有 {count} 个会话待办",
        "claude_session": "Claude 会话 {id}",
    },
    "en": {
        "notification_title": "Codex Draft Inbox",
        "draft_prefix": "Draft: {draft}",
        "task_completed": "Task completed and waiting for you",
        "task_failed": "Task failed and is waiting for you",
        "task_aborted": "Task aborted and is waiting for you",
        "task_started": "Task started and is waiting for you",
        "current_pending": "This conversation is still in your inbox",
        "pending_count_one": "{count} conversation is waiting for you",
        "pending_count_many": "{count} conversations are waiting for you",
        "claude_session": "Claude conversation {id}",
    },
}


def _codex_home() -> Path:
    return Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser()


def _global_state_path() -> Path:
    override = os.environ.get("CODEX_DRAFT_INBOX_GLOBAL_STATE_PATH")
    return Path(override).expanduser() if override else _codex_home() / ".codex-global-state.json"


def _thread_db_path() -> Path:
    override = os.environ.get("CODEX_DRAFT_INBOX_THREAD_DB_PATH")
    return Path(override).expanduser() if override else _codex_home() / "state_5.sqlite"


def _session_index_path() -> Path:
    override = os.environ.get("CODEX_DRAFT_INBOX_SESSION_INDEX_PATH")
    return Path(override).expanduser() if override else _codex_home() / "session_index.jsonl"


def _inbox_path() -> Path:
    override = os.environ.get("CODEX_DRAFT_INBOX_STATE_PATH")
    return Path(override).expanduser() if override else _codex_home() / "draft-inbox" / "pending.json"


def _observed_path() -> Path:
    override = os.environ.get("CODEX_DRAFT_INBOX_OBSERVED_PATH")
    return Path(override).expanduser() if override else _codex_home() / "draft-inbox" / "observed.json"


def _claude_state_path() -> Path:
    override = os.environ.get("CODEX_DRAFT_INBOX_CLAUDE_STATE_PATH")
    return Path(override).expanduser() if override else _codex_home() / "draft-inbox" / "claude.json"


def _settings_path() -> Path:
    override = os.environ.get("CODEX_DRAFT_INBOX_SETTINGS_PATH")
    return Path(override).expanduser() if override else _codex_home() / "draft-inbox" / "settings.json"


def _read_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, TypeError):
        return default


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _load_settings() -> dict[str, Any]:
    payload = _read_json(_settings_path(), DEFAULT_SETTINGS)
    if not isinstance(payload, dict):
        payload = dict(DEFAULT_SETTINGS)
    language = payload.get("language")
    if language not in SUPPORTED_LANGUAGES:
        language = "system"
    return {
        "version": 1,
        "show_notification_draft_preview": bool(payload.get("show_notification_draft_preview", False)),
        "show_completion_popover": bool(payload.get("show_completion_popover", True)),
        "language": language,
    }


def _set_boolean_setting(key: str, enabled: bool) -> bool:
    path = _settings_path()
    lock_path = path.with_suffix(path.suffix + ".lock")
    path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            previous = _load_settings()
            payload = {**previous, key: enabled}
            if previous == payload and path.is_file():
                return False
            _write_json_atomic(path, payload)
            return True
        finally:
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)


def set_notification_draft_preview(enabled: bool) -> bool:
    return _set_boolean_setting("show_notification_draft_preview", enabled)


def set_completion_popover(enabled: bool) -> bool:
    return _set_boolean_setting("show_completion_popover", enabled)


def set_language(language: str) -> bool:
    if language not in SUPPORTED_LANGUAGES:
        raise ValueError(f"Unsupported language: {language}")
    path = _settings_path()
    lock_path = path.with_suffix(path.suffix + ".lock")
    path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            previous = _load_settings()
            payload = {**previous, "language": language}
            if previous == payload and path.is_file():
                return False
            _write_json_atomic(path, payload)
            return True
        finally:
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)


def _effective_language() -> str:
    configured = str(_load_settings().get("language") or "system")
    if configured in {"zh-Hans", "en"}:
        return configured
    preferred = os.environ.get("CODEX_DRAFT_INBOX_SYSTEM_LANGUAGE", "")
    if not preferred and sys.platform == "darwin":
        try:
            result = subprocess.run(
                ["/usr/bin/defaults", "read", "-g", "AppleLanguages"],
                check=False,
                capture_output=True,
                text=True,
                timeout=1,
            )
            preferred = result.stdout
        except (OSError, subprocess.TimeoutExpired):
            preferred = ""
    return "zh-Hans" if re.search(r"(^|[^a-z])zh([^a-z]|$)", preferred, re.I) else "en"


def _tr(key: str, **values: Any) -> str:
    template = LOCALIZED_TEXT[_effective_language()][key]
    return template.format(**values)


def _pending_count_text(count: int) -> str:
    key = "pending_count_one" if count == 1 else "pending_count_many"
    return _tr(key, count=count)


def _empty_state() -> dict[str, Any]:
    return {"version": STATE_VERSION, "items": {}}


def _valid_pending_state(path: Path) -> dict[str, Any] | None:
    payload = _read_json(path, None)
    if not isinstance(payload, dict) or not isinstance(payload.get("items"), dict):
        return None
    return payload


def _load_pending_state(path: Path) -> tuple[dict[str, Any], bool]:
    primary = _valid_pending_state(path)
    if primary is not None:
        return primary, False
    backup = _valid_pending_state(path.with_suffix(path.suffix + ".bak"))
    if backup is not None:
        return backup, True
    return _empty_state(), False


@contextmanager
def _locked_state() -> Iterator[tuple[Path, dict[str, Any]]]:
    path = _inbox_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_suffix(path.suffix + ".lock")
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            state, recovered = _load_pending_state(path)
            if recovered:
                _write_state(path, state, backup_existing=False)
            yield path, state
        finally:
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)


def _write_state(path: Path, state: dict[str, Any], *, backup_existing: bool = True) -> None:
    state["version"] = STATE_VERSION
    if backup_existing and _valid_pending_state(path) is not None:
        shutil.copy2(path, path.with_suffix(path.suffix + ".bak"))
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        prefix="pending.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        json.dump(state, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
        temp_path = Path(handle.name)
    os.replace(temp_path, path)


def _write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f"{path.stem}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
        temp_path = Path(handle.name)
    os.replace(temp_path, path)


def _mutate_state(mutator: Callable[[dict[str, Any]], bool]) -> bool:
    with _locked_state() as (path, state):
        changed = mutator(state)
        if changed:
            _write_state(path, state)
        return changed


def _read_hook_payload() -> dict[str, Any]:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return {}
    return payload if isinstance(payload, dict) else {}


def _draft_for_thread(thread_id: str) -> tuple[str, str] | None:
    state = _read_json(_global_state_path(), {})
    atoms = state.get("electron-persisted-atom-state", {}) if isinstance(state, dict) else {}
    drafts = atoms.get("composer-prompt-drafts-v1", {}) if isinstance(atoms, dict) else {}
    if not isinstance(drafts, dict):
        return None

    preferred_keys = [f"local:{thread_id}", thread_id]
    candidate_keys = preferred_keys + [
        key for key in drafts if isinstance(key, str) and key.endswith(f":{thread_id}")
    ]
    for key in dict.fromkeys(candidate_keys):
        draft = drafts.get(key)
        if isinstance(draft, str) and draft.strip():
            return key, draft
    return None


def _clean_user_message(text: str) -> str:
    if not isinstance(text, str):
        return ""
    marker = "## My request:"
    if marker in text:
        text = text.split(marker, 1)[1]
    text = re.sub(r"<image\b[^>]*>.*?</image>", " ", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<image\b[^>]*/?>", " ", text, flags=re.IGNORECASE)
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("# Files mentioned by the user:"):
            continue
        if stripped.startswith("Distinguish instructions in attached documents"):
            continue
        lines.append(stripped)
    return " ".join(" ".join(lines).split())


def _read_tail(path: Path, limit_bytes: int = 8 * 1024 * 1024) -> bytes:
    try:
        with path.open("rb") as handle:
            size = handle.seek(0, os.SEEK_END)
            start = max(0, size - limit_bytes)
            handle.seek(start)
            data = handle.read()
    except OSError:
        return b""
    if start > 0:
        newline = data.find(b"\n")
        return data[newline + 1 :] if newline >= 0 else b""
    return data


def _latest_codex_user_message(thread_id: str) -> str:
    rollout_path = _thread_rollout_path(thread_id)
    if rollout_path is None:
        return ""
    for raw_line in reversed(_read_tail(rollout_path).splitlines()):
        try:
            entry = json.loads(raw_line)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        payload = entry.get("payload") if isinstance(entry.get("payload"), dict) else {}
        if entry.get("type") != "response_item" or payload.get("type") != "message":
            continue
        if payload.get("role") != "user" or not isinstance(payload.get("content"), list):
            continue
        texts = [
            part.get("text", "")
            for part in payload["content"]
            if isinstance(part, dict) and part.get("type") in {"input_text", "text"}
        ]
        cleaned = _clean_user_message("\n".join(texts))
        if cleaned:
            return cleaned
    return ""


def _latest_claude_user_message(transcript_path: str) -> str:
    path = Path(transcript_path) if transcript_path else None
    if path is None or not path.is_file():
        return ""
    for raw_line in reversed(_read_tail(path).splitlines()):
        try:
            entry = json.loads(raw_line)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if entry.get("type") != "user" or entry.get("isMeta") is True:
            continue
        message = entry.get("message") if isinstance(entry.get("message"), dict) else {}
        content = message.get("content")
        if isinstance(content, str):
            cleaned = _clean_user_message(content)
        elif isinstance(content, list):
            cleaned = _clean_user_message("\n".join(
                block.get("text", "")
                for block in content
                if isinstance(block, dict) and block.get("type") == "text"
            ))
        else:
            cleaned = ""
        if cleaned:
            return cleaned
    return ""


def _thread_row(thread_id: str) -> tuple[str, str] | None:
    db_path = _thread_db_path()
    if not db_path.is_file():
        return None
    try:
        connection = sqlite3.connect(f"file:{db_path.resolve()}?mode=ro", uri=True, timeout=1)
        try:
            row = connection.execute(
                "SELECT COALESCE(NULLIF(name, ''), NULLIF(title, ''), ''), rollout_path "
                "FROM threads WHERE id = ?",
                (thread_id,),
            ).fetchone()
        finally:
            connection.close()
    except sqlite3.Error:
        return None
    if not row:
        return None
    return str(row[0] or ""), str(row[1] or "")


def _looks_like_identifier(value: str) -> bool:
    return bool(re.fullmatch(r"(?:client-new-thread:)?[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", value, re.I))


def _session_thread_names() -> dict[str, str]:
    path = _session_index_path()
    if not path.is_file():
        return {}
    names: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return {}
    for line in lines:
        try:
            entry = json.loads(line)
        except (json.JSONDecodeError, TypeError):
            continue
        thread_id = entry.get("id") if isinstance(entry, dict) else None
        name = entry.get("thread_name") if isinstance(entry, dict) else None
        if isinstance(thread_id, str) and isinstance(name, str) and name.strip():
            names[thread_id] = _clean_user_message(name)
    return names


def _thread_title(thread_id: str, session_names: dict[str, str] | None = None) -> str:
    display_name = (session_names if session_names is not None else _session_thread_names()).get(thread_id, "")
    if display_name and not _looks_like_identifier(display_name):
        return display_name
    row = _thread_row(thread_id)
    database_title = _clean_user_message(row[0].strip()) if row else ""
    if database_title and not _looks_like_identifier(database_title):
        return database_title
    latest_user_message = _latest_codex_user_message(thread_id)
    if latest_user_message:
        return latest_user_message
    return database_title or thread_id


def _codex_thread_bindings() -> dict[str, str]:
    global_state = _read_json(_global_state_path(), {})
    atoms = global_state.get("electron-persisted-atom-state", {}) if isinstance(global_state, dict) else {}
    bindings = atoms.get("client-thread-bindings-v1", {}) if isinstance(atoms, dict) else {}
    return bindings if isinstance(bindings, dict) else {}


def _thread_id_from_transcript_path(transcript_path: str) -> str:
    if not transcript_path:
        return ""
    match = re.search(
        r"([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})\.jsonl$",
        Path(transcript_path).name,
        re.I,
    )
    return match.group(1) if match else ""


def _normalize_codex_thread_id(raw_thread_id: str, transcript_path: str = "") -> str:
    transcript_thread_id = _thread_id_from_transcript_path(transcript_path)
    if transcript_thread_id:
        return transcript_thread_id
    if _thread_row(raw_thread_id) is not None:
        return raw_thread_id
    bindings = _codex_thread_bindings()
    candidates = [raw_thread_id]
    if not raw_thread_id.startswith("client-new-thread:"):
        candidates.insert(0, f"client-new-thread:{raw_thread_id}")
    for candidate in candidates:
        mapped = bindings.get(candidate)
        if isinstance(mapped, str) and mapped:
            return mapped
    return raw_thread_id


def _thread_audience(thread_id: str) -> str:
    db_path = _thread_db_path()
    if not db_path.is_file():
        return "unknown"
    try:
        connection = sqlite3.connect(f"file:{db_path.resolve()}?mode=ro", uri=True, timeout=1)
        try:
            row = connection.execute(
                "SELECT source, thread_source, agent_path FROM threads WHERE id = ?",
                (thread_id,),
            ).fetchone()
        finally:
            connection.close()
    except sqlite3.Error:
        return "unknown"
    if row is None:
        return "missing"
    source, thread_source, agent_path = (str(row[0] or ""), str(row[1] or ""), str(row[2] or ""))
    if thread_source == "subagent" or source == "exec" or agent_path:
        return "internal"
    if thread_source == "user":
        return "user"
    return "other"


def _normalize_preview(text: str, limit: int = NOTIFICATION_PREVIEW_LENGTH) -> str:
    compact = " ".join(text.split())
    return compact if len(compact) <= limit else compact[: limit - 1] + "…"


def _notification_body(draft: str, fallback: str) -> str:
    if draft.strip() and _load_settings()["show_notification_draft_preview"]:
        return _tr("draft_prefix", draft=_normalize_preview(draft))
    return fallback


def _status_notification_fallback(status: str) -> str:
    key = {
        "completed": "task_completed",
        "failed": "task_failed",
        "aborted": "task_aborted",
    }.get(status, "task_started")
    return _tr(key)


def _apple_script_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def _notify(body: str, *, subtitle: str = "") -> None:
    if os.environ.get("CODEX_DRAFT_INBOX_DISABLE_NOTIFICATION") == "1" or sys.platform != "darwin":
        return
    title = _apple_script_string(_tr("notification_title"))
    script = f'display notification "{_apple_script_string(body)}" with title "{title}"'
    if subtitle:
        script += f' subtitle "{_apple_script_string(_normalize_preview(subtitle, 80))}"'
    try:
        subprocess.run(
            ["osascript", "-e", script],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def _draft_fingerprint(draft: str) -> str:
    return hashlib.sha256(draft.encode("utf-8")).hexdigest()


def _canonical_observation_token(token: Any) -> str | None:
    if not isinstance(token, str) or not token:
        return None
    match = re.fullmatch(r"turn:([^:]+):([0-9a-f]{64})", token)
    if match:
        return f"turn:{match.group(1)}:draft:{match.group(2)}"
    return token


def _next_completion_unread(existing: Any, status: str) -> bool:
    if status != "completed":
        return False
    if not isinstance(existing, dict) or existing.get("status") != "completed":
        return True
    return bool(existing.get("completion_unread", False))


def _remember_observation(thread_id: str, token: str, source: str) -> None:
    token = _canonical_observation_token(token) or token
    path = _observed_path()
    lock_path = path.with_suffix(path.suffix + ".lock")
    path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            observed = _read_json(path, {"version": 2, "threads": {}})
            if not isinstance(observed, dict) or not isinstance(observed.get("threads"), dict):
                observed = {"version": 2, "threads": {}}
            previous = observed["threads"].get(thread_id)
            dismissed = _canonical_observation_token(
                previous.get("dismissed_token") if isinstance(previous, dict) else None
            )
            observed["threads"][thread_id] = {
                "token": token,
                "source": source,
                "dismissed_token": dismissed if dismissed == token else None,
            }
            observed["version"] = 2
            _write_json_atomic(path, observed)
        finally:
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)


def capture(payload: dict[str, Any], *, remember: bool = True) -> bool:
    raw_thread_id = payload.get("session_id")
    if not isinstance(raw_thread_id, str) or not raw_thread_id:
        return False
    transcript_path = payload.get("transcript_path") if isinstance(payload.get("transcript_path"), str) else ""
    thread_id = _normalize_codex_thread_id(raw_thread_id, transcript_path)
    if _thread_audience(thread_id) != "user":
        return False

    draft_entry = None
    for attempt in range(4):
        draft_entry = _draft_for_thread(thread_id)
        if draft_entry is not None or attempt == 3:
            break
        time.sleep(0.1)
    draft_key, draft = draft_entry if draft_entry is not None else ("", "")
    title = _thread_title(thread_id)
    now = _now_iso()
    turn_id = payload.get("turn_id") if isinstance(payload.get("turn_id"), str) else "unknown"
    token = f"turn:{turn_id}:draft:{_draft_fingerprint(draft)}"
    completion_unread = thread_id in _unread_thread_ids(_read_json(_global_state_path(), {}))
    created = False

    def add_item(state: dict[str, Any]) -> bool:
        nonlocal created
        existing = state["items"].get(thread_id)
        fields = {
            "title": title,
            "draft": draft,
            "draft_key": draft_key,
            "status": "completed",
            "observation_token": token,
            "source": "codex",
            "lifecycle": _thread_metadata(thread_id)["lifecycle"],
            "verified_user_thread": True,
            "completion_unread": completion_unread,
        }
        if isinstance(existing, dict):
            if all(existing.get(key) == value for key, value in fields.items()):
                return False
            existing.update(fields)
            existing["last_activity_at"] = now
            return True
        created = True
        state["items"][thread_id] = {
            "thread_id": thread_id,
            "completed_at": now,
            "last_activity_at": now,
            **fields,
        }
        return True

    changed = _mutate_state(add_item)
    if created:
        body = _notification_body(draft, _tr("task_completed"))
        _notify(body, subtitle=title)
    if remember:
        _remember_observation(thread_id, token, "hook")
    return changed


def _draft_entries(global_state: dict[str, Any]) -> dict[str, tuple[str, str]]:
    atoms = global_state.get("electron-persisted-atom-state", {}) if isinstance(global_state, dict) else {}
    drafts = atoms.get("composer-prompt-drafts-v1", {}) if isinstance(atoms, dict) else {}
    if not isinstance(drafts, dict):
        return {}

    entries: dict[str, tuple[str, str]] = {}
    for key, value in drafts.items():
        if not isinstance(key, str) or not isinstance(value, str) or not value.strip():
            continue
        raw_thread_id = key.rsplit(":", 1)[-1]
        if raw_thread_id == "new-conversation":
            continue
        thread_id = _normalize_codex_thread_id(raw_thread_id)
        if _thread_audience(thread_id) != "user":
            continue
        if thread_id and (thread_id not in entries or key.startswith("local:")):
            entries[thread_id] = (key, value)
    return entries


def _unread_thread_ids(global_state: dict[str, Any]) -> set[str]:
    atoms = global_state.get("electron-persisted-atom-state", {}) if isinstance(global_state, dict) else {}
    by_host = atoms.get("unread-thread-ids-by-host-v1", {}) if isinstance(atoms, dict) else {}
    if not isinstance(by_host, dict):
        return set()
    return {
        thread_id
        for values in by_host.values()
        if isinstance(values, list)
        for thread_id in values
        if isinstance(thread_id, str)
    }


def _thread_rollout_path(thread_id: str) -> Path | None:
    db_path = _thread_db_path()
    if not db_path.is_file():
        return None
    try:
        connection = sqlite3.connect(f"file:{db_path.resolve()}?mode=ro", uri=True, timeout=1)
        try:
            row = connection.execute(
                "SELECT rollout_path FROM threads WHERE id = ?",
                (thread_id,),
            ).fetchone()
        finally:
            connection.close()
    except sqlite3.Error:
        return None
    if not row or not isinstance(row[0], str) or not row[0]:
        return None
    path = Path(row[0])
    return path if path.is_file() else None


def _latest_turn_marker(thread_id: str) -> tuple[str, str] | None:
    rollout_path = _thread_rollout_path(thread_id)
    if rollout_path is None:
        return None
    try:
        with rollout_path.open("rb") as handle:
            size = handle.seek(0, os.SEEK_END)
            start = max(0, size - ROLLOUT_TAIL_LIMIT_BYTES)
            handle.seek(start)
            data = handle.read()
    except OSError:
        return None

    if start > 0:
        newline = data.find(b"\n")
        data = data[newline + 1 :] if newline >= 0 else b""

    for raw_line in reversed(data.splitlines()):
        try:
            entry = json.loads(raw_line)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        entry_type = entry.get("type")
        payload = entry.get("payload") if isinstance(entry.get("payload"), dict) else {}
        if entry_type == "event_msg":
            terminal_status = TURN_EVENT_STATUSES.get(payload.get("type"))
            if terminal_status:
                return terminal_status, str(payload.get("turn_id") or "unknown")
        if entry_type == "turn_context":
            return "running", str(payload.get("turn_id") or "unknown")
    return None


def _recent_thread_ids(since_ms: int) -> tuple[set[str], int]:
    db_path = _thread_db_path()
    if not db_path.is_file():
        return set(), since_ms
    try:
        connection = sqlite3.connect(f"file:{db_path.resolve()}?mode=ro", uri=True, timeout=1)
        try:
            rows = connection.execute(
                "SELECT id, updated_at_ms FROM threads "
                "WHERE archived = 0 AND preview <> '' AND updated_at_ms >= ? "
                "AND source <> 'exec' AND thread_source = 'user' AND agent_path IS NULL",
                (since_ms,),
            ).fetchall()
        finally:
            connection.close()
    except sqlite3.Error:
        return set(), since_ms
    ids = {str(row[0]) for row in rows if row and row[0]}
    newest = max((int(row[1]) for row in rows if row and row[1]), default=since_ms)
    return ids, newest


def _pending_by_thread() -> dict[str, dict[str, Any]]:
    return {
        str(item.get("thread_id")): item
        for item in pending_items()
        if item.get("thread_id")
    }


def _normalize_pending_thread_ids() -> None:
    removed_thread_ids: set[str] = set()
    session_names = _session_thread_names()

    def normalize(state: dict[str, Any]) -> bool:
        changed = False
        items = state["items"]
        for thread_id, item in list(items.items()):
            if not isinstance(item, dict):
                continue
            if item.get("source") == "claude":
                title = str(item.get("title") or "")
                is_empty_placeholder = (
                    not str(item.get("draft") or "").strip()
                    and bool(
                        re.fullmatch(
                            r"Claude (?:会话|conversation) [0-9a-f]{8}",
                            title,
                            re.I,
                        )
                    )
                )
                if _is_internal_claude_message(title) or is_empty_placeholder:
                    items.pop(thread_id, None)
                    removed_thread_ids.add(str(thread_id))
                    changed = True
                continue
            thread_id = str(thread_id)
            normalized = _normalize_codex_thread_id(thread_id)
            audience = _thread_audience(normalized)
            if thread_id == "new-conversation" or audience in {"internal", "other"}:
                items.pop(thread_id, None)
                removed_thread_ids.add(thread_id)
                changed = True
                continue
            moved = dict(item)
            moved["thread_id"] = normalized
            if audience == "user":
                moved["title"] = _thread_title(normalized, session_names)
                moved["verified_user_thread"] = True
            elif audience == "missing":
                title = str(moved.get("title") or "")
                has_legacy_user_evidence = (
                    normalized in session_names
                    or (
                        bool(title.strip())
                        and title != "已删除的会话"
                        and not _looks_like_identifier(title)
                    )
                )
                if moved.get("verified_user_thread") is not True and not has_legacy_user_evidence:
                    items.pop(thread_id, None)
                    removed_thread_ids.add(thread_id)
                    changed = True
                    continue
                moved["lifecycle"] = "deleted"
                moved["verified_user_thread"] = True
            existing = items.get(normalized)
            if normalized != thread_id and isinstance(existing, dict):
                if moved.get("draft") and not existing.get("draft"):
                    existing["draft"] = moved["draft"]
                    existing["draft_key"] = moved.get("draft_key", "")
                if moved.get("status") == "running":
                    existing["status"] = "running"
                if moved.get("completion_unread") is True:
                    existing["completion_unread"] = True
                moved_activity = str(moved.get("last_activity_at") or moved.get("completed_at") or "")
                existing_activity = str(existing.get("last_activity_at") or existing.get("completed_at") or "")
                if moved_activity > existing_activity:
                    existing["last_activity_at"] = moved_activity
                if audience == "user":
                    existing["title"] = _thread_title(normalized, session_names)
            else:
                items[normalized] = moved
            if normalized != thread_id:
                items.pop(thread_id, None)
                removed_thread_ids.add(thread_id)
                changed = True
            elif moved != item:
                items[thread_id] = moved
                changed = True
        return changed

    _mutate_state(normalize)
    if removed_thread_ids:
        _remove_observed_threads(removed_thread_ids)


def _remove_observed_threads(thread_ids: set[str]) -> None:
    path = _observed_path()
    if not path.is_file():
        return
    lock_path = path.with_suffix(path.suffix + ".lock")
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            observed = _read_json(path, {})
            threads = observed.get("threads") if isinstance(observed, dict) else None
            if not isinstance(threads, dict):
                return
            changed = False
            for thread_id in thread_ids:
                changed = threads.pop(thread_id, None) is not None or changed
            if changed:
                _write_json_atomic(path, observed)
        finally:
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)


def _remove_pending_threads(thread_ids: set[str]) -> bool:
    def remove(state: dict[str, Any]) -> bool:
        changed = False
        for thread_id in thread_ids:
            changed = state["items"].pop(thread_id, None) is not None or changed
        return changed

    changed = _mutate_state(remove)
    if changed:
        _remove_observed_threads(thread_ids)
    return changed


def _observation_is_dismissed(thread_id: str, token: str) -> bool:
    observed = _read_json(_observed_path(), {})
    threads = observed.get("threads") if isinstance(observed, dict) else None
    entry = threads.get(thread_id) if isinstance(threads, dict) else None
    return (
        isinstance(entry, dict)
        and _canonical_observation_token(entry.get("dismissed_token"))
        == _canonical_observation_token(token)
    )


def _upsert_external_pending(
    thread_id: str,
    *,
    title: str,
    draft: str,
    status: str,
    token: str,
    external_session_id: str,
    cwd: str,
) -> bool:
    now = _now_iso()

    def update(state: dict[str, Any]) -> bool:
        existing = state["items"].get(thread_id)
        completion_unread = _next_completion_unread(existing, status)
        fields = {
            "title": title,
            "draft": draft,
            "draft_key": f"claude:{external_session_id}",
            "status": status,
            "observation_token": token,
            "source": "claude",
            "lifecycle": "active",
            "external_session_id": external_session_id,
            "cwd": cwd,
            "completion_unread": completion_unread,
        }
        if isinstance(existing, dict):
            if all(existing.get(key) == value for key, value in fields.items()):
                return False
            existing.update(fields)
            existing["last_activity_at"] = now
            return True
        state["items"][thread_id] = {
            "thread_id": thread_id,
            "completed_at": now,
            "last_activity_at": now,
            **fields,
        }
        return True

    return _mutate_state(update)


def _is_internal_claude_message(message: str) -> bool:
    compact = " ".join(message.split())
    return (
        compact.startswith("[工作环境] 输出目录:")
        and "[任务参数]" in compact
        and "[产出协议]" in compact
        and ".workspaces/" in compact
        and bool(re.search(r"/slot-[^/\s]+/workspace(?:\s|$)", compact))
    )


def _sanitize_internal_claude_sessions() -> None:
    state_path = _claude_state_path()
    if not state_path.is_file():
        return
    lock_path = state_path.with_suffix(state_path.suffix + ".lock")
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            state = _load_claude_state()
            changed = False
            for session_id, session in list(state["sessions"].items()):
                if not isinstance(session, dict):
                    continue
                if not _is_internal_claude_message(str(session.get("last_user_message") or "")):
                    continue
                state["sessions"][session_id] = {
                    "counter": int(session.get("counter") or 1),
                    "ignored": True,
                    "status": "ignored",
                }
                state["drafts"].pop(f"claude:{session_id}", None)
                changed = True
            if changed:
                _write_json_atomic(state_path, state)
        finally:
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)


def _load_claude_state() -> dict[str, Any]:
    state = _read_json(_claude_state_path(), {"version": 1, "sessions": {}, "drafts": {}})
    if not isinstance(state, dict):
        return {"version": 1, "sessions": {}, "drafts": {}}
    if not isinstance(state.get("sessions"), dict):
        state["sessions"] = {}
    if not isinstance(state.get("drafts"), dict):
        state["drafts"] = {}
    state["version"] = 1
    return state


def handle_claude_event(payload: dict[str, Any]) -> bool:
    event = payload.get("hook_event_name")
    session_id = payload.get("session_id")
    if event not in {"SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "SessionEnd"}:
        return False
    if not isinstance(session_id, str) or not session_id:
        return False

    thread_id = f"claude:{session_id}"
    state_path = _claude_state_path()
    lock_path = state_path.with_suffix(state_path.suffix + ".lock")
    state_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            state = _load_claude_state()
            session = state["sessions"].get(session_id)
            if not isinstance(session, dict):
                session = {"counter": 0}
            previous_status = str(session.get("status") or "")
            if event == "UserPromptSubmit":
                session["counter"] = int(session.get("counter") or 0) + 1
            prompt = payload.get("prompt") if isinstance(payload.get("prompt"), str) else ""
            transcript_path = payload.get("transcript_path") if isinstance(payload.get("transcript_path"), str) else ""
            latest_message = _clean_user_message(prompt) or _latest_claude_user_message(transcript_path)
            if latest_message:
                session["last_user_message"] = latest_message
            is_internal = (
                bool(payload.get("agent_id"))
                or bool(session.get("ignored"))
                or _is_internal_claude_message(str(session.get("last_user_message") or ""))
            )
            if is_internal:
                session["ignored"] = True
            session["cwd"] = str(payload.get("cwd") or session.get("cwd") or "")
            session["transcript_path"] = transcript_path or str(session.get("transcript_path") or "")
            state["sessions"][session_id] = session
            draft = str(state["drafts"].get(thread_id) or "")
            counter = int(session.get("counter") or 1)
            token = f"claude:{session_id}:{counter}:draft:{_draft_fingerprint(draft)}"
            title = str(
                session.get("last_user_message")
                or _tr("claude_session", id=session_id[:8])
            )
            cwd = str(session.get("cwd") or "")
            if event == "Stop":
                status = "completed"
            elif event == "StopFailure":
                status = "failed"
            elif event == "SessionEnd":
                status = previous_status if previous_status in {"completed", "failed", "aborted"} else "aborted"
            elif event == "SessionStart" and previous_status in {"completed", "failed", "aborted"}:
                status = previous_status
            else:
                status = "running"
            defer_pending = event == "SessionStart" or (
                event == "SessionEnd" and not str(session.get("last_user_message") or "").strip()
            )
            session["status"] = status
            if is_internal:
                session = {
                    "counter": counter,
                    "ignored": True,
                    "status": "ignored",
                }
            state["sessions"][session_id] = session
            if is_internal:
                state["drafts"].pop(thread_id, None)
            _write_json_atomic(state_path, state)
        finally:
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)

    if is_internal:
        _remove_pending_threads({thread_id})
        return False
    if defer_pending:
        return False
    if _observation_is_dismissed(thread_id, token):
        return False
    pending_before = thread_id in _pending_by_thread()
    changed = _upsert_external_pending(
        thread_id,
        title=title,
        draft=draft,
        status=status,
        token=token,
        external_session_id=session_id,
        cwd=cwd,
    )
    if changed and not pending_before:
        _notify(f"Claude：{_normalize_preview(title)}", subtitle="Claude Code")
    return changed


def set_claude_draft(thread_id: str, text: str) -> bool:
    if not thread_id.startswith("claude:"):
        return False
    session_id = thread_id.split(":", 1)[1]
    state_path = _claude_state_path()
    lock_path = state_path.with_suffix(state_path.suffix + ".lock")
    state_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            state = _load_claude_state()
            session = state["sessions"].get(session_id)
            if not isinstance(session, dict):
                return False
            state["drafts"][thread_id] = text
            counter = int(session.get("counter") or 1)
            token = f"claude:{session_id}:{counter}:draft:{_draft_fingerprint(text)}"
            title = str(
                session.get("last_user_message")
                or _tr("claude_session", id=session_id[:8])
            )
            cwd = str(session.get("cwd") or "")
            status = str(session.get("status") or "draft")
            _write_json_atomic(state_path, state)
        finally:
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)
    if _observation_is_dismissed(thread_id, token):
        return False
    return _upsert_external_pending(
        thread_id,
        title=title,
        draft=text,
        status=status,
        token=token,
        external_session_id=session_id,
        cwd=cwd,
    )


def _thread_metadata(thread_id: str) -> dict[str, Any]:
    db_path = _thread_db_path()
    if not db_path.is_file():
        return {"lifecycle": "unknown", "updated_at_ms": 0}
    try:
        connection = sqlite3.connect(f"file:{db_path.resolve()}?mode=ro", uri=True, timeout=1)
        try:
            row = connection.execute(
                "SELECT archived, preview, updated_at_ms FROM threads WHERE id = ?",
                (thread_id,),
            ).fetchone()
        finally:
            connection.close()
    except sqlite3.Error:
        return {"lifecycle": "unknown", "updated_at_ms": 0}
    if row is None:
        return {"lifecycle": "deleted", "updated_at_ms": 0}
    archived, preview, updated_at_ms = row
    if int(archived or 0) != 0:
        lifecycle = "archived"
    elif not str(preview or "").strip():
        lifecycle = "unavailable"
    else:
        lifecycle = "active"
    return {"lifecycle": lifecycle, "updated_at_ms": int(updated_at_ms or 0)}


def _update_pending_lifecycle(thread_id: str, lifecycle: str) -> bool:
    def update(state: dict[str, Any]) -> bool:
        existing = state["items"].get(thread_id)
        if not isinstance(existing, dict) or existing.get("lifecycle") == lifecycle:
            return False
        previous_lifecycle = existing.get("lifecycle")
        existing["lifecycle"] = lifecycle
        if previous_lifecycle is None:
            existing["last_activity_at"] = str(
                existing.get("last_activity_at") or existing.get("completed_at") or _now_iso()
            )
        else:
            existing["last_activity_at"] = _now_iso()
        return True

    return _mutate_state(update)


def _upsert_pending(
    thread_id: str,
    *,
    draft_key: str,
    draft: str,
    status: str,
    token: str,
    lifecycle: str,
    title: str | None = None,
    completion_unread: bool = False,
) -> bool:
    resolved_title = title or _thread_title(thread_id)
    now = _now_iso()

    def update(state: dict[str, Any]) -> bool:
        existing = state["items"].get(thread_id)
        title = resolved_title
        if (
            isinstance(existing, dict)
            and lifecycle != "active"
            and (not title or title == thread_id)
        ):
            title = str(existing.get("title") or thread_id)
        fields = {
            "title": title,
            "draft": draft,
            "draft_key": draft_key,
            "status": status,
            "observation_token": token,
            "lifecycle": lifecycle,
            "source": "codex",
            "verified_user_thread": True,
            "completion_unread": completion_unread,
        }
        if isinstance(existing, dict):
            if all(existing.get(key) == value for key, value in fields.items()):
                return False
            only_read_state_changed = all(
                key == "completion_unread" or existing.get(key) == value
                for key, value in fields.items()
            )
            existing.update(fields)
            if not only_read_state_changed:
                existing["last_activity_at"] = now
            return True
        state["items"][thread_id] = {
            "thread_id": thread_id,
            "completed_at": now,
            "last_activity_at": now,
            **fields,
        }
        return True

    return _mutate_state(update)


def _dismiss_observation(thread_id: str, token: str) -> None:
    token = _canonical_observation_token(token) or token
    path = _observed_path()
    lock_path = path.with_suffix(path.suffix + ".lock")
    path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            observed = _read_json(path, {"version": 2, "threads": {}})
            if not isinstance(observed, dict) or not isinstance(observed.get("threads"), dict):
                observed = {"version": 2, "threads": {}}
            entry = observed["threads"].get(thread_id)
            if not isinstance(entry, dict):
                entry = {"token": token, "source": "manual"}
            entry["dismissed_token"] = token
            observed["threads"][thread_id] = entry
            observed["version"] = 2
            _write_json_atomic(path, observed)
        finally:
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)


def sync_pending_drafts() -> int:
    global_state = _read_json(_global_state_path(), {})
    session_names = _session_thread_names()
    drafts = _draft_entries(global_state)
    unread = _unread_thread_ids(global_state)
    _sanitize_internal_claude_sessions()
    _normalize_pending_thread_ids()
    pending = _pending_by_thread()
    codex_pending = {
        thread_id: item
        for thread_id, item in pending.items()
        if item.get("source") != "claude"
    }
    observed_path = _observed_path()
    lock_path = observed_path.with_suffix(observed_path.suffix + ".lock")
    observed_path.parent.mkdir(parents=True, exist_ok=True)
    captured = 0

    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            observed = _read_json(observed_path, {})
            first_run = observed.get("version") != 2 or not isinstance(observed.get("threads"), dict)
            if first_run:
                observed = {"version": 2, "threads": {}, "last_updated_at_ms": 0}
            observed_before = json.dumps(observed, ensure_ascii=False, sort_keys=True)
            observed_threads = observed["threads"]
            now_ms = int(time.time() * 1000)
            since_ms = now_ms - 24 * 60 * 60 * 1000 if first_run else max(
                0, int(observed.get("last_updated_at_ms") or 0) - 2000
            )
            recent_ids, newest_updated_at_ms = _recent_thread_ids(since_ms)
            candidates = recent_ids | set(drafts) | set(codex_pending)

            for thread_id in candidates:
                draft_key, draft = drafts.get(thread_id, ("", ""))
                metadata = _thread_metadata(thread_id)
                lifecycle = str(metadata["lifecycle"])
                already_pending = thread_id in codex_pending
                if already_pending:
                    _update_pending_lifecycle(thread_id, lifecycle)
                elif not draft and lifecycle != "active":
                    continue
                marker = _latest_turn_marker(thread_id)
                if marker:
                    status = marker[0]
                    source = "rollout"
                    turn_id = marker[1]
                elif draft:
                    status = "draft"
                    source = "draft"
                    turn_id = "none"
                elif thread_id in unread:
                    status = "completed"
                    source = "unread"
                    turn_id = "unread"
                else:
                    continue

                token = f"turn:{turn_id}:draft:{_draft_fingerprint(draft)}"
                previous = observed_threads.get(thread_id)
                previous_token = _canonical_observation_token(
                    previous.get("token") if isinstance(previous, dict) else None
                )
                dismissed_token = _canonical_observation_token(
                    previous.get("dismissed_token") if isinstance(previous, dict) else None
                )
                if previous_token != token:
                    dismissed_token = None

                should_show = (
                    already_pending
                    or bool(draft)
                    or status == "running"
                    or (not first_run and previous_token != token)
                )
                if dismissed_token == token:
                    should_show = False

                if not should_show:
                    observed_threads[thread_id] = {
                        "token": token,
                        "source": source,
                        "dismissed_token": dismissed_token,
                    }
                    continue

                _upsert_pending(
                    thread_id,
                    draft_key=draft_key,
                    draft=draft,
                    status=status,
                    token=token,
                    lifecycle=lifecycle,
                    title=_thread_title(thread_id, session_names),
                    completion_unread=status == "completed" and thread_id in unread,
                )
                if not already_pending:
                    captured += 1
                    body = _notification_body(draft, _status_notification_fallback(status))
                    _notify(body, subtitle=_thread_title(thread_id, session_names))
                    codex_pending[thread_id] = {"thread_id": thread_id}
                observed_threads[thread_id] = {
                    "token": token,
                    "source": source,
                    "dismissed_token": dismissed_token,
                }

            observed["version"] = 2
            observed["last_updated_at_ms"] = max(
                int(observed.get("last_updated_at_ms") or 0),
                newest_updated_at_ms,
            )
            if json.dumps(observed, ensure_ascii=False, sort_keys=True) != observed_before:
                _write_json_atomic(observed_path, observed)
        finally:
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)

    return captured


def clear(thread_id: str, *, manual: bool = False) -> bool:
    if not manual:
        return False
    token: str | None = None

    def remove_item(state: dict[str, Any]) -> bool:
        nonlocal token
        removed = state["items"].pop(thread_id, None)
        if isinstance(removed, dict) and isinstance(removed.get("observation_token"), str):
            token = removed["observation_token"]
        return removed is not None

    changed = _mutate_state(remove_item)
    if manual and token:
        _dismiss_observation(thread_id, token)
    return changed


def mark_read(thread_id: str) -> bool:
    def update(state: dict[str, Any]) -> bool:
        existing = state["items"].get(thread_id)
        if not isinstance(existing, dict) or existing.get("completion_unread") is not True:
            return False
        existing["completion_unread"] = False
        return True

    return _mutate_state(update)


def pending_items() -> list[dict[str, Any]]:
    state, _ = _load_pending_state(_inbox_path())
    items = state.get("items", {}) if isinstance(state, dict) else {}
    if not isinstance(items, dict):
        return []
    valid_items = [item for item in items.values() if isinstance(item, dict)]
    return sorted(
        valid_items,
        key=lambda item: str(item.get("last_activity_at") or item.get("completed_at", "")),
        reverse=True,
    )


def remind(payload: dict[str, Any]) -> None:
    items = pending_items()
    if not items:
        return
    current_thread = payload.get("session_id")
    current = next((item for item in items if item.get("thread_id") == current_thread), None)
    if current:
        _notify(
            _notification_body(str(current.get("draft", "")), _tr("current_pending")),
            subtitle=str(current.get("title", current_thread)),
        )
        return
    newest = items[0]
    newest_draft = str(newest.get("draft", ""))
    fallback = _pending_count_text(len(items))
    _notify(
        _notification_body(newest_draft, fallback),
        subtitle=str(newest.get("title", "")),
    )


def render_markdown(items: list[dict[str, Any]]) -> str:
    if not items:
        return "目前没有草稿待办。"
    lines = [f"共有 {len(items)} 个草稿待办：", ""]
    for item in items:
        lines.extend(
            [
                f"- {item.get('title') or item.get('thread_id')}",
                f"  - 草稿：{_normalize_preview(str(item.get('draft', '')), 500)}",
                f"  - 会话状态：{item.get('lifecycle', 'active')}",
                f"  - task_id：`{item.get('thread_id', '')}`",
                f"  - 最近活动：{item.get('last_activity_at') or item.get('completed_at', '')}",
            ]
        )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("capture")
    subparsers.add_parser("remind")
    subparsers.add_parser("sync")
    subparsers.add_parser("claude-event")
    settings_parser = subparsers.add_parser("settings")
    settings_parser.add_argument("--json", action="store_true")
    preview_parser = subparsers.add_parser("set-notification-preview")
    preview_parser.add_argument("--enabled", choices=("true", "false"), required=True)
    completion_parser = subparsers.add_parser("set-completion-popover")
    completion_parser.add_argument("--enabled", choices=("true", "false"), required=True)
    language_parser = subparsers.add_parser("set-language")
    language_parser.add_argument("--language", choices=tuple(sorted(SUPPORTED_LANGUAGES)), required=True)
    claude_draft_parser = subparsers.add_parser("set-claude-draft")
    claude_draft_parser.add_argument("--thread-id", required=True)
    claude_draft_parser.add_argument("--text", default="")
    clear_parser = subparsers.add_parser("clear")
    clear_parser.add_argument("--thread-id")
    clear_parser.add_argument("--manual", action="store_true")
    read_parser = subparsers.add_parser("mark-read")
    read_parser.add_argument("--thread-id", required=True)
    list_parser = subparsers.add_parser("list")
    list_parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    if args.command == "list":
        items = pending_items()
        print(json.dumps(items, ensure_ascii=False, indent=2) if args.json else render_markdown(items))
        return 0

    if args.command == "settings":
        settings = _load_settings()
        print(json.dumps(settings, ensure_ascii=False, indent=2) if args.json else settings)
        return 0

    if args.command == "set-notification-preview":
        set_notification_draft_preview(args.enabled == "true")
        return 0

    if args.command == "set-completion-popover":
        set_completion_popover(args.enabled == "true")
        return 0

    if args.command == "set-language":
        set_language(args.language)
        return 0

    if args.command == "sync":
        sync_pending_drafts()
        return 0

    if args.command == "set-claude-draft":
        return 0 if set_claude_draft(args.thread_id, args.text) else 1

    if args.command == "mark-read":
        mark_read(args.thread_id)
        return 0

    payload = _read_hook_payload() if not getattr(args, "thread_id", None) else {}
    if args.command == "claude-event":
        handle_claude_event(payload)
    elif args.command == "capture":
        capture(payload)
    elif args.command == "remind":
        remind(payload)
    elif args.command == "clear":
        if not args.manual:
            return 0
        thread_id = args.thread_id or payload.get("session_id")
        if isinstance(thread_id, str) and thread_id:
            clear(thread_id, manual=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
