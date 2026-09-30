# ZSH-031: Cancellation is inferred from child exit statuses at every call site

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `upkg` search, outdated, upgrade, and clean across all managers; `_upkg_check_interrupt` |
| Evidence | Source inspection of the status-sniffing helper and all call sites; the claim that DNF5 maps SIGINT to status 1 was not independently verified |

## Summary

`_upkg_check_interrupt` decides that a child was cancelled purely from its exit status: `129`, `130`, or `143`. The helper is called at every leaf operation — 38 call sites, 35 of them in the backends — and no trap-owned flag records that the shell itself observed a signal. The result is wrong in both directions. A manager that converts `SIGINT` into its own status (reported for DNF5, which exits `1` after an interrupted operation) is recorded as `failed`, and the run continues through the remaining managers and cleanup phases, contradicting the documented cancellation contract. Conversely, any child that legitimately exits `129`, `130`, or `143` for unrelated reasons aborts the whole run as `cancelled`.

## Affected code and documentation

- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): `_upkg_check_interrupt`, which sets `_UPKG_INTERRUPTED_STATUS` and records the `cancelled` state from the status alone, plus `_upkg_record_cleanup_result`, which consults it before counting a step.
- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): the 35 backend call sites, including the per-backend `trap '… return 130' INT` / `143` / `129` handlers that translate signals into statuses for the same helper.
- [lib/functions-nix.zsh](../../lib/functions-nix.zsh): `_npkg_outdated`, which already uses the trap-flag pattern this report asks for and demonstrates that the pattern is available in the codebase.
- [GUIDE.md](../../GUIDE.md): the cancellation paragraph documenting that cancellation stops the remaining managers and cleanup phases and preserves statuses 130, 143, and 129.

## Trigger and reproduction

Prerequisites: a PATH stub for one manager; no real package operations.

1. In a fresh `zsh -f` shell at the repository root, source `init.zsh` and load the package domain.
2. Stub a selected backend so that it exits `1` while the shell has observed a signal, or exits `130` without any signal — the two directions can be stubbed separately.
3. Run `upkg outdated --only <manager>,<other>` and inspect which managers ran, the recorded states, and the exit status.

Observed at the baseline by inspection: with a status-1 child the run continues and records `failed`; with a status-130 child the run stops and records `cancelled`. Expected: the decision follows whether a signal was actually delivered to the run, not the numeric status of an unrelated child.

Evidence limit: the DNF5 `SIGINT`-to-`1` mapping is reported from the original audit and was not reproduced here; the architecture defect itself is visible in the source without it.

## Current behavior and impact

Cancellation behaves inconsistently across managers and call paths. On a manager that remaps the interrupt status, a user pressing `Ctrl+C` sees the run continue into further managers and cleanup steps — the opposite of the documented guarantee — and the interrupted backend is reported as a failure rather than as cancelled. In the other direction, a child that exits `130` for its own reasons (a manager reporting a fatal error with that status, or a stub in a test) cancels an otherwise healthy run and skips remaining work. Scripts that parse the exit status cannot distinguish an interrupt from an ordinary failure.

## Root cause

The implementation treats an exit status as a proxy for a signal because the signal is delivered to the whole foreground process group, so the shell's own trap usually does fire. That assumption fails whenever the signal reaches the manager but not the wrapper (a supervisor, `timeout`, or `kill -INT <pid>`), or when a manager catches the signal and exits with its own code. Statuses are also not reserved: any child may exit with 129, 130, or 143 without being cancelled.

## Fix goal and expected behavior

One trap in the `upkg` entry point owns cancellation state for the run: `INT`, `TERM`, and `HUP` set a flag (and record the corresponding status), and leaf operations consult that flag rather than their child's exit status. A child's `129`, `130`, or `143` alone must not cancel the run. Cancellation must still stop the remaining managers and cleanup phases, preserve the documented exit statuses, and produce the existing `cancelled` state. The per-call-site checks should collapse into the flag lookup so the architecture cannot drift back.

### Review comment — 2026-09-30

**Assessment:** Not reproduced as claimed; reject the flag-only repair requirement.

**Evidence:** Shared `_upkg_capture_query` already traps wrapper INT/TERM/HUP. The independent reviewer used a child that handles INT by exiting 1: signalling the wrapper still returned cancellation status 130 and skipped later managers. Direct upgrade wrapper/group INT fixtures also stopped execution. A bare child exit 130 is currently treated as cancellation by explicit convention.

**Reviewed scope and expected behavior:** No real manager ordinary-failure example using 129/130/143, or native DNF continuation after wrapper Ctrl+C, was established. Source inspection alone does not prove the reported continuation. Wrapper-only flags would miss child-only signal termination and cannot infer a child-only INT remapped to 1. Nix worker waits also examine child statuses, so they are not a pure flag-only precedent. Rewrite this as a signal-contract investigation with a failing native/representative reproduction before changing cancellation policy; retain the confirmed lifecycle work in ZSH-024.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Preserve the documented statuses: `130` for `INT`, `143` for `TERM`, `129` for `HUP`.
- Keep `localtraps` discipline and restore traps on every exit path, including the `always` blocks already used around captured queries.
- Do not change the `cancelled` state name or the plain/rich presentation contract; coordinate with [ZSH-020](020-interrupted-search-omitted-from-summary.md) and [ZSH-021](021-cancelled-counted-as-failed-in-rich-ui.md), which fix how the state is counted.
- Keep the helper usable in a `zsh -f` shell sourcing `init.zsh`, with no new dependency.
- Update GUIDE and the tips catalogue if the user-visible contract changes.

## Acceptance criteria

- [ ] A signal delivered to the run stops the remaining managers and cleanup phases even when the running child exits with an unrelated status.
- [ ] A child that exits `129`, `130`, or `143` without a signal does not cancel the run or change its recorded state.
- [ ] Cancellation still records the `cancelled` state and returns the documented status.
- [ ] Ordinary backend failures still record `failed` and continue other managers.
- [ ] The per-leaf status checks no longer decide cancellation.
- [ ] Regression stubs cover both directions against the audited behavior.

## Validation plan

Add fixtures to `scripts/test-package-audit.zsh` that (a) stub a backend to exit `1` after `kill -INT` is delivered to the wrapper and assert the run stops and reports cancelled, and (b) stub a backend to exit `130` with no signal and assert the run continues and reports failed. Run `zsh scripts/run-tests.zsh`. Compare the implementation against `_npkg_outdated` in [lib/functions-nix.zsh](../../lib/functions-nix.zsh) for the established trap-flag pattern.

## References

- Related: [ZSH-020](020-interrupted-search-omitted-from-summary.md), [ZSH-021](021-cancelled-counted-as-failed-in-rich-ui.md), [ZSH-024](024-cancellation-does-not-signal-children.md), [ZSH-032](032-cleanup-abort-discards-completed-phases.md), [ZSH-033](033-cancelled-search-leaves-progress-line.md)
- [GUIDE.md](../../GUIDE.md) cancellation paragraph
