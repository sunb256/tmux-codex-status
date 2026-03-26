from __future__ import annotations

import json
from pathlib import Path

from tmux_codex_status import commands
from tmux_codex_status.commands import SessionConfig


def session_config(stale_r_grace_seconds: int = 5) -> SessionConfig:
    return SessionConfig(
        sessions_dir="/tmp",
        lookback_minutes=240,
        scan_limit=40,
        cache_seconds=2,
        stale_r_grace_seconds=stale_r_grace_seconds,
    )


def test_infer_or_keep_state_keeps_fresh_explicit_w(monkeypatch) -> None:
    monkeypatch.setattr(commands, "infer_state_from_sessions", lambda *args, **kwargs: "R")

    assert (
        commands.infer_or_keep_state(
            "W",
            "100",
            "/cwd",
            "s:1",
            session_config(),
            101,
        )
        == "W"
    )


def test_infer_or_keep_state_allows_stale_w_to_be_inferred(monkeypatch) -> None:
    monkeypatch.setattr(commands, "infer_state_from_sessions", lambda *args, **kwargs: "R")

    assert (
        commands.infer_or_keep_state(
            "W",
            "100",
            "/cwd",
            "s:1",
            session_config(),
            106,
        )
        == "R"
    )


def test_infer_or_keep_state_infers_when_state_is_missing(monkeypatch) -> None:
    monkeypatch.setattr(commands, "infer_state_from_sessions", lambda *args, **kwargs: "R")

    assert (
        commands.infer_or_keep_state(
            "",
            "",
            "/cwd",
            "s:1",
            session_config(),
            101,
        )
        == "R"
    )


def test_infer_or_keep_state_stale_r_can_downgrade_to_w(monkeypatch) -> None:
    monkeypatch.setattr(commands, "infer_state_from_sessions", lambda *args, **kwargs: "W")

    assert (
        commands.infer_or_keep_state(
            "R",
            "100",
            "/cwd",
            "s:1",
            session_config(),
            106,
        )
        == "W"
    )


def test_state_bg_color_uses_legacy_color_when_bg_is_default(monkeypatch) -> None:
    options = {
        "@codex-status-bg-w": "colour15",
        "@codex-status-color-w": "colour160",
    }

    def fake_option_or_default(option: str, default: str) -> str:
        return options.get(option, default)

    monkeypatch.setattr(commands, "tmux_option_or_default", fake_option_or_default)

    assert commands.state_bg_color("W") == "colour160"


def test_state_bg_color_prefers_explicit_bg(monkeypatch) -> None:
    options = {
        "@codex-status-bg-w": "colour52",
        "@codex-status-color-w": "colour160",
    }

    def fake_option_or_default(option: str, default: str) -> str:
        return options.get(option, default)

    monkeypatch.setattr(commands, "tmux_option_or_default", fake_option_or_default)

    assert commands.state_bg_color("W") == "colour52"


def test_append_status_log_writes_json_line(tmp_path: Path, monkeypatch) -> None:
    log_path = tmp_path / "status.log"
    monkeypatch.setenv("CODEX_STATUS_LOG_FILE", str(log_path))

    commands.append_status_log(
        "notify",
        {
            "pane_id": "%1",
            "event": "task_started\nnext",
            "state": "R",
        },
    )

    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 1
    payload = json.loads(lines[0])
    assert payload["tag"] == "notify"
    assert payload["pane_id"] == "%1"
    assert payload["event"] == "task_started next"
    assert payload["state"] == "R"
