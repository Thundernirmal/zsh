# Plan 006: Remove rich-render captures while preserving terminal behavior

## Status and drift check

TODO; priority P1, gated; effort M; risk medium–high. Category: performance. Planned at `348906d0fa8e87f6d3198a63a0a832a4deeffbe1`, 2026-10-18. Depends on: 001, 002, 003. No implementation is included in this branch.

Run `git diff --stat 348906d0fa8e87f6d3198a63a0a832a4deeffbe1..HEAD -- 55-ui-helpers.zsh lib/functions-common.zsh lib/functions-upkg.zsh scripts/test-upkg.zsh scripts/test-functions.zsh scripts/test-ui-pty.py scripts/test-upkg-pty.py` first. Re-read the current-state excerpts if any scoped source changed. On mismatch, stop and refresh this plan. Read AGENTS.md. Future executor: use a separate implementation branch in the current checkout unless instructed otherwise; never publish or open a PR without authorization. Match existing `perf:`/`docs:` commit conventions. Keep the operator's unrelated changes.

## Current state and purpose

`lib/functions-upkg.zsh:1052` trims each rich description, and lines 1056/1060/1064/1069 capture manager/name/version/description truncation. The formatter has no row cap. The captures make helper stdout a pipe even when the outer table is a TTY. `_ui_ascii_mode` in `55-ui-helpers.zsh:80` consequently picks ASCII markers inside captures.

```zsh
_ui_pad left "$name_width" "$(_ui_truncate "$name_width" "$name")"
```

Direct `_ui_truncate_reply` is not interchangeable: normal UTF-8 TTY calls can choose `…`, changing kept text too. Icons have analogous captured fallback differences. An inherited render context could change captured helper behavior even before captures are removed. Color helpers can overwrite REPLY/reply; local scratch is required.

## Scope and compatibility

Only these paths may change during future implementation:

- `55-ui-helpers.zsh`
- `lib/functions-common.zsh presentation helpers only`
- `lib/functions-upkg.zsh formatter only`
- `scripts/test-upkg.zsh`
- `scripts/test-functions.zsh`
- `scripts/test-ui-pty.py`
- `scripts/test-upkg-pty.py`
- `plans/README.md and measurement evidence`

Runtime behavior is a strict compatibility constraint: no feature additions/removals, changed options/result sets/order/bytes, freshness or signal/error changes. Preserve fixed trusted lazy source paths, module fallbacks, function-body `command -v`, pure theme startup, no prompt hooks, optional no-secret-access CGM startup, sequential mutations and query ownership protection. Query/supervisor code, aliases, command records, dependency checker and unrelated domains are out of scope. If a behavior change is needed, stop; it requires a separate brief and synchronized README/GUIDE/80-tips/website review. Internal parity-preserving changes do not justify artificial user-facing tips.

## Steps and verification gates

1. Characterize current output before adding a context: real PTY and pipe, widths 59/60/80/100/120/130, all built-in themes and ansi/256/truecolor/none, glyph tiers, NO_COLOR, TERM=dumb and C locale. Freeze stdout/stderr/status and caller-visible REPLY/reply for present helper contracts. Include Unicode, visible controls and long cells. Verify PTY and existing upkg/function suites pass against the oracle.
2. Start with only package-search rendering. Use explicit legacy captured marker mode for converted cells; preserve the outer table's current padding/color behavior. Keep printing wrappers. Save each reply result before padding/color calls, localize scratch arrays/scalars and preserve option isolation. Do not pass a render context into nested captures unless its pipe behavior is represented explicitly. Verify transcripts match exactly, including ASCII ellipses under Unicode/Nerd tiers.
3. Profile after those conversions. Only if repeated capability/SGR work remains significant, prototype an invocation-local context scoped to the exact output destination. It must distinguish nested pipes/redirections, and observe terminal/theme changes between invocations. Prefer render-local SGR precomputation over global caches. Preserve `_zsh_theme_sgr` side effects (truecolor also populates reply); unsupported depth/layer behavior stays identical. Verify calls outside the context remain live and nested capture/redirection tests match.
4. Measure 100/1,000 rich rows on a real PTY with identical output hashes. Forced-rich sink measurements are useful but not a PTY substitute. Proposed adoption gate: at least 30% lower median post-query rendering, no lost rows or altered cells. Keep themes/roles and terminal-size checks authoritative. Verify `python3 scripts/test-upkg-pty.py`, `python3 scripts/test-ui-pty.py` and full runner before DONE.
5. Do not expand directly into every dashboard or CGM. Profile a consumer, characterize its captured icons/markers/REPLY and obtain a separate narrow plan before reuse. Do not impose a row cap, switch marker style, or claim wrapper removal alone solves all costs.

## Commands and done criteria

`zsh scripts/run-tests.zsh` must exit 0 after edits; it owns syntax, regression, real-fzf/UI/preview/timing PTY and fixed-install smoke ordering. `git diff --check` must exit 0. `git diff --name-only` must stay within the scope above (include new files when checking `git status --short`). Run the narrower commands specified at each step first, then the complete gate once candidate work is ready. Do not install dependencies or run native mutations to generate fixtures.

All baseline PTY/pipe transcripts and statuses match, full result sets remain visible, converted loops avoid printing-wrapper captures, no global terminal cache exists, candidate real-PTY evidence passes the selected gate, and full suite passes.

Update the status row in `plans/README.md` only after all gates pass; retain raw before/after evidence, versions, dimensions and output comparisons. Proposed performance gates are adoption criteria for future candidates, never current results or CI guarantees. If measurements show no material win, close the plan as declined with evidence rather than implementing added complexity.

## Stop conditions and maintenance

Stop on any icon/ellipsis/prefix/suffix/color/output-state change, context leakage into nested captures/redirections, unbounded/global caches, new public flags/row limits, or inability to prove matching terminal behavior.

Preserve existing helper locations/signatures for website extraction. If discovery structure, source paths or rendered public examples must change, coordinate the companion zsh-web parser/snapshot and run its verify/E2E/mobile checks; a passing shell suite is not website validation. Archive completed plans in Git history and keep enduring behavior in GUIDE.
