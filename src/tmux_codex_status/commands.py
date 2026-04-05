from __future__ import annotations

import json
import os
import re
import shlex
import time
from dataclasses import dataclass
from pathlib import Path

from .process import has_command, run_cmd
from .session_scan import (
    cksum_value,
    find_recent_session_file_for_cwd,
    infer_state_from_sessions,
)
from .state import (
    extract_event_from_notify_arg,
    map_event_to_state,
    normalize_state,
    state_rank,
)
from .tmux_api import (
    tmux_display_message,
    tmux_get_env,
    tmux_option_or_default,
    tmux_pane_value,
    tmux_ready,
    tmux_run,
    tmux_set_env,
    tmux_set_pane_option,
    tmux_set_window_option,
    tmux_unset_env,
)

WORD_RE_TEMPLATE = r"(^|[^A-Za-z0-9_]){name}($|[^A-Za-z0-9_])"
STATE_COLOR_OPTIONS: dict[str, tuple[str, str, str, str]] = {
    "R": ("@codex-status-bg-r", "colour88", "@codex-status-color-r", "colour208"),
    "W": ("@codex-status-bg-w", "colour15", "@codex-status-color-w", "colour255"),
    "I": ("@codex-status-bg-i", "colour15", "@codex-status-color-i", "colour226"),
    "E": ("@codex-status-bg-e", "colour196", "@codex-status-color-e", "colour196"),
}


@dataclass(frozen=True)
class SessionConfig:
    sessions_dir: str
    lookback_minutes: int
    scan_limit: int
    cache_seconds: int
    stale_r_grace_seconds: int


@dataclass(frozen=True)
class PaneRow:
    pane_id: str
    pane_tty: str
    pane_path: str
    pane_window_ref: str


@dataclass(frozen=True)
class DoctorCheck:
    status: str
    name: str
    detail: str
    hint: str = ""



def print_line(value: str) -> None:
    print(value)



def parse_non_negative(value: str, default_value: int) -> int:
    if value.isdigit():
        return int(value)
    return default_value



def sessions_dir_default() -> str:
    codex_home = os.environ.get("CODEX_HOME")
    if codex_home:
        return f"{codex_home}/sessions"
    home = os.environ.get("HOME", "")
    return f"{home}/.codex/sessions"



def load_session_config() -> SessionConfig:
    sessions_dir = tmux_option_or_default("@codex-status-sessions-dir", sessions_dir_default())
    lookback_raw = tmux_option_or_default("@codex-status-session-lookback-minutes", "240")
    scan_limit_raw = tmux_option_or_default("@codex-status-session-scan-limit", "40")
    cache_raw = tmux_option_or_default("@codex-status-session-cache-seconds", "2")
    stale_raw = tmux_option_or_default("@codex-status-stale-r-grace-seconds", "5")
    return SessionConfig(
        sessions_dir=sessions_dir,
        lookback_minutes=parse_non_negative(lookback_raw, 240),
        scan_limit=parse_non_negative(scan_limit_raw, 40),
        cache_seconds=parse_non_negative(cache_raw, 2),
        stale_r_grace_seconds=parse_non_negative(stale_raw, 5),
    )



def status_log_file() -> str:
    env_log = os.environ.get("CODEX_STATUS_LOG_FILE")
    if env_log is not None:
        return env_log
    return tmux_option_or_default("@codex-status-log-file", "")



def log_value(value: str) -> str:
    return value.replace("\n", " ").replace("\r", " ").replace("\t", " ")



def append_status_log(tag: str, fields: dict[str, str]) -> None:
    log_path = status_log_file()
    if log_path == "":
        return
    payload: dict[str, str] = {
        "timestamp": str(int(time.time())),
        "tag": tag,
    }
    for key, value in fields.items():
        payload[key] = log_value(str(value))
    path = Path(log_path).expanduser()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(payload, ensure_ascii=False) + "\n")
    except OSError:
        return



def state_color_options(state: str) -> tuple[str, str, str, str]:
    return STATE_COLOR_OPTIONS.get(state, STATE_COLOR_OPTIONS["W"])



def state_bg_color(state: str) -> str:
    bg_option, bg_default, color_option, color_default = state_color_options(state)
    bg_color = tmux_option_or_default(bg_option, bg_default)
    legacy_color = tmux_option_or_default(color_option, color_default)
    if bg_color == bg_default and legacy_color != color_default:
        return legacy_color
    return bg_color



def state_fg_color(state: str) -> str:
    if state == "R":
        return tmux_option_or_default("@codex-status-fg-r", "colour16")
    if state == "W":
        return tmux_option_or_default("@codex-status-fg-w", "colour16")
    if state == "I":
        return tmux_option_or_default("@codex-status-fg-i", "colour16")
    if state == "E":
        return tmux_option_or_default("@codex-status-fg-e", "colour255")
    return tmux_option_or_default("@codex-status-fg-w", "colour255")



def adjusted_fg_color(fg_color: str, bg_color: str) -> str:
    if fg_color != bg_color:
        return fg_color
    if bg_color == "colour16":
        return "colour255"
    return "colour16"



def pane_has_process(pane_tty: str, process_name: str) -> bool:
    if not pane_tty:
        return False

    tty_name = os.path.basename(pane_tty)
    result = run_cmd(["ps", "-t", tty_name, "-o", "command="])

    if result.code != 0:
        return False

    pattern = re.compile(WORD_RE_TEMPLATE.format(name=re.escape(process_name)))

    for line in result.out.splitlines():
        if pattern.search(line):
            return True

    return False


def default_plugin_dir() -> str:
    return os.path.expanduser("~/.tmux/plugins/tmux-codex-status")


def doctor_pythonpath(plugin_dir: str) -> str:
    plugin_src = f"{plugin_dir}/src"
    current = os.environ.get("PYTHONPATH", "")
    if current == "":
        return plugin_src
    return f"{plugin_src}:{current}"


def add_doctor_check(
    checks: list[DoctorCheck],
    status: str,
    name: str,
    detail: str,
    hint: str = "",
) -> None:
    checks.append(DoctorCheck(status, name, detail, hint))


def print_doctor_checks(checks: list[DoctorCheck]) -> None:
    for check in checks:
        print_line(f"[{check.status}] {check.name}: {check.detail}")
        if check.hint:
            print_line(f"  hint: {check.hint}")


def doctor_summary(checks: list[DoctorCheck]) -> tuple[int, int, int]:
    pass_count = sum(1 for check in checks if check.status == "PASS")
    warn_count = sum(1 for check in checks if check.status == "WARN")
    fail_count = sum(1 for check in checks if check.status == "FAIL")
    return pass_count, warn_count, fail_count


def run_doctor_module_check(python_bin: str, plugin_dir: str) -> tuple[bool, str]:
    result = run_cmd(
        [
            "env",
            f"PYTHONPATH={doctor_pythonpath(plugin_dir)}",
            python_bin,
            "-m",
            "tmux_codex_status.cli",
            "map-event",
            "task_started",
        ]
    )

    if result.code != 0:
        detail = result.err.strip() or result.out.strip() or "map-event command failed."
        return False, detail

    output = result.out.strip()
    if output == "R":
        return True, output

    return False, f"Unexpected output: {output!r}"


def run_doctor_window_badge_check(
    python_bin: str,
    plugin_dir: str,
    window_id: str,
) -> tuple[int, str]:
    result = run_cmd(
        [
            "env",
            f"PYTHONPATH={doctor_pythonpath(plugin_dir)}",
            python_bin,
            "-m",
            "tmux_codex_status.cli",
            "window-badge",
            window_id,
            "plain",
        ]
    )
    return result.code, result.out.strip()



def list_status_panes(target: str | None = None, all_panes: bool = False) -> list[PaneRow]:
    args = ["list-panes"]

    if all_panes:
        args.append("-a")

    if target is not None:
        args += ["-t", target]

    args += ["-F", "#{pane_id}\t#{pane_tty}\t#{pane_current_path}\t#{session_name}:#{window_index}"]
    output = tmux_run(args).out

    rows: list[PaneRow] = []

    for line in output.splitlines():
        parts = line.split("\t", 3)

        if len(parts) != 4 or parts[0] == "":
            continue

        rows.append(
            PaneRow(
                pane_id=parts[0],
                pane_tty=parts[1],
                pane_path=parts[2],
                pane_window_ref=parts[3],
            )
        )
    return rows

def pane_state_key(pane_id: str) -> str:
    return f"TMUX_CODEX_PANE_{pane_id}_STATE"

def pane_updated_key(pane_id: str) -> str:
    return f"TMUX_CODEX_PANE_{pane_id}_UPDATED_AT"

def infer_or_keep_state(
    pane_state: str,
    pane_updated_at: str,
    pane_path: str,
    pane_window_ref: str,
    config: SessionConfig,
    now_epoch: int,
) -> str:
    has_explicit_state = pane_state != ""
    state = normalize_state(pane_state or "W")

    if state == "W":
        # Keep a freshly notified W so stale session inference does not
        # immediately flip the badge back to R.
        if has_explicit_state and not state_is_stale(
            pane_updated_at,
            config.stale_r_grace_seconds,
            now_epoch,
        ):
            return "W"

        inferred = infer_state_from_sessions(
            pane_path,
            pane_window_ref,
            config.sessions_dir,
            config.lookback_minutes,
            config.scan_limit,
            config.cache_seconds,
            tmux_get_env,
            tmux_set_env,
            now_epoch,
        )

        if inferred == "R":
            return "R"

        return "W"

    if state != "R":
        return state

    stale = state_is_stale(pane_updated_at, config.stale_r_grace_seconds, now_epoch)

    if not stale:
        return state

    inferred = infer_state_from_sessions(
        pane_path,
        pane_window_ref,
        config.sessions_dir,
        config.lookback_minutes,
        config.scan_limit,
        config.cache_seconds,
        tmux_get_env,
        tmux_set_env,
        now_epoch,
    )

    if inferred == "W":
        return "W"

    return state

def state_is_stale(pane_updated_at: str, stale_r_grace_seconds: int, now_epoch: int) -> bool:
    if stale_r_grace_seconds == 0:
        return True

    if not pane_updated_at.isdigit():
        return False

    return now_epoch - int(pane_updated_at) >= stale_r_grace_seconds

def cmd_extract_event(raw_arg: str | None) -> int:
    print_line(extract_event_from_notify_arg(raw_arg))
    return 0

def cmd_map_event(event: str | None) -> int:
    print_line(map_event_to_state(event))
    return 0

def cmd_normalize_state(state: str | None) -> int:
    print_line(normalize_state(state))
    return 0

def cmd_state_rank(state: str | None) -> int:
    print_line(str(state_rank(state)))
    return 0

def cmd_window_badge(window_id: str | None, output_mode: str | None) -> int:

    if not window_id:
        return 0

    mode = output_mode if output_mode in {"styled", "plain"} else "styled"

    if not tmux_ready():
        return 0

    icon = tmux_option_or_default("@codex-status-icon", "🤖")
    process_name = tmux_option_or_default("@codex-status-process-name", "codex")
    config = load_session_config()
    codex_rows = codex_panes_for_window(window_id, process_name)

    if not codex_rows:
        tmux_set_window_option(window_id, "@codex-status-window-badge", "")
        print_line("")
        return 0

    winner_state = winner_state_for_rows(codex_rows, config)
    plain_badge = icon if icon else ""
    tmux_set_window_option(window_id, "@codex-status-window-badge", plain_badge)

    if mode == "plain":
        print_line(plain_badge)
        return 0

    print_line(styled_badge_text(plain_badge, winner_state))
    return 0

def codex_panes_for_window(window_id: str, process_name: str) -> list[PaneRow]:
    rows: list[PaneRow] = []

    for row in list_status_panes(target=window_id):
        if pane_has_process(row.pane_tty, process_name):
            rows.append(row)
    return rows

def winner_state_for_rows(rows: list[PaneRow], config: SessionConfig) -> str:
    winner_state = "W"
    winner_rank = 0
    now_epoch = int(time.time())

    for row in rows:
        state = tmux_get_env(pane_state_key(row.pane_id))
        updated = tmux_get_env(pane_updated_key(row.pane_id))

        effective = infer_or_keep_state(
            state,
            updated,
            row.pane_path,
            row.pane_window_ref,
            config,
            now_epoch,
        )

        rank = state_rank(effective)

        if rank > winner_rank:
            winner_rank = rank
            winner_state = effective

    return winner_state

def styled_badge_text(plain_badge: str, state: str) -> str:
    if not plain_badge:
        return ""

    bg_color = state_bg_color(state)
    fg_color = adjusted_fg_color(state_fg_color(state), bg_color)

    return f"#[fg={fg_color},bg={bg_color}]{plain_badge}#[default]"

def cmd_refresh_pane_badges() -> int:
    if not tmux_ready():
        return 0

    icon = tmux_option_or_default("@codex-status-icon", "🤖")
    separator = tmux_option_or_default("@codex-status-separator", " ")
    process_name = tmux_option_or_default("@codex-status-process-name", "codex")
    config = load_session_config()
    now_epoch = int(time.time())

    for row in list_status_panes(all_panes=True):
        badge = pane_badge_value(row, process_name, icon, separator, config, now_epoch)
        tmux_set_pane_option(row.pane_id, "@codex-status-pane-badge", badge)

    return 0

def pane_badge_value(
    row: PaneRow,
    process_name: str,
    icon: str,
    separator: str,
    config: SessionConfig,
    now_epoch: int,
) -> str:

    if not pane_has_process(row.pane_tty, process_name):
        return ""

    state = tmux_get_env(pane_state_key(row.pane_id))
    updated = tmux_get_env(pane_updated_key(row.pane_id))

    effective = infer_or_keep_state(
        state,
        updated,
        row.pane_path,
        row.pane_window_ref,
        config,
        now_epoch,
    )

    if icon:
        return f"{icon}{separator}{effective}"
    return effective

def cmd_notify(raw_arg: str | None) -> int:
    if not tmux_ready():
        return 0

    pane_id = os.environ.get("TMUX_PANE", "")
    if pane_id == "":
        pane_id = tmux_display_message("#{pane_id}").out.rstrip("\n")

    if pane_id == "":
        return 0

    if tmux_display_message("#{session_name}").code != 0:
        return 0

    event_type = extract_event_from_notify_arg(raw_arg)
    mapped_state = map_event_to_state(event_type)
    prev_state = tmux_get_env(pane_state_key(pane_id)) or "W"
    state = mapped_state
    if state == "K":
        state = prev_state

    now_epoch = int(time.time())
    tmux_set_env(pane_state_key(pane_id), state)
    tmux_set_env(pane_updated_key(pane_id), str(now_epoch))
    append_status_log(
        "notify",
        {
            "pane_id": pane_id,
            "event": event_type,
            "mapped_state": mapped_state,
            "state": state,
            "prev_state": prev_state,
        },
    )
    remember_cwd_window_ref(pane_id, state, now_epoch)
    cmd_state_gc()
    tmux_run(["refresh-client", "-S"])

    return 0

def remember_cwd_window_ref(pane_id: str, state: str, now_epoch: int) -> None:
    pane_path = tmux_pane_value(pane_id, "#{pane_current_path}")
    window_ref = tmux_pane_value(pane_id, "#{session_name}:#{window_index}")

    if pane_path == "" or window_ref == "":
        return

    cwd_suffix = cksum_value(pane_path)
    if cwd_suffix == "":
        return

    window_key = f"TMUX_CODEX_CWD_{cwd_suffix}_WINDOW_REF"
    updated_key = f"TMUX_CODEX_CWD_{cwd_suffix}_WINDOW_UPDATED_AT"
    current_ref = tmux_get_env(window_key)

    if state == "R" or current_ref == "" or current_ref == window_ref:
        tmux_set_env(window_key, window_ref)
        tmux_set_env(updated_key, str(now_epoch))

    config = load_session_config()
    session_file = find_recent_session_file_for_cwd(
        pane_path,
        config.sessions_dir,
        config.lookback_minutes,
        config.scan_limit,
    )

    if not session_file:
        return

    window_suffix = cksum_value(f"{pane_path}\t{window_ref}")
    session_key = f"TMUX_CODEX_CWD_{window_suffix}_SESSION_FILE"
    session_updated = f"TMUX_CODEX_CWD_{window_suffix}_SESSION_FILE_UPDATED_AT"
    tmux_set_env(session_key, session_file)
    tmux_set_env(session_updated, str(now_epoch))

def cmd_state_gc() -> int:
    if not tmux_ready():
        return 0

    active = active_pane_ids()
    env_lines = tmux_run(["show-environment", "-g"]).out.splitlines()

    for line in env_lines:
        stale_pane = stale_pane_id(line, active)
        if stale_pane == "":
            continue
        tmux_unset_env(pane_state_key(stale_pane))
        tmux_unset_env(pane_updated_key(stale_pane))
    return 0

def cmd_doctor() -> int:
    checks: list[DoctorCheck] = []

    tmux_exists = has_command("tmux")
    if tmux_exists:
        add_doctor_check(checks, "PASS", "tmux command", "tmux is available in PATH.")
    else:
        add_doctor_check(
            checks,
            "FAIL",
            "tmux command",
            "tmux command was not found in PATH.",
            "Install tmux and make sure `tmux` is executable in your shell.",
        )

    ready = False
    if tmux_exists:
        ready = tmux_ready()
        if ready:
            add_doctor_check(checks, "PASS", "tmux server", "tmux server is reachable.")
        else:
            add_doctor_check(
                checks,
                "FAIL",
                "tmux server",
                "tmux server is not reachable.",
                "Start tmux and run doctor from inside an active tmux session.",
            )

    plugin_dir = default_plugin_dir()
    if ready:
        plugin_dir = tmux_option_or_default("@codex-status-dir", default_plugin_dir())

    plugin_src = Path(plugin_dir).expanduser() / "src" / "tmux_codex_status"
    if plugin_dir == "":
        add_doctor_check(
            checks,
            "FAIL",
            "@codex-status-dir",
            "Plugin directory option is empty.",
            "Set `@codex-status-dir` to the plugin root path in `.tmux.conf`.",
        )
    elif plugin_src.is_dir():
        add_doctor_check(
            checks,
            "PASS",
            "@codex-status-dir",
            f"Resolved plugin package path exists: {plugin_src}.",
        )
    else:
        add_doctor_check(
            checks,
            "FAIL",
            "@codex-status-dir",
            f"Expected package path was not found: {plugin_src}.",
            "Set `@codex-status-dir` correctly and reload tmux config.",
        )

    python_bin = "python3"
    if ready:
        python_bin = tmux_option_or_default("@codex-status-python", "python3")

    python_result = run_cmd([python_bin, "--version"])
    if python_result.code == 0:
        version_text = python_result.out.strip() or python_result.err.strip() or "version ok"
        add_doctor_check(
            checks,
            "PASS",
            "@codex-status-python",
            f"Python command works ({version_text}).",
        )
    else:
        detail = python_result.err.strip() or python_result.out.strip() or "command failed."
        add_doctor_check(
            checks,
            "FAIL",
            "@codex-status-python",
            f"Python command failed: {detail}",
            "Set `@codex-status-python` to a valid Python executable.",
        )

    module_ok = False
    if python_result.code == 0 and plugin_dir != "":
        module_ok, module_detail = run_doctor_module_check(python_bin, plugin_dir)
        if module_ok:
            add_doctor_check(
                checks,
                "PASS",
                "module invocation",
                "tmux_codex_status module command succeeded (map-event -> R).",
            )
        else:
            add_doctor_check(
                checks,
                "FAIL",
                "module invocation",
                f"Module invocation failed: {module_detail}",
                "Verify `@codex-status-dir` and `@codex-status-python` values.",
            )
    else:
        add_doctor_check(
            checks,
            "FAIL",
            "module invocation",
            "Skipped because Python executable or plugin path check failed.",
            "Fix earlier FAIL items and run doctor again.",
        )

    if ready:
        format_value = tmux_run(["show-option", "-gqv", "window-status-format"]).out.rstrip("\n")
        needle = "tmux_codex_status.cli window-badge"
        if needle in format_value:
            add_doctor_check(
                checks,
                "PASS",
                "window-status-format",
                "window-status-format includes tmux_codex_status window-badge command.",
            )
        else:
            add_doctor_check(
                checks,
                "FAIL",
                "window-status-format",
                "window-status-format does not include tmux_codex_status window-badge command.",
                "Source `tmux/codex-status.tmux` and reload tmux config.",
            )

        current_format_result = tmux_run(["show-option", "-gqv", "window-status-current-format"])
        current_format = current_format_result.out.rstrip("\n")
        if needle in current_format:
            add_doctor_check(
                checks,
                "PASS",
                "window-status-current-format",
                "window-status-current-format includes tmux_codex_status window-badge command.",
            )
        else:
            add_doctor_check(
                checks,
                "WARN",
                "window-status-current-format",
                (
                    "window-status-current-format does not include "
                    "tmux_codex_status window-badge command."
                ),
                "Source `tmux/codex-status.tmux` and reload tmux config.",
            )
    else:
        add_doctor_check(
            checks,
            "WARN",
            "window-status-format",
            "Skipped because tmux server check failed.",
            "Fix tmux server access and run doctor again.",
        )

    pane_id = os.environ.get("TMUX_PANE", "")
    if not ready:
        add_doctor_check(
            checks,
            "WARN",
            "pane process detection",
            "Skipped because tmux server check failed.",
            "Run doctor from inside tmux.",
        )
    elif pane_id == "":
        add_doctor_check(
            checks,
            "WARN",
            "pane process detection",
            "TMUX_PANE is not set.",
            "Run doctor from inside a tmux pane where Codex runs.",
        )
    else:
        pane_tty = tmux_pane_value(pane_id, "#{pane_tty}")
        process_name = tmux_option_or_default("@codex-status-process-name", "codex")
        has_process = pane_has_process(pane_tty, process_name)
        if has_process:
            add_doctor_check(
                checks,
                "PASS",
                "pane process detection",
                f"Process `{process_name}` detected on {pane_tty}.",
            )
        else:
            add_doctor_check(
                checks,
                "WARN",
                "pane process detection",
                f"Process `{process_name}` was not detected on {pane_tty}.",
                "Start Codex in this pane or adjust `@codex-status-process-name`.",
            )

        window_id = tmux_pane_value(pane_id, "#{window_id}")
        if window_id == "":
            add_doctor_check(
                checks,
                "WARN",
                "window-badge command",
                "Current window id could not be resolved.",
                "Run doctor from an active tmux pane.",
            )
        elif not module_ok:
            add_doctor_check(
                checks,
                "FAIL",
                "window-badge command",
                "Skipped because module invocation check failed.",
                "Fix module invocation FAIL first.",
            )
        else:
            badge_code, badge_text = run_doctor_window_badge_check(
                python_bin,
                plugin_dir,
                window_id,
            )
            if badge_code != 0:
                add_doctor_check(
                    checks,
                    "FAIL",
                    "window-badge command",
                    "window-badge command failed.",
                    "Verify Python/module configuration and plugin path.",
                )
            elif has_process and badge_text == "":
                add_doctor_check(
                    checks,
                    "FAIL",
                    "window-badge command",
                    "window-badge returned empty output while Codex process is detected.",
                    "Verify process detection and tmux format configuration.",
                )
            elif has_process:
                add_doctor_check(
                    checks,
                    "PASS",
                    "window-badge command",
                    f"window-badge returned {badge_text!r}.",
                )
            else:
                add_doctor_check(
                    checks,
                    "WARN",
                    "window-badge command",
                    (
                        "Skipped strict badge assertion because Codex process "
                        "is not currently detected."
                    ),
                    "Run doctor while Codex is active in this pane.",
                )

    print_doctor_checks(checks)
    pass_count, warn_count, fail_count = doctor_summary(checks)
    print_line(f"Summary: {pass_count} PASS, {warn_count} WARN, {fail_count} FAIL")
    return 1 if fail_count > 0 else 0

def active_pane_ids() -> set[str]:
    output = tmux_run(["list-panes", "-a", "-F", "#{pane_id}"]).out
    return {line for line in output.splitlines() if line}

def stale_pane_id(env_line: str, active: set[str]) -> str:
    if env_line == "" or env_line.startswith("-"):
        return ""

    key = env_line.split("=", 1)[0]

    if key.startswith("TMUX_CODEX_PANE_") and key.endswith("_STATE"):
        pane_id = key.removeprefix("TMUX_CODEX_PANE_").removesuffix("_STATE")
    elif key.startswith("TMUX_CODEX_PANE_") and key.endswith("_UPDATED_AT"):
        pane_id = key.removeprefix("TMUX_CODEX_PANE_").removesuffix("_UPDATED_AT")
    else:
        return ""

    if pane_id in active:
        return ""

    return pane_id

def cmd_select_pane(session_name: str, window_index: str, pane_index: str) -> int:
    if not session_name or not window_index or not pane_index:
        return 0

    if not tmux_ready():
        return 0

    target_window = f"{session_name}:{window_index}"
    target_pane = f"{target_window}.{pane_index}"

    tmux_run(["switch-client", "-t", session_name])
    tmux_run(["select-window", "-t", target_window])
    tmux_run(["select-pane", "-t", target_pane])
    return 0

def cmd_pane_menu() -> int:

    if not tmux_ready():
        return 0

    cmd_refresh_pane_badges()
    menu_cmd = base_menu_command()
    index = append_menu_rows(menu_cmd)

    if index == 0:
        menu_cmd += ["No panes", "", ""]

    if os.environ.get("CODEX_STATUS_MENU_DRY_RUN") == "1":
        print(bash_quote_command(menu_cmd), end="")
        return 0

    run_cmd(menu_cmd)
    return 0

def base_menu_command() -> list[str]:
    title = tmux_run(["show-option", "-gqv", "@codex-status-menu-title"]).out.rstrip("\n")

    if title == "":
        title = "Codex Panes"

    return ["tmux", "display-menu", "-T", title, "-x", "C", "-y", "C"]

def append_menu_rows(menu_cmd: list[str]) -> int:
    icon = tmux_option_or_default("@codex-status-icon", "🤖")
    placeholder = badge_placeholder(icon)
    prefix = python_cli_prefix()

    index = 0

    for row in menu_rows():
        label = menu_row_label(row, icon, placeholder)
        key = menu_key_for_index(index)
        index += 1
        action = build_select_action(prefix, row[0], row[1], row[2])
        menu_cmd += [label, key, action]

    return index

def python_cli_prefix() -> str:
    python_bin = tmux_option_or_default("@codex-status-python", "python3")
    plugin_dir = tmux_option_or_default(
        "@codex-status-dir",
        os.path.expanduser("~/.tmux/plugins/tmux-codex-status"),
    )

    pythonpath = f"{plugin_dir}/src"

    return (
        f"PYTHONPATH={shlex.quote(pythonpath)} "
        f"{shlex.quote(python_bin)} -m tmux_codex_status.cli"
    )

def build_select_action(prefix: str, session: str, window: str, pane: str) -> str:
    session_q = shlex.quote(session)
    window_q = shlex.quote(window)
    pane_q = shlex.quote(pane)
    return f'run-shell "{prefix} select-pane {session_q} {window_q} {pane_q}"'

def badge_placeholder(icon: str) -> str:
    width = len(icon)
    if icon and not icon.isascii():
        width += 1
    return " " * width

def menu_rows() -> list[tuple[str, str, str, str, str, str]]:
    args = [
        "list-panes",
        "-a",
        "-F",
        "#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_id}\t[#{pane_current_command}]#{b:pane_current_path}\t#{@codex-status-pane-badge}",
    ]

    rows: list[tuple[str, str, str, str, str, str]] = []

    for line in tmux_run(args).out.splitlines():
        parts = line.split("\t", 5)

        if len(parts) != 6 or parts[3] == "":
            continue

        rows.append((parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]))
    return rows

def menu_row_label(
    row: tuple[str, str, str, str, str, str],
    icon: str,
    placeholder: str,
) -> str:

    session_name, window_index, pane_index, _, pane_label, pane_badge = row

    if pane_badge and icon:
        prefix = styled_pane_badge(pane_badge, icon)
        label = f"{prefix}S{session_name}:W{window_index}:P{pane_index} {pane_label}"
    else:
        label = f"{placeholder}S{session_name}:W{window_index}:P{pane_index} {pane_label}"
    return label.replace("\t", " ").replace("\n", " ")

def styled_pane_badge(pane_badge: str, icon: str) -> str:
    if icon == "":
        return ""

    state = badge_state(pane_badge)

    if state == "":
        return icon

    bg_color = state_bg_color(state)
    fg_color = adjusted_fg_color(state_fg_color(state), bg_color)

    return f"#[fg={fg_color},bg={bg_color}]{icon}#[default]"

def badge_state(pane_badge: str) -> str:
    if pane_badge.endswith("R"):
        return "R"
    if pane_badge.endswith("W"):
        return "W"
    if pane_badge.endswith("I"):
        return "I"
    if pane_badge.endswith("E"):
        return "E"
    return ""

def menu_key_for_index(index: int) -> str:
    if index < 9:
        return str(index + 1)
    if index < 35:
        return chr(97 + index - 9)
    return ""

def bash_quote_command(menu_cmd: list[str]) -> str:
    args = ["bash", "-lc", "printf '%q ' \"$@\"; printf '\\n'", "bash", *menu_cmd]
    return run_cmd(args).out
