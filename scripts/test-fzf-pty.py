#!/usr/bin/env python3
"""Exercise the shared fzf picker arguments through a real PTY.

The repository's shell fixtures validate generated arguments.  This test adds
the terminal boundary: the real fzf binary must render the context, preview,
and multi-selection controls, accept a multi-selection, and abort cleanly.
Only stdlib modules are used so the test can run in a small CI job.
"""

from __future__ import annotations

import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import termios
import textwrap
import time
from dataclasses import dataclass


REPO_ROOT = Path(__file__).resolve().parents[1]
ANSI_SGR = re.compile(rb"\x1b\[[0-9;]*m")
ANSI_CSI = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]")
ANSI_OSC = re.compile(rb"\x1b\][^\x07]*(?:\x07|\x1b\\)")
ANSI_SGR_PARAMS = re.compile(rb"\x1b\[([0-9;]*)m")


@dataclass(frozen=True)
class Case:
    name: str
    width: int
    glyphs: str
    no_color: bool
    action: str


CASES = (
    Case("narrow-unicode", 50, "unicode", False, "select"),
    Case("wide-ascii", 100, "ascii", False, "select"),
    Case("narrow-ascii-no-color", 50, "ascii", True, "cancel"),
    Case("wide-unicode-no-color", 100, "unicode", True, "select"),
)


CHILD_SCRIPT = textwrap.dedent(
    r'''
    emulate -L zsh
    setopt NO_UNSET

    repo_dir=$1
    typeset -g COLUMNS=${ZSH_PTY_WIDTH:-80}
    typeset -g LINES=24
    typeset -g ZSH_UI_THEME=terminal
    typeset -g ZSH_FZF_THEME=terminal
    typeset -g ZSH_FZF_LAYOUT=compact
    typeset -g ZSH_UI_GLYPHS=${ZSH_PTY_GLYPHS:-unicode}
    if [[ ${ZSH_PTY_NO_COLOR:-0} == 1 ]]; then
      typeset -g NO_COLOR=1
    else
      unset NO_COLOR
    fi

    source "$repo_dir/25-theme.zsh" || exit 10
    source "$repo_dir/40-fzf.zsh" || exit 11
    _fzf_require_ready || exit 17
    _zsh_theme_resolve_settings || exit 12
    _zsh_theme_fzf_chrome_args || exit 13
    local -a picker_args
    picker_args=( "${reply[@]}" )

    _fzf_picker_context_args 'PTY Rows' 'Type to filter rows' 'Enter choose  Tab mark  Selected 0  Esc close' || exit 14
    picker_args+=( "${reply[@]}" )
    _fzf_picker_preview_args Preview || exit 15
    picker_args+=( "${reply[@]}" --preview 'printf PREVIEW' )
    _fzf_picker_multi_args choose || exit 16
    picker_args+=( "${reply[@]}" --delimiter=$'\t' --with-nth=1,2 --accept-nth=2 --no-sort )

    local arg has_context=0 has_preview=0 has_multi=0 has_no_color=0
    local preview_position=unknown pointer=unknown
    for arg in "${picker_args[@]}"; do
      case $arg in
        '--border-label=PTY Rows') has_context=1 ;;
        '--preview-label=Preview') has_preview=1 ;;
        '--multi') has_multi=1 ;;
        '--no-color') has_no_color=1 ;;
        '--preview-window=right,'*) preview_position=right ;;
        '--preview-window=down,'*) preview_position=down ;;
        '--pointer='*) pointer=${arg#--pointer=} ;;
      esac
    done
    print -r -- "CONFIG_CONTEXT=$has_context CONFIG_PREVIEW=$has_preview CONFIG_MULTI=$has_multi CONFIG_NO_COLOR=$has_no_color"
    print -r -- "CONFIG_WIDTH=$COLUMNS CONFIG_GLYPHS=$_ZSH_UI_GLYPH_TIER CONFIG_PREVIEW_POSITION=$preview_position CONFIG_POINTER=$pointer"

    local selected rc
    selected=$(
      print -r -- $'alpha\talpha-value'
      print -r -- $'雪\t雪-value'
      print -r -- $'beta\tbeta-value'
    )
    selected=$(print -r -- "$selected" | "$FZF_BIN" "${picker_args[@]}" )
    rc=$?
    print -r -- "RESULT_RC=$rc"
    if [[ -n $selected ]]; then
      local -a selected_rows
      selected_rows=( "${(f)selected}" )
      print -r -- "RESULT_ROWS=${#selected_rows[@]}"
      print -r -- "RESULT_DATA=${(j:|:)selected_rows}"
    else
      print -r -- 'RESULT_ROWS=0'
      print -r -- 'RESULT_DATA='
    fi
    exit 0
    ''',
)


def set_window(fd: int, width: int, height: int = 24) -> None:
    """Tell the PTY and fzf the terminal size used by the scenario."""

    size = struct.pack("HHHH", height, width, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, size)


def read_available(master: int, output: bytearray) -> bool:
    """Drain currently available PTY bytes; return false after PTY closure."""

    try:
        chunk = os.read(master, 8192)
    except OSError as error:
        if error.errno == errno.EIO:
            return False
        raise
    if not chunk:
        return False
    output.extend(chunk)
    # fzf asks the terminal for its cursor position while entering raw mode.
    # A PTY is enough for input/output, but this small response keeps the
    # interaction deterministic without depending on a terminal emulator.
    for _ in range(chunk.count(b"\x1b[6n")):
        os.write(master, b"\x1b[1;1R")
    for _ in range(chunk.count(b"\x1b[?2004$p")):
        os.write(master, b"\x1b[?2004;1$y")
    return True


def read_until(
    master: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    marker: bytes,
    timeout: float,
) -> None:
    """Wait for a marker while enforcing a bound around interactive steps."""

    deadline = time.monotonic() + timeout
    while marker not in output:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise AssertionError(
                f"timed out waiting for {marker!r}; output was:\n{decode(output)}"
            )
        ready, _, _ = select.select([master], [], [], min(remaining, 0.25))
        if ready and not read_available(master, output):
            break
        if process.poll() is not None and not ready:
            break

    if marker not in output:
        raise AssertionError(
            f"process exited before {marker!r}; output was:\n{decode(output)}"
        )


def drain_until_exit(
    master: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    timeout: float,
) -> None:
    """Drain final screen updates and require the child to exit promptly."""

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            if not read_available(master, output):
                break
        elif process.poll() is not None:
            break
    # Linux can report PTY closure just before the child becomes waitable.
    # Reap it within the original deadline instead of treating that race as a
    # hang after all final output has already arrived.
    remaining = max(0.0, deadline - time.monotonic())
    if process.poll() is None and remaining > 0:
        try:
            process.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            pass
    if process.poll() is None:
        raise AssertionError(f"PTY child did not exit; output was:\n{decode(output)}")


def decode(value: bytes | bytearray) -> str:
    return bytes(value).decode("utf-8", errors="replace")


def strip_terminal_controls(value: bytes | bytearray) -> bytes:
    """Remove terminal drawing controls while preserving rendered text."""

    plain = ANSI_OSC.sub(b"", bytes(value))
    plain = ANSI_CSI.sub(b"", plain)
    return plain.replace(b"\x1b", b"")


def colored_sgr_sequences(value: bytes | bytearray) -> list[bytes]:
    """Return SGRs carrying a foreground/background color selection."""

    colored: list[bytes] = []
    for sequence in ANSI_SGR_PARAMS.finditer(bytes(value)):
        parameters = [int(part or 0) for part in sequence.group(1).split(b";")]
        if any(
            parameter in {38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 58, 59}
            or 30 <= parameter <= 37
            or 90 <= parameter <= 97
            or 100 <= parameter <= 107
            for parameter in parameters
        ):
            colored.append(sequence.group(0))
    return colored


def result_value(output: str, key: str) -> str:
    prefix = f"{key}="
    for line in output.splitlines():
        if line.startswith(prefix):
            return line[len(prefix) :]
    raise AssertionError(f"missing {prefix!r} in output:\n{output}")


def kill_process_group(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=1)


def run_case(zsh_bin: str, fzf_bin: str, case: Case) -> None:
    environment = os.environ.copy()
    environment.update(
        {
            "FZF_BIN": fzf_bin,
            "PATH": str(Path(fzf_bin).parent) + os.pathsep + os.environ.get("PATH", ""),
            "ZSH_PTY_WIDTH": str(case.width),
            "ZSH_PTY_GLYPHS": case.glyphs,
            "ZSH_PTY_NO_COLOR": "1" if case.no_color else "0",
            "TERM": "xterm-256color",
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
        }
    )
    for name in (
        "FZF_DEFAULT_OPTS",
        "FZF_CTRL_T_OPTS",
        "FZF_CTRL_R_OPTS",
        "FZF_ALT_C_OPTS",
        "FZF_COMPLETION_OPTS",
        "FZF_COMPLETION_PATH_OPTS",
        "FZF_COMPLETION_DIR_OPTS",
    ):
        environment.pop(name, None)
    if case.no_color:
        environment["NO_COLOR"] = "1"
    else:
        environment.pop("NO_COLOR", None)

    master, slave = pty.openpty()
    set_window(master, case.width)
    process = subprocess.Popen(
        [zsh_bin, "-f", "-c", CHILD_SCRIPT, "zsh", str(REPO_ROOT)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=environment,
        close_fds=True,
        start_new_session=True,
    )
    os.close(slave)
    output = bytearray()
    try:
        read_until(master, process, output, b"CONFIG_CONTEXT=1", 5.0)
        read_until(master, process, output, b"Search", 5.0)

        if case.action == "select":
            os.write(master, b"\x10\x10")  # shared Ctrl-P preview toggle off/on
            read_until(master, process, output, b"PREVIEW", 3.0)
            os.write(master, b"\t\t\r")
        else:
            os.write(master, b"\x1b")  # fzf's cancellation key

        drain_until_exit(master, process, output, 5.0)
        status = process.returncode
        if status != 0:
            raise AssertionError(f"zsh PTY child exited {status}:\n{decode(output)}")
    finally:
        kill_process_group(process)
        os.close(master)

    rendered = decode(strip_terminal_controls(output))
    if result_value(rendered, "CONFIG_CONTEXT") != "1 CONFIG_PREVIEW=1 CONFIG_MULTI=1 CONFIG_NO_COLOR=" + (
        "1" if case.no_color else "0"
    ):
        raise AssertionError(f"shared picker arguments were not all present:\n{rendered}")

    expected_position = "right" if case.width >= 100 else "down"
    width_line = result_value(rendered, "CONFIG_WIDTH")
    if f"CONFIG_WIDTH={case.width}" not in rendered:
        raise AssertionError(f"terminal width was not propagated for {case.name}:\n{rendered}")
    if f"CONFIG_GLYPHS={case.glyphs}" not in width_line:
        raise AssertionError(f"glyph tier was not resolved for {case.name}:\n{rendered}")
    if f"CONFIG_PREVIEW_POSITION={expected_position}" not in width_line:
        raise AssertionError(f"preview position was wrong for {case.name}:\n{rendered}")

    if case.no_color:
        if "CONFIG_NO_COLOR=1" not in rendered:
            raise AssertionError(f"NO_COLOR did not reach fzf args for {case.name}:\n{rendered}")
        unexpected_sgr = colored_sgr_sequences(output)
        if unexpected_sgr:
            raise AssertionError(f"NO_COLOR still emitted colored SGR for {case.name}: {unexpected_sgr!r}")
    elif "CONFIG_NO_COLOR=0" not in rendered:
        raise AssertionError(f"color mode unexpectedly changed for {case.name}:\n{rendered}")

    if case.action == "select":
        if result_value(rendered, "RESULT_RC") != "0":
            raise AssertionError(f"selection did not complete: {rendered}")
        if result_value(rendered, "RESULT_ROWS") != "2":
            raise AssertionError(f"multi-selection did not return two rows: {rendered}")
        data = result_value(rendered, "RESULT_DATA")
        if "alpha-value" not in data or "雪-value" not in data:
            raise AssertionError(f"stable selected fields were not returned: {rendered}")
    else:
        if result_value(rendered, "RESULT_RC") == "0":
            raise AssertionError(f"cancellation returned success: {rendered}")
        if result_value(rendered, "RESULT_ROWS") != "0":
            raise AssertionError(f"cancellation returned selected rows: {rendered}")


def fzf_version(fzf_bin: str) -> str:
    completed = subprocess.run(
        [fzf_bin, "--version"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=5,
    )
    return completed.stdout.strip().split()[0]


def main() -> int:
    fzf_bin = os.environ.get("FZF_BIN") or shutil.which("fzf")
    if not fzf_bin:
        print("fatal: fzf is required; set FZF_BIN or put fzf on PATH", file=sys.stderr)
        return 2
    zsh_bin = shutil.which("zsh")
    if not zsh_bin:
        print("fatal: zsh is required; put zsh on PATH", file=sys.stderr)
        return 2

    actual_version = fzf_version(fzf_bin)
    expected_version = os.environ.get("FZF_EXPECTED_VERSION")
    if expected_version and actual_version != expected_version:
        print(
            f"fatal: expected fzf {expected_version}, found {actual_version}",
            file=sys.stderr,
        )
        return 1
    print(f"fzf {actual_version}: PTY picker checks")

    for case in CASES:
        print(f"case {case.name}: width={case.width} glyphs={case.glyphs} no_color={case.no_color}")
        run_case(zsh_bin, fzf_bin, case)
        print(f"ok: {case.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
