# Open issue reports

This directory tracks the 1 unresolved findings from the 2026-09-30 full repository audit at commit `12e276a`. It describes defects and the behavior required after repair. Creating these reports does not fix the implementation or promise that no other defects exist.

Each report records its evidence, affected commands, reproduction, required behavior, and validation criteria. Completed findings and their audit evidence remain in Git history.

## Issue index

P1 indicates a high-priority safety-contract failure. P2 indicates a correctness or workflow failure needing repair. Priority does not establish that an exploit occurred.

| ID | Priority | Issue | Affected surface |
| --- | --- | --- | --- |
| [ZSH-013](013-npkg-subcommand-help-and-arguments.md) | P2 | Nix helper subcommands perform work for help and ignore unsupported arguments | npkg refresh; npkg find/pick/fzf; npkg outdated/check/diff |

## Report structure

Every issue uses the same metadata fields and ten sections:

1. Summary.
2. Affected code and documentation.
3. Trigger and reproduction, including the evidence boundary.
4. Current behavior and impact.
5. Root cause.
6. Fix goal and expected behavior.
7. Implementation constraints.
8. Acceptance criteria as checkable outcomes.
9. Validation plan.
10. References.

Use [TEMPLATE.md](TEMPLATE.md) when adding a finding. Source links point to the repository files; function names identify the relevant code without relying on line numbers that shift during fixes. The audited baseline records where the finding was observed. Proposed implementation approaches are guidance; acceptance criteria define the required result.

## Reproducing and validating findings

Run each reproduction in a fresh `zsh -f` shell with the working directory set to the repository root. Explicitly source the modules named in the report; these interactive helpers are not automatically available to automation. Examples containing scratch directories delete only their own temporary files when the test shell exits. Do not paste them into a long-lived working shell, because they install an EXIT trap or override fixture functions.

For startup and package workflows, use PATH-stubbed binaries, isolated caches, and temporary call logs as described in the existing test suites. Credential cases must use synthetic values and a fake Secret Service backend. Package fixtures must not perform real upgrades, orphan removal, or cache cleanup. Optional native checks must use the isolated installation or prefix specified by the report.

Before marking a fix ready:

- Reproduce the original defect and add a regression that fails on the audited behavior.
- Implement the smallest coherent fix and verify every acceptance criterion.
- Run `zsh scripts/run-tests.zsh`, as required by [AGENTS.md](../../AGENTS.md).
- Run `python3 scripts/test-fzf-pty.py` when changing picker integration or payload rendering and a supported real fzf is available.
- Update user-facing documentation, help, completion, and tips at their ownership level when behavior changes.
- Follow the requested repair loop: fix one issue, commit it, obtain subagent review, address review findings, then proceed to the next issue.

## Maintenance

Keep only unresolved reports here. When an issue is fixed, verified, and reviewed, update current behavior in [GUIDE.md](../../GUIDE.md), remove its report and index row, and preserve the explanation and verification evidence in the fix commit. Completed audits and specifications belong in Git history under the repository maintenance rules. Update the count and evidence summary above when removing reports. Stable issue IDs must not be renumbered or reused.

[README.md](../../README.md) is the project entrypoint; [GUIDE.md](../../GUIDE.md) is the user reference. These issue reports are repair requirements, rather than a replacement command reference.
