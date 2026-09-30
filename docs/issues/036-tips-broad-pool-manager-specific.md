# ZSH-036: Manager-specific tips appear in the broad any-manager pool

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `tips` on hosts that have only some supported managers |
| Evidence | Source inspection of the pool guards and the tips they contain |

## Summary

The tips pool gated on any of the eight supported managers contains tips that name a specific manager — `upkg search … --only=dnf`, `upkg outdated --only npm`, `upkg outdated --only flatpak`, and `upkg clean --dry-run --only dnf`. A host with, for example, only Homebrew installed passes the pool guard and can be shown actions it cannot perform, and the commands fail with the manager-unavailable error when attempted.

## Affected code and documentation

- [lib/tips-catalogue.zsh](../../lib/tips-catalogue.zsh): the pool guarded by `$+commands[paru] || $+commands[pacman] || $+commands[apt] || $+commands[dnf] || $+commands[brew] || $+commands[flatpak] || ($+commands[nix] && $+functions[npkg]) || $+commands[npm]`, which mixes manager-agnostic tips with tips naming DNF, npm, and flatpak.
- [lib/tips-catalogue.zsh](../../lib/tips-catalogue.zsh): the narrower distro pool, which contains the Arch, Paru, and APT tips that [ZSH-027](027-tips-advertise-unavailable-package-workflows.md) already reports.
- [80-tips.zsh](../../80-tips.zsh): the tips loader's summary comment, which should continue to describe what the catalogue covers.

## Trigger and reproduction

1. In a fresh `zsh -f` shell at the repository root, source `init.zsh` with a `PATH` that contains only one supported manager, for example `brew`.
2. Run `tips` and read the printed reminders.
3. Attempt the manager-specific reminders that are printed.

Observed at the baseline by inspection: the pool is entered because one manager exists, and the DNF, npm, and flatpak tips are printed; running them reports that the selected manager is not available. Expected: a reminder is printed only when the manager it names is present, and manager-agnostic reminders stay available to every host with at least one manager.

Evidence limit: established from the pool guards and tip text; the failure message for an absent manager is taken from the existing selection behavior.

## Current behavior and impact

The tips surface tells users to run workflows their host cannot perform, which is exactly the class of guidance [AGENTS.md](../../AGENTS.md) rules out: tips are for user-facing actions the user can perform. The misleading suggestions also cost a round trip, because the command fails only after it is typed. [ZSH-027](027-tips-advertise-unavailable-package-workflows.md) reports the same defect for the distro-only pool; this report covers the broader pool, whose tips name individual managers.

## Root cause

The pool guard records that some manager exists, while several entries assume a particular one. The catalogue gates by group rather than by the manager each tip names, and the recent additions kept the same coarse grouping.

## Fix goal and expected behavior

Every tip that names a manager is gated on that manager's presence, either by splitting the broad pool into per-manager pools or by a small helper that appends a tip only when its manager is available. Manager-agnostic tips — detection, preview, cancellation — remain visible to any host with at least one manager. No tip is printed for a manager the host lacks.

### Review comment — 2026-09-30

**Assessment:** Confirmed tip capability mismatch; same area as ZSH-027.

**Evidence:** A broad any-manager gate includes `--only dnf`, npm, or Flatpak reminders on hosts that only have another manager.

**Reviewed scope and expected behavior:** Gate each concrete manager reminder on that manager. `tips` prints one randomly selected reminder, so a single invocation cannot be expected to print all invalid entries as the reproduction implies. Test pool membership or deterministic selection. Consider addressing ZSH-027 and ZSH-036 in one coherent tips change.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep the catalogue hook-free and lazily loaded; the guard must stay cheap and must not probe executables beyond the `$commands` hash already used in the file.
- Keep the fixed loader in [80-tips.zsh](../../80-tips.zsh) unchanged in structure.
- Update the loader's summary comment only if the grouping it describes changes.
- Coordinate with [ZSH-027](027-tips-advertise-unavailable-package-workflows.md) so the two reports do not produce overlapping fixes for the same pool.

## Acceptance criteria

- [ ] On a host with a single manager, `tips` prints no tip naming an absent manager.
- [ ] Manager-agnostic tips remain available on every host with at least one manager.
- [ ] A host with all managers still sees the full set.
- [ ] A regression fixture with a stubbed `PATH` asserts pool membership for at least a single-manager and a multi-manager host.
- [ ] The tips suite passes under `zsh scripts/run-tests.zsh`.

## Validation plan

Extend the tips regression, or add a fixture to `scripts/test-command-ux.zsh`, that stubs `PATH` for a single-manager host and for a broad host, loads the catalogue, and asserts which reminders are present. Run `zsh scripts/run-tests.zsh`.

## References

- Related: [ZSH-027](027-tips-advertise-unavailable-package-workflows.md)
- [AGENTS.md](../../AGENTS.md) tips ownership rules
- [GUIDE.md](../../GUIDE.md) tips section
