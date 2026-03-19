from tmux_codex_status.state import (
    extract_event_from_notify_arg,
    map_event_to_state,
    normalize_state,
    state_rank,
)


def test_map_event_to_state() -> None:
    assert map_event_to_state("start") == "R"
    assert map_event_to_state("task_started") == "R"
    assert map_event_to_state("user_message") == "K"
    assert map_event_to_state("approval-requested") == "I"
    assert map_event_to_state("fail-hard") == "E"
    assert map_event_to_state("turn_aborted") == "W"
    assert map_event_to_state("unknown") == "W"



def test_extract_event_from_notify_arg() -> None:
    assert extract_event_from_notify_arg("") == "agent-turn-complete"
    assert (
        extract_event_from_notify_arg('{"type":"event_msg","payload":{"type":"task_started"}}')
        == "task_started"
    )
    assert extract_event_from_notify_arg('{"type":"approval-requested"}') == "approval-requested"
    assert extract_event_from_notify_arg("working") == "working"



def test_normalize_and_rank() -> None:
    assert normalize_state("r") == "R"
    assert normalize_state("invalid") == "W"
    assert state_rank("E") == 4
    assert state_rank("I") == 3
    assert state_rank("R") == 2
    assert state_rank("W") == 1
    assert state_rank("unknown") == 1
