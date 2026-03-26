from __future__ import annotations

import json
import re

SESSION_DONE_EVENT = "agent-turn-complete"
RUN_EVENTS = {
    "start",
    "session-start",
    "turn-start",
    "agent-turn-start",
    "task-start",
    "task-started",
    "task_started",
    "working",
    "running",
}
KEEP_EVENTS = {
    "user-message",
    "user_message",
    "agent-message",
    "agent_message",
    "token-count",
    "token_count",
}
WAIT_EVENTS = {
    "task-complete",
    "task_complete",
    "turn-aborted",
    "turn_aborted",
    "agent-turn-complete",
    "turn-completed",
    "complete",
    "completed",
    "done",
    "stop",
    "waiting",
    "idle",
}
INPUT_EVENTS = {"needs-input", "input-required", "ask-user", "approval-requested"}
ERROR_EVENTS = {"error", "errored", "failed"}
TASK_EVENTS = {"task_started", "task_complete", "turn_aborted"}

PAYLOAD_TYPE_RE = re.compile(r'"payload"\s*:\s*\{[^}]*"type"\s*:\s*"([^"]*)"')
TYPE_RE = re.compile(r'"type"\s*:\s*"([^"]*)"')

def extract_event_from_notify_arg(raw_arg: str | None) -> str:
    raw = raw_arg or ""

    if raw == "":
        return SESSION_DONE_EVENT

    if raw.startswith("{"):
        event = extract_json_event(raw)
        if event:
            return event
    return raw

def extract_json_event(raw: str) -> str:
    parsed = parse_json_event(raw)

    if parsed:
        return parsed
    return parse_json_event_fallback(raw)

def parse_json_event(raw: str) -> str:

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return ""

    if not isinstance(payload, dict):
        return ""
    
    msg_type = payload.get("type")
    inner = payload.get("payload")

    if msg_type == "event_msg" and isinstance(inner, dict):
        event = inner.get("type")
        if isinstance(event, str):
            return event
    
    if isinstance(msg_type, str):
        return msg_type

    if isinstance(inner, dict) and isinstance(inner.get("type"), str):
        return str(inner["type"])
    
    return ""

def parse_json_event_fallback(raw: str) -> str:
    payload_match = PAYLOAD_TYPE_RE.search(raw)
    if payload_match:
        return payload_match.group(1)
    
    outer_match = TYPE_RE.search(raw)
    if outer_match:
        return outer_match.group(1)
    
    return ""

def map_event_to_state(event: str | None) -> str:
    normalized = (event or SESSION_DONE_EVENT).lower()
    if normalized in RUN_EVENTS:
        return "R"

    if normalized in KEEP_EVENTS:
        return "K"

    if normalized.startswith("permission") or normalized.startswith("approv"):
        return "I"

    if normalized in INPUT_EVENTS:
        return "I"

    if normalized in ERROR_EVENTS or normalized.startswith("fail"):
        return "E"

    if normalized in WAIT_EVENTS:
        return "W"

    return "W"

def normalize_state(state: str | None) -> str:
    normalized = (state or "W").upper()
    if normalized in {"R", "W", "I", "E"}:
        return normalized
    return "W"

def state_rank(state: str | None) -> int:
    normalized = normalize_state(state)
    if normalized == "E":
        return 4
    if normalized == "I":
        return 3
    if normalized == "R":
        return 2
    if normalized == "W":
        return 1
    return 0

def map_task_event_to_state(event: str | None) -> str:
    if event == "task_started":
        return "R"
    if event in {"task_complete", "turn_aborted"}:
        return "W"
    return ""

