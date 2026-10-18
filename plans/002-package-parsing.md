# Plan 002: Remove pure package-parser captures

## Status and drift check

TODO; priority P1; effort M; risk medium. Category: performance. Planned at `348906d0fa8e87f6d3198a63a0a832a4deeffbe1`, 2026-10-18. Depends on: 001. No implementation is included in this branch.

Run `git diff --stat 348906d0fa8e87f6d3198a63a0a832a4deeffbe1..HEAD -- lib/functions-upkg.zsh lib/functions-upkg-backends.zsh scripts/test-upkg.zsh` first. Re-read the current-state excerpts if any scoped source changed. On mismatch, stop and refresh this plan. Read AGENTS.md. Future executor: use a separate implementation branch in the current checkout unless instructed otherwise; never publish or open a PR without authorization. Match existing `perf:`/`docs:` commit conventions. Keep the operator's unrelated changes.

## Current state and purpose

`lib/functions-upkg.zsh:883` normalizes CR, newlines, tabs and repeated/edge spaces in `_upkg_search_trim`. `lib/functions-upkg-backends.zsh:134` captures trim and append once each for a Pacman description; Paru/Nix have equivalent paths. Brew header and npm/Flatpak helpers contain more captures. At 1,000 synthetic Pacman results this costs seconds on this host; it excludes the native query.

```zsh
description=$(_upkg_search_trim "$line")
rows[-1]=$(_upkg_append_search_description "${rows[-1]}" "$description")
```

Follow existing `_ui_safe_text_reply` in `lib/functions-common.zsh:23`: `emulate -L zsh`, local scratch, return in `REPLY`, and retain the printing wrapper. These parser helpers are pure text operations; do not include terminal helpers in this step.

## Scope and compatibility

Only these paths may change during future implementation:

- `lib/functions-upkg.zsh`
- `lib/functions-upkg-backends.zsh`
- `scripts/test-upkg.zsh`
- `plans/README.md and measurement evidence`

Runtime behavior is a strict compatibility constraint: no feature additions/removals, changed options/result sets/order/bytes, freshness or signal/error changes. Preserve fixed trusted lazy source paths, module fallbacks, function-body `command -v`, pure theme startup, no prompt hooks, optional no-secret-access CGM startup, sequential mutations and query ownership protection. Query/supervisor code, aliases, command records, dependency checker and unrelated domains are out of scope. If a behavior change is needed, stop; it requires a separate brief and synchronized README/GUIDE/80-tips/website review. Internal parity-preserving changes do not justify artificial user-facing tips.

## Steps and verification gates

1. Extend existing fake-backend fixtures in `scripts/test-upkg.zsh` for CR, tabs, blank/multiple descriptions, repeated spaces, trailing newlines, Unicode, empty version, partial/failed/cancelled captures and Homebrew formula/cask info. Freeze stdout, stderr, return status, `_UPKG_SEARCH_ROWS`, last-state/detail and caller-visible `REPLY`/`reply` against HEAD (unset, set sentinel, and outer-local states). Verify `zsh scripts/test-upkg.zsh` passes before edits.
2. Add `_upkg_search_trim_reply` and equivalent reply-returning append/header helpers only where used. Keep printing wrappers for tests/extractor compatibility with explicit `local REPLY` (and array scratch if used), so they preserve the old nonmutating caller state. Isolate or save/restore the newly introduced REPLY writes at each converted pure-helper boundary. Do not blindly localize an entire existing backend: progress/theme helpers may already have observable scratch effects that baseline parity must retain. Use baseline sentinels in plain/rich/progress paths to decide the exact boundary. Direct callers save each result before another helper overwrites it. Verify unset/set/outer-local REPLY and reply sentinels plus return status; output equality alone is insufficient. Preserve command-substitution trailing-newline removal where applicable, empty initial tab separators, continuation spacing and local option boundaries. Verify `zsh -n lib/functions-upkg.zsh` and existing/new upkg fixtures pass.
3. Migrate only pure parser sites, backend by backend. Brew prefiltering is optional and requires frozen equivalence: name parsing runs for nonempty info lines but version parsing occurs only after matching headers. Do not assume two captures per arbitrary line. Do not include apt sed/error-output filtering here; that is a separate lower-priority behavior-sensitive change. Verify all backend frozen arrays, diagnostics and statuses match.
4. Measure 100/1,000/3,000 synthetic result parsers in alternating baseline/candidate runs. Count captured helper invocations separately from external executions. A proposed adoption criterion is at least 30% lower 1,000-row median with equivalent outputs; this is a decision gate, not a promised gain. Reject a candidate whose apparent gain is outside noisy sample support. Verify the full suite before marking DONE.

## Commands and done criteria

`zsh scripts/run-tests.zsh` must exit 0 after edits; it owns syntax, regression, real-fzf/UI/preview/timing PTY and fixed-install smoke ordering. `git diff --check` must exit 0. `git diff --name-only` must stay within the scope above (include new files when checking `git status --short`). Run the narrower commands specified at each step first, then the complete gate once candidate work is ready. Do not install dependencies or run native mutations to generate fixtures.

All parser fixtures and the full runner pass; outputs/state/status match the frozen oracle; converted parser loops never call printing wrappers (test-only sentinels); measured accepted speedup and raw samples are recorded. Header helpers remain in their current discovery files.

Update the status row in `plans/README.md` only after all gates pass; retain raw before/after evidence, versions, dimensions and output comparisons. Proposed performance gates are adoption criteria for future candidates, never current results or CI guarantees. If measurements show no material win, close the plan as declined with evidence rather than implementing added complexity.

## Stop conditions and maintenance

Stop on a parser/oracle mismatch, loss of multiline or error diagnostics, changed query execution/order/freshness, changed public options, or a helper move that requires unplanned website parser support.

Preserve existing helper locations/signatures for website extraction. If discovery structure, source paths or rendered public examples must change, coordinate the companion zsh-web parser/snapshot and run its verify/E2E/mobile checks; a passing shell suite is not website validation. Archive completed plans in Git history and keep enduring behavior in GUIDE.
