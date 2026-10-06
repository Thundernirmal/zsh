# Open issue reports

This directory tracks unresolved findings and their repair requirements. Reports contain evidence, reproduction steps, expected behavior, and acceptance criteria. Completed or declined findings remain in Git history; [GUIDE.md](../../GUIDE.md) describes current behavior.

## Issue index

There are currently no open issue reports. Completed findings are retained in Git history.

## Report structure and verification

Use [TEMPLATE.md](TEMPLATE.md) for the metadata and ten-section structure. Review comments clarify disputed evidence and supersede conflicting proposed acceptance criteria.

Follow [AGENTS.md](../../AGENTS.md) for required verification and documentation ownership. Reproductions must isolate optional tools and use synthetic credentials and package fixtures instead of real upgrades or cleanup.

The requested repair workflow is: fix one coherent issue, commit it, obtain subagent review, address findings, and then proceed to the next issue. Remove each resolved report and index entry once verified; preserve the explanation in its commit. IDs are stable and must not be renumbered or reused; the next new report starts at ZSH-049.
