# Measurements, reproduction and limits

Fresh synthetic observations were collected on 2026-10-18 against `348906d0fa8e87f6d3198a63a0a832a4deeffbe1`. The source is unchanged. [Raw samples and environment](./evidence/baseline.json) retain all accepted groups and expected count/width checks. Five sequential same-process samples per group; no discarded warmup. No optimized runtime implementation was benchmarked, so no speedup is claimed. CPU scheduling/thermal state and filesystem cache are uncontrolled.

Host: Linux-7.2.11-200.fc44.x86_64-x86_64-with-glibc2.43; Intel(R) Core(TM) i5-8300H CPU @ 2.30GHz; zsh 5.9 (x86_64-redhat-linux-gnu). PATH /usr/bin:/bin, C.UTF-8, 120x40, TERM xterm-256color, COLORTERM truecolor, terminal theme. Private HOME/ZDOTDIR/XDG; only required modules are sourced. `_ui_is_rich_terminal` is overridden for formatter groups. Forced-rich sink output is neither a real PTY nor terminal throughput, and the override also affects nested helper decisions. Its bytes are not an output-parity oracle.

## Accepted current-code observations

| Workload | Dimension | Median ms | Validation |
| --- | ---: | ---: | --- |
| parser | 100 | 152.086 | Count checked |
| formatter-plain | 100 | 2.848 | Rows supplied; function exit checked, output discarded |
| formatter-forced-rich | 100 | 697.889 | Rows supplied; function exit checked, output discarded |
| parser | 1000 | 1899.817 | Count checked |
| formatter-plain | 1000 | 24.997 | Rows supplied; function exit checked, output discarded |
| formatter-forced-rich | 1000 | 8012.546 | Rows supplied; function exit checked, output discarded |
| width-ascii | 40 | 0.051 | Exact width checked |
| width-ascii | 1000 | 0.090 | Exact width checked |
| width-mixed | 40 | 1.580 | Exact width checked |
| width-mixed | 1000 | 43.536 | Exact width checked |
| width-cjk | 40 | 6.597 | Exact width checked |
| width-cjk | 1000 | 357.862 | Exact width checked |
| record-reader | 1000 | 36.027 | Count checked |
| record-reader | 10000 | 448.486 | Count checked |

Pacman capture is an in-process fixture: parser times exclude native query/supervision. Formatter times include current helper work, with synthetic fields and nonempty descriptions. Plain/rich ratios are workload comparisons, not attainable optimization ratios. Width tables are warmed once before width groups; 40 characters represents ordinary labels, 1,000 exposes scaling. Record-reader times cover only the actual baseline NUL loop over prebuilt short paths, excluding find/du, sorting, totals and display. No kernel syscall attribution or RSS was collected.

The first attempted driver completed package groups, then failed constructing an ASCII fixture under NO_UNSET. Those incomplete-run observations were discarded. The fixture was corrected to pad an explicitly initialized empty variable and the entire run restarted. Only the successful run is retained above. This was an evidence-driver failure, not a project regression.

## Fresh offline-completion confirmation

A separate isolated 60,000-name fixture used a compdef stub, a fake native nix that logs and fails if called, and the actual lazy/completion modules. Across five cache-reset builds, median cold helper time was **3,029.865 ms**; each followed by a same-shell warm call, median **19.794 ms**. Every call returned 60,000 candidates, parse/build counters remained one for a warm hit, the Nix domain flag stayed zero in the parent, and **zero native nix calls** occurred. [Raw samples, method and exact Zsh body](./evidence/completion.json) retain the checks. This excludes compinit, compadd and actual Tab latency.

Reproduction driver (save under /tmp and execute from this checkout; output is the explicit plans evidence path in this recorded recipe, so choose a separate output path for comparisons):

```python
from pathlib import Path
import tempfile,subprocess,os,json,statistics
repo=Path.cwd().resolve()
code='''emulate -L zsh
zmodload zsh/datetime
compdef() { :; }
source "$1/60-functions.zsh"
source "$1/66-compdefs.zsh"
typeset -F t0
integer rep
for rep in {1..5}; do
 _ZSH_NPKG_COMPLETION_CACHE_DATA=(); _ZSH_NPKG_COMPLETION_CACHE_PATH_KEYS=()
 _ZSH_NPKG_COMPLETION_UNION=(); _ZSH_NPKG_COMPLETION_UNION_VALID=0
 _ZSH_NPKG_COMPLETION_PARSE_COUNT=0; _ZSH_NPKG_COMPLETION_BUILD_COUNT=0
 t0=$EPOCHREALTIME
 _zsh_npkg_cached_attributes || exit 1
 (( ${#reply} == 60000 && _ZSH_NPKG_COMPLETION_PARSE_COUNT == 1 )) || exit 2
 print -- "cold $rep $(( (EPOCHREALTIME-t0)*1000 )) ${#reply} ${_ZSH_FUNCTION_DOMAINS_LOADED[nix]:-0}"
 t0=$EPOCHREALTIME
 _zsh_npkg_cached_attributes || exit 1
 (( ${#reply} == 60000 && _ZSH_NPKG_COMPLETION_PARSE_COUNT == 1 && _ZSH_NPKG_COMPLETION_BUILD_COUNT == 1 )) || exit 2
 print -- "warm $rep $(( (EPOCHREALTIME-t0)*1000 )) ${#reply} ${_ZSH_FUNCTION_DOMAINS_LOADED[nix]:-0}"
done
'''
with tempfile.TemporaryDirectory(prefix='zsh-compl-proof-') as d:
 root=Path(d); (root/'cache/npkg').mkdir(parents=True); (root/'bin').mkdir(); (root/'home').mkdir()
 (root/'cache/npkg/nixpkgs-attrs-x86_64-linux.txt').write_text(''.join(f'pkg{i:06}\n' for i in range(60000)))
 fake=root/'bin/nix'; fake.write_text('#!/bin/sh\nprintf called >> "$NIX_PROOF_LOG"\nexit 99\n'); fake.chmod(0o700)
 env={'PATH':f'{root}/bin:/usr/bin:/bin','HOME':str(root/'home'),'XDG_CACHE_HOME':str(root/'cache'),'ZDOTDIR':str(root/'home'),'LC_ALL':'C.UTF-8','TERM':'dumb','NIX_PROOF_LOG':str(root/'calls')}
 r=subprocess.run(['/usr/bin/zsh','-dfc',code,'proof',str(repo)],text=True,capture_output=True,env=env,timeout=90)
 assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr,r.stdout)
 assert not (root/'calls').exists()
 groups={k:[] for k in ['cold','warm']}
 for line in r.stdout.splitlines():
  k,rep,ms,n,loaded=line.split(); assert n=='60000' and loaded=='0'; groups[k].append(float(ms))
 result={'raw_stdout':r.stdout,'native_nix_calls':0,'candidate_count':60000,'parent_nix_domain_loaded':0,'samples_ms':groups,'medians_ms':{k:statistics.median(v) for k,v in groups.items()},'code':code,'method':'Synthetic cache, compdef stub, fake nix fails/logs if invoked. Five cache-reset cold builds, each followed by same-shell warm helper. No real compinit/compadd or Tab.'}
 (repo/'plans/evidence/completion.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({k:v for k,v in result.items() if k not in ['code','raw_stdout']},indent=2))
```

## Independent structural and semantic checks

- Sun inventory recomputation: 388 runtime definition occurrences, 333 distinct names, exact CSV/source-location agreement. Retained JSON statistics recomputed. Inventory is coverage accounting, not per-function execution profiling.
- Availability counter using 53 literal registry records and synthetic registered implementations: default plain listing 103 availability checks, --all plain listing 53. Counts depend on available tools/functions; no latency saving established.
- Keymap proof: bindkey -lL yielded 8 definition/alias lines both before and after adding 100 emacs bindings. The large-binding-dump premise is false. A global assigned inside a captured helper remained unset in the parent.
- Real PTY semantic proof in UTF-8, width 100, unicode tier, NO_COLOR unset: direct truncation at width 10 gave `abcd…lmnop`; captured wrapper gave `abc...mnop`. Captures change the helper output destination.
- Separate truncator proof in ASCII mode: width 1 on abcdef gave ordinary `a`, safe `.`; width 4 gave ordinary `abcd`, safe `...f`.
- NUL fixture with trailing/repeated IFS tabs plus final unterminated record: old reader kept two normalized paths; naive bulk split kept three records and extra tabs. Line fixture alpha/newline/blank/beta without final newline: old completion read kept alpha; naive bulk split also kept beta.
- Completion proof on a small fixture: unchanged data parsed/built once; CR retained; final unterminated name ignored; Nix domain remained unloaded in the parent after captured lazy helper.
- Signal normalizer on Zsh 5.9: 0→0/(0), 9 or KILL→KILL/(9), 128→128/(128), 137→KILL/(137), CLD→CHLD/(17). No signal was sent. Naive signal-array indexing is not equivalent.

These short checks were independently executed by the source-review agents, using private temporary fixtures and no live backend, and cross-checked against source by the consolidating reviewer. They validate semantics and counts; they are not candidate timing results. See [review record](./review.md).

## Original evidence: retained claims and corrections

Sun stores raw observations for fresh-shell first calls and disk/catalogue groups; its existing startup-script groups retain summary stdout, not all 30 individual values. Initial package groups overlapped; sequential confirmations have only three 100-row samples. Unicode values are three-call means. Local JSON medians/p95 were independently recomputed. These support problem identification, not paired candidate gains.

Earth has genuine PTY render observations and synthetic reader/completion prototypes, but run-all suppresses some child failures with `|| true`, reuses an existing symlink without target verification, inherits locale, and does not reproduce every reported experiment. Its module TOTAL includes inter-module writes and unconditional CGM source; it is not init/OMZ end-to-end startup. Its fbr harness returns REPLY without printing and redirects the alleged TTY case, so that row is non-TTY formatter-only. Its arithmetic sum applies to rich mode and cannot explain its plain bigfiles headline. Bulk read is not proven one kernel syscall.

Sea performed static analysis only. Generic per-fork/jq/Nix costs and numerical improvement/CI targets are not accepted measurements. All three inputs have the same runtime baseline, but their environments/workload boundaries differ. Never add their savings or merge their timings as paired trials.

No live package search/mutation, actual network diagnostics, Secret Service, host shell configuration, OMZ Tab latency, cold disk distribution, WSL-long-PATH distribution or website performance was measured. Native backend time and query-ownership safety costs are not interchangeable with pure formatting costs.

## Reproduce the accepted package, width and reader groups

The following is evidence documentation, not a new project tool. Save the two fenced blocks as measure.zsh and measure.py together under a fresh /tmp directory, run from this repository, and provide an absolute output JSON path. The driver uses private disposable HOME/XDG and deletes its scratch files; it does not source init or host dotfiles, run managers, network, secrets or mutations. The script hash is recorded in baseline.json. The Python driver below discovers the checkout from cwd; the recorded run used the explicit current checkout path.

```sh
python3 /tmp/your-evidence-dir/measure.py /tmp/consolidation-repeat.json
```

```zsh
# Read-only synthetic evidence for the consolidation; not runtime code.
emulate -L zsh
setopt NO_UNSET
zmodload zsh/datetime
repo=${1:?repo}; scratch=${2:?scratch}
source "$repo/25-theme.zsh"
source "$repo/55-ui-helpers.zsh"
source "$repo/60-functions.zsh"
_zsh_functions_load upkg || exit 1
export COLUMNS=120 LINES=40 TERM=xterm-256color COLORTERM=truecolor LC_ALL=C.UTF-8
integer i n rep
typeset -F t0
typeset fixture text kind mode empty=''
typeset -a rows records
_upkg_search_progress() { :; }
_upkg_search_progress_clear() { :; }
_upkg_capture_query() { _UPKG_QUERY_STDOUT=$fixture; _UPKG_QUERY_STDERR=''; return 0; }
for n in 100 1000; do
  fixture=''; rows=()
  for (( i=1; i<=n; i++ )); do
    fixture+="extra/package-$i 1.2.3"$'\n    A package description for fixture '$i$'\n'
    rows+=("pacman"$'\t'"package-$i"$'\t'"1.2.3"$'\t'"A package description for fixture $i")
  done
  for rep in {1..5}; do
    _UPKG_SEARCH_ROWS=(); t0=$EPOCHREALTIME
    _upkg_run_search_pacman example >/dev/null || exit 1
    (( ${#_UPKG_SEARCH_ROWS} == n )) || exit 2
    print -r -- "parser $n $rep $(( (EPOCHREALTIME-t0)*1000 )) ${#_UPKG_SEARCH_ROWS}"
  done
  for mode in plain forced-rich; do
    if [[ $mode == plain ]]; then
      _ui_is_rich_terminal() { return 1; }; _UPKG_THEME_MODE=''
    else
      _ui_is_rich_terminal() { return 0; }; _UPKG_THEME_MODE=1
    fi
    for rep in {1..5}; do
      t0=$EPOCHREALTIME
      _upkg_format_search_rows "${rows[@]}" >/dev/null || exit 1
      print -r -- "formatter-$mode $n $rep $(( (EPOCHREALTIME-t0)*1000 )) $n"
    done
  done
done
_ui_display_width '雪'
for kind in ascii mixed cjk; do
  for n in 40 1000; do
    text=${(pl:$n::a:)empty}
    [[ $kind == mixed ]] && text="雪${text[2,-1]}"
    [[ $kind == cjk ]] && text=${text//a/雪}
    for rep in {1..5}; do
      t0=$EPOCHREALTIME; _ui_display_width "$text"
      print -r -- "width-$kind $n $rep $(( (EPOCHREALTIME-t0)*1000 )) $REPLY"
    done
  done
done
for n in 1000 10000; do
  : > "$scratch/records"
  for (( i=1; i<=n; i++ )); do
    print -rn -- "${i}"$'\t'"/synthetic/path/file-$i"$'\0'
  done > "$scratch/records"
  for rep in {1..5}; do
    records=(); t0=$EPOCHREALTIME
    while IFS=$'\t' read -r -d '' kib entry_path; do
      [[ $kib == <-> ]] || continue
      records+=("${kib}"$'\t'"${entry_path}")
    done < "$scratch/records"
    (( ${#records} == n )) || exit 2
    print -r -- "record-reader $n $rep $(( (EPOCHREALTIME-t0)*1000 )) ${#records}"
  done
done
```

```python
"""Run isolated synthetic baseline; writes JSON only to the requested path."""
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile

repo = Path.cwd().resolve()
output = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="zsh-consolidation-") as root:
    scratch = Path(root)
    home = scratch / "home"
    home.mkdir()
    env = {
        "HOME": str(home), "ZDOTDIR": str(home), "PATH": "/usr/bin:/bin",
        "XDG_CACHE_HOME": str(scratch / "cache"),
        "XDG_DATA_HOME": str(scratch / "data"),
        "XDG_STATE_HOME": str(scratch / "state"),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "TERM": "xterm-256color",
        "COLORTERM": "truecolor", "COLUMNS": "120", "LINES": "40",
    }
    script = Path(__file__).with_name("measure.zsh")
    p = subprocess.run(
        ["/usr/bin/zsh", "-df", str(script), str(repo), str(scratch)],
        env=env, cwd=scratch, text=True, capture_output=True, timeout=180,
    )
    if p.returncode or p.stderr:
        raise RuntimeError((p.returncode, p.stderr, p.stdout))
    groups = {}
    for line in p.stdout.splitlines():
        name, size, rep, ms, result = line.split()
        key = f"{name}/{size}"
        g = groups.setdefault(key, {"samples_ms": [], "results": []})
        g["samples_ms"].append(float(ms))
        g["results"].append(int(result))
    for key, g in groups.items():
        name, size = key.split("/")
        n = int(size)
        expected = n + 1 if name == "width-mixed" else 2*n if name == "width-cjk" else n
        assert g["results"] == [expected]*5, (key, g)
        g["median_ms"] = statistics.median(g["samples_ms"])
    data = {
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
        "date": "2026-10-18", "platform": platform.platform(),
        "zsh": subprocess.check_output(["/usr/bin/zsh", "--version"], text=True).strip(),
        "cpu": next((line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")), "unknown"),
        "environment": {k:v for k,v in env.items() if k not in {"HOME", "ZDOTDIR", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CONFIG_HOME"}},
        "script_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
        "method": "Sequential groups; 5 same-process samples; no discarded warmups. Forced-rich predicate with output sink, not PTY. Parser capture stub. Reader synthetic prebuilt NUL records. No candidate measured.",
        "groups": groups, "raw_stdout": p.stdout,
    }
    output.write_text(json.dumps(data, indent=2) + "\n")
    for name, g in groups.items():
        print(f"{name}: median {g['median_ms']:.3f} ms")
```

## Comparison rules for a future executor

Require exact result bytes/state/status against a frozen baseline before accepting candidate samples. Use same-host alternating runs, identical fixture dimensions/settings and tool versions, at least five expensive or 30 short-startup samples. Keep raw distributions and distinguish helper/fresh-shell/PTY/forced-rich/cold/warm. Validate cleanup, descendant shutdown and result counts/hashes. Record peak RSS for allocation/cache changes. If a candidate misses a declared gate, retain current code. Do not turn local laptop numbers into CI budgets.
