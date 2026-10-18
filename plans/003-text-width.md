# Plan 003: Optimize text width and ASCII truncation without changing cells

## Status and drift check

TODO; priority P1; effort M; risk medium. Category: performance. Planned at `348906d0fa8e87f6d3198a63a0a832a4deeffbe1`, 2026-10-18. Depends on: 001. No implementation is included in this branch.

Run `git diff --stat 348906d0fa8e87f6d3198a63a0a832a4deeffbe1..HEAD -- 55-ui-helpers.zsh lib/functions-common.zsh scripts/test-functions.zsh scripts/test-ui-pty.py` first. Re-read the current-state excerpts if any scoped source changed. On mismatch, stop and refresh this plan. Read AGENTS.md. Future executor: use a separate implementation branch in the current checkout unless instructed otherwise; never publish or open a PR without authorization. Match existing `perf:`/`docs:` commit conventions. Keep the operator's unrelated changes.

## Current state and purpose

`55-ui-helpers.zsh:259` measures sanitized text. The printable-ASCII path uses string length; one non-ASCII character routes the whole string through indexed character traversal and `_ui_char_width`, whose non-ASCII cases binary-search committed intervals. `_ui_truncate_reply` at line 296 and `_ui_pad_reply` at 380 repeat width/truncation work. `_ui_safe_truncate` in `lib/functions-common.zsh:68` separately tokenizes visible control escapes.

```zsh
if [[ $text != ${~non_ascii_pattern} ]]; then
  REPLY=${#text}
  return 0
fi
```

The two truncators have different narrow-width behavior. In plain mode, width 1 on `abcdef` returns `a` from `_ui_truncate`, but `.` from `_ui_safe_truncate`; width 4 gives `abcd` versus `...f`. Preserve both. Capture also forces ASCII marker selection, whereas a direct TTY call may use `…`.

## Scope and compatibility

Only these paths may change during future implementation:

- `55-ui-helpers.zsh`
- `lib/functions-common.zsh presentation helpers only`
- `scripts/test-functions.zsh`
- `scripts/test-ui-pty.py`
- `plans/README.md and measurement evidence`

Runtime behavior is a strict compatibility constraint: no feature additions/removals, changed options/result sets/order/bytes, freshness or signal/error changes. Preserve fixed trusted lazy source paths, module fallbacks, function-body `command -v`, pure theme startup, no prompt hooks, optional no-secret-access CGM startup, sequential mutations and query ownership protection. Query/supervisor code, aliases, command records, dependency checker and unrelated domains are out of scope. If a behavior change is needed, stop; it requires a separate brief and synchronized README/GUIDE/80-tips/website review. Internal parity-preserving changes do not justify artificial user-facing tips.

## Steps and verification gates

1. Freeze both truncators, width and padding as test-only oracles, following the frozen-reference structure in `scripts/test-ui-pty.py`. Exercise ASCII lengths 0–80 and widths 0–40; escaped backslash/control tokens; combining, leading marks, CJK, emoji and private-use glyphs; UTF-8/C locales and both marker modes. Capture caller-visible REPLY/reply and status too, including unset/set/outer-local values and fallback configurations without display-width/leading-mark helpers. Verify `zsh scripts/test-functions.zsh` and `python3 scripts/test-ui-pty.py` match baseline before edits.
2. Add a printable-ASCII slicing fast path to `_ui_truncate_reply` after resolving its legacy marker and narrow-width branch. For `_ui_safe_truncate`, only take the fast path when no backslash can be a visible escape token, and preserve its different marker-prefix branch. Keep full Unicode/token fallback. Safe printing truncation currently mutates REPLY: with plain ASCII width 1 it can leave marker width 3; width 4 can leave suffix f. The fast path must reproduce characterized legacy scratch effects as well as output; adding a blanket local REPLY would itself change that contract. Verify exhaustive ASCII matrix, frozen escape fixtures and scratch/status sentinels match exactly. Do not substitute one truncator for the other.
3. Separately compare ASCII-run traversal and one-time character splitting for mixed text. Preserve the current per-code-point cell model; this is not a grapheme redesign. An optional width cache must have a small explicit entry cap, deterministic eviction/reset and cold-miss parity; the full Unicode range is not an acceptable practical memory bound. Keep `lib/ui-width-data.zsh` unchanged and lazily loaded. Verify ASCII calls still leave the width tables unloaded and every result matches the oracle.
4. Measure realistic 16–80-character labels plus 1,000-character ASCII/mixed/CJK inputs, width-only and consumers separately; record RSS if materializing arrays. Proposed acceptance: at least 2x mixed-input improvement, with short ASCII no more than 10% slower. Time short ASCII as batches of at least 1,000 calls per sample, because single calls (~0.05 ms baseline) are at timer-noise level and a per-call absolute allowance would permit doubling the hottest path. Report CJK independently and discard losing prototypes. Verify full runner, fbr canonical row/selection and PTY output bytes before DONE.

## Commands and done criteria

`zsh scripts/run-tests.zsh` must exit 0 after edits; it owns syntax, regression, real-fzf/UI/preview/timing PTY and fixed-install smoke ordering. `git diff --check` must exit 0. `git diff --name-only` must stay within the scope above (include new files when checking `git status --short`). Run the narrower commands specified at each step first, then the complete gate once candidate work is ready. Do not install dependencies or run native mutations to generate fixtures.

Cell widths and rendered bytes match the frozen oracles for both distinct truncators; no new subprocess or eager table load; cache cap if used is tested above its capacity; same-host candidate evidence satisfies the selected gate and full suite passes.

Update the status row in `plans/README.md` only after all gates pass; retain raw before/after evidence, versions, dimensions and output comparisons. Proposed performance gates are adoption criteria for future candidates, never current results or CI guarantees. If measurements show no material win, close the plan as declined with evidence rather than implementing added complexity.

## Stop conditions and maintenance

Stop on changed combining-mark behavior, split escape tokens, any marker/icon change, non-ASCII truncation mismatch, unbounded memoization, new Unicode data/runtime dependencies, or a short-ASCII regression beyond the declared allowance.

Preserve existing helper locations/signatures for website extraction. If discovery structure, source paths or rendered public examples must change, coordinate the companion zsh-web parser/snapshot and run its verify/E2E/mobile checks; a passing shell suite is not website validation. Archive completed plans in Git history and keep enduring behavior in GUIDE.
