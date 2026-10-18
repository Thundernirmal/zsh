# Plan 004: Accelerate complete scan-record ingestion

## Status and drift check

TODO; priority P1; effort M; risk medium. Category: performance. Planned at `348906d0fa8e87f6d3198a63a0a832a4deeffbe1`, 2026-10-18. Depends on: 001. No implementation is included in this branch.

Run `git diff --stat 348906d0fa8e87f6d3198a63a0a832a4deeffbe1..HEAD -- lib/functions-files.zsh scripts/test-functions.zsh scripts/test-command-ux.zsh scripts/test-ui-pty.py` first. Re-read the current-state excerpts if any scoped source changed. On mismatch, stop and refresh this plan. Read AGENTS.md. Future executor: use a separate implementation branch in the current checkout unless instructed otherwise; never publish or open a PR without authorization. Match existing `perf:`/`docs:` commit conventions. Keep the operator's unrelated changes.

## Current state and purpose

`lib/functions-files.zsh:513` owns complete find/du collection and cleanup. The line 541 NUL reader retains valid rows, then `dusage`/`bigfiles` sort the entire record array at lines 628/805.

```zsh
while IFS=$'\t' read -r -d '' kib entry_path; do
  [[ $kib == <-> ]] || continue
  records+=("${kib}"$'\t'"${entry_path}")
done <"$raw_output_file"
```

IFS tab handling trims/combines delimiter whitespace, and a final unterminated record is ignored. A naive bulk split changes those bytes. `(On)` sorts the complete record naturally/numerically, including digits in pathnames. Rich-only totals cannot explain a plain-mode benchmark. No syscall trace or RSS reduction was established by this consolidation.

## Scope and compatibility

Only these paths may change during future implementation:

- `lib/functions-files.zsh`
- `scripts/test-functions.zsh`
- `scripts/test-command-ux.zsh`
- `scripts/test-ui-pty.py`
- `plans/README.md and measurement evidence`

Runtime behavior is a strict compatibility constraint: no feature additions/removals, changed options/result sets/order/bytes, freshness or signal/error changes. Preserve fixed trusted lazy source paths, module fallbacks, function-body `command -v`, pure theme startup, no prompt hooks, optional no-secret-access CGM startup, sequential mutations and query ownership protection. Query/supervisor code, aliases, command records, dependency checker and unrelated domains are out of scope. If a behavior change is needed, stop; it requires a separate brief and synchronized README/GUIDE/80-tips/website review. Internal parity-preserving changes do not justify artificial user-facing tips.

## Steps and verification gates

1. Freeze collector records, caller-visible REPLY/reply and public stdout/stderr/status using existing fake-find/du patterns in `scripts/test-command-ux.zsh`: empty data, malformed KiB, repeated/leading/trailing tabs, newlines, controls, Unicode, missing final NUL, numeric filenames/ties, hardlinks, sparse files, partial find/du failure and INT/TERM/HUP. Verify `zsh scripts/test-command-ux.zsh` and current collector oracle pass.
2. Prototype reading raw bytes in bulk or bounded chunks, without changing find/du input sets or error bookkeeping. Split complete NUL records and reproduce current field parsing/validation; keep a fallback if the optional builtin/module is unavailable. Do not adopt Earth's tab/unterminated-record semantic changes. Retain `(On)` and existing totals in this step. Verify exact raw-record arrays and all partial/error/signal fixtures match baseline.
3. Benchmark prebuilt 1k/10k/100k records with short/long paths, then end-to-end synthetic trees separately. Record peak RSS as well as latency for any bulk-allocation candidate. Proposed adoption gate: at least 2x reader speed at 100k, material end-to-end benefit, and an explicit acceptable memory bound; reject or use chunks if memory growth is excessive. Verify result arrays/hashes/counts and selected rows are identical before accepting timings.
4. Run full suite, inspect rich totals, full counts, viewport overflow and plain output. Keep resource cleanup and signal status 129/130/143 unchanged. No new dependency or public flag. Bounded top-K selection and arithmetic-expression joins are excluded: after ingestion is fixed, attribute selection/sum/RSS before opening a separate spike. Verify no complete record is lost even when requested display count is zero.

## Commands and done criteria

`zsh scripts/run-tests.zsh` must exit 0 after edits; it owns syntax, regression, real-fzf/UI/preview/timing PTY and fixed-install smoke ordering. `git diff --check` must exit 0. `git diff --name-only` must stay within the scope above (include new files when checking `git status --short`). Run the narrower commands specified at each step first, then the complete gate once candidate work is ready. Do not install dependencies or run native mutations to generate fixtures.

Exact current raw-record and public-output contracts pass; complete scans and find/du status remain intact; direct reader and end-to-end candidate evidence plus RSS are recorded; full runner passes. No change to hardlink/allocated-KiB semantics or sort comparator.

Update the status row in `plans/README.md` only after all gates pass; retain raw before/after evidence, versions, dimensions and output comparisons. Proposed performance gates are adoption criteria for future candidates, never current results or CI guarantees. If measurements show no material win, close the plan as declined with evidence rather than implementing added complexity.

## Stop conditions and maintenance

Stop if byte parity requires changing tab/unterminated-record behavior, statuses or ordering, if a helper needs a new runtime dependency, if memory is unbounded relative to an accepted fixture limit, or if a proposed top-K optimization drops complete-scan metadata.

Preserve existing helper locations/signatures for website extraction. If discovery structure, source paths or rendered public examples must change, coordinate the companion zsh-web parser/snapshot and run its verify/E2E/mobile checks; a passing shell suite is not website validation. Archive completed plans in Git history and keep enduring behavior in GUIDE.
