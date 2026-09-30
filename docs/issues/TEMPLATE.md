# ZSH-NNN: Specific observable failure

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P1 or P2, with rationale in impact |
| Audit date | YYYY-MM-DD |
| Audited baseline | Commit SHA |
| Affected surface | Commands, startup path, or integration |
| Evidence | Reproduced fixture, native integration check, or source/manual inspection |

## Summary

Describe the concrete failure and why the reader needs to address it.

## Affected code and documentation

Link the owning source files, function names, relevant test suites, and user documentation. Keep line references tied to the baseline if used.

## Trigger and reproduction

State prerequisites, isolation boundaries, exact input/status/stream fixtures, steps, and observed results. Distinguish a runnable reproduction from a proposed future test. Do not use real credentials or live destructive package operations.

## Current behavior and impact

Explain observable output, file or shell-state changes, return status, affected users, and practical consequence. State conditions and evidence limits without claiming unobserved compromise or data loss.

## Root cause

Explain the implementation assumption and control flow that produces the failure.

## Fix goal and expected behavior

Define the required result after the fix: successful behavior, failure behavior, side effects, status, and state preservation. Separate required outcomes from optional implementation choices.

## Implementation constraints

List portability, guards, lazy loading, safety boundaries, compatibility, dependencies, and documentation ownership requirements that the fix must preserve.

## Acceptance criteria

- [ ] Add measurable success cases.
- [ ] Add measurable error/cancellation/state-preservation cases.
- [ ] Add a case that prevents recurrence of the original defect.

## Validation plan

Name targeted regressions and assertions, plus required zsh scripts/run-tests.zsh verification. Describe any optional isolated native checks and subagent review.

## References

Link official documentation/man pages, upstream source where needed, related issue reports, and the relevant repository contract.
