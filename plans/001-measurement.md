# Plan 001: Retain comparable workload evidence

## Status and drift check

TODO; priority Enabler; effort S–M; risk low. Category: performance. Planned at `348906d0fa8e87f6d3198a63a0a832a4deeffbe1`, 2026-10-18. Depends on: none. No implementation is included in this branch.

Run `git diff --stat 348906d0fa8e87f6d3198a63a0a832a4deeffbe1..HEAD -- scripts/benchmark-startup.zsh scripts/benchmark-workloads.py GUIDE.md README.md 80-tips.zsh` first. Re-read the current-state excerpts if any scoped source changed. On mismatch, stop and refresh this plan. Read AGENTS.md. Future executor: use a separate implementation branch in the current checkout unless instructed otherwise; never publish or open a PR without authorization. Match existing `perf:`/`docs:` commit conventions. Keep the operator's unrelated changes.

## Current state and purpose

`scripts/benchmark-startup.zsh:19` already requires the actual resolved checkout at `$HOME/.config/zsh`; lines 41–100 measure warm command/interactive stdin startup with three warmups and median/p95/min/max. It does not measure parser, render, width, scan-reader or completion workloads. Sea's claim that no startup benchmark exists is incorrect.

```zsh
if [[ $benchmark_root != ${HOME}/.config/zsh ]]; then
  print -u2 -r -- "benchmark requires the repository at ${HOME}/.config/zsh"
  exit 2
fi
```

Use `scripts/test-ui-pty.py` for standard-library temporary-directory, controlled-env and subprocess cleanup conventions. Keep the existing benchmark's invocation and reported lower-middle median convention unless a format change is explicit.

## Scope and compatibility

Only these paths may change during future implementation:

- `scripts/benchmark-startup.zsh`
- `scripts/benchmark-workloads.py (new, optional developer tool)`
- `GUIDE.md within Maintenance and verification`
- `README.md maintenance link`
- `plans/README.md and measurement evidence`

Runtime behavior is a strict compatibility constraint: no feature additions/removals, changed options/result sets/order/bytes, freshness or signal/error changes. Preserve fixed trusted lazy source paths, module fallbacks, function-body `command -v`, pure theme startup, no prompt hooks, optional no-secret-access CGM startup, sequential mutations and query ownership protection. Query/supervisor code, aliases, command records, dependency checker and unrelated domains are out of scope. If a behavior change is needed, stop; it requires a separate brief and synchronized README/GUIDE/80-tips/website review. Internal parity-preserving changes do not justify artificial user-facing tips.

## Steps and verification gates

1. Specify the smallest useful developer harness: parser/formatter at 100/1,000 rows; text at 40/1,000 characters; prebuilt NUL records at 1k/10k; offline completion at 60k attributes. Use the documented recipes in `plans/measurements.md`, not real package managers. Define expected counts, widths, output bytes/hashes and statuses before recording timings. Verify each fixture against current implementations; an invalid fixture produces no accepted sample.
2. Add an optional standard-library driver with `--help`, workload/sample selection and a caller-selected JSON output path. Use an allowlisted environment and private HOME/ZDOTDIR/XDG directories. Startup needs a real temporary install copy, because `${0:A}` resolves symlinks and a symlink does not satisfy the existing script's path check. Use `zsh -dfi` fed stdin for normal interactive startup; `-i -c` takes different integration paths. Verify help does no workload work and invalid arguments exit 2.
3. Record raw samples, SHA and dirty state, dimensions, theme, locale, tool versions, warmups, same-process versus fresh-shell and forced-rich versus real PTY. At least five samples for expensive groups and 30 for short startup paths. Same-host alternating baseline/candidate order is required for speedup claims; do not compare independent medians by subtraction. Verify sample counts, result hashes/statuses and recomputed statistics; use no laptop wall-time CI gate.
4. Bound subprocess duration, terminate/reap fixture descendants and always remove private scratch files. Test failure, timeout and interrupt cleanup with synthetic callbacks. Store only requested evidence, never arbitrary environment dumps. Verify host HOME/XDG remain untouched under hostile inherited settings. No runtime dependency is added.
5. Document only the supported developer workflow inside existing GUIDE headings, plus a short README link if useful. This is a developer tool, not a user-facing shell feature: leave `80-tips.zsh` and `lib/tips-catalogue.zsh` unchanged and create no implementation-note tips. Run the full repository gate and review affected website maintenance content before a coordinated publication.

## Commands and done criteria

`zsh scripts/run-tests.zsh` must exit 0 after edits; it owns syntax, regression, real-fzf/UI/preview/timing PTY and fixed-install smoke ordering. `git diff --check` must exit 0. `git diff --name-only` must stay within the scope above (include new files when checking `git status --short`). Run the narrower commands specified at each step first, then the complete gate once candidate work is ready. Do not install dependencies or run native mutations to generate fixtures.

A repeatable optional workload driver emits validated raw results, cleans up on success/failure/interrupt, preserves the existing startup invocation, and adds no product startup work. A failing or skipped prerequisite is reported rather than fabricated. Benchmark correctness replaces no regression suite.

Update the status row in `plans/README.md` only after all gates pass; retain raw before/after evidence, versions, dimensions and output comparisons. Proposed performance gates are adoption criteria for future candidates, never current results or CI guarantees. If measurements show no material win, close the plan as declined with evidence rather than implementing added complexity.

## Stop conditions and maintenance

Stop if isolation requires host dotfile changes, live package/Secret Service/network calls, a new runtime dependency, unbounded children, new guide topics, or mutation of user-selected output paths other than the requested result file.

Preserve existing helper locations/signatures for website extraction. If discovery structure, source paths or rendered public examples must change, coordinate the companion zsh-web parser/snapshot and run its verify/E2E/mobile checks; a passing shell suite is not website validation. Archive completed plans in Git history and keep enduring behavior in GUIDE.
