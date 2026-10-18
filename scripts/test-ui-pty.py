#!/usr/bin/env python3
"""Characterize rich UI output and live terminal checks through a real PTY."""
import errno
import hashlib
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def run(script, tty=True):
    env = dict(os.environ, TERM="xterm-256color", COLORTERM="truecolor",
               LC_ALL="C.UTF-8", NO_COLOR="", ZSH_UI_THEME="terminal")
    with tempfile.TemporaryDirectory(prefix="zsh-ui-test-") as work:
        env.update(HOME=work, XDG_CACHE_HOME=work, XDG_DATA_HOME=work)
        args = ["zsh", "-dfc", 'source "$1/55-ui-helpers.zsh"\n' + script, "test", str(ROOT)]
        if not tty:
            return subprocess.check_output(args, env=env, timeout=30)
        master, slave = pty.openpty()
        with tempfile.TemporaryFile() as errors:
            child = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=slave, stderr=errors, env=env)
            os.close(slave)
            output = bytearray()
            deadline = time.monotonic() + 30
            try:
                while True:
                    if time.monotonic() > deadline:
                        raise TimeoutError("UI PTY test timed out")
                    if not select.select([master], [], [], .1)[0]:
                        continue
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not chunk:
                        break
                    output.extend(chunk)
                child.wait(timeout=5)
                errors.seek(0)
                assert child.returncode == 0, (child.returncode, errors.read().decode(errors="replace"), bytes(output))
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()
                os.close(master)
            return bytes(output).replace(b"\r\n", b"\n")


# Frozen pre-C01 predicate: compare presentation and scratch state, not timings.
REFERENCE = r'''
_ui_is_rich_terminal() {
  emulate -L zsh
  local width
  [[ -t 1 && -n ${TERM:-} && $TERM != dumb && -z ${NO_COLOR:-} ]] || return 1
  _ui_locale_is_utf8 || return 1
  width=$(_ui_term_width)
  (( width >= 60 ))
}
'''
MATRIX = r'''
for ZSH_UI_THEME in terminal nord; do
  _zsh_theme_resolve_settings || exit 10
  for _ZSH_UI_COLOR_DEPTH in ansi 256 truecolor; do
    for COLUMNS in 59 60 120; do
      for mode in rich no-color dumb ascii-locale; do
        NO_COLOR= TERM=xterm-256color LC_ALL=C.UTF-8
        case $mode in no-color) NO_COLOR=1;; dumb) TERM=dumb;; ascii-locale) LC_ALL=C;; esac
        REPLY=sentinel; reply=(one two)
        _ui_panel_kv Key Value
        _ui_section_break
        _ui_status_icon upgraded
        print -r -- "scratch=$REPLY:${(j:,:)reply}"
      done
    done
  done
done
'''


# Direct TTY truncation selects the Unicode marker while captured calls see a
# pipe and select ASCII; both are frozen from the pre-fast-path helpers.
TRUNCATION = r'''
source "$1/lib/functions-common.zsh"
COLUMNS=100
for _ZSH_UI_GLYPH_TIER in unicode ascii; do
  for text in abcdefghijklmnop 'ab雪cdefgh雪ijklmn' $'éxyzabcdefghij' 'tab\there\nnext line'; do
    for w in 1 2 4 10; do
      REPLY=sentinel
      _ui_truncate_reply $w "$text"; print -r -- "direct-trunc $w ${(q)text} [$REPLY]"
      print -r -- "captured-trunc $w ${(q)text} [$(_ui_truncate $w "$text")]"
      _ui_pad_reply left $w "$text"; print -r -- "direct-pad $w ${(q)text} [$REPLY]"
      REPLY=sentinel
      print -rn -- "direct-safe $w ${(q)text} ["; _ui_safe_truncate $w "$text"; print -r -- "] scratch=$REPLY"
      print -r -- "captured-safe $w ${(q)text} [$(_ui_safe_truncate $w "$text")]"
    done
  done
done
'''
TRUNCATION_SHA256 = "3cc3bf37f8418e5bf14dc14126a1cefbaeebf538e879435db86df5fbdb39a85a"


def main():
    for tty in (True, False):
        assert run(MATRIX, tty) == run(REFERENCE + MATRIX, tty)
    run(r'''
REPLY=sentinel; reply=(one two)
mkdir "$HOME/bin"
print -rl -- '#!/bin/sh' 'echo tput >> "$HOME/calls"; echo 80' > "$HOME/bin/tput"
chmod +x "$HOME/bin/tput"
path=("$HOME/bin" $path)
for COLUMNS in 60 120 59 60; do
  _ui_is_rich_terminal; rc=$?
  (( COLUMNS < 60 ? rc == 1 : rc == 0 )) || exit 11
done
[[ ! -e $HOME/calls && $REPLY == sentinel && ${(j:,:)reply} == one,two ]] || exit 12
unset COLUMNS
_ui_is_rich_terminal || exit 13
[[ -s $HOME/calls ]] || exit 14
# Hide the special integer type to exercise the defensive invalid-value path.
() { local -h COLUMNS=invalid; _ui_is_rich_terminal || exit 15; }
[[ $(<"$HOME/calls") == $'tput\ntput' && $REPLY == sentinel ]] || exit 16
functions[_ui_term_height]='print -r -- 12'
[[ $(_ui_visible_count 20 20 3) == 9 ]] || exit 17
''')
    # Exercise real missing-width fallback with failing tput, without host terminfo.
    run(r'''
unset COLUMNS
mkdir "$HOME/bin"
print -r -- '#!/bin/sh' 'exit 1' > "$HOME/bin/tput"
chmod +x "$HOME/bin/tput"
path=("$HOME/bin")
[[ $(_ui_term_width) == 80 ]] || exit 18
_ui_is_rich_terminal || exit 19
''')
    output = run(TRUNCATION)
    assert b"direct-trunc 10 abcdefghijklmnop [abcd\xe2\x80\xa6lmnop]" in output, output
    assert b"captured-trunc 10 abcdefghijklmnop [abc...mnop]" in output, output
    assert b"direct-safe 4 abcdefghijklmnop [a\xe2\x80\xa6op\n] scratch=op" in output, output
    assert hashlib.sha256(output).hexdigest() == TRUNCATION_SHA256, output.decode(errors="replace")
    print("ok: UI PTY parity, live width, fallback, scratch state, and public height override")


if __name__ == "__main__":
    main()
