#!/usr/bin/env python3
"""Exercise upkg elapsed timing through a real PTY.

Shell fixtures inject deterministic clock samples.  This test keeps the real
clock and terminal boundary: a fake native prompt must read its answer from the
TTY, the wait before answering must be included in the elapsed time, and a
terminal Ctrl-C must keep the interrupted manager's time and a partial total.
A terminal with unset or invalid COLUMNS must still wrap long rows without
running tput. A child that outlives the deadline is terminated and reaped, so
a regression fails instead of hanging. Only stdlib modules are used, and no
package manager is executed.
"""

from __future__ import annotations

import os
from pathlib import Path
import pty
import re
import select
import signal
import sys
import tempfile
import textwrap
import time


REPO_ROOT = Path(__file__).resolve().parents[1]
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
PROMPT_DELAY = 1.5
CANCEL_DELAY = 1.0
RUN_DEADLINE = 30.0
REAP_GRACE = 5.0
RENDER_DEADLINE = 120.0
LONG_DETAIL = "npm upgrade failed: " + "x" * 70

CHILD_SCRIPT = textwrap.dedent(
    r'''
    emulate -L zsh
    repo_dir=$1
    source "$repo_dir/25-theme.zsh" || exit 10
    source "$repo_dir/55-ui-helpers.zsh" || exit 11
    source "$repo_dir/60-functions.zsh" || exit 12
    _zsh_functions_load upkg || exit 13

    _upkg_detect_managers() {
      typeset -g -a _UPKG_ACTIVE_MANAGERS=(npm brew) _UPKG_ALTERNATE_MANAGERS=()
    }
    _upkg_run_upgrade_npm() {
      local rc
      _upkg_print_section npm
      if [[ $UPKG_PTY_CASE == wrap ]]; then
        print -r -- 'NATIVE DONE'
        _upkg_set_last_result 'failed' "$UPKG_PTY_DETAIL"
        return 1
      fi
      if [[ $UPKG_PTY_CASE == hidden ]]; then
        # A regression that hides the prompt leaves the native read waiting.
        command sh -c 'read answer'
      elif [[ $UPKG_PTY_CASE == prompt ]]; then
        command sh -c 'printf "Proceed? [y/N] "; read answer; printf "answer=%s\n" "$answer"; [ "$answer" = y ]'
      else
        print -r -- 'NATIVE SLEEPING'
        command sleep 30
      fi
      rc=$?
      _upkg_finish_upgrade_result "$rc" 'npm upgrade failed'
    }
    _upkg_run_upgrade_brew() {
      _upkg_print_section brew
      print -r -- 'BREW RAN'
      _upkg_set_last_result 'upgraded' ''
    }

    # Zsh sets COLUMNS from the terminal at startup, so clear it here.
    case ${UPKG_PTY_COLUMNS_MODE:-} in
      unset) unset COLUMNS ;;
      invalid) COLUMNS=0 ;;
    esac
    upkg upgrade
    print -r -- "UPKG_STATUS=$?"
    '''
)


SEARCH_RENDER_SCRIPT = r"""emulate -L zsh
repo=$1 mode=$2 legacy=$3
export LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm-256color
unset NO_COLOR COLORTERM
source "$repo/25-theme.zsh" || exit 10
source "$repo/55-ui-helpers.zsh" || exit 11
source "$repo/60-functions.zsh" || exit 12
_zsh_functions_load upkg || exit 13
case $mode in
  frozen) source "$legacy" || exit 14 ;;
  sentinel)
    # Converted rich cells must not call the capturing printing wrappers.
    _ui_truncate() { print -r -- PRINTING-WRAPPER-CALLED; }
    _upkg_search_trim() { print -r -- PRINTING-WRAPPER-CALLED; }
    ;;
esac
typeset -g _UPKG_THEME_MODE=1
local -a rows widths themes depths glyphs
rows=(
  $'pacman\tripgrep\t14.1.0-1\tA search tool that combines the usability of ag with the raw speed of grep'
  $'apt\tvery-long-package-name-that-exceeds-every-column-width-0123456789\t1:2.3.4+dfsg-5ubuntu0.1~22.04.1\tshort'
  $'nix\tlegacyPackages.x86_64-linux.python3Packages.something\t\t'
  $'brew\t日本語パッケージ名前テスト\t版本一二三四五六七八九十\t説明文は全角文字で書かれていて非常に長いので切り詰められるべきです'
  $'flatpak\tcafé-combininǵ́\t1.0́\tCombining marks é at cut points éééééééééé'
  $'npm\temoji-\U1F600-pkg-\U1F600\U1F600\U1F600\U1F600\U1F600\U1F600\U1F600\t\U1F44D1.0\t\U1F680 rocket \U1F680 description with emoji \U1F680\U1F680\U1F680\U1F680\U1F680\U1F680\U1F680\U1F680\U1F680\U1F680'
  $'paru\tctrl\e[31mred\x01\x7f\t1.0\x01\tdesc with \e]0;title\a controls and \r\n newlines \t tabs   '
  $'superlongmanagername\tname-with-trailing-newline\n\n\t2.0\n\t  padded description  '
  $'apt\tx\t\t   '
  $'apt\t\t\t'
  $'nix\tinvalid-\xff\xfe-bytes\t1.\xe9\t\xe9\x9b trailing incomplete'
)
widths=(59 60 100 130) themes=(catppuccin-mocha terminal) depths=(256 truecolor none) glyphs=(nerd unicode ascii)
render() {
  REPLY=reply-sentinel
  reply=(array-sentinel)
  print -r -- "=== $1"
  _upkg_format_search_rows "${rows[@]}"
  print -r -- "--- rc=$? REPLY=${(q+)REPLY} reply=${(q+)${(j:|:)reply}}"
}
local w t d g
for w in $widths; do for t in $themes; do for d in $depths; do for g in $glyphs; do
  unset NO_COLOR COLORTERM
  TERM=xterm-256color
  case $d in
    truecolor) COLORTERM=truecolor ;;
    none) export NO_COLOR=1 ;;
  esac
  ZSH_UI_THEME=$t ZSH_UI_GLYPHS=$g
  _zsh_theme_resolve_settings
  COLUMNS=$w
  render "w=$w theme=$t depth=$d glyphs=$g"
done; done; done; done
unset NO_COLOR COLORTERM
ZSH_UI_THEME=catppuccin-mocha ZSH_UI_GLYPHS=nerd TERM=dumb
_zsh_theme_resolve_settings
COLUMNS=120
render dumb
TERM=xterm-256color LC_ALL=C LANG=C
_zsh_theme_resolve_settings
render c-locale
"""

# Frozen pre-conversion formatter: every rich cell used a captured helper.
LEGACY_SEARCH_FORMAT = r"""_upkg_format_search_rows() {
  emulate -L zsh

  local row manager name version description
  local width manager_width name_width version_width desc_width REPLY
  local failed_count=0 cancelled_count=0
  local failed_managers=''
  local -a rows=( "$@" ) fields

  if (( ${#rows[@]} == 0 )); then
    for manager in "${_UPKG_SUMMARY_ORDER[@]}"; do
      case ${_UPKG_SUMMARY_STATE[$manager]} in
        failed) (( failed_count++ )) ;;
        cancelled) (( cancelled_count++ )) ;;
      esac
    done

    if (( cancelled_count > 0 )); then
      print 'Search cancelled; results are incomplete.'
    elif (( failed_count > 0 )); then
      failed_managers=$(_upkg_summary_managers_by_state failed)
      if [ -n "$failed_managers" ]; then
        print "Search results unavailable; failed manager(s): $failed_managers."
      else
        print 'Search results unavailable; one or more selected managers failed.'
      fi
    else
      print 'No matches found across selected managers.'
    fi
    return 0
  fi

  if _ui_plain_mode || [ -z "${_UPKG_THEME_MODE:-}" ]; then
    printf '%-8s %-36s %-18s %s\n' 'Manager' 'Package' 'Available' 'Description'
    printf '%-8s %-36s %-18s %s\n' '-------' '-------' '---------' '-----------'

    for row in "${rows[@]}"; do
      fields=("${(@ps:\t:)row}")
      manager=${fields[1]:-}; name=${fields[2]:-}; version=${fields[3]:-}; description=${fields[4]:-}
      [ -n "$version" ] || version='?'
      printf '%-8s %-36s %-18s %s\n' "$manager" "$name" "$version" "$description"
    done
  else
    _ui_term_width_reply
    width=$REPLY
    if (( width >= 130 )); then
      manager_width=10
      name_width=36
      version_width=18
    elif (( width >= 100 )); then
      manager_width=9
      name_width=30
      version_width=16
    elif (( width >= 80 )); then
      manager_width=8
      name_width=24
      version_width=14
    else
      manager_width=7
      name_width=18
      version_width=12
    fi
    desc_width=$(( width - manager_width - name_width - version_width - 13 ))
    (( desc_width < 18 )) && desc_width=18

    _ui_panel_kv 'Results' "${#rows[@]} match(es)" muted text
    _ui_section_break

    for row in "${rows[@]}"; do
      fields=("${(@ps:\t:)row}")
      manager=${fields[1]:-}; name=${fields[2]:-}; version=${fields[3]:-}; description=${fields[4]:-}
      [ -n "$version" ] || version='?'
      description=$(_upkg_search_trim "$description")

      _ui_panel_prefix
      _ui_color accent
      _ui_pad left "$manager_width" "$(_ui_truncate "$manager_width" "$manager")"
      _ui_reset
      print -nr -- ' '
      _ui_color text
      _ui_pad left "$name_width" "$(_ui_truncate "$name_width" "$name")"
      _ui_reset
      print -nr -- ' '
      _ui_color info
      _ui_pad left "$version_width" "$(_ui_truncate "$version_width" "$version")"
      _ui_reset
      if [ -n "$description" ]; then
        print -nr -- ' '
        _ui_color muted
        print -nr -- "$(_ui_truncate "$desc_width" "$description")"
        _ui_reset
      fi
      print ''
    done
  fi
}
"""


def run_render(args: list[str], env: dict[str, str], use_pty: bool) -> tuple[bytes, int]:
    """Run one render child through a real PTY or a pipe within the deadline."""
    if not use_pty:
        import subprocess
        done = subprocess.run(args, env=env, capture_output=True, timeout=RENDER_DEADLINE)
        return done.stdout + b"\n--stderr--\n" + done.stderr, done.returncode
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe(args[0], args, env)
    output = b""
    eof = False
    deadline = time.monotonic() + RENDER_DEADLINE
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([fd], [], [], 0.1)
            if not ready:
                continue
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                eof = True
                break
            if not chunk:
                eof = True
                break
            output += chunk
    finally:
        status, killed = reap(pid, REAP_GRACE if eof else 0.0)
        os.close(fd)
    if killed:
        raise AssertionError(f"render child still running after {RENDER_DEADLINE:g}s; terminated")
    return output, os.waitstatus_to_exitcode(status)


def check_search_render_oracle() -> None:
    with tempfile.TemporaryDirectory(prefix="upkg-render-") as tmp:
        script = Path(tmp) / "render.zsh"
        legacy = Path(tmp) / "legacy.zsh"
        script.write_text(SEARCH_RENDER_SCRIPT)
        legacy.write_text(LEGACY_SEARCH_FORMAT)
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": tmp, "LINES": "40"}
        for use_pty, label in ((True, "PTY"), (False, "pipe")):
            results = {}
            for mode in ("frozen", "live", "sentinel"):
                results[mode] = run_render(["zsh", "-f", str(script), str(REPO_ROOT), mode, str(legacy)], env, use_pty)
            frozen, live, sentinel = results["frozen"], results["live"], results["sentinel"]
            text = frozen[0].decode("utf-8", "replace")
            check(frozen[1] == 0 and frozen[0].count(b"=== ") == 74, f"{label} search render oracle covers the matrix", text[-2000:])
            if use_pty:
                check("\x1b[" in text and "..." in text and "\u2026" not in text,
                      "PTY oracle renders rich cells with the captured ASCII marker", text[:2000])
            check(live == frozen, f"{label} rich search rows match the frozen captured formatter byte for byte",
                  live[0].decode("utf-8", "replace")[-2000:])
            check(sentinel == frozen and b"PRINTING-WRAPPER-CALLED" not in sentinel[0],
                  f"{label} rich search rows avoid the printing-wrapper captures", sentinel[0].decode("utf-8", "replace")[-2000:])


def reap(pid: int, grace: float) -> tuple[int, bool]:
    """Wait up to grace seconds, then terminate the child's session.

    Returns the wait status and whether the child had to be killed. The PTY
    child leads its own session, so signalling its process group also stops a
    native command it is waiting on.
    """
    deadline = time.monotonic() + grace
    while True:
        done, status = os.waitpid(pid, os.WNOHANG)
        if done:
            return status, False
        if time.monotonic() >= deadline:
            break
        time.sleep(0.05)
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, sig)
        except ProcessLookupError:
            pass
        stop = time.monotonic() + 2.0
        while time.monotonic() < stop:
            done, status = os.waitpid(pid, os.WNOHANG)
            if done:
                return status, True
            time.sleep(0.05)
    _, status = os.waitpid(pid, 0)
    return status, True


def run_case(case: str, env_overrides: dict[str, str | None], *, deadline_seconds: float = RUN_DEADLINE) -> str:
    with tempfile.TemporaryDirectory(prefix="upkg-pty-") as tmp:
        script = Path(tmp) / "child.zsh"
        script.write_text(CHILD_SCRIPT)
        env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": tmp,
            "UPKG_PTY_CASE": case,
            "UPKG_PTY_DETAIL": LONG_DETAIL,
            "COLUMNS": "100",
            "LINES": "30",
        }
        for key, value in env_overrides.items():
            if value is None:
                env.pop(key, None)
            else:
                env[key] = value
        pid, fd = pty.fork()
        if pid == 0:
            os.execvpe("zsh", ["zsh", "-f", str(script), str(REPO_ROOT)], env)

        buffer = ""
        deadline = time.monotonic() + deadline_seconds
        sent = False
        markers = {"prompt": "Proceed? [y/N]", "cancel": "NATIVE SLEEPING", "wrap": "NATIVE DONE"}
        marker = markers[case]
        delay = {"prompt": PROMPT_DELAY, "cancel": CANCEL_DELAY}.get(case)
        seen_at = None
        eof = False
        try:
            while time.monotonic() < deadline:
                if seen_at is None and marker in buffer:
                    seen_at = time.monotonic()
                    sent = delay is None
                if seen_at is not None and not sent and time.monotonic() - seen_at >= delay:
                    os.write(fd, b"y\r" if case == "prompt" else b"\x03")
                    sent = True
                ready, _, _ = select.select([fd], [], [], 0.05)
                if not ready:
                    continue
                try:
                    chunk = os.read(fd, 4096)
                except OSError:
                    eof = True
                    break
                if not chunk:
                    eof = True
                    break
                buffer += chunk.decode("utf-8", "replace")
        finally:
            status, killed = reap(pid, REAP_GRACE if eof else 0.0)
            os.close(fd)
        if killed:
            raise AssertionError(f"{case}: child still running after {deadline_seconds:g}s; terminated\n{buffer}")
        if not sent:
            raise AssertionError(f"{case}: marker {marker!r} never appeared\n{buffer}")
        if os.WIFSIGNALED(status):
            raise AssertionError(f"{case}: child died from signal {os.WTERMSIG(status)}\n{buffer}")
        return ANSI.sub("", buffer).replace("\r", "")


def seconds(text: str) -> float:
    if text == "<0.1s":
        return 0.0
    match = re.fullmatch(r"(?:(\d+)h )?(?:(\d+)m )?(\d+)\.(\d)s", text)
    if not match:
        raise AssertionError(f"unexpected duration: {text!r}")
    hours, minutes, whole, tenth = match.groups()
    return int(hours or 0) * 3600 + int(minutes or 0) * 60 + int(whole) + int(tenth) / 10


def check(condition: bool, label: str, output: str) -> None:
    if not condition:
        raise AssertionError(f"{label}\n{output}")
    print(f"ok: {label}")


def main() -> int:
    plain = {"TERM": "dumb", "LANG": "C"}
    output = run_case("prompt", plain)
    check("answer=y" in output, "fake native prompt reads its answer from the TTY", output)
    manager = re.search(r"npm: upgraded \| elapsed ([^\n]+)", output)
    total = re.search(r"Total elapsed \(upgrade\): ([^\n]+)", output)
    check(manager is not None and total is not None, "PTY prompt run reports manager and total timing", output)
    check(seconds(manager.group(1)) >= PROMPT_DELAY, "manager elapsed time includes the native prompt wait", output)
    check(seconds(total.group(1)) >= seconds(manager.group(1)), "total elapsed time covers the manager", output)
    check("UPKG_STATUS=0" in output and "BREW RAN" in output, "prompted upgrade continues to later managers", output)

    rich = {"TERM": "xterm-256color", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"}
    output = run_case("cancel", rich)
    check("UPKG_STATUS=130" in output, "terminal Ctrl-C keeps status 130", output)
    check("BREW RAN" not in output, "terminal Ctrl-C stops later managers", output)
    manager = re.search(r"\[cancelled\][^\n]*?(?:\| |\n\s+)elapsed ([^\n]+)", output)
    total = re.search(r"Total elapsed \(upgrade\): ([^\n]+?) so far", output)
    check(manager is not None, "rich cancelled row keeps its elapsed time", output)
    check(seconds(manager.group(1)) >= CANCEL_DELAY, "interrupted manager is timed through teardown", output)
    check(total is not None, "rich cancelled run prints the elapsed total so far", output)

    # Plain terminal output without a usable COLUMNS wraps at 80 in-process.
    for label in ("unset", "invalid"):
        with tempfile.TemporaryDirectory(prefix="upkg-pty-tput-") as fakebin:
            log = Path(fakebin) / "tput.log"
            tput = Path(fakebin) / "tput"
            tput.write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{log}"\nprintf "100\\n"\n')
            tput.chmod(0o755)
            output = run_case("wrap", {
                "TERM": "xterm-256color",
                "LANG": "C",
                "LC_ALL": "C",
                "UPKG_PTY_COLUMNS_MODE": label,
                "PATH": f"{fakebin}:{os.environ.get('PATH', '/usr/bin:/bin')}",
            })
            row = f"  npm: failed - {LONG_DETAIL}"
            check(f"{row}\n    elapsed " in output, f"{label} COLUMNS wraps a long row at 80 columns", output)
            check("  brew: upgraded | elapsed " in output, f"{label} COLUMNS keeps short rows on one line", output)
            check(not log.exists(), f"{label} COLUMNS timing never runs tput", output)

    # A hidden prompt must fail within the deadline instead of hanging.
    started = time.monotonic()
    try:
        run_case("prompt", {"TERM": "dumb", "LANG": "C", "UPKG_PTY_CASE": "hidden"}, deadline_seconds=2.0)
    except AssertionError as error:
        hidden_error = str(error)
    else:
        hidden_error = ""
    check(
        "child still running" in hidden_error and time.monotonic() - started < 2.0 + 10.0,
        "a stuck child is terminated after the deadline instead of hanging",
        hidden_error,
    )

    check_search_render_oracle()
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    sys.exit(main())
