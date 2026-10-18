#!/usr/bin/env python3
"""Optional developer benchmark for helper workloads in this Zsh config.

Each sample runs a fresh `zsh -df` child with an allowlisted environment and
private HOME/ZDOTDIR/XDG directories. Fixtures are synthetic and prebuilt;
no package manager, network, Secret Service or host dotfile is used. The child
times only the workload section; results are validated (counts, widths and
output hashes) before any sample is accepted.

With --baseline-ref, samples alternate between an archived Git revision and
the working tree on the same host. Use those paired runs for any speedup
claim; never subtract independently collected medians.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import pty
import re
import select
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]

DEFAULT_SIZES = {
    "parser": [100, 1000],
    "formatter-plain": [100, 1000],
    "formatter-rich": [100, 1000],
    "formatter-pty": [100, 1000],
    "width": [40, 1000],
    "truncate": [40, 1000],
    "safe-truncate": [40, 1000],
    "pad": [40, 1000],
    "records": [1000, 10000],
    "bigfiles-tree": [2000],
    "completion-cold": [60000],
    "completion-warm": [60000],
    "startup-command": [1],
    "startup-interactive": [1],
}
DEFAULT_WORKLOADS = ["parser", "formatter-plain", "formatter-rich", "width",
                     "records", "completion-cold", "completion-warm"]
TEXT_WORKLOADS = {"width", "truncate", "safe-truncate", "pad"}
TEXT_KINDS = ["ascii", "mixed", "cjk"]
# Short inputs run as call batches: single calls are at timer-noise level.
SHORT_TEXT_LIMIT = 80
SHORT_TEXT_BATCH = 1000
TRUNCATE_WIDTH = 24
# Absolute zsh resolved once from the invoking PATH; children keep a fixed PATH.
ZSH_BIN = "zsh"
STARTUP_WARMUPS = 3

# The child body is fixed: it sources only the modules each workload needs
# from the revision under test and writes timing/result files in scratch.
CHILD = r'''
emulate -L zsh
setopt NO_UNSET
zmodload zsh/datetime
repo=$1 workload=$2 size=$3 kind=$4 scratch=$5
typeset -F t0 elapsed
integer i n=$size batch=1 rc=0
typeset text=''
typeset -a rows
_finish() {
  local hwm=''
  # Peak resident set of this shell (Linux /proc only; empty elsewhere).
  [[ -r /proc/$$/status ]] && hwm=${${(M)${(f)"$(</proc/$$/status)"}:#VmHWM:*}//[^0-9]/}
  print -r -- "$elapsed" >| "$scratch/timing"
  print -r -- "$rc" >| "$scratch/status"
  print -r -- "$hwm" >| "$scratch/rss"
}
case $workload in
  parser|formatter-*)
    source "$repo/25-theme.zsh"
    source "$repo/55-ui-helpers.zsh"
    source "$repo/60-functions.zsh"
    _zsh_functions_load upkg || exit 90
    ;;
  width|truncate|safe-truncate|pad)
    source "$repo/25-theme.zsh"
    source "$repo/55-ui-helpers.zsh"
    source "$repo/lib/functions-common.zsh"
    text=$(<"$scratch/text")
    (( size <= SHORT_LIMIT )) && batch=SHORT_BATCH
    ;;
  records|bigfiles-tree)
    source "$repo/55-ui-helpers.zsh"
    source "$repo/60-functions.zsh"
    _zsh_functions_load files || exit 90
    ;;
  completion-*)
    compdef() { :; }
    source "$repo/60-functions.zsh"
    source "$repo/66-compdefs.zsh"
    ;;
esac
case $workload in
  parser)
    _upkg_search_progress() { :; }
    _upkg_search_progress_clear() { :; }
    _upkg_capture_query() {
      _UPKG_QUERY_STDOUT=$(<"$scratch/fixture"); _UPKG_QUERY_STDERR=''
      return 0
    }
    _UPKG_SEARCH_ROWS=()
    t0=$EPOCHREALTIME
    _upkg_run_search_pacman example >/dev/null; rc=$?
    elapsed=$(( (EPOCHREALTIME - t0) * 1000 ))
    print -rl -- "${_UPKG_SEARCH_ROWS[@]}" >| "$scratch/result"
    ;;
  formatter-plain|formatter-rich|formatter-pty)
    rows=( "${(@f)$(<"$scratch/fixture")}" )
    case $workload in
      formatter-plain) _ui_is_rich_terminal() { return 1; }; _UPKG_THEME_MODE='' ;;
      # Forced predicate with a file sink: not a PTY and not an output oracle.
      # Subshells (command substitutions) stay plain, as they see a pipe.
      formatter-rich) _ui_is_rich_terminal() { (( ZSH_SUBSHELL == 0 )); }; _UPKG_THEME_MODE=1 ;;
      formatter-pty) _UPKG_THEME_MODE=1 ;;
    esac
    if [[ $workload == formatter-pty ]]; then
      t0=$EPOCHREALTIME
      _upkg_format_search_rows "${rows[@]}"; rc=$?
      elapsed=$(( (EPOCHREALTIME - t0) * 1000 ))
    else
      t0=$EPOCHREALTIME
      _upkg_format_search_rows "${rows[@]}" >| "$scratch/result"; rc=$?
      elapsed=$(( (EPOCHREALTIME - t0) * 1000 ))
    fi
    ;;
  width)
    _ui_display_width '雪'
    t0=$EPOCHREALTIME
    for (( i = 1; i <= batch; i++ )); do _ui_display_width "$text"; done
    elapsed=$(( (EPOCHREALTIME - t0) * 1000 ))
    print -r -- "$REPLY" >| "$scratch/result"
    ;;
  truncate)
    _ui_display_width '雪'
    t0=$EPOCHREALTIME
    for (( i = 1; i <= batch; i++ )); do _ui_truncate_reply TRUNC_WIDTH "$text"; done
    elapsed=$(( (EPOCHREALTIME - t0) * 1000 ))
    print -r -- "$REPLY" >| "$scratch/result"
    ;;
  safe-truncate)
    _ui_display_width '雪'
    t0=$EPOCHREALTIME
    for (( i = 1; i <= batch; i++ )); do _ui_safe_truncate TRUNC_WIDTH "$text"; done >| "$scratch/result"
    elapsed=$(( (EPOCHREALTIME - t0) * 1000 ))
    ;;
  pad)
    _ui_display_width '雪'
    t0=$EPOCHREALTIME
    for (( i = 1; i <= batch; i++ )); do _ui_pad_reply left TRUNC_WIDTH "$text"; done
    elapsed=$(( (EPOCHREALTIME - t0) * 1000 ))
    print -r -- "$REPLY" >| "$scratch/result"
    ;;
  records)
    # A fake du replays prebuilt NUL records through the real collector.
    path=("$scratch/bin" $path)
    typeset -a records
    typeset -A scan_result
    integer signal_status=0
    t0=$EPOCHREALTIME
    _zsh_scan_collect dusage "$scratch" "$scratch/fixture"; rc=$?
    elapsed=$(( (EPOCHREALTIME - t0) * 1000 ))
    print -rl -- "${records[@]}" "status=${scan_result[status]}" >| "$scratch/result"
    ;;
  bigfiles-tree)
    # Real find/du over a synthetic tree; plain renderer into a file sink.
    _ui_is_rich_terminal() { return 1; }
    t0=$EPOCHREALTIME
    bigfiles "$scratch/tree" 20 >| "$scratch/result"; rc=$?
    elapsed=$(( (EPOCHREALTIME - t0) * 1000 ))
    ;;
  completion-cold|completion-warm)
    if [[ $workload == completion-warm ]]; then
      _zsh_npkg_cached_attributes || exit 91
    fi
    t0=$EPOCHREALTIME
    _zsh_npkg_cached_attributes; rc=$?
    elapsed=$(( (EPOCHREALTIME - t0) * 1000 ))
    print -rl -- "${reply[@]}" "parse=$_ZSH_NPKG_COMPLETION_PARSE_COUNT" >| "$scratch/result"
    ;;
  *) exit 92 ;;
esac
_finish
'''.replace("SHORT_LIMIT", str(SHORT_TEXT_LIMIT)).replace(
    "SHORT_BATCH", str(SHORT_TEXT_BATCH)).replace("TRUNC_WIDTH", str(TRUNCATE_WIDTH))


class BenchmarkError(Exception):
    """A fixture, prerequisite or child failed; no sample is accepted."""


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Optional synthetic helper-workload benchmark (developer tool).",
        epilog="Workloads: " + ", ".join(DEFAULT_SIZES)
               + ". Text workloads run kinds: " + ", ".join(TEXT_KINDS) + ".")
    parser.add_argument("--workload", action="append", choices=list(DEFAULT_SIZES),
                        help="workload to run (repeatable; default: %s)" % ", ".join(DEFAULT_WORKLOADS))
    parser.add_argument("--size", action="append", type=int,
                        help="override the workload dimensions (repeatable)")
    parser.add_argument("--kind", action="append", choices=TEXT_KINDS,
                        help="text kinds for text workloads (repeatable; default all)")
    parser.add_argument("--samples", type=int,
                        help="samples per group (default 5; startup default 30; minimum 5)")
    parser.add_argument("--baseline-ref",
                        help="Git revision archived privately and alternated with the working tree")
    parser.add_argument("--output", type=Path,
                        help="write raw JSON results to this file (nothing else is written)")
    parser.add_argument("--timeout", type=float, default=300.0,
                        help="per-child timeout in seconds (default 300)")
    parser.add_argument("--self-test", action="store_true",
                        help="check failure, timeout, interrupt and isolation cleanup, then exit")
    args = parser.parse_args(argv)
    if args.samples is not None and args.samples < 5:
        parser.error("--samples must be at least 5")
    if args.size is not None and any(size < 1 for size in args.size):
        parser.error("--size values must be positive")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    return args


FIXED_ENV = {
    "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
    "TERM": "xterm-256color", "COLORTERM": "truecolor", "COLUMNS": "120", "LINES": "40",
    "ZSH_UI_THEME": "terminal",
}


def private_env(scratch):
    """Allowlisted environment; inherited HOME/XDG/ZDOTDIR/ZSH_* are ignored."""
    home = scratch / "home"
    for path in (home, scratch / "cache", scratch / "data", scratch / "state", home / ".config"):
        path.mkdir(parents=True, exist_ok=True)
    return dict(FIXED_ENV, HOME=str(home), ZDOTDIR=str(home), TMPDIR=str(scratch),
                XDG_CACHE_HOME=str(scratch / "cache"), XDG_DATA_HOME=str(scratch / "data"),
                XDG_STATE_HOME=str(scratch / "state"), XDG_CONFIG_HOME=str(home / ".config"))


def stop_group(proc):
    """Terminate, then kill, the child's whole process group and reap it."""
    if proc.poll() is None:
        for sig, wait in ((signal.SIGTERM, 2), (signal.SIGKILL, 5)):
            try:
                os.killpg(proc.pid, sig)
            except ProcessLookupError:
                break
            try:
                proc.wait(timeout=wait)
                break
            except subprocess.TimeoutExpired:
                continue
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    proc.wait()


def run_child(args, env, cwd, timeout, stdin=None):
    """Run a bounded child in its own session; return (status, stdout, stderr)."""
    proc = subprocess.Popen(args, env=env, cwd=cwd, stdin=stdin or subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            start_new_session=True)
    try:
        out, err = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        stop_group(proc)
        raise BenchmarkError("child exceeded %.1fs timeout: %s" % (timeout, args[:3]))
    except BaseException:
        stop_group(proc)
        raise
    stop_group(proc)  # reap any descendant left in the session
    return proc.returncode, out, err


def run_child_pty(args, env, cwd, timeout):
    """Run a bounded child on a real PTY; return (status, output bytes, stderr)."""
    master, slave = pty.openpty()
    errors = tempfile.TemporaryFile()
    try:
        proc = subprocess.Popen(args, env=env, cwd=cwd, stdin=slave, stdout=slave,
                                stderr=errors, start_new_session=True)
    except BaseException:
        os.close(master)
        os.close(slave)
        errors.close()
        raise
    os.close(slave)
    output = bytearray()
    deadline = time.monotonic() + timeout
    try:
        while True:
            if time.monotonic() > deadline:
                raise BenchmarkError("PTY child exceeded %.1fs timeout" % timeout)
            if not select.select([master], [], [], .1)[0]:
                if proc.poll() is not None and not select.select([master], [], [], 0)[0]:
                    break
                continue
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            output.extend(chunk)
        proc.wait(timeout=max(1.0, deadline - time.monotonic()))
        errors.seek(0)
        return proc.returncode, bytes(output), errors.read()
    finally:
        stop_group(proc)
        os.close(master)
        errors.close()


def text_fixture(kind, size):
    text = "a" * size
    if kind == "mixed":
        text = "雪" + text[1:]
    elif kind == "cjk":
        text = "雪" * size
    return text


def expected_width(kind, size):
    return {"ascii": size, "mixed": size + 1, "cjk": 2 * size}[kind]


def expected_text_result(kind, size):
    """Exact truncation of the fixed fixtures at TRUNCATE_WIDTH; returns (text, cells).

    Results go to a file, so helpers use the ASCII '...' marker and a cut keeps
    10 cells before it and 11 after. A CJK cut leaves one cell unused.
    """
    assert TRUNCATE_WIDTH == 24
    width = expected_width(kind, size)
    if width <= TRUNCATE_WIDTH:
        return text_fixture(kind, size), width
    return {"ascii": ("a" * 10 + "..." + "a" * 11, 24),
            "mixed": ("雪" + "a" * 8 + "..." + "a" * 11, 24),
            "cjk": ("雪" * 5 + "..." + "雪" * 5, 23)}[kind]


def write_fixture(workload, size, kind, scratch):
    """Write the synthetic fixture; return a validator for the result bytes."""
    fixture = scratch / "fixture"
    if workload == "parser":
        fixture.write_text("".join(
            f"extra/package-{i} 1.2.{i % 7}\n    A package  description\tfor fixture {i}\n"
            for i in range(1, size + 1)))

        def check(result):
            lines = result.decode().splitlines()
            ok = len(lines) == size and all(
                line == f"pacman\tpackage-{i}\t1.2.{i % 7}\tA package description for fixture {i}"
                for i, line in enumerate(lines, 1))
            return ok, len(lines)
        return check
    if workload.startswith("formatter-"):
        fixture.write_text("".join(
            f"pacman\tp{i}\t1.2.{i % 7}\tA package description for fixture {i} with a longer tail\n"
            for i in range(1, size + 1)))

        def check(result):
            text = re.sub(r"\x1b\[[0-9;]*m", "", result.decode(errors="replace"))
            names = set(re.findall(r"\bp(\d+)\b", text))
            return len(names) == size, len(names)
        return check
    if workload in TEXT_WORKLOADS:
        text = text_fixture(kind, size)
        (scratch / "text").write_text(text)
        width = expected_width(kind, size)
        batch = SHORT_TEXT_BATCH if size <= SHORT_TEXT_LIMIT else 1
        truncated, cells = expected_text_result(kind, size)
        expected = {"width": f"{width}\n", "truncate": truncated + "\n",
                    "pad": truncated + " " * (TRUNCATE_WIDTH - cells) + "\n",
                    "safe-truncate": (truncated + "\n") * batch}[workload]

        def check(result):
            value = result.decode(errors="replace")
            observed = len(value.splitlines()) if workload == "safe-truncate" else value.rstrip("\n")
            return value == expected, observed
        return check
    if workload == "records":
        (scratch / "bin").mkdir(exist_ok=True)
        raw = scratch / "raw-records"
        with raw.open("wb") as handle:
            for i in range(1, size + 1):
                handle.write(f"{i}\t/synthetic/path/file-{i}\0".encode())
        du = scratch / "bin" / "du"
        du.write_text("#!/bin/sh\nexec cat -- \"$BENCH_RAW_RECORDS\"\n")
        du.chmod(0o700)
        fixture.write_text("x")

        def check(result):
            lines = result.decode().splitlines()
            return len(lines) == size + 1 and lines[-1] == "status=0", len(lines) - 1
        return check
    if workload == "bigfiles-tree":
        tree = scratch / "tree"
        for i in range(size):
            directory = tree / f"dir-{i % 37}"
            directory.mkdir(parents=True, exist_ok=True)
            (directory / f"file-{i}.bin").write_bytes(b"x" * (512 * (i % 29 + 1)))

        def check(result):
            lines = result.decode().splitlines()
            return len(lines) == 20 and all("/tree/dir-" in line for line in lines), len(lines)
        return check
    if workload.startswith("completion-"):
        cache = scratch / "cache" / "npkg"
        cache.mkdir(parents=True, exist_ok=True)
        (cache / "nixpkgs-attrs-x86_64-linux.txt").write_text(
            "".join(f"pkg{i:06}\n" for i in range(size)))
        bindir = scratch / "bin"
        bindir.mkdir(exist_ok=True)
        nix = bindir / "nix"
        nix.write_text("#!/bin/sh\nprintf called >> \"$BENCH_NIX_LOG\"\nexit 99\n")
        nix.chmod(0o700)

        def check(result):
            lines = result.decode().splitlines()
            # Candidates and parse count are compared; where the fixed lazy Nix
            # domain loads is an implementation detail, but native Nix must never run.
            ok = (len(lines) == size + 1 and lines[-1] == "parse=1"
                  and not (scratch / "nix-calls").exists())
            return ok, len(lines) - 1
        return check
    raise BenchmarkError("no fixture for " + workload)


def run_sample(repo, workload, size, kind, scratch, timeout):
    """One validated sample; returns (ms, result sha256, observed count/width)."""
    for name in ("timing", "status", "result"):
        (scratch / name).unlink(missing_ok=True)
    check = write_fixture(workload, size, kind, scratch)
    env = private_env(scratch)
    env["BENCH_RAW_RECORDS"] = str(scratch / "raw-records")
    env["BENCH_NIX_LOG"] = str(scratch / "nix-calls")
    if workload.startswith("completion-"):
        env["PATH"] = f"{scratch / 'bin'}:{env['PATH']}"
    args = [ZSH_BIN, "-dfc", CHILD, "bench", str(repo), workload, str(size), kind, str(scratch)]
    if workload == "formatter-pty":
        status, output, err = run_child_pty(args, env, scratch, timeout)
        result = output.replace(b"\r\n", b"\n")
    else:
        status, _, err = run_child(args, env, scratch, timeout)
        result = (scratch / "result").read_bytes() if (scratch / "result").exists() else b""
    if status != 0 or err:
        raise BenchmarkError(f"{workload}/{size}/{kind} child status {status}: "
                             + err.decode(errors="replace")[-400:])
    if (scratch / "status").read_text().strip() != "0":
        raise BenchmarkError(f"{workload}/{size}/{kind} workload returned nonzero")
    ok, observed = check(result)
    if not ok:
        raise BenchmarkError(f"{workload}/{size}/{kind} fixture validation failed ({observed})")
    ms = float((scratch / "timing").read_text())
    rss = (scratch / "rss").read_text().strip()
    return ms, hashlib.sha256(result).hexdigest(), observed, int(rss) if rss else None


def install_copy(source, scratch):
    """Real copy under the private HOME: ${0:A} resolves symlinks."""
    target = scratch / "home" / ".config" / "zsh"
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target, symlinks=True,
                    ignore=shutil.ignore_patterns(".git", "plans", "__pycache__"))
    return target


def run_startup_sample(repo, workload, scratch, timeout):
    """Fresh-shell startup with the existing benchmark's -df/-dfi stdin invocation."""
    install = install_copy(repo, scratch)
    env = private_env(scratch)
    script = scratch / "startup-input"
    script.write_text(f"source {shlex.quote(str(install / 'init.zsh'))}\nexit\n")
    flag = "-dfi" if workload == "startup-interactive" else "-df"
    for _ in range(STARTUP_WARMUPS):
        with script.open("rb") as stdin:
            run_child([ZSH_BIN, flag], env, scratch, timeout, stdin=stdin)
    with script.open("rb") as stdin:
        started = time.perf_counter()
        status, _, _ = run_child([ZSH_BIN, flag], env, scratch, timeout, stdin=stdin)
        elapsed = (time.perf_counter() - started) * 1000
    if status != 0:
        raise BenchmarkError(f"{workload} startup exited {status}")
    return elapsed, None, 1, None


def lower_middle(values):
    ordered = sorted(values)
    return ordered[(len(ordered) + 1) // 2 - 1]


def summarize(samples):
    ordered = sorted(samples)
    index95 = min(len(ordered), (len(ordered) * 95 + 99) // 100)
    return {"median_ms": lower_middle(ordered), "p95_ms": ordered[index95 - 1],
            "min_ms": ordered[0], "max_ms": ordered[-1], "n": len(ordered)}


def revision_info(repo):
    def git(*args):
        result = subprocess.run(["git", *args], cwd=repo, text=True, capture_output=True, timeout=30)
        return result.stdout.strip() if result.returncode == 0 else None
    status = git("status", "--porcelain", "--untracked-files=no")
    return {"sha": git("rev-parse", "HEAD"), "dirty": bool(status) if status is not None else None,
            "tracked_content_sha256": tracked_content_sha256(repo)}


def tracked_content_sha256(repo):
    """Digest of every tracked path with its working-tree bytes, link target and
    owner-execute bit (the bit Git records as 100755/100644), read via lstat.

    Untracked files are excluded. Files are read directly, so git diff drivers,
    textconv and diff settings cannot change it, and access policy (noexec
    mounts, ACLs, privileges) is not consulted for the mode.
    """
    try:
        listing = subprocess.run(["git", "ls-files", "-z"], cwd=repo, capture_output=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if listing.returncode != 0:
        return None
    digest = hashlib.sha256()
    for name in sorted(filter(None, listing.stdout.split(b"\0"))):
        full = Path(repo) / os.fsdecode(name)
        if full.is_symlink():
            entry = b"L" + os.fsencode(os.readlink(full))
        elif full.is_file():
            entry = (b"X" if full.lstat().st_mode & stat.S_IXUSR else b"F") + full.read_bytes()
        else:
            entry = b"M"
        digest.update(b"%d\0" % len(name) + name + b"%d\0" % len(entry) + entry)
    return digest.hexdigest()


def archive_ref(ref, scratch):
    target = scratch / "baseline-tree"
    target.mkdir()
    archive = scratch / "baseline.tar"
    with archive.open("wb") as handle:
        result = subprocess.run(["git", "archive", "--format=tar", ref], cwd=ROOT,
                                stdout=handle, stderr=subprocess.PIPE, timeout=60)
    if result.returncode:
        raise BenchmarkError("git archive failed: " + result.stderr.decode(errors="replace"))
    with tarfile.open(archive) as tar:
        tar.extractall(target, filter="data")
    archive.unlink()
    sha = subprocess.run(["git", "rev-parse", ref + "^{commit}"], cwd=ROOT, text=True,
                         capture_output=True, timeout=30).stdout.strip()
    return target, sha


def tool_versions():
    def first_line(*args):
        try:
            return subprocess.run(args, text=True, capture_output=True, timeout=10).stdout.splitlines()[0]
        except (OSError, IndexError, subprocess.TimeoutExpired):
            return None
    return {"zsh": first_line(ZSH_BIN, "--version"), "zsh_path": ZSH_BIN, "python": platform.python_version(),
            "git": first_line("git", "--version")}


def benchmark(args):
    workloads = args.workload or DEFAULT_WORKLOADS
    results = {"tool": "scripts/benchmark-workloads.py", "date": time.strftime("%Y-%m-%d"),
               "platform": platform.platform(), "versions": tool_versions(),
               "candidate": revision_info(ROOT), "baseline": None,
               "environment": dict(FIXED_ENV, private="HOME, ZDOTDIR, TMPDIR and XDG_* under scratch"),
               "method": ("Fresh zsh -df child per sample; in-child EPOCHREALTIME around the workload "
                          "section. Groups alternate baseline/candidate per sample when a baseline is "
                          "given. Lower-middle median. formatter-rich forces the rich predicate into a "
                          "file sink (not a PTY); formatter-pty runs on a real PTY. Startup is "
                          "fresh-shell wall time with 3 warmups per sample."),
               "groups": []}
    with tempfile.TemporaryDirectory(prefix="zsh-workloads-") as root:
        scratch_root = Path(root)
        revisions = [("candidate", ROOT)]
        if args.baseline_ref:
            tree, sha = archive_ref(args.baseline_ref, scratch_root)
            results["baseline"] = {"ref": args.baseline_ref, "sha": sha}
            revisions.insert(0, ("baseline", tree))
        for workload in workloads:
            startup = workload.startswith("startup-")
            sizes = args.size or DEFAULT_SIZES[workload]
            kinds = (args.kind or TEXT_KINDS) if workload in TEXT_WORKLOADS else ["-"]
            samples = args.samples or (30 if startup else 5)
            for size in ([1] if startup else sizes):
                for kind in kinds:
                    group = {"workload": workload, "size": size, "kind": kind,
                             "mode": "real-pty" if workload == "formatter-pty" else
                                     "forced-rich-sink" if workload == "formatter-rich" else
                                     "fresh-shell" if startup else "in-child",
                             "batch_calls": (SHORT_TEXT_BATCH if workload in TEXT_WORKLOADS
                                             and size <= SHORT_TEXT_LIMIT else 1),
                             "revisions": {}}
                    for name, _ in revisions:
                        group["revisions"][name] = {"samples_ms": [], "peak_rss_kib": [],
                                                    "sha256": None, "observed": None}
                    for index in range(samples):
                        # Alternate which revision runs first in each round.
                        order = revisions if index % 2 == 0 else list(reversed(revisions))
                        for name, repo in order:
                            # One scratch path for both revisions keeps outputs comparable.
                            scratch = scratch_root / "work"
                            if scratch.exists():
                                shutil.rmtree(scratch)
                            scratch.mkdir()
                            if startup:
                                ms, digest, observed, rss = run_startup_sample(repo, workload, scratch, args.timeout)
                            else:
                                ms, digest, observed, rss = run_sample(repo, workload, size, kind, scratch, args.timeout)
                            record = group["revisions"][name]
                            if record["sha256"] not in (None, digest):
                                raise BenchmarkError(f"{name} {workload}/{size}/{kind} result changed between samples")
                            record["sha256"], record["observed"] = digest, observed
                            record["samples_ms"].append(ms)
                            record["peak_rss_kib"].append(rss)
                    for record in group["revisions"].values():
                        record.update(summarize(record["samples_ms"]))
                    if len(revisions) == 2 and not startup:
                        hashes = {r["sha256"] for r in group["revisions"].values()}
                        group["outputs_identical"] = len(hashes) == 1
                        if not group["outputs_identical"]:
                            raise BenchmarkError(f"{workload}/{size}/{kind}: baseline and candidate outputs differ")
                    results["groups"].append(group)
                    print_group(group)
    if args.output:
        args.output.write_text(json.dumps(results, indent=2) + "\n")
    return 0


def print_group(group):
    label = f"{group['workload']}/{group['size']}" + (f"/{group['kind']}" if group["kind"] != "-" else "")
    parts = []
    for name, record in group["revisions"].items():
        rss = [value for value in record["peak_rss_kib"] if value is not None]
        rss_text = f" rss<={max(rss)}KiB" if rss else ""
        parts.append(f"{name} median={record['median_ms']:.3f}ms p95={record['p95_ms']:.3f}ms n={record['n']}{rss_text}")
    revisions = group["revisions"]
    if "baseline" in revisions:
        ratio = revisions["baseline"]["median_ms"] / max(revisions["candidate"]["median_ms"], 1e-9)
        parts.append(f"baseline/candidate={ratio:.2f}x")
    print(f"{label}: " + "  ".join(parts), flush=True)


def self_test():
    """Synthetic callbacks: failure, timeout, interrupt and hostile inherited env."""
    if not __debug__:
        print("self-test needs assertions; run without -O or PYTHONOPTIMIZE", file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix="zsh-workloads-selftest-") as root:
        base = Path(root)
        env = private_env(base / "env")
        # Failure: status is reported, nothing lingers.
        status, _, _ = run_child(["sh", "-c", "exit 7"], env, base, 10)
        assert status == 7, status
        # Timeout: the session (including a grandchild) is terminated and reaped.
        marker = base / "grandchild.pid"
        try:
            run_child(["sh", "-c", f"sleep 30 & echo $! > {shlex.quote(str(marker))}; wait"], env, base, 1)
        except BenchmarkError:
            pass
        else:
            raise AssertionError("timeout was not reported")
        assert marker.exists()
        grandchild = int(marker.read_text())
        time.sleep(.2)
        try:
            os.kill(grandchild, 0)
            raise AssertionError("timed-out grandchild survived")
        except ProcessLookupError:
            pass
        # Interrupt: a driver run is cancelled and leaves no scratch directory.
        hostile = base / "hostile"
        for name in ("home", "cache", "zdot"):
            (hostile / name).mkdir(parents=True)
        (hostile / "zdot" / ".zshenv").write_text(f"print hostile > {shlex.quote(str(hostile / 'zshenv-ran'))}\n")
        driver_env = dict(os.environ, HOME=str(hostile / "home"), XDG_CACHE_HOME=str(hostile / "cache"),
                          ZDOTDIR=str(hostile / "zdot"), ZSH_UI_THEME="bogus", ENV=str(hostile / "env"),
                          TMPDIR=str(base))
        # A fake zsh first on the driver's PATH blocks only for a workload sample
        # (zsh -dfc CHILD bench REPO WORKLOAD SIZE KIND SCRATCH); other calls such
        # as the version probe run the real zsh. Its marker names the sample's
        # scratch directory, so SIGINT provably lands during run_sample().
        real_zsh = shutil.which("zsh")
        assert real_zsh, "self-test requires zsh on PATH"
        fakebin = base / "fake-zsh-bin"
        fakebin.mkdir()
        started = base / "fake-zsh.started"
        pending = shlex.quote(str(started) + ".tmp")
        (fakebin / "zsh").write_text(
            "#!/bin/sh\n"
            'if [ "$1" = -dfc ] && [ "$3" = bench ]; then\n'
            f'  printf "%s\\n%s\\n" "$$" "$8" > {pending} && mv {pending} {shlex.quote(str(started))}\n'
            "  exec sleep 60\n"
            "fi\n"
            f'exec {shlex.quote(real_zsh)} "$@"\n')
        (fakebin / "zsh").chmod(0o755)
        interrupt_env = dict(driver_env, PATH=f"{fakebin}:{os.environ.get('PATH', '/usr/bin:/bin')}")
        proc = subprocess.Popen([sys.executable, __file__, "--workload", "width", "--kind", "ascii",
                                 "--size", "40", "--samples", "5"],
                                env=interrupt_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                start_new_session=True)
        deadline = time.monotonic() + 60
        while not started.exists():
            if proc.poll() is not None or time.monotonic() > deadline:
                stop_group(proc)
                raise AssertionError("driver never started a sample child")
            time.sleep(.05)
        sample_child, sample_scratch = started.read_text().split("\n")[:2]
        sample_scratch = Path(sample_scratch)
        assert sample_scratch.is_dir(), sample_scratch
        assert sample_scratch.parent.parent == base and sample_scratch.parent.name.startswith("zsh-workloads-"), \
            sample_scratch
        os.killpg(proc.pid, signal.SIGINT)
        _, err = proc.communicate(timeout=60)
        assert proc.returncode == 130, (proc.returncode, err)
        assert b"benchmark interrupted; scratch removed" in err, err
        try:
            os.kill(int(sample_child), 0)
            raise AssertionError("interrupted sample child survived")
        except ProcessLookupError:
            pass
        assert not sample_scratch.exists(), sample_scratch
        leftovers = [p for p in base.iterdir() if p.name.startswith("zsh-workloads-")]
        assert not leftovers, leftovers
        # Hostile inherited settings: a full short run leaves host paths untouched.
        out = subprocess.run([sys.executable, __file__, "--workload", "width", "--kind", "ascii",
                              "--size", "40", "--samples", "5"], env=driver_env,
                             capture_output=True, text=True, timeout=120)
        assert out.returncode == 0, out.stderr
        for name in ("home", "cache"):
            assert not any((hostile / name).iterdir()), name
        assert not (hostile / "zshenv-ran").exists()
        leftovers = [p for p in base.iterdir() if p.name.startswith("zsh-workloads-")]
        assert not leftovers, leftovers
        # Invalid arguments exit 2 without doing workload work.
        bad = subprocess.run([sys.executable, __file__, "--samples", "1"], capture_output=True, timeout=30)
        assert bad.returncode == 2, bad.returncode
    print("ok: benchmark driver failure, timeout, interrupt and isolation cleanup")
    return 0


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if args.self_test:
        return self_test()
    global ZSH_BIN
    resolved = shutil.which("zsh")
    if resolved is None:
        print("benchmark requires zsh on PATH", file=sys.stderr)
        return 2
    # Keep the invoked name: zsh selects its emulation from argv[0].
    ZSH_BIN = os.path.abspath(resolved)

    def interrupted(signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    try:
        return benchmark(args)
    except BenchmarkError as error:
        print(f"benchmark failed: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("benchmark interrupted; scratch removed", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
