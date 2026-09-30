# ZSH-009: npm inventory drops success warnings and rejects valid warned results

| Field | Value |
| --- | --- |
| Status | Open; not fixed by this documentation change |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `12e276a` |
| Affected surface | upkg outdated --only npm; npm update inventory |
| Evidence | Reproduced during audit; independently checked by a review subagent |

## Summary

npm inventory captures stderr separately but does not handle it consistently. Status-0 diagnostics disappear, while any stderr accompanying a valid status-1 update table makes the backend report failure.

## Affected code and documentation

- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): `_upkg_run_outdated_npm` status branches.
- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): `_upkg_npm_outdated_looks_valid`.
- [scripts/test-upkg.zsh](../../scripts/test-upkg.zsh): npm success, update, and error fixtures.
- [GUIDE.md](../../GUIDE.md): warnings and inventory state.

## Trigger and reproduction

Use a fake npm binary in a temporary PATH and load the package domain without running an upgrade.

1. For the first fixture, fake `npm outdated -g --depth=0` emits a benign configuration warning on stderr, no stdout, and status 0.
2. Run `_upkg_run_outdated_npm` and inspect captured stderr. Audit result: it was empty; the warning disappeared.
3. For the second fixture, emit this stdout, the same benign stderr warning, and status 1:

```text
Package Current Wanted Latest Location
example 1.0.0 2.0.0 2.0.0 global
```

4. Run the backend again. Audit result: status 1 and state `failed`, despite a valid update table.

An isolated real npm 11.19.1 empty-prefix query with an unknown configuration setting also emitted a status-0 warning that the wrapper suppressed. No real registry or credential lookup is needed for the empty-prefix case.

## Current behavior and impact

Useful native warnings are lost during successful queries. A normal configuration warning can also prevent users from seeing a successful update inventory as such. npm's status 1 can mean outdated packages were found; stderr's presence alone cannot distinguish that result from a genuine failure.

## Root cause

The status-0 branch never forwards the captured stderr. The status-1 branch requires stderr to be completely empty before accepting otherwise valid output.

## Fix goal and expected behavior

Always preserve native diagnostics on stderr. Classify a recognized valid update result with benign warnings as updates available, and classify genuine errors as failures. An empty successful result with warnings must remain up to date while showing those warnings. Package rows and diagnostics must stay separate.

## Implementation constraints

- Define how genuine npm errors are recognized alongside the chosen stable output format.
- Do not ignore all status-1 stderr; that would hide real failure.
- Do not turn warning text into package rows.
- Preserve interrupts and temporary-file cleanup.
- Coordinate output-format handling with [ZSH-008](008-npm-outdated-output-format.md).

## Acceptance criteria

- [ ] Status-0 warnings remain visible on stderr.
- [ ] A valid status-1 inventory with a benign warning is updates available and returns backend success.
- [ ] A status-1 genuine error remains failed, even if some stdout was emitted.
- [ ] Diagnostics never increase the package count or create fake update rows.
- [ ] Empty successful output with warnings remains up to date.
- [ ] Cancellation preserves its status and stops subsequent managers.

## Validation plan

Extend npm fixtures in `scripts/test-upkg.zsh` with success warnings, warned updates, actual errors, partial stdout plus errors, and cancellation. Assert stdout and stderr separately, summary state, return code, and temporary-file cleanup. Run `zsh scripts/run-tests.zsh`.

## References

- [npm outdated documentation](https://docs.npmjs.com/cli/v11/commands/npm-outdated/)
- [npm implementation: status 1 for outdated results](https://github.com/npm/cli/blob/latest/lib/commands/outdated.js)
