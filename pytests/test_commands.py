from __future__ import annotations

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
