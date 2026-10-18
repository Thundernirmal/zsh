# Plan 005: Improve offline Nix completion preparation

## Status and drift check

TODO; priority P1; effort M; risk medium. Category: performance. Planned at `348906d0fa8e87f6d3198a63a0a832a4deeffbe1`, 2026-10-18. Depends on: 001. No implementation is included in this branch.

Run `git diff --stat 348906d0fa8e87f6d3198a63a0a832a4deeffbe1..HEAD -- 66-compdefs.zsh 60-functions.zsh lib/functions-nix.zsh scripts/test-completions.zsh scripts/test-domains.zsh` first. Re-read the current-state excerpts if any scoped source changed. On mismatch, stop and refresh this plan. Read AGENTS.md. Future executor: use a separate implementation branch in the current checkout unless instructed otherwise; never publish or open a PR without authorization. Match existing `perf:`/`docs:` commit conventions. Keep the operator's unrelated changes.

## Current state and purpose

`66-compdefs.zsh:140` already has identity-keyed per-file parsed data and a signature-keyed ordered union. Every request still checks eligible files and invokes `cache_dir=$(_npkg_cache_dir)` at line 152; the lazy Nix domain can be loaded only in that discarded child. Lines 181–184 read unchanged-file misses one line at a time, and lines 168/192 copy the union to `reply`; line 204 offers `reply` to compadd.

```zsh
while IFS= read -r attribute; do
  [[ -n $attribute ]] || continue
  file_attributes+=("$attribute")
done < "$cache_file"
```

Completion never calls `nix eval` or refreshes an index. The current loop keeps CR bytes, drops empty lines and ignores the unterminated final line. Do not confuse this cold parse with C04's already-optimized warm reuse.

## Scope and compatibility

Only these paths may change during future implementation:

- `66-compdefs.zsh`
- `60-functions.zsh fixed Nix lazy-registration entry if required`
- `lib/functions-nix.zsh cache-path helper only`
- `scripts/test-completions.zsh`
- `scripts/test-domains.zsh`
- `plans/README.md and measurement evidence`

Runtime behavior is a strict compatibility constraint: no feature additions/removals, changed options/result sets/order/bytes, freshness or signal/error changes. Preserve fixed trusted lazy source paths, module fallbacks, function-body `command -v`, pure theme startup, no prompt hooks, optional no-secret-access CGM startup, sequential mutations and query ownership protection. Query/supervisor code, aliases, command records, dependency checker and unrelated domains are out of scope. If a behavior change is needed, stop; it requires a separate brief and synchronized README/GUIDE/80-tips/website review. Internal parity-preserving changes do not justify artificial user-facing tips.

## Steps and verification gates

1. Extend completion fixtures for empty files, CRLF, duplicates across files, unterminated tail, symlink/unreadable files, deletion, replacement, changed identity and unavailable stat support. Assert exact order, parse/build counters, return status and legacy caller-visible REPLY/reply for empty, changed, warm and unreadable caches. A new cache-path reply helper must not leak new scratch changes into cases where the original preserved a sentinel. Stub native nix to fail if executed. Verify `zsh scripts/test-completions.zsh` passes before edits.
2. Eliminate repeated discarded domain loads using a reply-returning cache-path helper at a fixed trusted source location or a parent-shell domain load at first completion. Compare parse/memory costs before selecting; never source eagerly during startup. Preserve single authoritative absolute HOME/XDG policy, fresh path evaluation and local option boundaries. Verify domain/caching fixtures and `zsh scripts/test-domains.zsh` pass with no native nix calls.
3. On a cache miss, prototype optional `zsh/mapfile` or another builtin bulk read with the existing loop as fallback. Preserve final-record exclusion, blank-line and CR handling, eligibility checks, identity signatures, invalidation and first-occurrence order. Verify exact candidates plus parse/build counters match the baseline for every fixture.
4. Avoid copying the entire union to `reply` only inside the completion adapter if measurement warrants it. Retain `_zsh_npkg_cached_attributes`'s output contract and stale-data failure behavior; `_wanted`/compadd must see the same candidates. Verify fake compadd captures identical arguments/candidates for empty, warm, changed and invalid caches.
5. Measure 60k names separately for first parse, warm helper, adapter and real compinit/Tab path. Proposed gate: at least 2x faster cold preparation with no material warm regression; distinguish helper gains from actual Tab latency. Verify full runner and fresh PATH/XDG changes before DONE.

## Commands and done criteria

`zsh scripts/run-tests.zsh` must exit 0 after edits; it owns syntax, regression, real-fzf/UI/preview/timing PTY and fixed-install smoke ordering. `git diff --check` must exit 0. `git diff --name-only` must stay within the scope above (include new files when checking `git status --short`). Run the narrower commands specified at each step first, then the complete gate once candidate work is ready. Do not install dependencies or run native mutations to generate fixtures.

No native query occurs in any completion fixture; all candidate bytes/order and counters match; domain loading stays lazy in the parent if selected; old caller contracts and module fallbacks survive; cold/warm evidence and full-suite result are recorded.

Update the status row in `plans/README.md` only after all gates pass; retain raw before/after evidence, versions, dimensions and output comparisons. Proposed performance gates are adoption criteria for future candidates, never current results or CI guarantees. If measurements show no material win, close the plan as declined with evidence rather than implementing added complexity.

## Stop conditions and maintenance

Stop on new network/native Nix work, changed eligibility/identity checks, lost unterminated-tail/CR behavior, new startup parsing, hidden candidate pruning, or changes needed outside the scoped cache-path implementation.

Preserve existing helper locations/signatures for website extraction. If discovery structure, source paths or rendered public examples must change, coordinate the companion zsh-web parser/snapshot and run its verify/E2E/mobile checks; a passing shell suite is not website validation. Archive completed plans in Git history and keep enduring behavior in GUIDE.
