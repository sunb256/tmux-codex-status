from __future__ import annotations

from collections.abc import Sequence

from .process import CmdResult, has_command, run_cmd


def tmux_run(args: Sequence[str]) -> CmdResult:
    return run_cmd(["tmux", *args])

def tmux_ready() -> bool:
    if not has_command("tmux"):
        return False
    return tmux_run(["list-sessions"]).code == 0

def tmux_get_env(key: str) -> str:
    line = tmux_run(["show-environment", "-g", key]).out.strip()
    if line.startswith(f"{key}="):
        return line.split("=", 1)[1]
    return ""

def tmux_set_env(key: str, value: str) -> None:
    tmux_run(["set-environment", "-g", key, value])

def tmux_unset_env(key: str) -> None:
    tmux_run(["set-environment", "-gu", key])

def tmux_option_is_set(option: str) -> bool:
    raw = tmux_run(["show-option", "-gq", option]).out
    return raw != ""

def tmux_option_or_default(option: str, default: str) -> str:
    if tmux_option_is_set(option):
        value = tmux_run(["show-option", "-gqv", option]).out.rstrip("\n")
        return value
    return default

def tmux_pane_value(pane_id: str, fmt: str) -> str:
    return tmux_run(["display-message", "-p", "-t", pane_id, fmt]).out.rstrip("\n")

def tmux_set_window_option(window_id: str, option: str, value: str) -> None:
    tmux_run(["set-window-option", "-q", "-t", window_id, option, value])

def tmux_set_pane_option(pane_id: str, option: str, value: str) -> None:
    tmux_run(["set-option", "-p", "-q", "-t", pane_id, option, value])

def tmux_display_message(fmt: str, target: str | None = None) -> CmdResult:
    args = ["display-message", "-p"]
    if target:
        args += ["-t", target]
    args.append(fmt)
    return tmux_run(args)
