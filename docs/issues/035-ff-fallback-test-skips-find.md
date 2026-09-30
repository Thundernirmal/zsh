# ZSH-035: The ff fallback test never reaches the find fallback

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `scripts/test-package-audit.zsh`; `ff` error preservation |
| Evidence | Reproduced in a fresh `zsh -f` shell: the guard returns before any fallback runs |

## Summary

The fixture that asserts find and grep fallbacks preserve errors calls `ff needle "$scratch/nonexistent"`. `ff` rejects a non-directory root in its own guard and returns before the find fallback executes, so the fixture's three assertions — nonzero status, non-empty stderr, empty stdout — are satisfied by the guard message alone. The find fallback's error handling, including the removal of the `2>/dev/null` suppression this change relied on, is not covered by the test that claims to cover it.

## Affected code and documentation

- [scripts/test-package-audit.zsh](../../scripts/test-package-audit.zsh): the fallback fixture, which sets `PATH` to a directory containing only `find` and `grep` symlinks and then searches a nonexistent path with `ff` and a bad pattern with `ft`.
- [lib/functions-files.zsh](../../lib/functions-files.zsh): `ff` — the `[ ! -d "$search_root" ]` guard that prints `'…' is not a directory` and returns `1`, and the `command find` fallback it never reaches.
- [scripts/run-tests.zsh](../../scripts/run-tests.zsh): the runner that includes the audit suite.

## Trigger and reproduction

Run in a fresh `zsh -f` shell at the repository root:

1. Source `init.zsh`, then load the files domain (`_zsh_functions_load files`).
2. Run `ff needle /tmp/definitely-missing-dir > out 2> err` and inspect the status and streams.

Observed at the baseline: status `1`, stdout empty, and stderr contains `'/tmp/definitely-missing-dir' is not a directory` — the guard's message, produced without invoking `find`. Because the audited change removed a `2>/dev/null` from the fallback, the assertions pass identically before and after the change. Expected: the fixture reaches the fallback and fails if its diagnostics are suppressed again.

Evidence limit: the guard short-circuit is reproduced; that the same assertions pass against the pre-change implementation was established by reading the guard, which is unchanged by the fallback diff.

## Current behavior and impact

The suite reports coverage of error preservation for the find fallback while exercising only the pre-flight guard. A future edit that re-suppresses find's stderr, or that breaks the fallback's diagnostics, passes CI. The `ft` half of the fixture does reach its backend, because an invalid pattern is passed through to `grep`, so only the `ff` half is hollow.

## Root cause

The fixture triggers the error path through the argument that `ff` validates first, rather than through the traversal that the change touched. The nonexistent path is a valid way to produce a nonzero status, but it is rejected before backend selection, so the stubbed `PATH` that forces the fallback never matters.

## Fix goal and expected behavior

The fixture exercises the find fallback with a root that passes the guard, and fails when the fallback's stderr is suppressed. The bad-pattern case for `ft` continues to cover the grep fallback. The fixture must remain deterministic in CI, including when the suite runs as root, where permission-based diagnostics may not occur.

### Review comment — 2026-09-30

**Assessment:** Confirmed regression-test coverage gap; find failure not established.

**Evidence:** The missing-root fixture exits at `ff`’s directory guard before invoking find. A stubbed backend call log confirmed that find was never called.

**Reviewed scope and expected behavior:** Use an existing temporary directory and a fake find that emits known stderr and fails; assert invocation, diagnostic preservation, and status. Permission-based fixtures can pass under privileged users. The existing test does not prove the fallback broken; it fails to exercise the intended failure path.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep the isolated `PATH` stubs so the real `fd`/`fdfind` on the host cannot satisfy the search; the fallback is selected by absence.
- Choose a trigger whose diagnostic does not depend on the test user lacking privileges, since root can read directories that a normal user cannot.
- Do not depend on a live network, a real manager, or a writable system path.
- Keep the suite runnable from [scripts/run-tests.zsh](../../scripts/run-tests.zsh) with no new dependency.

## Acceptance criteria

- [ ] The fallback fixture reaches `command find` when `fd` and `fdfind` are absent.
- [ ] Restoring a `2>/dev/null` suppression in the find fallback makes the fixture fail.
- [ ] The fixture produces the same result when the suite runs as root.
- [ ] The `ft` half continues to cover the grep fallback.
- [ ] The full suite passes under `zsh scripts/run-tests.zsh`.

## Validation plan

Rework the fixture to search an existing root that still makes `find` write a diagnostic — for example a structure containing a path that cannot be traversed, or an intentionally malformed search root that passes the guard — and assert that the diagnostic reaches stderr. Verify by temporarily reintroducing the suppression and confirming the fixture fails. Run `zsh scripts/run-tests.zsh`.

## References

- Related: [ZSH-017](017-theme-atomicity-test-not-isolated.md) (regression isolation in the same suite)
- [AGENTS.md](../../AGENTS.md) verification requirements
