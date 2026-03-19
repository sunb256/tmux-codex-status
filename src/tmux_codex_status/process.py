from __future__ import annotations

import shutil
import subprocess
from collections.abc import Sequence
from dataclasses import dataclass


@dataclass(frozen=True)
class CmdResult:
    code: int
    out: str
    err: str


def has_command(name: str) -> bool:
    return shutil.which(name) is not None


def run_cmd(args: Sequence[str], text_input: str | None = None) -> CmdResult:
    proc = subprocess.run(
        list(args),
        input=text_input,
        text=True,
        capture_output=True,
        check=False,
    )
    return CmdResult(
        code=proc.returncode,
        out=proc.stdout or "",
        err=proc.stderr or "",
    )
