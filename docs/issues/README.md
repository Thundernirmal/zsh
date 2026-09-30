# Open issue reports

This directory tracks unresolved findings from the 2026-09-30 reviews of the package, startup, theme, credential, and documentation changes. The ZSH-014–028 series reports the review at commit `453cf43`; the ZSH-029–037 series reports the review of branch `codex/sol61`, with every finding re-verified against `453cf43`. It describes defects and the behavior required after repair. Creating these reports does not fix the implementation or promise that no other defects exist.

The reviews covered every commit in the changes under audit: package search and inventory backends, cancellation, the Nix bridge, fzf activation, theme state, credential handling, branch selection, and the documentation surfaces the changes updated. Findings were verified against native DNF5 5.4.6, npm 11.19.1, Nix, and Git on a Fedora host, through real PTY shells for the startup and editor-integration cases, and by source inspection where a reproduction was not available. Evidence limits are stated in each report.

## Issue index

P1 means a high-priority safety-contract failure: a user cannot remove a credential from the shell through the tool, and `cgm delete` can clear storage while leaving the value live. P2 means a correctness or workflow failure needing repair. Priority does not describe whether an exploit has occurred on this machine.

| ID | Priority | Issue | Affected surface |
| --- | --- | --- | --- |
| [ZSH-014](014-dnf-quiet-no-match-misclassified.md) | P2 | DNF5 reports an empty package search as a failed backend | `upkg search` with DNF/DNF5 |
| [ZSH-015](015-npm-search-column-layout.md) | P2 | npm search shows keywords as the available version and drops keyword-less matches | `upkg search` with npm |
| [ZSH-016](016-fzf-phantom-widget-aborts-activation.md) | P2 | A stale widget-name key binding aborts fzf integration activation | Shell startup; fzf integration and pickers |
| [ZSH-017](017-theme-atomicity-test-not-isolated.md) | P2 | The theme atomicity regression is not environment-isolated and stops the regression runner | `scripts/test-theme.zsh`; `scripts/run-tests.zsh` |
| [ZSH-018](018-nix-search-replays-evaluation-progress.md) | P2 | Nix search replays captured evaluation progress to the terminal | `upkg search` with Nix |
| [ZSH-019](019-nix-bridge-merges-npkg-stderr.md) | P2 | The upkg Nix bridge merges npkg diagnostics into update-inventory stdout | `upkg outdated --only nix` |
| [ZSH-020](020-interrupted-search-omitted-from-summary.md) | P2 | An interrupted search is omitted from the search summary | `upkg search` with any manager |
| [ZSH-021](021-cancelled-counted-as-failed-in-rich-ui.md) | P2 | The rich summary counts cancelled managers as failed and loses the cleanup layout | Rich rendering of `upkg search`, `upgrade`, `clean`, `outdated` |
| [ZSH-022](022-cgm-unset-delete-reject-attributed-scalars.md) | P1 | cgm unset and delete refuse attributed scalar credentials | `cgm unset`; `cgm delete` |
| [ZSH-023](023-fzf-snapshot-cost-per-startup.md) | P2 | fzf activation snapshots every function and widget on each interactive startup | Shell startup; fzf integration |
| [ZSH-024](024-cancellation-does-not-signal-children.md) | P2 | Cancellation traps do not signal the running package or evaluation children | `upkg` backends; `npkg outdated` |
| [ZSH-025](025-issue-tracker-restates-maintenance-rules.md) | P2 | The issue tracker's standing pages restate maintenance rules owned elsewhere | README index; `docs/issues/` |
| [ZSH-026](026-guide-optional-integration-table-missing-checkupdates.md) | P2 | GUIDE's optional-integration table omits checkupdates | GUIDE optional integrations; Pacman inventories |
| [ZSH-027](027-tips-advertise-unavailable-package-workflows.md) | P2 | Tips advertise package workflows the current host cannot perform | `tips` on single-manager hosts |
| [ZSH-028](028-fbr-identity-falls-back-silently.md) | P2 | The fbr formatter accepts an optional identity that falls back to the display label | `fbr`; `_fbr_format_entry` |
| [ZSH-029](029-pacman-checkupdates-fakeroot-guard.md) | P2 | Pacman inventories choose checkupdates without verifying fakeroot | `upkg`, `upkg outdated`, `upkg plan` with pacman; `scripts/check-deps.sh` |
| [ZSH-030](030-checkupdates-resyncs-repositories-per-run.md) | P2 | Every pacman inventory re-syncs all repository databases | `upkg`, `upkg outdated`, `upkg plan` with pacman |
| [ZSH-031](031-cancellation-inferred-from-child-status.md) | P2 | Cancellation is inferred from child exit statuses at every call site | `upkg` backends; `_upkg_check_interrupt` |
| [ZSH-032](032-cleanup-abort-discards-completed-phases.md) | P2 | Interrupting a cleanup step discards the accounting of completed phases | `upkg clean` across all managers |
| [ZSH-033](033-cancelled-search-leaves-progress-line.md) | P2 | A cancelled search leaves the rich progress line on screen | Rich rendering of `upkg search` |
| [ZSH-034](034-upkg-dry-run-completion-text-drift.md) | P2 | The live upkg completion keeps the pre-rename --dry-run text | `upkg` completion; `66-compdefs.zsh` |
| [ZSH-035](035-ff-fallback-test-skips-find.md) | P2 | The ff fallback test never reaches the find fallback | `scripts/test-package-audit.zsh`; `ff` |
| [ZSH-036](036-tips-broad-pool-manager-specific.md) | P2 | Manager-specific tips appear in the broad any-manager pool | `tips` on single-manager hosts |
| [ZSH-037](037-guide-npkg-cancellation-statuses.md) | P2 | GUIDE documents only status 130 for npkg cancellation | GUIDE `npkg` reference |

## Review assessment — 2026-09-30

The follow-up review checked baseline `453cf43` against source, safe PATH-stubbed fixtures, native DNF5/npm/Nix behavior, and an independent subagent review. Each report now has a **Review comment** under its fix-goal section. Those comments preserve the original report while identifying evidence, disputed claims, and corrected expectations. No implementation fixes were made during this review.

| Disposition | Reports | Required next step |
| --- | --- | --- |
| Confirmed runtime or regression-test gap | ZSH-014, 015, 016, 017, 018, 019, 020, 021, 022, 024, 032, 033, 035 | Repair against the reviewed scope; several original acceptance criteria need correction first. |
| Smaller documentation, dependency guidance, or tips gap | ZSH-026, 027, 029, 034, 036, 037 | Address consistency/capability guidance; 029 already preserves the native failure diagnostic, and 037’s Ctrl+C statement is accurate. |
| Investigation, optional hardening, or overstated report | ZSH-023, 025, 028, 030, 031 | Do not implement the original goals as mandatory correctness fixes. Measure performance for 023/030; narrow 025/028; establish and rewrite 031 before changing signal policy. |

The original priority fields remain unchanged for traceability. This review recommends P2 for ZSH-022 rather than P1, and lower priority for wording, documentation, and optional hardening. ZSH-027 and ZSH-036 overlap and should receive one coherent capability-gating change. The fix/commit/subagent-review loop comes from the user’s instructions, rather than AGENTS.md.

The full runner passes in the clean environment. The inherited-options reproduction for ZSH-017 still fails, confirming a fixture gap that the clean pass misses. Wrapper-only signal fixtures also reproduced the child-lifecycle defect in ZSH-024; the broader continuation claim in ZSH-031 did not reproduce. Original source-only evidence labels should be read alongside these updated review comments.

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

For startup and package workflows, use PATH-stubbed binaries, isolated caches, and temporary call logs as described in the existing test suites. Credential cases must use synthetic values and a fake Secret Service backend. Package fixtures must not perform real upgrades, orphan removal, or cache cleanup. Native read-only queries that refresh metadata are acceptable for manual confirmation but must not become the regression fixture. Optional native checks must use the isolated installation or prefix specified by the report.

Findings whose evidence is source inspection rather than a reproduction — ZSH-023 (for its cost magnitude), ZSH-024, and ZSH-029 through ZSH-034, ZSH-036, and ZSH-037 — require the fix to add a reproduction that fails against the audited implementation before it is accepted. ZSH-035 was reproduced directly in a fresh `zsh -f` shell.

Before marking a fix ready:

- Reproduce the original defect and add a regression that fails on the audited behavior.
- Implement the smallest coherent fix and verify every acceptance criterion.
- Run `zsh scripts/run-tests.zsh`, as required by [AGENTS.md](../../AGENTS.md).
- Run `python3 scripts/test-fzf-pty.py` when changing picker integration or payload rendering and a supported real fzf is available.
- Update user-facing documentation, help, completion, and tips at their ownership level when behavior changes.
- Follow the requested repair loop: fix one issue, commit it, obtain subagent review, address review findings, then proceed to the next issue.

## Maintenance

Keep only unresolved reports here. When an issue is fixed, verified, and reviewed, update current behavior in [GUIDE.md](../../GUIDE.md), remove its report and index row, and preserve the explanation and verification evidence in the fix commit. Completed audits and specifications belong in Git history under the repository maintenance rules. Update the index when adding or removing reports. Stable issue IDs must not be renumbered or reused; the next report after this series starts at ZSH-038.

[README.md](../../README.md) is the project entrypoint; [GUIDE.md](../../GUIDE.md) is the user reference. These issue reports are repair requirements, rather than a replacement command reference.
