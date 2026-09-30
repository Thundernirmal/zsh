# ZSH-032: Interrupting a cleanup step discards the accounting of completed phases

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `upkg clean` across all managers; `_upkg_run_cleanup_step`, `_upkg_finish_cleanup_result` |
| Evidence | Source inspection of every cleanup backend and the two helpers |

## Summary

Each cleanup backend runs its phases through `_upkg_run_cleanup_step … || return $?`. When a step is cancelled, the helper returns the signal status, the backend returns immediately, and `_upkg_finish_cleanup_result` is never reached. The counters and failure details that earlier phases already recorded are therefore discarded: the manager's row keeps only the `cancelled` state, and no partial summary reports what completed or what had already failed.

## Affected code and documentation

- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): `_upkg_run_cleanup_step`, which forwards the child status into `_upkg_record_cleanup_result`; `_upkg_record_cleanup_result`, which increments the caller's `succeeded`/`failed` counters, appends the failure detail, returns the signal status for cancellation but `0` for an ordinary failure; and `_upkg_finish_cleanup_result`, which is the only place that sets `cleaned`, `planned`, `partial`, or `failed` from those counters.
- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): every cleanup backend — `_upkg_run_clean_apt`, `_upkg_run_clean_dnf`, `_upkg_run_clean_pacman`, `_upkg_run_clean_paru`, `_upkg_run_clean_brew`, `_upkg_run_clean_flatpak`, `_upkg_run_clean_nix`, and `_upkg_run_clean_npm` — where each `|| return $?` precedes the final `_upkg_finish_cleanup_result`.
- [GUIDE.md](../../GUIDE.md): the cleanup section describing conservative phases and the partial-result contract.

## Trigger and reproduction

Prerequisites: PATH stubs for one manager; no real removal.

1. In a fresh `zsh -f` shell at the repository root, source `init.zsh` and load the package domain.
2. Stub the manager so that its first cleanup phase succeeds and its second exits `130`.
3. Run `upkg clean --only <manager>` and inspect the row state, any summary, and the exit status.

Observed at the baseline by inspection: the row reads only `cancelled - interrupted (status 130)`, with no mention of the phase that completed, and no partial summary is printed. Expected: the row and any summary report the phases that already ran — at minimum that one phase completed and which phase was interrupted — while the cancellation status is preserved.

Evidence limit: established by source inspection of the call sites; no end-to-end run was performed, and the reproduction above is a proposed fixture.

## Current behavior and impact

A user who interrupts a long cleanup loses the record of the work already done. On a manager where an early phase removed packages and a later phase was interrupted, the report claims nothing was achieved and hides any failure that occurred before the interrupt, so the user cannot tell whether to re-run the command or whether a phase needs attention. The same accounting feeds the plain and rich summaries, so both forms are affected, and the loss is specific to cancellation: ordinary phase failures are counted and reported normally.

## Root cause

Cleanup phases were written as `step || return`, which is correct for the ordinary-failure case because `_upkg_record_cleanup_result` deliberately returns `0` there. Cancellation is the one path where the helper returns nonzero, and it does so before the backend has finalized its result, so the early return bypasses the only code that turns counters into a row state.

## Fix goal and expected behavior

A cancelled cleanup finalizes the manager's row from the counters recorded so far. Completed phases stay counted, failure details collected before the interrupt survive, and the interrupted phase is identified as cancelled rather than as failed. The documented cancellation status is preserved, and the run must not claim a successful cleanup. If some phases never ran, the report must not imply they did.

### Review comment — 2026-09-30

**Assessment:** Confirmed summary-detail gap; prior output is retained.

**Evidence:** A mocked cleanup completed its first phase and cancelled its second with status 130. The final row contained only generic cancellation detail, omitting accumulated counters. Earlier phase headings and native stdout remained visible.

**Reviewed scope and expected behavior:** The report overstates impact when it says completed execution output is discarded or the command claims nothing completed. Finalize completed/failed phase accounting on cancellation while retaining state cancelled and the original cancellation status. This is a reporting improvement; cancellation must not be turned into success merely because some phases completed.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Preserve the documented state set and the distinction between `cancelled`, `partial`, and `failed`; coordinate with [ZSH-021](021-cancelled-counted-as-failed-in-rich-ui.md), which fixes how the rich UI buckets the cancelled state.
- Do not weaken the ordinary-failure path: a failing phase must still be counted and reported as today.
- Keep plain and rich output consistent; both consume the same accounting.
- Do not change cancellation propagation or the statuses 129, 130, and 143, which [ZSH-031](031-cancellation-inferred-from-child-status.md) addresses separately.
- Keep dry-run behavior unchanged, and keep the rule that previews never invoke `sudo`.

## Acceptance criteria

- [ ] Interrupting a later phase reports the phases that completed before it.
- [ ] Failure details recorded before the interrupt remain visible.
- [ ] The interrupted phase is identified as cancelled and is not counted as failed.
- [ ] The exit status matches the documented cancellation status.
- [ ] An undisturbed cleanup reports exactly as it does today.
- [ ] Plain and rich output agree on the accounting.

## Validation plan

Add a fixture to `scripts/test-package-audit.zsh` that stubs a manager whose first cleanup phase succeeds and whose second returns `130`, then asserts the row state, the completed-phase count, and the exit status in both plain and rich modes. Add a companion case asserting an ordinary mid-run failure still reports as it does today. Run `zsh scripts/run-tests.zsh`.

## References

- Related: [ZSH-020](020-interrupted-search-omitted-from-summary.md), [ZSH-021](021-cancelled-counted-as-failed-in-rich-ui.md), [ZSH-031](031-cancellation-inferred-from-child-status.md)
- [GUIDE.md](../../GUIDE.md) cleanup section and status-state table
