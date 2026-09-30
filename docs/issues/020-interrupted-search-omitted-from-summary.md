# ZSH-020: An interrupted search is omitted from the search summary

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `upkg search` with any manager; `_upkg_print_search_summary` |
| Evidence | Established by source inspection of the summary accounting and the cancelled-state producers |

## Summary

`_upkg_print_search_summary` counts managers in only three states: `matches found`, `no matches`, and `failed`. The `cancelled` state introduced by this series is counted in none of them, so an interrupted search is dropped from both the manager count and the failed count and is reported as an ordinary empty result.

## Affected code and documentation

- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): `_upkg_print_search_summary` — the state `case` and the `failed_managers` suffix, plus `_upkg_check_interrupt` and `_upkg_set_last_result`, which produce `cancelled`.
- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): `_upkg_format_search_rows`, which decides between `Search results unavailable; failed manager(s): …` and `No matches found across selected managers.`
- [GUIDE.md](../../GUIDE.md): the status-state table, which documents `cancelled` as its own state and describes how interrupted runs are reported.

## Trigger and reproduction

In a fresh `zsh -f` shell at the repository root, using a stub backend rather than a real manager:

1. `source init.zsh`, then load the package domain.
2. Stub `brew` (or any selected backend) to return 130 with no output.
3. Run `upkg search sample --only brew,flatpak` and inspect the summary lines and the exit status.

Observed at the baseline: `No matches found across selected managers.` and `Search summary: 0 result(s) across 0 manager(s).` with a nonzero status, and the interrupted manager named nowhere. Expected: the interrupted manager is identified, alongside the existing cancelled status.

## Current behavior and impact

A user who interrupts a search sees a summary that looks like a completed empty search. The manager that was interrupted is not named, so the report is misleading about what actually ran, and the manager count understates the selected set. The same accounting feeds the plain and rich summary paths, so both forms are affected. Outdated, upgrade, and clean already surface cancellation, making search the inconsistent surface.

## Root cause

The summary was written before the cancelled state existed and enumerates states explicitly rather than deriving the selected set from the run. Cancellation short-circuits before the result of the interrupted manager can fall into any counted state, leaving a gap between `_UPKG_SUMMARY_ORDER` and the counted total.

## Fix goal and expected behavior

Every selected manager must be accounted for exactly once in the summary, in one of the documented states. An interrupted manager must be identified as cancelled, must not be counted as failed or as an empty result, and must not be reported as a completed search. The existing exit status must be preserved.

### Review comment — 2026-09-30

**Assessment:** Confirmed cancellation-summary defect; count attempted work accurately.

**Evidence:** A cancelled backend with status 130 produced “No matches found across selected managers” and a summary of zero managers. The summary ignores the cancelled state.

**Reviewed scope and expected behavior:** The corrected summary must distinguish cancellation from a successful empty query and retain any completed results. Do not count every selected manager as queried: cancellation deliberately prevents later managers from starting. Report completed/attempted/cancelled work accurately and keep the cancellation exit status.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep the documented state set: no new state names without a GUIDE update.
- Preserve the existing wording for genuinely failed managers and for a completed empty search.
- Keep the plain-output path and the rich path consistent; both consume the same accounting.
- Do not change cancellation propagation or the status codes 129, 130, and 143.

## Acceptance criteria

- [ ] An interrupted search names the interrupted manager in the summary.
- [ ] The interrupted manager is not counted as failed and not counted as an empty result.
- [ ] The manager count reflects every selected manager.
- [ ] A completed empty search keeps its current wording.
- [ ] Plain and rich output agree on the accounting.
- [ ] The exit status matches the documented cancelled status.

## Validation plan

Add a case to `scripts/test-package-audit.zsh` that stubs one backend to return 130 among several selected managers, then assert the summary text, the manager count, and the exit status in both plain and rich modes. Run `zsh scripts/run-tests.zsh`.

## References

- [GUIDE.md](../../GUIDE.md) status-state table and search summary
- Related: [ZSH-021](021-cancelled-counted-as-failed-in-rich-ui.md)
