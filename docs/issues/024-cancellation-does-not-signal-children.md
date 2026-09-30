# ZSH-024: Cancellation traps do not signal the running package or evaluation children

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `upkg search`, `upkg outdated`, `upkg upgrade`, `upkg clean`; `npkg outdated` |
| Evidence | Source inspection; the signal-delivery scenario was not reproduced in the audit environment |

## Summary

The cancellation traps in the shared query helper record a status and return, but do not signal the command the helper is waiting on. The Nix worker reaping path does signal its recorded worker subshells, but only with `kill` against those subshells, which does not reach the evaluation processes they spawned. Cancellation therefore depends on the signal reaching the native child by some other means — which terminal Ctrl-C provides through the foreground process group, and which a signal delivered only to the shell does not.

## Affected code and documentation

- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): `_upkg_capture_query`, whose INT, TERM, and HUP traps only `return` the corresponding status, and `_upkg_check_interrupt`, which consumes that status.
- [lib/functions-nix.zsh](../../lib/functions-nix.zsh): `_npkg_outdated` and its cancellation traps, and `_npkg_wait_workers`, which `wait`s on recorded pids and `command kill`s the remaining subshells.
- [GUIDE.md](../../GUIDE.md): the statement that Ctrl-C stops and reaps only the command's recorded evaluation workers, and the `upkg` cancellation paragraph.
- [scripts/test-package-audit.zsh](../../scripts/test-package-audit.zsh): cancellation fixtures.

## Trigger and reproduction

Proposed reproduction, not executed during this audit — the audit shell could not deliver a signal to a single process without affecting the harness:

1. In a fresh `zsh -f` shell, load the package domain and stub a backend with a long-running command, for example `fake_backend() { exec sleep 45 }`.
2. Deliver TERM to the shell process only — not to its process group — while `_upkg_capture_query fake_backend` is waiting, as a supervisor or wrapper would.
3. Observe whether the fake command is still running, and when the helper returns.

Expected under the current implementation: the trap body is not evaluated until the foreground command completes, and the child is never signalled by the helper, so the run reports `cancelled` only after the native command finishes on its own. For the Nix path, the recorded worker subshells receive SIGTERM while the evaluation processes they spawned do not, so a run reported as cancelled can leave evaluation work running.

Evidence limit: the code-level facts — trap bodies that only return, and worker reaping that targets subshells without a process-group signal — are established by source inspection. The observed timing and the survival of grandchildren were not reproduced here and must be confirmed before the fix is accepted.

## Current behavior and impact

When a signal reaches the whole foreground process group, as with an interactive Ctrl-C, behavior matches the documentation. When a signal reaches only the shell — a supervisor, a job-control kill, or a wrapper that signals the shell rather than the group — the command stays parked in the wait, the documented status appears late, and the native work continues in the meantime. On the Nix path this can leave `nix eval` processes consuming CPU and holding store locks after the tool has reported cancellation and returned. The cancellation contract is therefore accurate only for one delivery mode, and GUIDE does not distinguish them.

## Root cause

The traps were written to produce a status for the orchestration layer, not to terminate the work in progress. Signalling relies on the terminal's foreground process-group behavior, which the implementation does not control and does not establish. The worker reaping path records subshell pids because it needs their exit status, and it kills exactly those pids; the descendants spawned inside them are never recorded and so are never signalled.

## Fix goal and expected behavior

Cancellation must terminate the work it interrupts, for signals delivered to the shell and for signals delivered to the process group. The helper must ensure the awaited command does not outlive the cancellation, and the Nix path must reap evaluation descendants rather than only their immediate subshells. The documented statuses 129, 130, and 143 must continue to be preserved and propagated.

### Review comment — 2026-09-30

**Assessment:** Confirmed child-lifecycle defect; specify signal delivery.

**Evidence:** The independent reviewer delivered TERM only to a wrapper running a synthetic query child. The child remained alive and the wrapper waited about two seconds before returning 143. A separate mocked Nix evaluation returned 143 while an evaluation descendant remained alive. The synthetic descendant was terminated afterward.

**Reviewed scope and expected behavior:** These reproductions strengthen the original source-only evidence. They establish wrapper-only signal and descendant-lifecycle gaps; terminal Ctrl+C delivered to the foreground process group is a different case and is not universally broken. The fix must stop and reap owned processes without signalling unrelated shell jobs, and retain the documented cancellation statuses.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Do not leave orphaned processes that continue consuming resources or holding locks after a reported cancellation.
- Preserve the existing status mapping and the `_UPKG_INTERRUPTED_STATUS` contract.
- Keep unrelated background jobs untouched: cancellation stops this command's work only.
- Preserve temporary-file cleanup on the interrupted paths.
- Keep the trap bodies free of work that could itself be interrupted.
- Update GUIDE.md if the described guarantee becomes stronger or more precisely scoped.

## Acceptance criteria

- [ ] A signal delivered to the shell alone stops the awaited command promptly rather than after it finishes.
- [ ] Evaluation descendants do not survive a reported cancellation.
- [ ] The reported status is 130 for INT, 143 for TERM, and 129 for HUP.
- [ ] Unrelated background jobs survive cancellation.
- [ ] Temporary files are removed on the interrupted path.
- [ ] A regression asserts both the returned status and the absence of surviving descendants.

## Validation plan

Add fixtures that stub a long-running backend and a Nix worker spawning a distinguishable descendant, assert termination of both, and assert the statuses, in `scripts/test-package-audit.zsh`. The audit environment could not deliver single-process signals, so the fix must add a reproduction that fails against the audited implementation before it is accepted. Run `zsh scripts/run-tests.zsh`.

## References

- [GUIDE.md](../../GUIDE.md) cancellation and Nix worker notes
- [Zsh signal handling and traps](https://zsh.sourceforge.io/Doc/Release/Signals.html)
- Related: [ZSH-014](014-dnf-quiet-no-match-misclassified.md) — the cancellation path interacts with the no-match classification
