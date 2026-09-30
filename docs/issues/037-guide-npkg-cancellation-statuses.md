# ZSH-037: GUIDE documents only status 130 for npkg cancellation

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | GUIDE `npkg` reference; `npkg outdated` cancellation contract |
| Evidence | Source inspection comparing the GUIDE paragraph with the trap returns in the module |

## Summary

The GUIDE paragraph for `npkg` documents cancellation as returning `130` only. The module returns `143` on `TERM` and `129` on `HUP`, both for the interactive paths and for the outdated workers. A user or script that sends `TERM` or `HUP` has no documented status to rely on, while the equivalent `upkg` paragraph already documents the full set.

## Affected code and documentation

- [GUIDE.md](../../GUIDE.md): the `npkg` paragraph stating that `Ctrl+C` "returns `130`", and the separate `upkg` cancellation paragraph that documents `130` (INT), `143` (TERM), and `129` (HUP).
- [lib/functions-nix.zsh](../../lib/functions-nix.zsh): the trap handlers in the interactive and outdated paths that return `130`, `143`, and `129` respectively.

## Trigger and reproduction

1. Read the `npkg` paragraph in [GUIDE.md](../../GUIDE.md) and the cancellation paragraph for `upkg`.
2. Compare both with the trap returns in [lib/functions-nix.zsh](../../lib/functions-nix.zsh).

Observed at the baseline: the `npkg` paragraph names only `130`; the module returns `143` for `TERM` and `129` for `HUP`. Expected: the `npkg` reference states the same three-status contract as `upkg`, so a caller can distinguish an interrupt from a termination request.

Evidence limit: established by source and documentation inspection; no signal was delivered to a live `npkg` run during this audit.

## Current behavior and impact

Scripts and wrappers that supervise `npkg outdated` cannot interpret its exit status after `TERM` or `HUP`, and a reader of the GUIDE may assume the command only ever returns `130` for cancellation. The documentation is inconsistent with the module and with the sibling `upkg` text, which is the surface a reader is most likely to compare it against.

## Root cause

The `npkg` paragraph predates the addition of `TERM` and `HUP` handlers, and the documentation update covered the `upkg` contract without updating the corresponding `npkg` sentence.

## Fix goal and expected behavior

The `npkg` section documents the full cancellation contract: `130` for `INT`, `143` for `TERM`, and `129` for `HUP`, consistent with the `upkg` paragraph. No behavior change is required; if any path intentionally returns a different status, the implementation is the subject of a separate report rather than an exception here.

### Review comment — 2026-09-30

**Assessment:** Documentation completeness improvement; current Ctrl+C statement is true.

**Evidence:** The GUIDE explicitly states that Ctrl+C returns 130. The implementation also has TERM/HUP paths returning 143/129.

**Reviewed scope and expected behavior:** The GUIDE does not claim every cancellation returns 130; therefore the existing Ctrl+C sentence is accurate. Add TERM/HUP outcomes for the applicable wrapper-owned npkg paths as P3 reference completeness. Do not assert all native passthrough subcommands or picker outcomes share those statuses without testing them.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Documentation-only change; no module behavior may change.
- Keep the wording consistent with the `upkg` paragraph instead of restating the mechanism in different terms.
- Follow the documentation ownership rules in [AGENTS.md](../../AGENTS.md): the GUIDE carries the detailed contract; `README.md` and tips stay at their own level.

## Acceptance criteria

- [ ] The `npkg` section names `130`, `143`, and `129` with their signals.
- [ ] The wording matches the `upkg` cancellation paragraph.
- [ ] No other documented `npkg` behavior changes.
- [ ] The documentation suite passes under `zsh scripts/run-tests.zsh`.

## Validation plan

Update the paragraph and run the documentation checks in `zsh scripts/run-tests.zsh`. If the help or tips surfaces mention cancellation for `npkg`, confirm they remain accurate at their own level of detail.

## References

- Related: [ZSH-024](024-cancellation-does-not-signal-children.md), [ZSH-031](031-cancellation-inferred-from-child-status.md)
- [GUIDE.md](../../GUIDE.md) `npkg` and `upkg` cancellation paragraphs
