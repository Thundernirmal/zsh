#!/usr/bin/env python3
"""Non-gating, offline review probes. Writes JSON to stdout; uses scratch trees only.

Run from any directory: python3 docs/performance/validate.py [git-revision]
Requires GNU/Linux, Python 3, git, tar, zsh, GNU sed, jq, fzf and zoxide.
No package operations or credentials are used. Timings are observations, not gates.
"""

import errno
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import pty
import re
import select
import shutil
import statistics
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
REV = sys.argv[1] if len(sys.argv) > 1 else "a6605d20eecd32ff9609a01c750f9516185feda1"
REV = subprocess.check_output(["git", "rev-parse", "--verify", REV + "^{commit}"], cwd=ROOT, text=True).strip()
RESULT = {"revision": REV, "platform": platform.platform(), "date_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
RESULT["load_average_start"] = os.getloadavg()
RESULT["cpu"] = next(line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name"))


def summary(samples):
    return {"n": len(samples), "median_ms": statistics.median(samples),
            "p95_ms": sorted(samples)[math.ceil(len(samples) * .95) - 1], "samples_ms": samples}


with tempfile.TemporaryDirectory(prefix="zsh-consolidated-review-") as work:
    work = Path(work)
    env = {"PATH": "/usr/bin:/bin", "TERM": "xterm-256color", "COLORTERM": "truecolor",
           "LC_ALL": "C.UTF-8", "LANG": "C.UTF-8", "COLUMNS": "120", "LINES": "40",
           "TMPDIR": str(work), "ZSH_UI_THEME": "terminal"}
    for tool in ("zsh", "jq", "fzf", "zoxide", "sed"):
        RESULT[tool] = subprocess.check_output([tool, "--version"], env=env, text=True).splitlines()[0]

    def tree(name):
        dest = work / name
        dest.mkdir()
        archive = subprocess.check_output(["git", "archive", REV], cwd=ROOT)
        subprocess.run(["tar", "-x", "-C", str(dest)], input=archive, check=True)
        return dest

    base, compiled = tree("text"), tree("compiled")

    def environment(source):
        home = work / (source.name + "-home")
        (home / ".config").mkdir(parents=True, exist_ok=True)
        link = home / ".config/zsh"
        if not link.exists():
            link.symlink_to(source)
        return dict(env, HOME=str(home), XDG_CACHE_HOME=str(home / ".cache"),
                    XDG_DATA_HOME=str(home / ".local/share"), AUDIT_TREE=str(source), AUDIT_WORK=str(work))

    def run(code, source=base, tty=False, interactive=False, extra=None):
        script = work / "probe.zsh"
        script.write_text("zmodload zsh/datetime\n" + code + "\n", encoding="utf-8")
        run_env = environment(source)
        run_env.update(extra or {})
        args = ["zsh", "-dfi" if interactive else "-df", str(script)]
        if not tty:
            result = subprocess.run(args, env=run_env, stdin=subprocess.DEVNULL, capture_output=True, timeout=120)
            assert result.returncode == 0, (result.returncode, result.stderr.decode(errors="replace"))
            return result.stdout
        master, slave = pty.openpty()
        # stdout is a PTY, stdin remains scripted; this is not a full prompt test.
        with tempfile.TemporaryFile() as errors:
            process = subprocess.Popen(args, env=run_env, stdin=subprocess.DEVNULL, stdout=slave, stderr=errors)
            os.close(slave)
            chunks = []
            deadline = time.monotonic() + 120
            try:
                while True:
                    if time.monotonic() > deadline:
                        process.kill()
                        process.wait()
                        raise TimeoutError("PTY probe exceeded 120 seconds")
                    if not select.select([master], [], [], 1)[0]:
                        continue
                    try:
                        data = os.read(master, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not data:
                        break
                    chunks.append(data)
            finally:
                os.close(master)
            process.wait(timeout=120)
            errors.seek(0)
            assert process.returncode == 0, errors.read().decode(errors="replace")
        return b"".join(chunks).replace(b"\r\n", b"\n")

    def values(output):
        return [float(value) for value in re.findall(rb"BENCH ([0-9.]+)", output)]

    # Warm startup: no compinit/user rc; all sources and caches isolated.
    modules = [p for p in compiled.glob("[0-9][0-9]-*.zsh")]
    modules += [compiled / "lib" / name for name in ("upkg-registry.zsh", "theme-palettes.zsh", "theme-registry.zsh")]
    for module in modules:
        subprocess.run(["zsh", "-dfc", 'zcompile -U -- "$1"', "audit", str(module)], check=True, env=env)
    startup = 'typeset -F start=$EPOCHREALTIME\nsource "$HOME/.config/zsh/init.zsh"\nprint "BENCH $(( (EPOCHREALTIME-start)*1000 ))"'
    startup_samples = {"text": [], "compiled_modules_prototype": []}
    for index in range(23):
        for name, source in (("text", base), ("compiled_modules_prototype", compiled)):
            samples = values(run(startup, source, tty=True, interactive=True))
            assert len(samples) == 1
            if index >= 3:
                startup_samples[name] += samples
    RESULT["startup"] = {key: summary(value) for key, value in startup_samples.items()}

    # Seven exact-byte preview fixtures, plus large regular-file timing.
    fixtures = [b"", b"one", b"x\n" * 199, b"x\n" * 200, b"x\n" * 201,
                b"x\n" * 199 + b"last", b"a\x00\x1b\r\n" * 201]
    preview_file = work / "- preview file"
    q_diff = []
    for index, data in enumerate(fixtures):
        preview_file.write_bytes(data)
        outputs = [subprocess.run(["sed", "-n", program, "--", str(preview_file)], capture_output=True, check=True).stdout
                   for program in ("1,200p", "1,200p;200Q", "1,200p;200q")]
        assert outputs[0] == outputs[1]
        if outputs[0] != outputs[2]:
            q_diff.append(index)
    with preview_file.open("wb") as stream:
        for _ in range(4000):
            stream.write((b"x" * 63 + b"\n") * 1000)
    preview_samples = {"full_scan": [], "bounded_Q": []}
    for _ in range(5):
        for name, program in (("full_scan", "1,200p"), ("bounded_Q", "1,200p;200Q")):
            start = time.perf_counter()
            subprocess.run(["sed", "-n", program, "--", str(preview_file)], stdout=subprocess.DEVNULL, check=True)
            preview_samples[name].append((time.perf_counter() - start) * 1000)
    RESULT["preview"] = {"bytes": preview_file.stat().st_size, "Q_equal_fixtures": 7, "q_different_fixture_indexes": q_diff,
                         **{key: summary(value) for key, value in preview_samples.items()}}

    common = 'source "$AUDIT_TREE/25-theme.zsh"\nsource "$AUDIT_TREE/55-ui-helpers.zsh"\nsource "$AUDIT_TREE/lib/functions-common.zsh"\n'
    # In-memory predicate prototype only; retain original fallback and other helpers.
    rich_patch = r'''
functions[_ui_is_rich_terminal]=${functions[_ui_is_rich_terminal]/'width=$(_ui_term_width)'/'width=${COLUMNS:-}; case $width in (""|*[!0-9]*) width=$(_ui_term_width) ;; esac'}
'''
    rich_samples = {"baseline": [], "numeric_width_prototype": []}
    transcripts = {}
    for _ in range(3):
        for name, patch in (("baseline", ""), ("numeric_width_prototype", rich_patch)):
            output = run(common + patch + '''
COLUMNS=120
_ui_is_rich_terminal || exit 3
typeset -F start=$EPOCHREALTIME
repeat 100; do _ui_panel_kv Key Value; done
print "BENCH $(( (EPOCHREALTIME-start)*1000 ))"
''', tty=True)
            rich_samples[name] += values(output)
            transcripts[name] = re.sub(rb"BENCH [0-9.]+\n", b"", output)
    assert transcripts["baseline"] == transcripts["numeric_width_prototype"]
    RESULT["rich_rows"] = {"rows": 100, "bytes_equal": len(transcripts["baseline"]),
                           **{key: summary(value) for key, value in rich_samples.items()}}

    # Characterize ASCII fast path against the actual sanitizer, including controls.
    ascii_probe = common + r'''
functions[_audit_safe_original]=$functions[_ui_safe_text_reply]
_audit_fast() {
  emulate -L zsh
  local pattern='*[^ -~]*'
  if [[ $1 != ${~pattern} ]]; then REPLY=$1; else _audit_safe_original "$1"; fi
}
local -a cases=('' 'printable ASCII ~' 'é界😀' $'e\u0301' $'a\e[31mb' $'a\xffb')
integer code
local escaped char value expected
for (( code=0; code<=159; code++ )); do
  printf -v escaped '\\u%04x' $code
  printf -v char '%b' "$escaped"
  cases+=("a${char}b")
done
for value in "${cases[@]}"; do
  _audit_safe_original "$value"; expected=$REPLY
  _audit_fast "$value"
  [[ $REPLY == "$expected" ]] || exit 4
done
print "CASES ${#cases}"
fpath=("$AUDIT_TREE/functions" $fpath)
autoload -Uz _fbr_format_entry
for variant in baseline fast; do
  [[ $variant == fast ]] && functions[_ui_safe_text_reply]=$functions[_audit_fast]
  typeset -F start=$EPOCHREALTIME
  repeat 1000; do _fbr_format_entry feature '2 days ago' 'An ordinary ASCII commit subject' '' '' '' 32 14 refs/heads/feature; done
  print "BENCH $(( (EPOCHREALTIME-start)*1000 ))"
done
'''
    RESULT["ascii"] = {"fixtures": 166, "rows": 1000, "baseline_then_prototype_ms": values(run(ascii_probe))}

    # Real completion helper; only its cache location and compdef are stubbed.
    cache = work / "attributes"
    cache.mkdir()
    completion = r'''
compdef() { :; }
source "$AUDIT_TREE/66-compdefs.zsh"
_npkg_cache_dir() { print -r -- "$AUDIT_WORK/attributes"; }
repeat 3; do
  typeset -F start=$EPOCHREALTIME
  _zsh_npkg_cached_attributes
  print "BENCH $(( (EPOCHREALTIME-start)*1000 ))"
  print "STATE ${#reply} $_ZSH_NPKG_COMPLETION_PARSE_COUNT"
done
'''
    RESULT["completion"] = {}
    for count in (10000, 30000, 60000):
        (cache / "nixpkgs-attrs-a.txt").write_text("".join(f"pkg{i}\n" for i in range(count)))
        output = run(completion)
        states = re.findall(rb"STATE (\d+) (\d+)", output)
        assert states == [(str(count).encode(), b"1")] * 3
        RESULT["completion"][str(count)] = {"cold_then_two_warm_ms": values(output), "parse_count_each": 1}
    (cache / "nixpkgs-attrs-a.txt").write_text("a\nb\nlast")
    assert re.findall(rb"STATE (\d+) (\d+)", run(completion)) == [(b"2", b"1")] * 3
    RESULT["completion"]["unterminated_final_record_dropped"] = True

    # Count actual jq processes with a scratch PATH wrapper, never invoke nix.
    bin_dir = work / "bin"
    bin_dir.mkdir()
    jq_binary = shutil.which("jq", path=env["PATH"])
    (bin_dir / "jq").write_text('#!/bin/sh\nprintf "jq\\n" >> "$AUDIT_WORK/jq-count"\nexec ' + jq_binary + ' "$@"\n')
    (bin_dir / "jq").chmod(0o700)
    nix_prefix = common + r'''
source "$AUDIT_TREE/lib/functions-nix.zsh"
_zsh_run_owned_query() { "$@"; }
_npkg_nix() { command cat "$AUDIT_WORK/profile.json"; }
'''
    RESULT["nix_decode"] = {}
    for count in (0, 20, 100):
        (work / "profile.json").write_text(json.dumps({"elements": [{"name": f"pkg{i}"} for i in range(count)]}))
        (work / "jq-count").write_text("")
        output = run(nix_prefix + '''
typeset -F start=$EPOCHREALTIME
_npkg_outdated > "$AUDIT_WORK/nix-output"
print "BENCH $(( (EPOCHREALTIME-start)*1000 ))"
print "STATE $_NPKG_OUTDATED_TOTAL $_NPKG_OUTDATED_UNKNOWN $_NPKG_OUTDATED_STATE"
''', extra={"PATH": str(bin_dir) + ":" + env["PATH"]})
        calls = len((work / "jq-count").read_text().splitlines())
        assert calls == 2 + 7 * count
        assert f"STATE {count} {count} {'partial' if count else 'current'}".encode() in output
        RESULT["nix_decode"][str(count)] = {"elapsed_ms": values(output)[0], "jq_processes": calls}

    # Actual scheduler, synthetic evaluations; supervisor boundary bypassed here only.
    (work / "profile.json").write_text(json.dumps({"elements": [
        {"name": f"pkg{i}", "attrPath": str(i), "originalUrl": "fixture", "storePaths": ["/nix/store/fixture"]}
        for i in range(1, 17)]}))
    output = run(nix_prefix + r'''
_npkg_eval_installable_record() {
  print -r -- "start $2 $EPOCHREALTIME" >> "$AUDIT_WORK/events"
  case $2 in 1|9) command sleep 0.6 ;; *) command sleep 0.03 ;; esac
  print -r -- "end $2 $EPOCHREALTIME" >> "$AUDIT_WORK/events"
  print -r -- '{"paths":["/nix/store/fixture"],"version":"1"}'
}
_npkg_outdated > "$AUDIT_WORK/nix-output"
''')
    events = [line.split() for line in (work / "events").read_text().splitlines()]
    event_times = {(kind, int(index)): float(stamp) for kind, index, stamp in events}
    assert event_times["start", 9] >= event_times["end", 1]
    RESULT["scheduler"] = {"entry9_after_entry1_end": True,
                           "first_fast_end_to_entry9_start_ms": (event_times["start", 9] - event_times["end", 2]) * 1000,
                           "evaluation_span_ms": (max(event_times.values()) - min(event_times.values())) * 1000}

    # Fresh loads, not cumulative zprof counters.
    registry = []
    for _ in range(10):
        output = run('typeset -F start=$EPOCHREALTIME\nsource "$AUDIT_TREE/lib/command-registry.zsh"\nprint "BENCH $(( (EPOCHREALTIME-start)*1000 ))"\nprint "COUNT ${#_ZSH_HELP_ORDER}"')
        assert b"COUNT 53" in output
        registry += values(output)
    RESULT["registry"] = {"records": 53, **summary(registry)}

    # Count repeated role resolutions while preserving the implementation.
    output = run(r'''
source "$AUDIT_TREE/25-theme.zsh"
_zsh_theme_load_registry
functions[_audit_color_original]=$functions[_zsh_theme_color_value]
typeset -A seen
integer calls=0
_zsh_theme_color_value() { (( calls++ )); seen[$1]=1; _audit_color_original "$@"; }
_zsh_theme_fzf_color_args
print "ROLES $calls ${#seen}"
''')
    RESULT["color_roles"] = output.decode().strip()
    assert b"ROLES 40 13" in output, output

    # Exhaustive component proof of the proposed nearest-color arithmetic.
    # Gray distance = constant - 2*g*(r+g+b) + 3*g*g, so only the sum matters.
    levels = (0, 95, 135, 175, 215, 255)
    for channel in range(256):
        reference = min(range(6), key=lambda i: (channel - levels[i]) ** 2)
        proposed = 0 if channel <= 47 else 1 if channel <= 115 else (channel - 116) // 40 + 2
        assert reference == proposed
    for total in range(766):
        reference = min(range(24), key=lambda i: 3 * (8 + 10 * i) ** 2 - 2 * (8 + 10 * i) * total)
        proposed = 0 if total - 24 <= 15 else min(23, (total - 24 + 14) // 30)
        assert reference == proposed
    RESULT["color_arithmetic"] = {"cube_channels_checked": 256, "gray_sums_checked": 766,
                                  "scope": "mathematical component equivalence; not production Zsh/cache parity"}

    # Captured truncation uses ASCII while the same helper on a TTY uses Unicode.
    captured = run(common + 'print -r -- "$(_ui_safe_truncate 5 abcdefgh)"', tty=True)
    direct = run(common + '_ui_safe_truncate 5 abcdefgh', tty=True)
    assert captured != direct
    RESULT["truncation_context"] = {"captured": captured.decode().strip(), "direct_tty": direct.decode().strip()}

    # Raw NUL framing is ambiguous if field values may themselves contain NUL.
    nul_frames = [subprocess.check_output(["jq", "-j", '.[] | ., "\\u0000"'], input=json.dumps(fields).encode())
                  for fields in (["a\0b", "c"], ["a", "b\0c"])]
    assert nul_frames[0] == nul_frames[1]
    RESULT["raw_nul_framing_collision"] = True

    # Wordcode counterexamples, deliberately confined to throwaway files.
    source = work / "stale.zsh"
    source.write_text("print old\n")
    subprocess.run(["zsh", "-dfc", 'zcompile -U -- "$1"', "audit", str(source)], check=True)
    source.write_text("print new\n")
    stamp = int(time.time()) - 10
    os.utime(source, (stamp, stamp))
    os.utime(str(source) + ".zwc", (stamp, stamp))
    stale = run('source "$AUDIT_WORK/stale.zsh"').decode().strip()
    assert stale == "old"
    alias_code = r'''
alias print=AUDIT_SENTINEL
source "$HOME/.config/zsh/init.zsh"
integer hits=0
local body
for body in "${functions[@]}"; do [[ $body == *AUDIT_SENTINEL* ]] && (( hits++ )); done
builtin print "HITS $hits"
'''
    hits = [int(re.search(rb"HITS (\d+)", run(alias_code, source, interactive=True))[1]) for source in (base, compiled)]
    assert hits[0] > 0 and hits[1] == 0
    RESULT["wordcode"] = {"equal_timestamp_result": stale, "alias_affected_functions_text_compiled": hits,
                          "default_mode": oct((work / "stale.zsh.zwc").stat().st_mode & 0o777)}
    RESULT["runtime_source_sha256"] = {str(p.relative_to(base)): hashlib.sha256(p.read_bytes()).hexdigest()
                                       for p in sorted(base.glob("*.zsh"))}

RESULT["load_average_end"] = os.getloadavg()
print(json.dumps(RESULT, indent=2, sort_keys=True))
