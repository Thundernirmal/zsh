# Research for upkg action timing

Researched on 2026-10-15 against shell revision `a6605d2`. These findings support [SPEC.md](./SPEC.md); they do not describe an implemented feature.

## Existing behavior and integration points

- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh) owns parsing, canonical action selection, filtering, a sequential per-manager dispatch loop, cancellation aggregation, and both summary renderers. Sampling around that loop covers every package action uniformly.
- `plan`, default `--dry-run`, and `upgrade --dry-run` use the outdated handlers. Their timing must describe the inventory they actually execute.
- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh) owns backend work. APT upgrade has two commands; several other managers expose one combined native upgrade command. Cleanup may have multiple phases, and search may perform metadata enrichment. A portable refresh/download/install breakdown cannot be derived merely by timing the manager dispatch.
- Search uses `_upkg_format_search_rows` followed by `_upkg_print_search_summary`; its summary currently reports aggregate counts rather than every manager's status. Per-manager timings therefore need a compact additional list in this path.
- Existing normal summary states and details are stored separately, keyed by manager. Timing can be separate numeric data rather than being embedded into backend diagnostic strings.
- Ordinary failures continue to later managers. Cancellation records the current result, stops the loop, and preserves interrupt status. Capture timing after the backend returns without moving work into another process or intercepting its prompts.
- The package domain is loaded lazily through [lib/functions-catalogue.zsh](../../lib/functions-catalogue.zsh). Timing belongs inside its action execution, preserving shell startup behavior.
- [scripts/test-upkg.zsh](../../scripts/test-upkg.zsh) already provides fake managers and output/status assertions. Package audit and query-ownership suites cover cancellation details and process cleanup. Extend these fixtures rather than running real package mutations.

## Default output versus a flag

| Choice | Benefit | Cost | Decision |
|---|---|---|---|
| Always display elapsed summaries | Immediate feedback on ordinary runs; one documented behavior | Human-readable output changes and gains a small amount of text | Selected by the user |
| Default on, with `--no-timing` | Can suppress output for personal preference | Adds parsing, completion, documentation, and another output path | Not selected |
| Opt in with `--timing` | Keeps existing default output bytes | Easy to forget on a slow run; cannot recover past durations; adds a second mode | Not selected |

The cost of two in-shell timestamps per manager does not justify requiring opt-in on its own. Terminal output is the more visible tradeoff, so append concise values to existing summaries, render once, and avoid a live timer. This is a product recommendation informed by local measurements, not a universal rule about CLI design.

Backend-specific diagnostics are a different feature: [npm's logging documentation](https://docs.npmjs.com/cli/v11/using-npm/logging/#timing-information) describes `--timing` as terminal diagnostics plus a timing file containing internal timers. Passing that flag through would add npm-specific output/files and would not supply consistent timing for other managers. Keep `upkg` timing outside backend argv.

## Clock alternatives

| Mechanism | Characteristics | Assessment |
|---|---|---|
| Zsh `EPOCHREALTIME` | Fractional timestamp from a Zsh module; same-process access; read-only parameter | Preferred, with guarded first-use loading |
| Floating-point `SECONDS` | Built-in elapsed parameter; no module; mutable and visible to nested functions | Feasible but needs careful caller-state handling |
| Zsh `time` keyword | Native execution report, configurable via `TIMEFMT` | Better suited to external ad hoc inspection than collecting summary fields |
| External `date` or `/usr/bin/time` | Additional processes and platform-specific output behavior | Unnecessary for bounded summary timing |
| Helper exposing a monotonic clock | Avoids wall-clock adjustments | Adds a runtime/platform dependency or persistent helper; outside this feature |

The [Zsh parameter manual](https://zsh.sourceforge.io/Doc/Release/Parameters.html) supports fractional `SECONDS` and documents `TIMEFMT`. The [datetime module manual](https://zsh.sourceforge.io/Doc/Release/Zsh-Modules.html#The-zsh_002fdatetime-Module) describes `EPOCHREALTIME` and its precision limitations. Fractional representation is useful for UI rounding; it is not a promise of nanosecond measurement accuracy.

Reviewing the [Zsh 5.9 `SECONDS` implementation](https://github.com/zsh-users/zsh/blob/zsh-5.9/Src/params.c#L4129-L4183) confirms that it uses `gettimeofday`; it should not be advertised as monotonic. [Zsh's datetime implementation](https://github.com/zsh-users/zsh/blob/zsh-5.9/Src/Modules/datetime.c#L198-L204) reads its fractional epoch value through `zgettime`. The documented epoch-clock contract is sufficient to rule out a monotonic guarantee for `EPOCHREALTIME` too.

A local scope probe confirmed that `local -F 6 SECONDS=0` restored the caller's advancing floating-point timer on Zsh 5.9 after a short sleep. However, changing this special parameter inside `upkg` would still be observable by nested shell functions while the call runs, and unusual caller attributes need care. The proposed module clock avoids modifying `SECONDS`. If that clock cannot be enabled, unavailable timing is preferable to breaking package work or implementing multiple clock systems for this small feature.

The selected design accepts that system-clock corrections can distort elapsed values. It detects sampled backward movement and reports unavailable values; it cannot reliably detect a forward jump. A guaranteed monotonic duration would require revisiting the dependency constraint.

## Local performance experiment

Environment: Linux `7.2.10-200.fc44.x86_64`, glibc 2.43, Zsh 5.9 (`x86_64-redhat-linux-gnu`). The experiment ran standalone `zsh -dfc` processes without sourcing the repository, executing package tools, or changing package state.

For each case, run one warmup and seven measured batches. In-shell cases used 100,000 iterations per batch; external `date` used 200. Time only the loop using `EPOCHREALTIME`. The baseline uses the same loop and declarations with a `:` body. Numbers include loop overhead; estimated added cost subtracts the baseline median.

| Case | Median per iteration | Observed range of batch averages | Added over baseline |
|---|---|---|---|
| Empty loop body | 2.804 microseconds | 2.598–3.097 microseconds | — |
| Two floating `SECONDS` reads and subtraction | 8.788 microseconds | 8.108–10.081 microseconds | 5.984 microseconds |
| Two `EPOCHREALTIME` reads and subtraction | 9.735 microseconds | 9.327–10.902 microseconds | 6.931 microseconds |
| Epoch reads, subtraction, associative storage, `printf -v` | 20.452 microseconds | 19.976–22.276 microseconds | 17.648 microseconds |
| Two external GNU `date +%s.%N` calls and subtraction | 2514.871 microseconds | 2496.957–2575.637 microseconds | 2512.067 microseconds |

Eight repetitions of the storage/formatting primitive imply roughly `0.14 ms` of added work on this host, before total-clock samples and actual renderer/helper overhead. This is an extrapolation, not a measurement of the final feature. The `printf` case only formats decimal seconds; it does not include the specified multi-unit formatter or terminal rendering.

A separate fresh-shell comparison used three warmups and 50 samples timed by Python's monotonic `perf_counter_ns`. Median shell launch with `:` was `2.263 ms`; launch plus `zmodload zsh/datetime` was `2.053 ms`. The reversed result demonstrates noise/order effects; it does **not** establish negative or zero module-load overhead. Cold integration cost remains unquantified and must be measured with interleaved baseline/candidate trials during implementation.

These results favor avoiding external process launches. They do not establish a perceptible speedup, production latency, p95 feature overhead, or behavior on other operating systems. First-use filesystem caches, CPU scheduling, terminal speed, query supervision, and native commands all affect an actual run.

### Reproducing the loop measurements

Run this Python snippet locally. Python and GNU `date` are research tools here, not proposed runtime dependencies. The external-date case is Linux-specific and is not a portability recommendation.

```python
import statistics
import subprocess

cases = {
    "baseline": (100000, ":"),
    "SECONDS pair": (100000,
        "start=$SECONDS; elapsed=$(( SECONDS - start ))"),
    "epoch pair": (100000,
        "start=$EPOCHREALTIME; elapsed=$(( EPOCHREALTIME - start ))"),
    "pair + store + format": (100000,
        'start=$EPOCHREALTIME; elapsed=$(( EPOCHREALTIME - start )); '
        'durations[brew]=$elapsed; printf -v formatted "%.1fs" "$elapsed"'),
    "external date pair": (200,
        "start=$(command date +%s.%N); finish=$(command date +%s.%N); "
        "elapsed=$(( finish - start ))"),
}
samples = {name: [] for name in cases}
for batch in range(8):
    for name, (count, body) in cases.items():
        script = f'''emulate -L zsh
zmodload zsh/datetime || exit 1
typeset -F 6 SECONDS
typeset -F start finish elapsed bench_start
typeset -A durations
typeset formatted
integer i
bench_start=$EPOCHREALTIME
for (( i=0; i<{count}; i++ )); do
  {body}
done
print -r -- $(( (EPOCHREALTIME - bench_start) * 1000000.0 / {count} ))
'''
        value = float(subprocess.check_output(
            ["zsh", "-dfc", script], text=True))
        if batch:
            samples[name].append(value)
for name, values in samples.items():
    print(name, "median us:", statistics.median(values),
          "range:", min(values), max(values))
```

## Delivery boundary

This work produces a feature specification and supporting research only. The local benchmark is evidence for the design choice; feature implementation and its acceptance checks remain pending. Runtime documentation is deliberately left describing current behavior until implementation.

The shell verification command for this documentation change is `zsh scripts/run-tests.zsh`. The future implementation also needs end-to-end overhead measurements and the website checks listed in [SPEC.md](./SPEC.md#acceptance-and-verification).
