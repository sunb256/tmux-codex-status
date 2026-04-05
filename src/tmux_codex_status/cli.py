from __future__ import annotations

import argparse
import sys

from .commands import (
    cmd_doctor,
    cmd_extract_event,
    cmd_map_event,
    cmd_normalize_state,
    cmd_notify,
    cmd_pane_menu,
    cmd_refresh_pane_badges,
    cmd_select_pane,
    cmd_setup,
    cmd_state_gc,
    cmd_state_rank,
    cmd_window_badge,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="tmux-codex-status")
    sub = parser.add_subparsers(dest="command", required=True)

    extract_parser = sub.add_parser("extract-event")
    extract_parser.add_argument("raw_arg", nargs="?")

    map_parser = sub.add_parser("map-event")
    map_parser.add_argument("event", nargs="?")

    normalize_parser = sub.add_parser("normalize-state")
    normalize_parser.add_argument("state", nargs="?")

    rank_parser = sub.add_parser("state-rank")
    rank_parser.add_argument("state", nargs="?")

    notify_parser = sub.add_parser("notify")
    notify_parser.add_argument("raw_arg", nargs="?")

    window_parser = sub.add_parser("window-badge")
    window_parser.add_argument("window_id", nargs="?")
    window_parser.add_argument("output_mode", nargs="?")

    sub.add_parser("refresh-pane-badges")
    sub.add_parser("pane-menu")
    sub.add_parser("state-gc")
    sub.add_parser("doctor")
    setup_parser = sub.add_parser("setup")
    setup_parser.add_argument("--apply", action="store_true")
    setup_parser.add_argument("--plugin-dir")
    setup_parser.add_argument("--tmux-conf")
    setup_parser.add_argument("--codex-config")

    select_parser = sub.add_parser("select-pane")
    select_parser.add_argument("session_name", nargs="?")
    select_parser.add_argument("window_index", nargs="?")
    select_parser.add_argument("pane_index", nargs="?")
    return parser

def dispatch(args: argparse.Namespace) -> int:
    if args.command == "extract-event":
        return cmd_extract_event(args.raw_arg)
    if args.command == "map-event":
        return cmd_map_event(args.event)
    if args.command == "normalize-state":
        return cmd_normalize_state(args.state)
    if args.command == "state-rank":
        return cmd_state_rank(args.state)
    if args.command == "notify":
        return cmd_notify(args.raw_arg)
    if args.command == "window-badge":
        return cmd_window_badge(args.window_id, args.output_mode)
    if args.command == "refresh-pane-badges":
        return cmd_refresh_pane_badges()
    if args.command == "pane-menu":
        return cmd_pane_menu()
    if args.command == "state-gc":
        return cmd_state_gc()
    if args.command == "doctor":
        return cmd_doctor()
    if args.command == "setup":
        return cmd_setup(args.apply, args.plugin_dir, args.tmux_conf, args.codex_config)
    if args.command == "select-pane":
        return cmd_select_pane(args.session_name, args.window_index, args.pane_index)
    return 1

def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    parsed = parser.parse_args(argv)
    return dispatch(parsed)

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
