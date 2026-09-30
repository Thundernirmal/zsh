# ZSH-021: The rich summary counts cancelled managers as failed and loses the cleanup layout

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | Rich rendering of `upkg search`, `upkg upgrade`, `upkg clean`, and `upkg outdated` |
| Evidence | Established by source inspection of the status metadata and the aggregate counters |

## Summary

The status metadata maps `cancelled` to the `failed` bucket in the rich UI. The aggregate count therefore reports interrupted managers as failures, while the per-manager badge and the plain output both say `cancelled`. An interrupted cleanup run also loses its cleanup layout, because the family detection never matches the cancelled state.

## Affected code and documentation

- [55-ui-helpers.zsh](../../55-ui-helpers.zsh): the status metadata `case` entry mapping `cancelled` to the `failed` bucket, and the aggregate counters that consume buckets.
- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): the summary counters and the family detection used to choose the cleanup layout.
- [GUIDE.md](../../GUIDE.md): the status-state table, which documents `cancelled` separately from `failed`, and the cleanup presentation notes.

## Trigger and reproduction

In a fresh `zsh -f` shell at the repository root with a rich terminal and colour enabled:

1. `source init.zsh`, then load the package domain.
2. Stub one backend to return 130.
3. Run `upkg upgrade --only brew,npm` and compare the aggregate counters with the row badge and with the plain output.

Observed at the baseline: the aggregate renders `[0 ok] [0 updates] [1 failed]` while the row badge reads `cancelled` and plain output reads `brew: cancelled - interrupted (status 130)`. Interrupting a cleanup run on its first phase additionally falls back to the package badges instead of the cleanup layout.

## Current behavior and impact

The same run is described two ways in one screen, and the aggregate contradicts the documented state table. A user reading only the counters concludes that a manager failed rather than that they interrupted it, which changes what remediation looks like. The cleanup-layout regression makes an interrupted cleanup visually indistinguishable from an interrupted upgrade.

## Root cause

The cancelled state was added to the state table and the plain renderer, but the rich UI's bucket assignment was not extended, so cancellation inherits the failure presentation for counting purposes. The family detection keys on states that a cancelled run never reaches.

## Fix goal and expected behavior

`cancelled` must be presented and counted distinctly from `failed` in the rich UI, matching the documented state table and the plain output. An interrupted cleanup must retain the cleanup layout. Aggregate counters must agree with the per-row badges for the same run.

### Review comment — 2026-09-30

**Assessment:** Confirmed rich-summary defect; narrow affected paths.

**Evidence:** `_ui_status_metadata cancelled` returns the failed aggregate category. Consequently rich operation summaries count cancellation as failure. Cleanup layout can also be lost when no completed state identifies the cleanup family.

**Reviewed scope and expected behavior:** `upkg search` uses its own `_upkg_print_search_summary`, rather than this aggregate metadata path; its counting defect belongs to ZSH-020. A prior cleaned, planned, or partial cleanup state can preserve the cleanup layout, so layout loss is conditional. Preserve an explicit cancelled category and the operation family independently of result state.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep the existing bucket vocabulary unless a new bucket is added deliberately and documented.
- Preserve the current presentation of genuine failures and of skipped and blocked managers.
- Keep the glyph and palette roles sourced from the theme module rather than introducing raw colours.
- Keep the plain-output path unchanged: it already reports correctly.
- Update GUIDE.md if the rendered vocabulary changes.

## Acceptance criteria

- [ ] An interrupted manager renders as cancelled, not failed, in the badge and in the aggregate.
- [ ] Aggregate counters sum to the number of selected managers.
- [ ] An interrupted cleanup renders the cleanup layout.
- [ ] Genuine failures still render as failed.
- [ ] Rich and plain output describe the same run consistently.

## Validation plan

Add rendering assertions covering a cancelled manager in `upkg upgrade` and in `upkg clean`, in both rich and plain modes, checking the badge, the aggregate counters, and the layout family. Run `zsh scripts/run-tests.zsh`.

## References

- [GUIDE.md](../../GUIDE.md) status-state table
- Related: [ZSH-020](020-interrupted-search-omitted-from-summary.md)
