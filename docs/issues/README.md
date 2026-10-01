# Open issue reports

This directory tracks unresolved findings and their repair requirements. Reports contain evidence, reproduction steps, expected behavior, and acceptance criteria. Completed or declined findings remain in Git history; [GUIDE.md](../../GUIDE.md) describes current behavior.

## Issue index

| ID | Priority | Finding |
| --- | --- | --- |
| [ZSH-042](ZSH-042.md) | P2 | Roomy preview opens below the list at exactly 100 columns |
| [ZSH-043](ZSH-043.md) | P2 | Fixed percentage heights do not deliver the documented short-terminal guarantee |
| [ZSH-044](ZSH-044.md) | P2 | Launcher cleanup can abandon stopped processes and signal unverified PIDs |
| [ZSH-045](ZSH-045.md) | P2 | Children-list parsing follows the caller's IFS and bypasses the launcher fallback |
| [ZSH-046](ZSH-046.md) | P2 | PTY harness can inherit host FZF_DEFAULT_OPTS_FILE and change case outcomes |
| [ZSH-047](ZSH-047.md) | P2 | PTY coverage claims exceed what the suite verifies |

## Report structure and verification

Use [TEMPLATE.md](TEMPLATE.md) for the metadata and ten-section structure. Review comments clarify disputed evidence and supersede conflicting proposed acceptance criteria.

Follow [AGENTS.md](../../AGENTS.md) for required verification and documentation ownership. Reproductions must isolate optional tools and use synthetic credentials and package fixtures instead of real upgrades or cleanup.

The requested repair workflow is: fix one coherent issue, commit it, obtain subagent review, address findings, and then proceed to the next issue. Remove each resolved report and index entry once verified; preserve the explanation in its commit. IDs are stable and must not be renumbered or reused; the next new report starts at ZSH-048.
