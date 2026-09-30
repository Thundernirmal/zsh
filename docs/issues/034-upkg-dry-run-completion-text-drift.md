# ZSH-034: The live upkg completion keeps the pre-rename --dry-run text

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `upkg` completion; `_zsh_upkg` |
| Evidence | Reproduced by comparing the two in-repository definitions and the assertions in the completion test |

## Summary

`_zsh_upkg` registers `--dry-run` with the description `preview upgrades or cleanup without changing packages`, while the shared flag table `_ZSH_UPKG_FLAGS` carries the updated wording `Inventory updates or preview cleanup without changing packages`. The completion test asserts only the shared table, so the string users actually see when completing a flag still describes the pre-rename behavior.

## Affected code and documentation

- [66-compdefs.zsh](../../66-compdefs.zsh): `_ZSH_UPKG_FLAGS`, the fixed flag table, and `_zsh_upkg`, the completion function registered with `compdef`, whose inline `--dry-run[...]` description is the one presented to users.
- [scripts/test-completions.zsh](../../scripts/test-completions.zsh): the assertion that compares `_ZSH_UPKG_FLAGS` entries, which passes because the table is correct while the live registration is not.
- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): the `upkg` usage text, which uses the updated wording.

## Trigger and reproduction

1. In an interactive shell with completion active, type `upkg <TAB> --dry-run` and read the description, or grep the two definitions directly in [66-compdefs.zsh](../../66-compdefs.zsh).
2. Compare them with `upkg help` and the GUIDE entry for `--dry-run`.

Observed at the baseline: the live completion still reads `preview upgrades or cleanup without changing packages`; the help text and GUIDE use the inventory wording. Expected: the live completion, the fixed table, the help text, and the GUIDE describe the same behavior.

Evidence limit: reproduced statically by comparing the definitions and the test assertion; no interactive terminal session was captured.

## Current behavior and impact

Users completing the flag are told the old behavior, which contradicts `upkg help` and the GUIDE page. [AGENTS.md](../../AGENTS.md) requires user-facing aliases, functions, completion behavior, and workflows to keep `80-tips.zsh`, `README.md`, and `GUIDE.md` consistent in the same change, and the completion surface is the one most users read. Because the regression test inspects the wrong array, a future rename can drift again without failing CI.

## Root cause

The flag description exists twice: once in the fixed table that the test consumes, and once inline in the registered completion. The rename updated the table and its assertion but not the inline registration, and the test cannot detect the difference because it never inspects the live completion.

## Fix goal and expected behavior

One source of truth for the flag description, consumed by the registered completion and by any test, or an assertion that compares the live registration with the table and fails when they differ. The completion text matches the help text and GUIDE.

### Review comment — 2026-09-30

**Assessment:** Confirmed completion wording drift; documentation priority.

**Evidence:** The live completion describes `--dry-run` as previewing upgrades or cleanup, although the flag also covers inventory/update behavior described elsewhere.

**Reviewed scope and expected behavior:** Synchronize the completion description with the current flag contract. This is P3 wording consistency, not evidence that dry-run performs mutations.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep the fixed lazy registration structure and the `compdef` guard described in [AGENTS.md](../../AGENTS.md); no new dependency and no eager work on startup.
- Keep the table usable by `scripts/test-completions.zsh` and by the completion function itself.
- Make the drift impossible rather than correcting a single string, so the next rename cannot repeat it.
- Update `README.md`, `GUIDE.md`, and `80-tips.zsh` only if the wording itself changes.

## Acceptance criteria

- [ ] `upkg <TAB> --dry-run` describes the current behavior.
- [ ] The live completion, `_ZSH_UPKG_FLAGS`, `upkg help`, and the GUIDE agree.
- [ ] `scripts/test-completions.zsh` fails if the live registration and the table disagree.
- [ ] No change to other completion values, and the full completion test suite still passes.

## Validation plan

Derive the registered description from the shared table in [66-compdefs.zsh](../../66-compdefs.zsh) and extend `scripts/test-completions.zsh` to assert the live registration for every flag, not only the table entries. Run `zsh scripts/run-tests.zsh`.

## References

- Related: [ZSH-025](025-issue-tracker-restates-maintenance-rules.md)
- [AGENTS.md](../../AGENTS.md) documentation synchronization rule
- [GUIDE.md](../../GUIDE.md) `upkg` flag reference
