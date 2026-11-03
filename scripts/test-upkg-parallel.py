#!/usr/bin/env python3
"""Exercise upkg --parallel with stubbed managers.

Checks that queries overlap, that results keep the usual manager order, that
search rows merge in that order, that non-query commands ignore the flag, and
that a real terminal Ctrl-C stops every manager and cleans up. No package
manager is executed. Only stdlib modules are used.
"""

from __future__ import annotations

import os
from pathlib import Path
import pty
import re
import select
import signal
import stat
import subprocess
import sys
import tempfile
import time


REPO_ROOT = Path(__file__).resolve().parents[1]
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
SLOW = 1.0

STUBS = {
    # flatpak is slowest and first, so a later manager finishes before it.
    "flatpak": f"""#!/bin/sh
echo "$$" >> "$STUB_PIDS"
case "$*" in
  *search*) sleep {SLOW}; printf 'org.example.App\\t1.0\\tApp\\tFrom flatpak\\n' ;;
  *) sleep {SLOW}; echo 'org.example.App update' ;;
esac
""",
    "brew": f"""#!/bin/sh
echo "$$" >> "$STUB_PIDS"
case "$*" in
  outdated) sleep {SLOW}; echo 'brew-pkg (1.0) < 2.0' ;;
  upgrade) echo "brew upgraded in order" ;;
  *) exit 1 ;;
esac
""",
    "npm": f"""#!/bin/sh
echo "$$" >> "$STUB_PIDS"
case "$*" in
  *search*) sleep 0.1; printf 'npm-pkg\\tFrom npm\\tauthor\\t2026-01-01\\t1.0.0\\tkw\\n' ;;
  *outdated*) sleep 0.1 ;;
  *) exit 1 ;;
esac
""",
}


def check(condition: bool, label: str, output: str = "") -> None:
    if not condition:
        print(f"not ok: {label}\n{output}", file=sys.stderr)
        sys.exit(1)
    print(f"ok: {label}")


def make_env(work: Path) -> dict[str, str]:
    home = work / "home"
    (home / ".config").mkdir(parents=True)
    (home / ".config" / "zsh").symlink_to(REPO_ROOT)
    stubs = work / "bin"
    stubs.mkdir()
    for name, body in STUBS.items():
        tool = stubs / name
        tool.write_text(body)
        tool.chmod(tool.stat().st_mode | stat.S_IXUSR)
    tmp = work / "tmp"
    tmp.mkdir()
    return dict(
        os.environ,
        HOME=str(home),
        XDG_CACHE_HOME=str(home / "cache"),
        XDG_DATA_HOME=str(home / "data"),
        ZSH_HISTFILE=str(home / "history"),
        TMPDIR=str(tmp),
        STUB_PIDS=str(work / "pids"),
        PATH=f"{stubs}:{os.environ['PATH']}",
        LC_ALL="C.UTF-8",
        NO_COLOR="1",
    )


def run_plain(env: dict[str, str], command: str) -> tuple[int, str, float]:
    script = f'source "$HOME/.config/zsh/init.zsh"\n{command}'
    start = time.monotonic()
    result = subprocess.run(["zsh", "-dfc", script], env=env, capture_output=True, text=True, timeout=60)
    return result.returncode, result.stdout + result.stderr, time.monotonic() - start


def test_order_and_overlap(env: dict[str, str]) -> None:
    status, output, elapsed = run_plain(env, "upkg plan --only flatpak,brew,npm --parallel")
    check(status == 0, "parallel plan exits 0", output)
    check(elapsed < SLOW * 2 - 0.1, f"managers overlap ({elapsed:.1f}s against {SLOW * 2:.1f}s in sequence)", output)
    order = [output.index(f"==> {name}") for name in ("Flatpak", "Homebrew", "npm")]
    check(order == sorted(order), "results keep the requested manager order", output)
    check("org.example.App update" in output and "brew-pkg" in output, "captured output is printed", output)
    for name in ("flatpak", "brew", "npm"):
        check(re.search(rf"{name}: [^\n|]+ \| elapsed \d", output) is not None, f"{name} keeps its own elapsed time", output)
    check("clock moved backward" not in output, "overlap is not mistaken for a clock problem", output)
    check("Total elapsed (plan): " in output, "the total is still reported", output)
    leftovers = list(Path(env["TMPDIR"]).iterdir())
    check(not leftovers, "no temporary files remain after a parallel run", str(leftovers))


def test_search_merges_in_order(env: dict[str, str]) -> None:
    status, output, _ = run_plain(env, "upkg search sample --only flatpak,npm --parallel")
    check(status == 0, "parallel search exits 0", output)
    check(output.index("org.example.App") < output.index("npm-pkg"), "search rows merge in manager order", output)
    check("2 result(s) across 2 manager(s)" in output, "search counts every manager's rows", output)


def test_mutating_commands_ignore_the_flag(env: dict[str, str]) -> None:
    status, output, _ = run_plain(env, "upkg upgrade --only brew,npm --skip npm --parallel")
    check(status == 0, "a command that changes packages accepts and ignores --parallel", output)
    check("brew upgraded in order" in output, "the upgrade still runs its native command", output)


def test_terminal_ctrl_c(env: dict[str, str], work: Path) -> None:
    env = dict(env, TERM="xterm-256color", COLUMNS="100", LINES="40")
    env.pop("NO_COLOR", None)
    pids = Path(env["STUB_PIDS"])
    pids.unlink(missing_ok=True)
    pid, master = pty.fork()
    if pid == 0:
        os.execvpe("zsh", ["zsh", "-dfi"], env)

    buffer = ""

    def expect(needle: str, deadline: float = 20.0) -> str:
        nonlocal buffer
        end = time.monotonic() + deadline
        while needle not in buffer:
            if time.monotonic() > end:
                raise AssertionError(f"timed out waiting for {needle!r}; saw {buffer!r}")
            if select.select([master], [], [], 0.1)[0]:
                buffer += os.read(master, 65536).decode("utf-8", "replace")
        head, _, buffer = buffer.partition(needle)
        return head

    try:
        os.write(master, b"source \"$HOME/.config/zsh/init.zsh\"; PS1='READY> '\n")
        expect("READY> ")
        os.write(master, b"upkg plan --only flatpak,brew --parallel; print -r -- \"status=$?\" DO''NE\n")
        expect("Checking")
        time.sleep(0.3)
        os.write(master, b"\x03")
        output = ANSI.sub("", expect("DONE"))
        check("status=130" in output, "Ctrl-C makes a parallel run return 130", output)
        check("cancelled" in output, "the summary reports cancelled managers", output)
        check("so far" in output, "the total ends in 'so far'", output)
        leftovers = sorted(path.name for path in Path(env["TMPDIR"]).iterdir())
        check(not leftovers, "Ctrl-C leaves no temporary files", str(leftovers))
    finally:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        os.close(master)

    # Stubs exec nothing, so their PIDs stay valid long enough to check them.
    time.sleep(0.2)
    alive = []
    for line in pids.read_text().split():
        try:
            state = Path(f"/proc/{line}/stat").read_text().rsplit(") ", 1)[1].split()[0]
        except OSError:
            continue
        if state != "Z":
            alive.append(line)
    check(not alive, "Ctrl-C stops every manager's native query", str(alive))


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="zsh-upkg-parallel-") as name:
        work = Path(name)
        env = make_env(work)
        test_order_and_overlap(env)
        test_search_merges_in_order(env)
        test_mutating_commands_ignore_the_flag(env)
        test_terminal_ctrl_c(env, work)


if __name__ == "__main__":
    main()
