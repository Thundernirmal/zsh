# ZSH-014: DNF5 reports an empty package search as a failed backend

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `upkg search` with DNF/DNF5; `_upkg_run_search_dnf` |
| Evidence | Reproduced against native DNF5 5.4.6 on a Fedora host, end-to-end through the repository functions |

## Summary

`_upkg_run_search_dnf` runs `dnf -q` and then decides that a status-1 result is a legitimate empty inventory only when the literal text `No matches found.` (or a documented variant) appears in the combined output. DNF5 suppresses that text under `-q`, so a genuine no-match query returns status 1 with both streams empty and is recorded as a failed backend. On any DNF5 host, `upkg search` reports failure for every query the package manager does not carry.

## Affected code and documentation

- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): `_upkg_run_search_dnf` — the `dnf -q --color=never list --available` invocation and the status-1 no-match whitelist.
- [scripts/test-package-audit.zsh](../../scripts/test-package-audit.zsh): the `-q --color=never list --available *empty5*` fixture, which emits the no-match text that real DNF5 withholds under `-q`.
- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): `_upkg_finish_search_results`, `_upkg_set_last_result`, `_upkg_format_search_rows`, and `_upkg_print_search_summary`.
- [GUIDE.md](../../GUIDE.md): DNF search behavior, no-match conventions, and the search summary.

## Trigger and reproduction

Native behavior, on a host with DNF5 (metadata refresh is read-only network traffic):

1. `dnf -q --color=never list --available '*zzzznosuchpkg123*'` exits 1 with 0 bytes on stdout and 0 bytes on stderr.
2. `dnf --color=never list --available '*zzzznosuchpkg123*'` exits 1 with `No matches found.` on stderr.

Repository behavior, in a fresh `zsh -f` shell at the repository root:

1. `source init.zsh`, then load the package domain.
2. Call `_upkg_run_search_dnf zzzznosuchpkg123456`.

Observed at the baseline: `rc=1`, `state=failed`, `rows=0`. Expected: `rc=0`, `state=no matches`, `rows=0`.

## Current behavior and impact

A search for a package DNF does not carry prints `Search results unavailable; failed manager(s): dnf.` and returns nonzero, instead of the documented empty-result summary. This is the common case for misspelled or third-party package names, so the affected surface is every `upkg search` invocation on a DNF5 host, including single-manager searches. The defect is invisible to the current suite because the fixture supplies the text under conditions where the native tool never emits it.

## Root cause

Empty-result classification depends on native message text rather than on the documented status and stream contract. `-q` was added for quieter output, but it removes exactly the diagnostic the classifier reads. No fallback treats `status 1` with empty stdout and empty stderr as an empty inventory, although that is the DNF5 no-match shape.

## Fix goal and expected behavior

An empty native inventory must be reported as `no matches` with status 0 and zero rows, for DNF4 and DNF5, with and without quiet output. A real failure — status 1 accompanied by diagnostics, or any nonzero status with an unrelated error — must remain a failed backend with its diagnostics preserved on stderr. The no-match decision must not depend on optional, suppressible human-readable text alone.

### Review comment — 2026-09-30

**Assessment:** Confirmed defect; correct the failure criterion.

**Evidence:** Native DNF5 5.4.6, using cache-only metadata and a temporary log directory, returned status 1 with both streams empty for a quiet no-match query. The same query without `-q` returned status 1 with `No matches found.` on stderr. A stub with the quiet shape produced `state=failed` in `_upkg_run_search_dnf`.

**Reviewed scope and expected behavior:** The requirement that status 1 accompanied by diagnostics always means failure is incorrect: the legitimate unquiet no-match case has diagnostics. Distinguish recognized no-match output from genuine errors, and do not convert every quiet status-1 failure to success without checking the native contract. Model both native shapes in regressions.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep native diagnostics on stderr and out of package records, per the stream separation established for the other backends.
- Preserve DNF4 compatibility; both generations use status 1 for an empty list.
- Keep the status-1 convention scoped so that a genuine query error that also returns 1 is not silently converted into an empty success.
- Keep the `command -v`-style guards inside function bodies unchanged so PATH-stubbed fixtures keep working.
- Update the search behavior notes in GUIDE.md at the same level of detail as the other backends.

## Acceptance criteria

- [ ] A DNF5 no-match query produces zero rows, state `no matches`, and status 0.
- [ ] The same query with and without quiet output produces the same classified result.
- [ ] A DNF failure carrying diagnostics still produces state `failed` and a nonzero status.
- [ ] No-match text is never required for the success classification.
- [ ] The regression fixture models real DNF5 behavior under `-q` and fails against the audited implementation.

## Validation plan

Replace the fixture in `scripts/test-package-audit.zsh` with one that returns status 1 and empty streams for the quiet invocation, and add a case asserting that the unquiet invocation with real no-match text classifies identically. Retain an error case with stderr diagnostics. Run `zsh scripts/run-tests.zsh`, and optionally confirm against a real DNF5 host.

## References

- [DNF5 command reference](https://dnf5.readthedocs.io/en/latest/)
- [DNF4 command reference](https://dnf.readthedocs.io/en/latest/command_ref.html)
- [GUIDE.md](../../GUIDE.md) package backend notes
- Related: [ZSH-015](015-npm-search-column-layout.md) — the sibling search-parsing defect
