from __future__ import annotations

from pathlib import Path

from tmux_codex_status.session_scan import (
    infer_keys,
    infer_state_from_sessions,
    session_latest_task_event,
)


def write_session(path: Path, cwd: str, event: str) -> None:
    path.write_text(
        "\n".join(
            [
                '{"timestamp":"2026-02-22T00:00:00.000Z","type":"session_meta","payload":{"id":"test","timestamp":"2026-02-22T00:00:00.000Z","cwd":"'
                + cwd
                + '"}}',
                '{"timestamp":"2026-02-22T00:00:01.000Z","type":"event_msg","payload":{"type":"'
                + event
                + '","turn_id":"turn-1"}}',
            ]
        )
        + "\n",
        encoding="utf-8",
    )



def test_session_latest_task_event(tmp_path: Path) -> None:
    session_file = tmp_path / "a.jsonl"
    write_session(session_file, "/work", "task_started")
    assert session_latest_task_event(str(session_file)) == "task_started"



def test_infer_state_uses_mapped_file(tmp_path: Path) -> None:
    env: dict[str, str] = {}

    def get_env(key: str) -> str:
        return env.get(key, "")

    def set_env(key: str, value: str) -> None:
        env[key] = value

    pane_path = str(tmp_path / "cwd")
    pane_window = "s:1"
    session_file = tmp_path / "mapped.jsonl"
    write_session(session_file, pane_path, "task_started")

    keys = infer_keys(pane_path, pane_window)
    env[keys.session_file_key] = str(session_file)

    state = infer_state_from_sessions(
        pane_path,
        pane_window,
        str(tmp_path),
        240,
        40,
        2,
        get_env,
        set_env,
        now_epoch=100,
    )
    assert state == "R"
    assert env[keys.cache_state_key] == "R"



def test_infer_state_requires_window_ref_when_unmapped(tmp_path: Path) -> None:
    env: dict[str, str] = {}

    def get_env(key: str) -> str:
        return env.get(key, "")

    def set_env(key: str, value: str) -> None:
        env[key] = value

    pane_path = str(tmp_path / "cwd")
    pane_window = "s:1"

    state = infer_state_from_sessions(
        pane_path,
        pane_window,
        str(tmp_path),
        240,
        40,
        0,
        get_env,
        set_env,
        now_epoch=100,
    )
    assert state == ""
