# Open issue reports

This directory tracks unresolved findings and their repair requirements. Reports contain evidence, reproduction steps, expected behavior, and acceptance criteria. Completed or declined findings remain in Git history; [GUIDE.md](../../GUIDE.md) describes current behavior.

## Issue index

| ID | Priority | Issue |
| --- | --- | --- |
| [ZSH-021](021-cancelled-counted-as-failed-in-rich-ui.md) | P2 | The rich summary counts cancelled managers as failed and loses the cleanup layout |
| [ZSH-022](022-cgm-unset-delete-reject-attributed-scalars.md) | P1 — a user cannot remove a credential from the shell through the tool, and `cgm delete` can clear storage while leaving the value live | cgm unset and delete refuse attributed scalar credentials |
| [ZSH-023](023-fzf-snapshot-cost-per-startup.md) | P2 | fzf activation snapshots every function and widget on each interactive startup |
| [ZSH-024](024-cancellation-does-not-signal-children.md) | P2 | Cancellation traps do not signal the running package or evaluation children |
| [ZSH-025](025-issue-tracker-restates-maintenance-rules.md) | P2 | The issue tracker's standing pages restate maintenance rules owned elsewhere |
| [ZSH-026](026-guide-optional-integration-table-missing-checkupdates.md) | P2 | GUIDE's optional-integration table omits checkupdates |
| [ZSH-027](027-tips-advertise-unavailable-package-workflows.md) | P2 | Tips advertise package workflows the current host cannot perform |
| [ZSH-028](028-fbr-identity-falls-back-silently.md) | P2 | The fbr formatter accepts an optional identity that falls back to the display label |
| [ZSH-029](029-pacman-checkupdates-fakeroot-guard.md) | P2 | Pacman inventories choose checkupdates without verifying fakeroot |
| [ZSH-030](030-checkupdates-resyncs-repositories-per-run.md) | P2 | Every pacman inventory re-syncs all repository databases |
| [ZSH-031](031-cancellation-inferred-from-child-status.md) | P2 | Cancellation is inferred from child exit statuses at every call site |
| [ZSH-032](032-cleanup-abort-discards-completed-phases.md) | P2 | Interrupting a cleanup step discards the accounting of completed phases |
| [ZSH-033](033-cancelled-search-leaves-progress-line.md) | P2 | A cancelled search leaves the rich progress line on screen |
| [ZSH-034](034-upkg-dry-run-completion-text-drift.md) | P2 | The live upkg completion keeps the pre-rename --dry-run text |
| [ZSH-035](035-ff-fallback-test-skips-find.md) | P2 | The ff fallback test never reaches the find fallback |
| [ZSH-036](036-tips-broad-pool-manager-specific.md) | P2 | Manager-specific tips appear in the broad any-manager pool |
| [ZSH-037](037-guide-npkg-cancellation-statuses.md) | P2 | GUIDE documents only status 130 for npkg cancellation |

## Report structure and verification

Use [TEMPLATE.md](TEMPLATE.md) for the metadata and ten-section structure. Review comments clarify disputed evidence and supersede conflicting proposed acceptance criteria.

Follow [AGENTS.md](../../AGENTS.md) for required verification and documentation ownership. Reproductions must isolate optional tools and use synthetic credentials and package fixtures instead of real upgrades or cleanup.

The requested repair workflow is: fix one coherent issue, commit it, obtain subagent review, address findings, and then proceed to the next issue. Remove each resolved report and index entry once verified; preserve the explanation in its commit. IDs are stable and must not be renumbered or reused; the next new report starts at ZSH-038.
