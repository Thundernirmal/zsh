#!/usr/bin/env python3
"""Press Ctrl-C at the cgm set prompt in a real interactive shell.

An interactive Zsh aborts the running function when a foreground child dies
from SIGINT, so only a real terminal shows what a cancelled prompt leaves
behind. secret-tool is a stub, so no Secret Service is contacted. Only stdlib
modules are used.
"""

from __future__ import annotations

import os
from pathlib import Path
import pty
import select
import signal
import stat
import tempfile
import time


REPO_ROOT = Path(__file__).resolve().parents[1]
DEADLINE = 20.0


class Terminal:
    def __init__(self, master: int) -> None:
        self.master = master
        self.buffer = ""

    def send(self, text: str) -> None:
        os.write(self.master, text.encode())

    def expect(self, needle: str) -> str:
        end = time.monotonic() + DEADLINE
        while needle not in self.buffer:
            if time.monotonic() > end:
                raise AssertionError(f"timed out waiting for {needle!r}; saw {self.buffer!r}")
            if select.select([self.master], [], [], 0.1)[0]:
                try:
                    self.buffer += os.read(self.master, 65536).decode("utf-8", "replace")
                except OSError as error:
                    raise AssertionError(f"terminal closed; saw {self.buffer!r}") from error
        head, _, self.buffer = self.buffer.partition(needle)
        return head


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="zsh-cgm-pty-") as work_name:
        work = Path(work_name)
        home = work / "home"
        (home / ".config").mkdir(parents=True)
        (home / ".config" / "zsh").symlink_to(REPO_ROOT)
        stubs = work / "bin"
        stubs.mkdir()
        tool = stubs / "secret-tool"
        tool.write_text('#!/bin/sh\necho "stub-prompt: $1" >&2\nexec sleep 30\n')
        tool.chmod(tool.stat().st_mode | stat.S_IXUSR)
        data = home / "data"

        env = dict(
            os.environ,
            HOME=str(home),
            XDG_DATA_HOME=str(data),
            XDG_CACHE_HOME=str(home / "cache"),
            ZSH_HISTFILE=str(home / "history"),
            TERM="xterm-256color",
            LC_ALL="C.UTF-8",
            PATH=f"{stubs}:{os.environ['PATH']}",
            NO_COLOR="1",
        )
        pid, master = pty.fork()
        if pid == 0:
            os.execvpe("zsh", ["zsh", "-dfi"], env)
        terminal = Terminal(master)
        try:
            terminal.send("source \"$HOME/.config/zsh/init.zsh\"; PS1='READY> '\n")
            terminal.expect("READY> ")
            terminal.send("cgm set PHANTOM_TOKEN\n")
            terminal.expect("stub-prompt: store")
            terminal.send("\x03")
            terminal.expect("READY> ")
            terminal.send("cgm list; print -r -- LIST''DONE\n")
            listing = terminal.expect("LISTDONE")
            # The first LISTDONE-free text holds the echoed command and the output.
            assert "No credentials saved." in listing, listing
            assert not (data / "cgm" / "entries" / "PHANTOM_TOKEN").exists()
        finally:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
            os.close(master)
    print("ok: Ctrl-C at the cgm set prompt records no credential name")


if __name__ == "__main__":
    main()
