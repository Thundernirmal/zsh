# ZSH-023: fzf activation snapshots every function and widget on each interactive startup

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | Shell startup; fzf integration |
| Evidence | Established by source inspection; the cost scales with the user's defined functions and keymaps, and the magnitude was not isolated at this baseline |

## Summary

`_fzf_activate_integration_file` builds a rollback snapshot on every interactive startup: it iterates every defined function with a pattern test, parses `bindkey -lL` output twice with `${(z)}` and `${(@Q)}`, and clones every keymap and every fzf-related ZLE widget before sourcing the integration. The clones are discarded in the `always` block even when activation succeeds, so the work is unconditional and is never used on the common path.

## Affected code and documentation

- [40-fzf.zsh](../../40-fzf.zsh): `_fzf_activate_integration_file` — the `${(k)functions}` scan, the two `bindkey -lL` parsing passes, the `bindkey -N` clone loop, the `${(k)widgets}` loop with `zle -A`, and the `always` block that deletes the clones.
- [40-fzf.zsh](../../40-fzf.zsh): the interactive-only guard that decides whether this runs at all.
- [AGENTS.md](../../AGENTS.md): the startup-latency constraints on module load and guard choice.

## Trigger and reproduction

The cost is proportional to the number of defined functions, keymaps, and widgets, so a plugin-heavy shell shows it most clearly.

1. In a real interactive shell, count the snapshot inputs: `print ${#functions}` and `bindkey -lL | wc -l`.
2. Compare interactive startup time with the fzf module enabled and with the fzf branch skipped, across several runs, on the same host and terminal.

Observed at the baseline: the snapshot performs one pattern test per defined function and one `bindkey -N` plus one `zle -A` per keymap and fzf widget, on every start, whether or not the integration later fails. Audit note: the absolute per-start delta was not isolated in this environment — the measurement harness was dominated by process fork and exit — so the reported impact is the unconditional work and its scaling, not a specific millisecond figure.

## Current behavior and impact

Every interactive shell pays for rollback machinery that only matters when activation fails. On a shell with roughly 1600 defined functions, the function scan alone is a full pass over the function table, and the keymap and widget clones add allocations that are immediately freed. The cost lands on the startup path that this repository explicitly keeps lean, and it grows with the user's plugin count rather than with anything under the repository's control.

## Root cause

Rollback correctness was pursued by snapshotting broadly, and the snapshot was placed before the commit point rather than being made conditional on a failure that can actually occur. Because the snapshot and the commit happen in the same function, the successful path cannot avoid building state it will never consult.

## Fix goal and expected behavior

Correctness must be preserved: a failed activation must still leave no new or overwritten functions, widgets, keymaps, options, or aliases. The successful path must not pay for a snapshot it discards. Startup cost must not scale with the number of unrelated functions in the user's shell.

### Review comment — 2026-09-30

**Assessment:** Unmeasured performance investigation; not an established runtime defect.

**Evidence:** The snapshot scans functions and widget names, saves matching fzf functions/widgets, and clones keymaps. This work occurs on the successful path, but no startup delta or meaningful regression threshold was established.

**Reviewed scope and expected behavior:** It does not snapshot every function and widget. Before-activation snapshots are necessary to restore originals after failed mutation; taking the snapshot only after failure cannot recover overwritten state. Benchmark representative shells first, then target measurable cost while preserving rollback. “Successful activation pays no snapshot cost” is not a valid unconditional acceptance criterion; classify this as performance investigation rather than a demonstrated P2 failure.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Preserve the existing rollback contract for every object class the snapshot covers.
- Do not introduce `eval` of generated shell text; the keymap parsing deliberately avoids it.
- Keep the interactive-only guard and the non-prompt startup guarantees unchanged.
- Keep the snapshot free of external commands; use builtins available on the startup path.
- If narrowing the snapshot, document which object classes remain guaranteed and which are no longer restorable.

## Acceptance criteria

- [ ] A failed activation still restores functions, widgets, keymaps, options, and aliases.
- [ ] The successful path performs no snapshot work proportional to the total defined-function count.
- [ ] Interactive startup time with the fzf integration ready does not regress against the pre-change baseline in a controlled measurement.
- [ ] Non-prompt startup paths remain unaffected.
- [ ] Existing fzf integration tests and the real PTY checks still pass.

## Validation plan

Keep the rollback fixtures in `scripts/test-init.zsh` and add a case asserting no snapshot artifacts remain after a successful activation. Measure interactive startup on a consistent host and terminal, reporting the method and variance rather than a single number. Run `zsh scripts/run-tests.zsh` and `python3 scripts/test-fzf-pty.py`.

## References

- [AGENTS.md](../../AGENTS.md) startup and guard requirements
- Related: ZSH-005 (fzf partial integration rollback, repaired at this baseline) — the change that introduced the snapshot
