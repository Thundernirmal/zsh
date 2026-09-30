# ZSH-026: GUIDE's optional-integration table omits checkupdates

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | GUIDE optional integrations; `upkg outdated`, `upkg upgrade`, and `upkg clean` with Pacman |
| Evidence | Established by source inspection of the merged tree |

## Summary

This series adds `checkupdates` from `pacman-contrib` as a probed optional dependency that changes the Pacman inventory from cached data to a fresh repository refresh against a private database. README, `scripts/check-deps.sh`, and the backend notes in GUIDE describe it, but GUIDE's optional-integrations table — the surface that exists to enumerate exactly this — does not list it.

## Affected code and documentation

- [GUIDE.md](../../GUIDE.md): the optional integrations and fallbacks table, which lists `bat`, `tree`, `fd`/`fdfind`, `rg`, `jq`, `secret-tool`, `gdbus`, `nix`, and `nix-collect-garbage` only; and the Pacman backend notes elsewhere in the same file.
- [scripts/check-deps.sh](../../scripts/check-deps.sh): the optional `checkupdates` probe gated on a `pacman` host.
- [README.md](../../README.md): the optional integrations summary, which does mention `checkupdates`.
- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): the Pacman inventory path that selects between `checkupdates` and cached `pacman -Qu`.

## Trigger and reproduction

1. Open `GUIDE.md` and read the optional integrations and fallbacks table.
2. Compare it with `README.md`'s optional integrations paragraph, the `checkupdates` probe in `scripts/check-deps.sh`, and the Pacman notes in GUIDE.

Observed at the baseline: the table does not mention `checkupdates`, while the other three surfaces do. Expected: the table lists it with its effect and its absence behavior, like every other optional tool.

## Current behavior and impact

A user reading the completeness surface for optional dependencies never learns that an Arch host's Pacman inventory depends on an optional helper, that installing it changes the query from cached metadata to a network refresh, or what the output and summary look like without it. The dependency notes are split across three surfaces, and the one designated as complete is the one that is missing the entry. The repository's documentation rule makes GUIDE the owner of dependency notes, so the omission is a contract violation rather than a wording preference.

## Root cause

The optional dependency was added at the feature level — the backend notes, the dependency checker, and the README summary — without updating the table that enumerates optional integrations. The table is maintained by hand, so adding a dependency to three surfaces did not add it to the fourth.

## Fix goal and expected behavior

GUIDE's table must list `checkupdates` with the same structure as its other rows: the command name, the effect when present, and the fallback or absence behavior. The wording must agree with the backend notes in the same file and with the README summary, each at its own level of detail.

### Review comment — 2026-09-30

**Assessment:** Confirmed documentation omission; lower priority.

**Evidence:** GUIDE’s optional-integration table omits `checkupdates`, although the backend, dependency checker, and other documentation mention it.

**Reviewed scope and expected behavior:** Add the optional integration with its fresh Pacman inventory role and dependency conditions. This is a small documentation consistency issue, appropriately P3; it does not establish a new inventory execution failure.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep GUIDE as the owner of dependency notes; do not duplicate the backend detail into README.
- Keep the row's absence behavior consistent with the backend notes: without the helper, the output and summary identify cached repository data.
- Do not change backend behavior as part of the documentation fix.
- Keep `scripts/check-deps.sh` optional-tool semantics unchanged: a missing optional tool still exits 0 with a hint.

## Acceptance criteria

- [ ] GUIDE's optional-integrations table includes `checkupdates`.
- [ ] The row states the effect when present and the behavior when absent or failing.
- [ ] The row agrees with the Pacman notes elsewhere in GUIDE.
- [ ] README remains a summary and does not gain backend detail.
- [ ] No behavior or dependency-check change is bundled with the documentation fix.

## Validation plan

Compare the table, the Pacman backend notes, the README summary, and the `check-deps.sh` probe for consistency at the merged commit. No test suite covers documentation tables; verification is by inspection.

## References

- [GUIDE.md](../../GUIDE.md) optional integrations and package backends
- [checkupdates manual](https://man.archlinux.org/man/checkupdates.8.en)
- Related: [ZSH-025](025-issue-tracker-restates-maintenance-rules.md) — the same documentation-contract class
