# ZSH-028: The fbr formatter accepts an optional identity that falls back to the display label

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `fbr`; `_fbr_format_entry` and its callers |
| Evidence | Established by source inspection of the formatter and its call sites |

## Summary

`_fbr_format_entry` takes the canonical reference identity as an optional ninth argument and silently substitutes the display label when it is absent. The ambiguity this series fixed — a shortened display branch name being reused as the selection identity — can therefore be reintroduced by any caller that omits the argument, with no error and no failing test.

## Affected code and documentation

- [functions/_fbr_format_entry](../../functions/_fbr_format_entry): the `local identity=${9:-$1}` fallback and the trailing `$'\t'"$identity"` field of the produced row.
- [lib/functions-git.zsh](../../lib/functions-git.zsh): `_fbr_ref_rows`, which passes the canonical ref as the ninth argument, and `_fbr_activate`, which consumes the identity.
- [scripts/test-functions.zsh](../../scripts/test-functions.zsh): the formatter cases, five of which call the function with eight arguments and therefore exercise the fallback path.
- [GUIDE.md](../../GUIDE.md): branch selection and the display-versus-canonical distinction.

## Trigger and reproduction

Source inspection, with the call sites compared:

1. Read `functions/_fbr_format_entry` and note the ninth argument and its default.
2. Compare the production call in `_fbr_ref_rows`, which supplies the canonical ref, with the five calls in `scripts/test-functions.zsh`, which do not.

Observed at the baseline: an eight-argument call yields a row whose identity field is the display label, and every such call passes. Expected: the canonical identity is required by the formatter, or its absence is an explicit, tested decision.

## Current behavior and impact

The formatter's contract is weaker than the invariant the branch-selection fix depends on, and nothing enforces it. A future row producer — a tags view, a second picker variant, or code adapted from the pre-fix version — can omit the ninth argument, pass syntax checks and review, and re-emit the shortened display name as the selection identity. That is exactly the branch, tag, and remote-namespace collision the earlier fix addressed, and the existing eight-argument test calls would keep passing, so the regression would surface only as a user-visible mis-selection.

## Root cause

The canonical identity was added as an optional parameter to avoid changing the existing call sites and their tests. The default was chosen for convenience — the display label is the correct identity for a plain local branch — but it is also the value that produces the collision for every other ref shape, so the fallback cannot distinguish a safe omission from an unsafe one.

## Fix goal and expected behavior

The formatter must require the canonical identity, or must fail loudly when it is absent for a ref shape whose display label is not itself canonical. Existing tests must be updated to pass the identity explicitly rather than relying on the fallback. A caller that omits a required argument must fail at development time, not silently select the wrong reference.

### Review comment — 2026-09-30

**Assessment:** Private-helper hardening; no current wrong-branch defect established.

**Evidence:** `_fbr_format_entry` has a display-label fallback for an omitted ninth identity argument. However, the production row producer supplies the canonical ref, and activation rejects shortened identities. Existing end-to-end regressions exercise canonical refs.

**Reviewed scope and expected behavior:** The claimed current user-facing identity failure is not established. Requiring the argument is reasonable P3 hardening against future caller mistakes, not a repair for demonstrated wrong checkout. A plain local display label is also not a valid activation identity under the canonical-ref contract. Keep production canonical identity regressions and fail closed for missing identity.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Preserve the produced row layout: display field, relative field, subject, worktree path, and canonical identity.
- Preserve the display-label shortening used for remote refs; only the identity field must stay canonical.
- Keep the formatter lazy-loaded and repo-local, and keep its calling convention compatible with the picker that consumes it.
- Do not change `_fbr_activate`'s canonical-ref handling, which is correct at this baseline.
- Update GUIDE only if the user-visible selection behavior changes.

## Acceptance criteria

- [ ] The formatter cannot silently emit a display label as a canonical identity.
- [ ] Existing formatter tests pass the identity explicitly.
- [ ] Local, remote-tracking, worktree, and tag-shaped inputs resolve to distinct, correct identities.
- [ ] The produced row layout and padding behavior are unchanged.
- [ ] An omitted identity produces a visible failure or an explicit, documented default that is safe for every ref shape.

## Validation plan

Update the formatter cases in `scripts/test-functions.zsh` to pass the canonical identity, and add a case asserting that the identity field carries the canonical ref rather than the display label for a remote-tracking input. Run `zsh scripts/run-tests.zsh`.

## References

- [GUIDE.md](../../GUIDE.md) branch selection
- [AGENTS.md](../../AGENTS.md) repository-local lazy helper requirements
- Related: ZSH-011 (ambiguous ref identity, repaired at this baseline) — the defect this fallback can reintroduce
