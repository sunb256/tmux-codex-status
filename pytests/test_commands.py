from __future__ import annotations

import json
from pathlib import Path

from tmux_codex_status import commands
from tmux_codex_status.commands import SessionConfig
from tmux_codex_status.process import CmdResult


def session_config(stale_r_grace_seconds: int = 5) -> SessionConfig:
    return SessionConfig(
        sessions_dir="/tmp",
        lookback_minutes=240,
        scan_limit=40,
        cache_seconds=2,
        stale_r_grace_seconds=stale_r_grace_seconds,
    )


def create_plugin_layout(tmp_path: Path) -> Path:
    plugin_dir = tmp_path / "plugin"
    (plugin_dir / "tmux").mkdir(parents=True)
    (plugin_dir / "scripts").mkdir(parents=True)
    (plugin_dir / "tmux" / "codex-status.tmux").write_text("# mock\n", encoding="utf-8")
    (plugin_dir / "scripts" / "codex-notify.sh").write_text(
        "#!/usr/bin/env bash\n",
        encoding="utf-8",
    )
    return plugin_dir


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


def configure_doctor_happy_path(
    monkeypatch,
    tmp_path: Path,
    *,
    pane_has_codex: bool = True,
    window_status_ok: bool = True,
    module_ok: bool = True,
    python_ok: bool = True,
) -> None:
    plugin_dir = tmp_path / "plugin"
    (plugin_dir / "src" / "tmux_codex_status").mkdir(parents=True)

    monkeypatch.setattr(commands, "has_command", lambda name: name == "tmux")
    monkeypatch.setattr(commands, "tmux_ready", lambda: True)

    def fake_option_or_default(option: str, default: str) -> str:
        options = {
            "@codex-status-dir": str(plugin_dir),
            "@codex-status-python": "python3",
            "@codex-status-process-name": "codex",
        }
        return options.get(option, default)

    monkeypatch.setattr(commands, "tmux_option_or_default", fake_option_or_default)

    def fake_run_cmd(args, text_input=None):
        if args == ["python3", "--version"]:
            if python_ok:
                return CmdResult(0, "Python 3.11.9\n", "")
            return CmdResult(1, "", "python3 not found")
        return CmdResult(0, "", "")

    monkeypatch.setattr(commands, "run_cmd", fake_run_cmd)
    if module_ok:
        monkeypatch.setattr(commands, "run_doctor_module_check", lambda *_: (True, "R"))
    else:
        monkeypatch.setattr(
            commands,
            "run_doctor_module_check",
            lambda *_: (False, "import failed"),
        )

    needle = "tmux_codex_status.cli window-badge"

    def fake_tmux_run(args):
        if args == ["show-option", "-gqv", "window-status-format"]:
            if window_status_ok:
                return CmdResult(0, f"#({needle} \"#{{window_id}}\")#I:#W\n", "")
            return CmdResult(0, "#I:#W\n", "")
        if args == ["show-option", "-gqv", "window-status-current-format"]:
            return CmdResult(0, f"#({needle} \"#{{window_id}}\")#I:#W\n", "")
        return CmdResult(0, "", "")

    monkeypatch.setattr(commands, "tmux_run", fake_tmux_run)
    monkeypatch.setenv("TMUX_PANE", "%1")

    def fake_pane_value(pane_id: str, fmt: str) -> str:
        if fmt == "#{pane_tty}":
            return "/dev/ttys001"
        if fmt == "#{window_id}":
            return "@1"
        return ""

    monkeypatch.setattr(commands, "tmux_pane_value", fake_pane_value)
    monkeypatch.setattr(commands, "pane_has_process", lambda *_: pane_has_codex)
    monkeypatch.setattr(commands, "run_doctor_window_badge_check", lambda *_: (0, "🤖"))


def test_cmd_doctor_returns_zero_when_all_required_checks_pass(
    tmp_path: Path, monkeypatch, capsys
) -> None:
    configure_doctor_happy_path(monkeypatch, tmp_path)

    assert commands.cmd_doctor() == 0
    output = capsys.readouterr().out
    assert "Summary:" in output
    assert "0 FAIL" in output


def test_cmd_doctor_fails_when_tmux_is_missing(monkeypatch, capsys) -> None:
    monkeypatch.setattr(commands, "has_command", lambda *_: False)
    monkeypatch.setattr(
        commands,
        "run_cmd",
        lambda *_args, **_kwargs: CmdResult(0, "Python 3.11.9", ""),
    )
    monkeypatch.delenv("TMUX_PANE", raising=False)

    assert commands.cmd_doctor() == 1
    output = capsys.readouterr().out
    assert "[FAIL] tmux command" in output


def test_cmd_doctor_fails_when_window_status_format_is_not_configured(
    tmp_path: Path, monkeypatch, capsys
) -> None:
    configure_doctor_happy_path(monkeypatch, tmp_path, window_status_ok=False)

    assert commands.cmd_doctor() == 1
    output = capsys.readouterr().out
    assert "[FAIL] window-status-format" in output


def test_cmd_doctor_warns_when_codex_process_not_detected(
    tmp_path: Path, monkeypatch, capsys
) -> None:
    configure_doctor_happy_path(monkeypatch, tmp_path, pane_has_codex=False)

    assert commands.cmd_doctor() == 0
    output = capsys.readouterr().out
    assert "[WARN] pane process detection" in output


def test_cmd_doctor_fails_when_module_invocation_fails(tmp_path: Path, monkeypatch, capsys) -> None:
    configure_doctor_happy_path(monkeypatch, tmp_path, module_ok=False)

    assert commands.cmd_doctor() == 1
    output = capsys.readouterr().out
    assert "[FAIL] module invocation" in output


def test_cmd_notify_falls_back_to_display_message_pane_id(monkeypatch) -> None:
    set_calls: list[tuple[str, str]] = []

    monkeypatch.setattr(commands, "tmux_ready", lambda: True)
    monkeypatch.delenv("TMUX_PANE", raising=False)

    def fake_display_message(fmt: str, target: str | None = None) -> CmdResult:
        if fmt == "#{pane_id}":
            return CmdResult(0, "%42\n", "")
        if fmt == "#{session_name}":
            return CmdResult(0, "s\n", "")
        return CmdResult(1, "", "unsupported")

    monkeypatch.setattr(commands, "tmux_display_message", fake_display_message)
    monkeypatch.setattr(commands, "tmux_get_env", lambda *_: "")
    monkeypatch.setattr(commands, "tmux_set_env", lambda key, value: set_calls.append((key, value)))
    monkeypatch.setattr(commands, "append_status_log", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(commands, "remember_cwd_window_ref", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(commands, "cmd_state_gc", lambda: 0)
    monkeypatch.setattr(commands, "tmux_run", lambda *_args, **_kwargs: CmdResult(0, "", ""))

    assert commands.cmd_notify("task_started") == 0
    assert ("TMUX_CODEX_PANE_%42_STATE", "R") in set_calls


def test_cmd_notify_returns_without_pane_id(monkeypatch) -> None:
    monkeypatch.setattr(commands, "tmux_ready", lambda: True)
    monkeypatch.delenv("TMUX_PANE", raising=False)
    monkeypatch.setattr(
        commands,
        "tmux_display_message",
        lambda *_args, **_kwargs: CmdResult(0, "", ""),
    )
    monkeypatch.setattr(
        commands,
        "tmux_set_env",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(RuntimeError),
    )

    assert commands.cmd_notify("task_started") == 0


def test_cmd_setup_apply_updates_tmux_and_codex_configs(tmp_path: Path, capsys) -> None:
    plugin_dir = create_plugin_layout(tmp_path)
    tmux_conf = tmp_path / "tmux.conf"
    codex_config = tmp_path / "config.toml"
    tmux_conf.write_text("set -g mouse on\n", encoding="utf-8")
    codex_config.write_text('model = "gpt-5"\n', encoding="utf-8")

    assert commands.cmd_setup(True, str(plugin_dir), str(tmux_conf), str(codex_config)) == 0
    output = capsys.readouterr().out
    assert "[OK]" in output

    tmux_text = tmux_conf.read_text(encoding="utf-8")
    assert commands.TMUX_SETUP_START in tmux_text
    assert f'source-file "{plugin_dir / "tmux" / "codex-status.tmux"}"' in tmux_text

    codex_text = codex_config.read_text(encoding="utf-8")
    assert f'notify = ["bash", "{plugin_dir / "scripts" / "codex-notify.sh"}"]' in codex_text


def test_cmd_setup_apply_replaces_existing_notify_assignment(tmp_path: Path) -> None:
    plugin_dir = create_plugin_layout(tmp_path)
    tmux_conf = tmp_path / "tmux.conf"
    codex_config = tmp_path / "config.toml"
    codex_config.write_text(
        "\n".join(
            [
                'model = "gpt-5"',
                'notify = ["bash", "/tmp/old-notify.sh"]',
                "",
            ]
        ),
        encoding="utf-8",
    )

    assert commands.cmd_setup(True, str(plugin_dir), str(tmux_conf), str(codex_config)) == 0

    codex_text = codex_config.read_text(encoding="utf-8")
    assert 'notify = ["bash", "/tmp/old-notify.sh"]' not in codex_text
    assert f'notify = ["bash", "{plugin_dir / "scripts" / "codex-notify.sh"}"]' in codex_text
    assert commands.CODEX_SETUP_START not in codex_text


def test_cmd_setup_dry_run_does_not_write_files(tmp_path: Path, capsys) -> None:
    plugin_dir = create_plugin_layout(tmp_path)
    tmux_conf = tmp_path / "tmux.conf"
    codex_config = tmp_path / "config.toml"

    assert commands.cmd_setup(False, str(plugin_dir), str(tmux_conf), str(codex_config)) == 0
    output = capsys.readouterr().out
    assert "Dry-run only" in output
    assert not tmux_conf.exists()
    assert not codex_config.exists()
