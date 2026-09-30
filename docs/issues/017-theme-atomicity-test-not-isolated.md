# ZSH-017: The theme atomicity regression is not environment-isolated and stops the regression runner

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `scripts/test-theme.zsh`; `zsh scripts/run-tests.zsh` |
| Evidence | Reproduced by running the documented verification command in a shell carrying this configuration's exported options |

## Summary

The new custom-theme atomicity case asserts that `FZF_CTRL_T_OPTS` is absent after a failed theme switch. The rollback under test correctly restores a pre-existing inherited value, so the assertion fails whenever the ambient environment already exports the option — which is precisely the environment this configuration creates on every interactive start. Because the runner sets `ERR_EXIT`, the failure stops the suite and the remaining test files never execute.

## Affected code and documentation

- [scripts/test-theme.zsh](../../scripts/test-theme.zsh): the custom-theme atomicity case and its `ctrl-t=0` expectation.
- [scripts/run-tests.zsh](../../scripts/run-tests.zsh): the ordered suite list under `setopt ERR_EXIT`.
- [40-fzf.zsh](../../40-fzf.zsh): the module that exports `FZF_DEFAULT_OPTS`, `FZF_CTRL_T_OPTS`, `FZF_CTRL_R_OPTS`, and `FZF_ALT_C_OPTS` on interactive start.
- [AGENTS.md](../../AGENTS.md): the requirement to run `zsh scripts/run-tests.zsh` after edits.

## Trigger and reproduction

1. In a terminal where this configuration is loaded, confirm the exported options are present: `env | grep '^FZF_'` shows all seven variables.
2. From the repository root, run `zsh scripts/run-tests.zsh`.

Observed at the baseline: exit status 1 after 373 `ok` lines, with

```
not ok: failed custom switch restores palette, options, presence, and signatures
expected: failure=1 active=111111 opts=original ctrl-t=0 signature=old count=1 ui=custom
actual:   failure=1 active=111111 opts=original ctrl-t=1 signature=old count=1 ui=custom
```

3. Re-run with the ambient options removed: `env -u FZF_DEFAULT_OPTS -u FZF_CTRL_T_OPTS -u FZF_CTRL_R_OPTS -u FZF_ALT_C_OPTS -u FZF_DEFAULT_COMMAND -u FZF_CTRL_T_COMMAND -u FZF_ALT_C_COMMAND zsh scripts/run-tests.zsh`.

Observed: exit status 0 with 1817 `ok` and no failures. The only difference between the two runs is the inherited environment.

## Current behavior and impact

The documented verification command fails on a developer machine that runs this configuration, while passing in CI, because the CI runner does not export `FZF_*`. With `ERR_EXIT` set, `test-functions`, `test-command-ux`, `test-domains`, `test-cgm`, `test-upkg`, `test-package-audit`, `test-completions`, `test-help`, `test-doctor`, and the fixed-install smoke test never run, so nine of twelve suites are skipped exactly where the maintainer needs them. The failure also trains the reader to distrust a red suite, and the case under test is not actually broken.

## Root cause

The new case asserts on option presence without first neutralizing the ambient environment, while every other suite unsets `FZF_*` before running. The assertion conflates two distinct outcomes: an option that the fixture never introduced, versus an option that the fixture inherited and the rollback correctly restored. The inherited case is the correct behavior, and asserting absence inverts it.

## Fix goal and expected behavior

The atomicity case must be independent of the caller's environment. Running `zsh scripts/run-tests.zsh` from a shell that carries this configuration's exported options must produce the same result as running it from a clean environment: exit 0, with every suite executed. The case must still verify that a failed switch restores the committed palette, option values, presence state, and finder signatures.

### Review comment — 2026-09-30

**Assessment:** Confirmed test-isolation defect; production rollback is correct.

**Evidence:** `FZF_CTRL_T_OPTS=inherited zsh scripts/test-theme.zsh` fails the rollback assertion with `ctrl-t=1`; the clean-environment full runner passes. The fixture expects the variable to be absent without first establishing absence.

**Reviewed scope and expected behavior:** Isolate the fixture and test both initially absent and initially present variables. Do not change production rollback to discard inherited options. The runner invokes eleven regression-suite scripts plus the smoke test, and the claim that every other suite scrubs these variables should be removed unless individually established.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Do not weaken the case: presence restoration must remain asserted, not merely value restoration.
- Prefer environment isolation inside the test file or the runner over changing the rollback being tested.
- Keep each suite's process boundary unchanged so failures remain attributable.
- Preserve the existing `ERR_EXIT` behavior for genuine failures.
- Do not require the developer to re-export or unset options by hand.

## Acceptance criteria

- [ ] `zsh scripts/run-tests.zsh` exits 0 from a shell with all seven `FZF_*` variables exported.
- [ ] The same command exits 0 from a clean environment.
- [ ] The atomicity case still distinguishes an option that was absent before the switch from one that was present.
- [ ] All twelve suites and the fixed-install smoke test execute in both runs.
- [ ] The case fails if the rollback stops restoring an inherited option.

## Validation plan

Add environment scrubbing to the theme suite or to the runner's per-suite invocation, then assert the atomicity case for both the absent and inherited option shapes. Verify both documented invocations above. Run `zsh scripts/run-tests.zsh` and confirm the total `ok` count matches, and confirm the smoke test and later suites appear in the output.

## References

- [40-fzf.zsh](../../40-fzf.zsh) exported option defaults
- [AGENTS.md](../../AGENTS.md) verification requirements
- Related: ZSH-006 (custom-theme state mutation, repaired at this baseline)
