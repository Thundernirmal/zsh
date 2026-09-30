# Open issue reports

This directory tracks unresolved findings and their repair requirements. Reports contain evidence, reproduction steps, expected behavior, and acceptance criteria. Completed or declined findings remain in Git history; [GUIDE.md](../../GUIDE.md) describes current behavior.

## Issue index

| ID | Priority | Issue |
| --- | --- | --- |
| [ZSH-023](023-fzf-snapshot-cost-per-startup.md) | P2 | fzf activation snapshots every function and widget on each interactive startup |
| [ZSH-025](025-issue-tracker-restates-maintenance-rules.md) | P2 | The issue tracker's standing pages restate maintenance rules owned elsewhere |
| [ZSH-030](030-checkupdates-resyncs-repositories-per-run.md) | P2 | Every pacman inventory re-syncs all repository databases |
| [ZSH-031](031-cancellation-inferred-from-child-status.md) | P2 | Cancellation is inferred from child exit statuses at every call site |
| [ZSH-033](033-cancelled-search-leaves-progress-line.md) | P2 | A cancelled search leaves the rich progress line on screen |
| [ZSH-034](034-upkg-dry-run-completion-text-drift.md) | P2 | The live upkg completion keeps the pre-rename --dry-run text |
| [ZSH-035](035-ff-fallback-test-skips-find.md) | P2 | The ff fallback test never reaches the find fallback |

## Report structure and verification

Use [TEMPLATE.md](TEMPLATE.md) for the metadata and ten-section structure. Review comments clarify disputed evidence and supersede conflicting proposed acceptance criteria.

Follow [AGENTS.md](../../AGENTS.md) for required verification and documentation ownership. Reproductions must isolate optional tools and use synthetic credentials and package fixtures instead of real upgrades or cleanup.

The requested repair workflow is: fix one coherent issue, commit it, obtain subagent review, address findings, and then proceed to the next issue. Remove each resolved report and index entry once verified; preserve the explanation in its commit. IDs are stable and must not be renumbered or reused; the next new report starts at ZSH-038.
