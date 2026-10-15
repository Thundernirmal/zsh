#!/usr/bin/env python3
"""Test the actual exported Ctrl-T preview with a controlled backend PATH."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="zsh-preview-test-") as work:
        work = Path(work)
        tools = work / "bin"
        tools.mkdir()
        for name in ("sed", "ls"):
            (tools / name).symlink_to(shutil.which(name))
        zsh = shutil.which("zsh")
        env = dict(os.environ, HOME=str(work), XDG_CACHE_HOME=str(work / "cache"),
                   XDG_DATA_HOME=str(work / "data"), TERM="xterm-256color")
        for name in list(env):
            if name.startswith("FZF_"):
                del env[name]
        fixtures = [b"", b"one", b"x\n" * 199, b"x\n" * 200,
                    b"x\n" * 201, b"x\n" * 199 + b"last", b"a\0\x1b\r\n" * 201]
        for no_color in ("", "1"):
            env["NO_COLOR"] = no_color
            preview = subprocess.check_output([zsh, "-dfc", r'''
source "$1/25-theme.zsh"
source "$1/40-fzf.zsh"
_fzf_require_ready || exit 1
local arg
for arg in ${(z)FZF_CTRL_T_OPTS}; do
  arg=${(Q)arg}
  [[ $arg == --preview=* ]] && print -r -- "${arg#--preview=}"
done
exit 0
''', "test", str(ROOT)], env=env, text=True).strip()
            assert preview and '200Q' in preview

            def execute(path, timeout=5):
                return subprocess.run([zsh, "-dfc", preview.replace("{}", shlex.quote(str(path)))],
                                      env=dict(env, PATH=str(tools)), capture_output=True, timeout=timeout)

            target = work / "- quoted ' file"
            for data in fixtures:
                target.write_bytes(data)
                expected = subprocess.run(["sed", "-n", "1,200p", "--", str(target)], env=dict(env, PATH=str(tools)), capture_output=True)
                actual = execute(target)
                assert (actual.stdout, actual.stderr, actual.returncode) == (expected.stdout, expected.stderr, expected.returncode)
            target.unlink()
            expected = subprocess.run(["sed", "-n", "1,200p", "--", str(target)], env=dict(env, PATH=str(tools)), capture_output=True)
            actual = execute(target)
            assert (actual.stdout, actual.stderr, actual.returncode) == (expected.stdout, expected.stderr, expected.returncode)
            target.write_bytes(b"unreadable\n")
            target.chmod(0)
            expected = subprocess.run(["sed", "-n", "1,200p", "--", str(target)], env=dict(env, PATH=str(tools)), capture_output=True)
            actual = execute(target)
            assert (actual.stdout, actual.stderr, actual.returncode) == (expected.stdout, expected.stderr, expected.returncode)
            target.chmod(0o600)
            # Keep the producer open: a full-file scan would hang awaiting EOF.
            fifo = work / "stream"
            os.mkfifo(fifo)
            fd = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
            try:
                os.write(fd, b"x\n" * 200)
                actual = execute(fifo, timeout=3)
                assert actual.returncode == 0 and actual.stdout == b"x\n" * 200
            finally:
                os.close(fd)
                fifo.unlink()
            assert execute(work).returncode == 0
            bat = tools / "bat"
            bat.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
            bat.chmod(0o700)
            actual = execute(target)
            assert b"--line-range=:200" in actual.stdout
            assert (b"--color=never" if no_color else b"--color=always") in actual.stdout
            bat.unlink()
    print("ok: exported file previews preserve bytes/errors/backends and stop at line 200 without EOF")


if __name__ == "__main__":
    main()
