from __future__ import annotations

import re
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from .process import run_cmd
from .state import TASK_EVENTS, map_task_event_to_state

CWD_RE = re.compile(r'"cwd":"([^"]*)"')


@dataclass(frozen=True)
class InferKeys:
    cache_state_key: str
    cache_updated_key: str
    session_file_key: str
    session_file_updated_key: str

def cksum_value(value: str) -> str:
    result = run_cmd(["cksum"], text_input=value)
    parts = result.out.strip().split()
    if parts:
        return parts[0]
    return ""

def is_non_negative_integer(value: str) -> bool:
    return value.isdigit()

def first_line(path: str) -> str:
    try:
        with Path(path).open("r", encoding="utf-8", errors="ignore") as stream:
            return stream.readline().rstrip("\n")
    except OSError:
        return ""

def session_meta_cwd_from_file(path: str) -> str:
    line = first_line(path)

    if '"type":"session_meta"' not in line:
        return ""

    match = CWD_RE.search(line)

    if not match:
        return ""
    return match.group(1)

def task_event_from_line(line: str) -> str:
    if '"type":"event_msg"' not in line:
        return ""

    if '"payload":{"type":"' not in line:
        return ""

    for event in TASK_EVENTS:
        if f'"payload":{{"type":"{event}"' in line:
            return event
    return ""

def session_latest_task_event(path: str) -> str:
    latest = ""
    try:
        with Path(path).open("r", encoding="utf-8", errors="ignore") as stream:
            for line in stream:
                event = task_event_from_line(line.rstrip("\n"))
                if event:
                    latest = event
    except OSError:
        return ""
    return latest

def recent_session_files(
    sessions_dir: str,
    lookback_minutes: int,
    scan_limit: int,
) -> list[str]:

    root = Path(sessions_dir)

    if not root.is_dir() or scan_limit <= 0 or lookback_minutes <= 0:
        return []

    min_mtime = time.time() - (lookback_minutes * 60)
    files: list[tuple[float, str]] = []

    for path in root.rglob("*.jsonl"):
        if not path.is_file():
            continue

        try:
            mtime = path.stat().st_mtime
        except OSError:
            continue

        if mtime >= min_mtime:
            files.append((mtime, str(path)))

    files.sort(key=lambda pair: pair[0], reverse=True)
    return [path for _, path in files[:scan_limit]]

def find_recent_session_file_for_cwd(
    pane_path: str,
    sessions_dir: str,
    lookback_minutes: int,
    scan_limit: int,
) -> str:

    if not pane_path:
        return ""
    
    for session_file in recent_session_files(sessions_dir, lookback_minutes, scan_limit):
        if session_meta_cwd_from_file(session_file) == pane_path:
            return session_file
    return ""

def infer_keys(pane_path: str, pane_window_ref: str) -> InferKeys:
    cache_suffix = cksum_value(f"{pane_path}\t{pane_window_ref}")

    return InferKeys(
        cache_state_key=f"TMUX_CODEX_CWD_{cache_suffix}_INFERRED_STATE",
        cache_updated_key=f"TMUX_CODEX_CWD_{cache_suffix}_INFERRED_UPDATED_AT",
        session_file_key=f"TMUX_CODEX_CWD_{cache_suffix}_SESSION_FILE",
        session_file_updated_key=f"TMUX_CODEX_CWD_{cache_suffix}_SESSION_FILE_UPDATED_AT",
    )

def has_valid_mapped_file(mapped_file: str, pane_path: str) -> bool:
    if not mapped_file:
        return False

    if not Path(mapped_file).is_file():
        return False

    return session_meta_cwd_from_file(mapped_file) == pane_path

def window_ref_matches(
    pane_path: str,
    pane_window_ref: str,
    tmux_get_env: Callable[[str], str],
) -> bool:

    cwd_suffix = cksum_value(pane_path)
    if not cwd_suffix:
        return False
    
    key = f"TMUX_CODEX_CWD_{cwd_suffix}_WINDOW_REF"
    cached = tmux_get_env(key)
    
    return cached != "" and cached == pane_window_ref

def cached_inferred_state(
    keys: InferKeys,
    session_cache_seconds: int,
    now_epoch: int,
    tmux_get_env: Callable[[str], str],
) -> tuple[bool, str]:

    cached_state = tmux_get_env(keys.cache_state_key)
    cached_updated = tmux_get_env(keys.cache_updated_key)

    if session_cache_seconds <= 0 or not is_non_negative_integer(cached_updated):
        return (False, "")

    if now_epoch - int(cached_updated) > session_cache_seconds:
        return (False, "")

    if cached_state in {"R", "W"}:
        return (True, cached_state)

    return (True, "")

def unique_matching_session_file(
    pane_path: str,
    sessions_dir: str,
    lookback_minutes: int,
    scan_limit: int,
) -> str:

    matched_file = ""
    match_count = 0

    for session_file in recent_session_files(sessions_dir, lookback_minutes, scan_limit):

        if session_meta_cwd_from_file(session_file) != pane_path:
            continue

        match_count += 1
        if match_count == 1:
            matched_file = session_file
            continue

        break

    if match_count == 1:
        return matched_file
    return ""

def infer_event_from_sessions(
    mapped_file: str,
    pane_path: str,
    keys: InferKeys,
    now_epoch: int,
    sessions_dir: str,
    lookback_minutes: int,
    scan_limit: int,
    tmux_set_env: Callable[[str, str], None],
) -> str:

    if mapped_file:
        return session_latest_task_event(mapped_file)

    matched_file = unique_matching_session_file(
        pane_path,
        sessions_dir,
        lookback_minutes,
        scan_limit,
    )

    if not matched_file:
        return ""
    
    tmux_set_env(keys.session_file_key, matched_file)
    tmux_set_env(keys.session_file_updated_key, str(now_epoch))
    return session_latest_task_event(matched_file)

def infer_state_from_sessions(
    pane_path: str,
    pane_window_ref: str,
    sessions_dir: str,
    lookback_minutes: int,
    scan_limit: int,
    session_cache_seconds: int,
    tmux_get_env: Callable[[str], str],
    tmux_set_env: Callable[[str, str], None],
    now_epoch: int | None = None,
) -> str:

    if not pane_path or not pane_window_ref:
        return ""

    if not Path(sessions_dir).is_dir() or scan_limit <= 0 or lookback_minutes <= 0:
        return ""

    now = int(time.time()) if now_epoch is None else now_epoch
    keys = infer_keys(pane_path, pane_window_ref)
    mapped_file = tmux_get_env(keys.session_file_key)

    if not has_valid_mapped_file(mapped_file, pane_path):
        mapped_file = ""
        if not window_ref_matches(pane_path, pane_window_ref, tmux_get_env):
            return ""
    
    cache_hit, cached = cached_inferred_state(keys, session_cache_seconds, now, tmux_get_env)
    if cache_hit:
        return cached
    
    event = infer_event_from_sessions(
        mapped_file,
        pane_path,
        keys,
        now,
        sessions_dir,
        lookback_minutes,
        scan_limit,
        tmux_set_env,
    )

    inferred_state = map_task_event_to_state(event)
    
    if inferred_state and session_cache_seconds > 0:
        tmux_set_env(keys.cache_state_key, inferred_state)
        tmux_set_env(keys.cache_updated_key, str(now))
    return inferred_state
