# upkg action timing

Status: ready for implementation; runtime behavior is not changed by this document.

Branch: `feat/upkg-action-timing`

Research date: 2026-10-15

Source baseline: `a6605d2`

## Outcome and agreed preferences

Every package action should tell the user how long each attempted manager took and how long the overall action took. Timing is part of the normal result, with no new flag or environment setting. Elapsed time includes network waits, native confirmations, password entry, and other waits within the measured operation.

The user explicitly selected these three preferences during discovery:

- Always show timing; do not add a timing flag.
- Show each manager's action and the total; do not break down backend substeps.
- Include all waiting time to represent the elapsed time the user experiences.

Timing appears in the existing final summaries. There is no live ticking display. [RESEARCH.md](./RESEARCH.md) records the alternatives, source inspection, benchmarks, and clock limitations behind the design.

## Scope

| Invocation | Timing describes |
|---|---|
| `upkg`, `outdated`, `check`, `list` | The outdated inventory for each attempted manager and the overall inventory |
| `upkg search <query>` | Each manager's complete search, including metadata enrichment, and the overall search |
| `upkg plan` | Each manager's inventory and the overall plan |
| `upkg upgrade`, `up`, `update` | Each manager's complete upgrade action and the overall upgrade |
| `upkg clean` | Each manager's complete cleanup action and the overall cleanup |
| Default check or upgrade with `--dry-run` | The actual inventory performed, labeled as a plan |
| `upkg clean --dry-run` | The actual preview performed, labeled as a cleanup preview |
| `upkg help`, `-h`, `--help`, `managers` | No timing summary; these do not run package actions |

Aliases retain their existing canonical action. A dry run never estimates the duration of a future mutation. An upgrade does not add an outdated query solely to produce a separate check duration. Running a check and then an upgrade produces two independent summaries; no history is stored or combined.

No per-package, refresh/download/install-phase, CPU-time, historical, telemetry, JSON-export, or parallel-execution feature is included. Standalone `npkg` behavior is unchanged; the Nix action called through `upkg` is timed as a whole.

## Measurement boundaries

Initialize timing in the real `upkg()` function after valid action parsing and dry-run normalization, after the help return and with `managers` excluded, before the action title, manager detection, and filtering. Take the total start sample immediately after clock initialization. This keeps timers out of startup, completion, help, and manager listing.

The total ends immediately before printing the final summary. For search, take that end sample after the consolidated search rows have been rendered and before `_upkg_print_search_summary`. Thus the total includes detection, filtering, manager execution, between-manager bookkeeping, captured-query cleanup, and result rendering before the summary. It excludes argument parsing, the outer lazy loader, clock initialization, and the final summary itself. Document this small boundary difference from an external stopwatch; do not call the value exact shell-command execution time.

For each manager, start immediately before its existing dispatch branch and stop as soon as that backend returns. Capture its return status before calling any timer helper. Its elapsed time includes its section rendering, preflight checks, native processes, output processing, native interactive waits, and any query-supervisor teardown performed before return. APT refresh and full-upgrade therefore share one duration. Cleanup phases share one duration. The npm prefix check belongs to its manager duration.

Measure the total independently; do not calculate it by summing manager durations. It includes work outside the manager boundaries. Display rounding can make rounded values appear not to add up, and this is expected.

## Output contract

Add an `elapsed <duration>` suffix to each existing attempted-manager summary row. Keep the status and diagnostic detail intact. Add one final `Total elapsed (<action>): <duration>` line; canonical action labels are `outdated`, `search`, `plan`, `upgrade`, `clean`, and `clean preview`.

Illustrative plain output, with fictional durations:

```text
Summary:
  brew: updates available | elapsed 2.4s
  npm: up to date | elapsed 0.8s
Total elapsed (outdated): 3.3s
```

```text
Summary:
  apt: upgraded | elapsed 1m 42.3s
  brew: failed - brew upgrade failed | elapsed 4.7s
Total elapsed (upgrade): 1m 47.2s
```

Search currently has aggregate counts rather than a row for every manager. Retain its existing summary and failed/cancelled-manager diagnostics, then add an `Elapsed by manager:` list in summary order. Include manager ID, existing state, and elapsed value; do not alter the normalized search-result table.

```text
Search summary: 4 result(s) across 2 manager(s).
Elapsed by manager:
  brew: matches | elapsed 1.8s
  npm: matches | elapsed 0.5s
Total elapsed (search): 2.4s
```

Use the same data and duration formatter for plain, rich, ASCII, and no-color output. Rich output uses existing semantic muted/text roles for durations, retaining status colors and icons. Do not add a palette, glyph, fixed-width timing column, or timing-specific UI mode. At narrow widths, move the suffix to an indented continuation line when needed instead of dropping or truncating the duration or diagnostics.

Timing is summary information on stdout, following the existing summary stream. Native diagnostics remain on stderr. Pipes and redirected output retain plain formatting and include timing. This changes human-readable output; do not advertise the current output as a stable machine-readable schema. There is no opt-out flag to preserve old bytes.

### Duration formatting

- Retain fractional seconds internally; format only at rendering time.
- Valid elapsed values below `0.1` seconds display `<0.1s`, including an interval below clock resolution. This avoids presenting a fast attempt as having taken exactly zero time.
- Other values round to the nearest tenth of a second, using arithmetic that handles carry before splitting units: `2.4s`, `1m 02.4s`, `1h 02m 03.4s`.
- For values rounded across a minute/hour boundary, display the normalized next unit, never `60.0s` or `60m` within a larger unit.
- Hours may exceed 23; do not wrap to a time of day.
- Use a decimal point and ASCII unit letters in all modes. Restrict any locale override to formatting so native commands retain their existing locale behavior.
- Missing or invalid samples display `elapsed unavailable`; never fabricate `0s`.

### Failures, skips, and interruption

| Result | Timing behavior |
|---|---|
| Successful inventory, search, upgrade, or cleanup | Show elapsed time for the complete attempted manager |
| Ordinary failure or partial cleanup | Show elapsed time until return; preserve continuation and failure details |
| Blocked action | Show elapsed time for the preflight attempt; the blocked status makes clear that mutation did not run |
| Cancellation | Preserve completed manager durations, show the interrupted manager's duration through teardown, and print elapsed total so far |
| Manager skipped by filter | Show `not run` instead of a numeric duration, retaining `skipped` state |
| Manager never reached after cancellation | Keep the current omission behavior; no duration and no inflation of attempted-manager counts |
| Help, invalid arguments, no detected managers, or empty selection | Keep the existing early return without a timing summary |

The same skipped-row rule applies to search's new timing list without changing search's attempted-manager count. Cancellation retains `129`, `130`, or `143` as applicable and stops later managers and cleanup phases. A failed clock or rendering helper must not replace a backend result, suppress a diagnostic, prevent remaining authorized work, or change the aggregate exit status. No summary is promised if the shell is forcibly terminated before its existing cancellation path can regain control.

## Clock and state design

Use the Zsh `zsh/datetime` module's `EPOCHREALTIME`, loaded on demand inside the action path with a guarded `zmodload`. It gives fractional wall-clock samples without an external executable, subprocess, or timer daemon. The repository already uses it in its startup benchmark; normal shell initialization must not load it for this feature.

Only use the module's actual special parameter; do not treat an ordinary caller-created variable named `EPOCHREALTIME` as a working clock. If the module/feature cannot be enabled or a clock sample is invalid, continue package work and display unavailable timings. Preserve the normal summary layout and add at most one short explanatory timing note per invocation. Do not install a dependency, fall back to `date`, alter caller parameters, or write a log file.

This is a wall clock, not a monotonic clock. If a sampled timestamp moves backward relative to the preceding sample in this invocation, keep completed valid durations, mark the active and subsequent durations unavailable, and mark total elapsed unavailable with a single `Timing unavailable: clock moved backward.` note. A forward clock adjustment, or a reversal entirely between samples, cannot be reliably identified by this scheme. The guide must describe this limitation; do not claim immunity to clock changes. Normal waits and suspend time are included to the extent represented by the system clock.

Store timestamps and elapsed values as invocation-local numeric state. A local associative array keyed by manager can hold durations alongside the existing summary state. Keep validity separate from the duration, so zero, missing, skipped, and unavailable are distinct. Shared timing helpers may access invocation-local state through Zsh dynamic scoping. Do not persist measurements in exported variables or leave values that a later invocation can accidentally reuse.

Timer helpers must run synchronously in the same shell and return through local state/output parameters, not `$(...)`. Do not wrap native commands in a pipeline, subshell, external `time`, output capture, or a different process supervisor for timing. Preserve native TTY access, stdin, argv, privilege handling, and query ownership. Do not add signal traps; integrate with the existing cancellation path and keep manager order unchanged.

Keep the existing fixed dispatch and loader paths. Backend implementations should not need timing-specific edits for manager-level timing. Rendering helpers must tolerate direct calls without initialized timing state, because existing regression tests exercise them independently.

## Performance expectations

The design adds two clock samples per attempted manager, two for the action, bounded bookkeeping, and final-summary formatting. It does no per-package sampling, polling, persistent writes, or extra package-manager calls. Storage and work scale with the number of attempted managers, not package count or action duration. Nothing new executes during normal shell startup.

Local experiments measured approximately `6.9 microseconds` above the loop baseline for a pair of `EPOCHREALTIME` samples and subtraction, and `17.6 microseconds` when adding associative storage and simple formatting. These are primitive measurements, not an implemented-feature benchmark. See [the method and limitations](./RESEARCH.md#local-performance-experiment).

Before implementation is accepted, compare the baseline and candidate using fake managers, both with timing work and final rendering included. Run at least three warmups and 30 samples; report median and p95 for a single-manager and an eight-manager run in plain and rich modes. Redirect output to a file or `/dev/null` for repeatability, and inspect a real terminal separately. Also report cold first-use time and `scripts/benchmark-startup.zsh` results. Keep backend fixtures identical and do not benchmark real upgrades.

Use an added warm median below `1 ms` per eight-manager plain run as an investigation threshold, not an already-proven guarantee or a flaky CI assertion. If it is exceeded, identify whether the cost is clock/state work or rendering before accepting the implementation. Report absolute deltas; a large percentage on a no-op fixture can still represent a tiny elapsed cost. Do not add an opt-in flag solely to hide avoidable implementation overhead.

## Implementation and documentation plan

1. Add private timing initialization/sampling/formatting helpers in [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh). Keep them within the existing lazy domain and avoid new startup registrations or general-purpose infrastructure.
2. Add invocation-local timing state and samples around the existing manager dispatch. Preserve all return states, cancellation handling, manager filters, and summary order.
3. Extend `_upkg_print_summary` and `_upkg_print_search_summary` using one duration formatter, retaining existing result information and UI policies.
4. Add regression coverage to [scripts/test-upkg.zsh](../../scripts/test-upkg.zsh), plus cancellation/query ownership and lazy-load coverage in existing relevant suites where necessary.
5. Update the `Package manager: upkg` body in [GUIDE.md](../../GUIDE.md) with scope, boundaries, prompt waits, previews, output changes, and clock limitations. Keep its established headings and anchors.
6. Update [README.md](../../README.md) at entrypoint level with a short timed-summary mention/link. Update [80-tips.zsh](../../80-tips.zsh) consistently with its loader ownership and add an actionable literal reminder in [lib/tips-catalogue.zsh](../../lib/tips-catalogue.zsh), such as comparing manager elapsed times after `upkg --only=brew,npm`. Do not put implementation details into user tips.
7. Update `_upkg_usage` in its rich and plain forms to explain automatic elapsed summaries. Review [lib/command-registry.zsh](../../lib/command-registry.zsh) for concise consistency; preserve the eight-literal-field registration format. No CLI flag, completion option, or shared external dependency is added, so no new entries in the option registry or `scripts/check-deps.sh` are needed.

This spec-only branch does not update current-behavior README/guide/help/tips or change runtime code. Those changes belong to implementation, so users are not told an unimplemented feature exists. Remove these planning documents when the completed behavior has been documented and verified; preserve the design history in Git in accordance with [AGENTS.md](../../AGENTS.md).

## Acceptance and verification

Use deterministic clock samples and fake package executables. No automated check may perform real package upgrades or cleanup.

- Cover every canonical action and alias, default invocation, `plan`, upgrade/default dry runs, and cleanup previews. Help, managers, invalid arguments, and empty selections retain their early-return behavior.
- Verify exact per-manager and independently measured total values from injected samples, manager order, rounding/carry, sub-`0.1s` values, multi-hour values, and locale-independent formatting.
- Verify successful, empty, failed, partial, blocked, filtered, and interrupted results. Earlier results remain visible, skipped managers have no number, and never-started managers are not counted.
- Exercise both summary renderers, direct renderer calls without timer state, repeated invocations, rich/plain/ASCII/no-color output, stdout versus stderr separation, and narrow terminal wrapping.
- Cover clock initialization failure, disabled or shadowed clock parameters, invalid samples, and a backward sample. Timing failures cannot change the backend status or terminate package work. A completed valid duration remains valid after a later clock failure.
- Confirm native argv, invocation count, stdin/TTY behavior, privilege gates, failure continuation, and existing INT/TERM/HUP semantics are preserved. PTY checks should include cancellation and a delayed response to a fake native prompt so prompt waiting is demonstrably included.
- Confirm startup and completion do not initialize the timer and no extra external commands or processes are created for sampling, bookkeeping, or formatting.
- Run `zsh scripts/run-tests.zsh`, as required by the repository, and record the performance comparisons described above. Use manual terminal inspection for long native output, wrapping, and the readability of the added search timing list.

The companion checkout was found at `/home/nirmal/projects/zsh-web`. This spec-only change does not modify its extracted inputs, and website verification has not been performed. Implementation must review extraction of `upkg` help, source details, examples, tips, availability, and rendered guide content. Do not assume a successful parse proves the new summary is represented correctly.

After shell implementation is reviewed and committed in a clean checkout, follow the website's current `README.md` and `AGENTS.md`, run `ZSH_CONFIG_DIR="$HOME/.config/zsh" npm run sync`, inspect generated changes, and run `npm run verify` and `npm run test:e2e`. Check affected topics, anchors, search, mobile tables/code, and payload/DOM budgets. Publish the shell revision before website CI needs it. No new guide topic, command category, or parser structure is planned; any implementation-driven structural change requires coordinated extractor coverage.

## Remaining work

Product preferences are settled. Implementation, feature regressions, cross-platform validation, end-to-end performance comparisons, manual terminal QA, and the coordinated website snapshot remain to be done. Linux research measurements do not establish macOS or WSL performance.
