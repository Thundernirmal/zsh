# ZSH-027: Tips advertise package workflows the current host cannot perform

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `tips` on hosts with only one distribution package manager |
| Evidence | Established by source inspection of the tip pool gating on a DNF-only host |

## Summary

The package tip pool is gated on `paru`, `pacman`, `apt`, or `dnf` being present and then offers Arch-specific and APT-specific actions to whatever host satisfied the gate. On a DNF-only Fedora host the pool advertises `checkupdates`, the Paru `Devel` configuration, and an APT-only upgrade invocation, none of which the host can perform.

## Affected code and documentation

- [lib/tips-catalogue.zsh](../../lib/tips-catalogue.zsh): the tip pool block gated on `paru`, `pacman`, `apt`, or `dnf`, which contains the `checkupdates`, `paru.conf` Devel, and `--only=apt` tips.
- [lib/tips-catalogue.zsh](../../lib/tips-catalogue.zsh): the Nix tip block, which gates on `$+commands[nix] && $+commands[jq]` and is the local pattern for a precise gate.
- [80-tips.zsh](../../80-tips.zsh): the tips loader.
- [AGENTS.md](../../AGENTS.md): the rule that tips exist for user-facing actions the user can perform, and the requirement to keep tips and documentation synchronized with behavior.
- [GUIDE.md](../../GUIDE.md): the note that `checkupdates` applies to Arch-family systems.

## Trigger and reproduction

1. On a host with `dnf` and without `pacman`, `paru`, or `apt`, load this configuration and run `tips`.
2. Read the package-related entries.

Observed at the baseline: the pool includes `Run checkupdates for a fresh Arch repo inventory without changing the live DB`, `Use Devel in paru.conf to enable development-package commit update checks`, and `Run upkg upgrade --sudo --only=apt after resolving APT refresh errors`. Expected: entries the host can act on.

## Current behavior and impact

Tips are the surface that teaches users what this configuration can do, so an entry naming an unavailable command sends the user to a tool they do not have and to a package workflow that will fail or is meaningless on their distribution. The failure is quiet — the tip reads as advice, not as a capability claim — and it repeats on every invocation of `tips`. The Nix tips show that per-integration gating is already the established pattern here.

## Root cause

A single condition was used for a set of tips that do not share a host requirement. The gate answers "is this a Linux package-manager host" while the entries assume Arch, Paru, and APT specifically. Because the condition is a disjunction of four managers, any one of them admits every entry.

## Fix goal and expected behavior

Each tip must be shown only on a host that can perform the action it describes. Arch-family entries require an Arch-family tool, the Paru entry requires Paru, and the APT entry requires APT. Entries that apply to any of the supported managers may keep the broad gate. The pool must remain non-empty on a host with at least one supported manager.

### Review comment — 2026-09-30

**Assessment:** Confirmed capability-gating defect; coordinate with ZSH-036.

**Evidence:** The broad package-tip condition can admit tips requiring checkupdates, Paru configuration, or APT flags on a DNF-only host.

**Reviewed scope and expected behavior:** Gate manager-specific reminders on their actual capability and keep broadly usable reminders broad. Coordinate with ZSH-036 to avoid two inconsistent fixes to the same pool. `tips` displays one randomly selected reminder per call, not the whole pool; inspect `_zsh_tip_pool` or select deterministically in tests.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep the tip pool hook-free and cheap: gates are evaluated when `tips` runs, not at startup.
- Keep the existing `$+commands[...]` form, which is correct inside function bodies and compatible with the PATH-stubbed fixtures.
- Do not remove user-facing tips that are accurate for their platform.
- Update the tips and their documentation surface together, within the ownership boundaries in AGENTS.md.

## Acceptance criteria

- [ ] A DNF-only host shows no Arch-only or APT-only tip.
- [ ] A Paru host shows the Paru entry; an APT host shows the APT entry.
- [ ] Every remaining entry is performable on the host that shows it.
- [ ] The pool is non-empty on a host with at least one supported manager.
- [ ] Tip rendering and `tips` startup behavior are unchanged otherwise.

## Validation plan

Add cases to the tips coverage that exercise the pool for representative host shapes — DNF-only, APT-only, Pacman with and without Paru, and Nix — and assert the presence and absence of the manager-specific entries. Run `zsh scripts/run-tests.zsh`.

## References

- [AGENTS.md](../../AGENTS.md) tips ownership and purpose
- [GUIDE.md](../../GUIDE.md) package backends and `checkupdates` scope
- Related: [ZSH-026](026-guide-optional-integration-table-missing-checkupdates.md)
