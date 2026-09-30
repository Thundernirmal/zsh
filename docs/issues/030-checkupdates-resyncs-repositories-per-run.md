# ZSH-030: Every pacman inventory re-syncs all repository databases

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `upkg`, `upkg outdated`, `upkg plan` with pacman; `_upkg_run_outdated_pacman` |
| Evidence | Source inspection of the database lifetime; the cost magnitude was not measured |

## Summary

`_upkg_run_outdated_pacman` creates a fresh `mktemp -d` database on every invocation and runs `checkupdates` against it, which performs a full repository-database sync before answering. The directory is removed afterwards. Every default `upkg`, `upkg outdated`, and `upkg plan` on an Arch host therefore re-downloads and rewrites all repository databases, where the previous cached `pacman -Qu` query used the local metadata already on disk.

## Affected code and documentation

- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): `_upkg_run_outdated_pacman` — the per-call `mktemp -d` database, the `CHECKUPDATES_DB=… checkupdates` call, and the `always` block that deletes the directory.
- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): `_upkg_capture_query`, which allocates its own temporary output directory per query, so two temporary trees are created per invocation.
- [scripts/test-package-audit.zsh](../../scripts/test-package-audit.zsh): the pacman inventory fixture, which currently locks in the per-call database behavior.
- [GUIDE.md](../../GUIDE.md): the pacman inventory section, which documents a private, per-call database that is removed afterward.

## Trigger and reproduction

Prerequisites: an Arch-family host with `pacman-contrib`, or a PATH stub that records its arguments and environment.

1. In a fresh `zsh -f` shell at the repository root, source `init.zsh` and load the package domain.
2. Stub `checkupdates` to append `$CHECKUPDATES_DB` to a log and exit `2` with empty output (the empty-inventory status).
3. Run `upkg outdated --only pacman` twice and compare the logged database paths.

Observed at the baseline by inspection: each run passes a distinct `mktemp -d` directory, so the helper starts from an empty database and must sync the repositories again. Expected: repeated inventories in a short window do not re-download unchanged repository databases, while the freshness contract documented in GUIDE is preserved.

Evidence limit: the per-call database lifetime is established from the source; the wall-clock and bandwidth cost were not measured because that requires an Arch host and network access.

## Current behavior and impact

Each inventory pays a full repository sync: network round-trips for every configured repository, tens of megabytes of writes to a temporary directory, and the same work again on the next invocation. Read-only previews (`upkg`, `upkg outdated`, `upkg plan`) become the most expensive routine package commands on Arch, and a loop or a script that inventories repeatedly multiplies the cost. Users who previously relied on the cached query now incur a network operation for every check.

## Root cause

The freshness guarantee is implemented by giving `checkupdates` a brand-new database each call rather than by refreshing a stable private one. Because the database never survives the invocation, every run starts cold, and the documented "per-call database removed afterward" phrasing records the implementation's lifetime rather than a required property.

## Fix goal and expected behavior

Keep the documented freshness contract — a separate database, never the live pacman database, and no silent fallback to cached success — while avoiding a cold full sync on every invocation. A stable private database with a defined refresh policy, or an equivalent reuse of the helper's own refresh behavior, satisfies the goal. The chosen policy must be observable in the labeling the backend already prints, so a user can tell whether the displayed inventory is fresh or cached.

### Review comment — 2026-09-30

**Assessment:** Intentional freshness tradeoff; performance enhancement requires measurement.

**Evidence:** The backend deliberately creates and removes a private CHECKUPDATES_DB for each query. Native checkupdates synchronizes repositories there. Repeated synchronization follows from this implementation and the documented fresh-inventory contract.

**Reviewed scope and expected behavior:** This is a possible optimization, not proof of incorrect package results or an introduced correctness regression. Claims about byte volume and relative cost need measurements. A persistent cache requires ownership, symlink, locking, failure, and freshness rules; reusing metadata without refresh changes the freshness contract. Set a measured performance target before choosing a reuse window or changing behavior.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Never sync or write the live pacman database; the separate-database rule is a safety boundary.
- A persistent database must be private: owner-only permissions, not a symlink target, and published atomically if it is shared across processes, following the cache contract used by the zoxide integration.
- Do not add a required dependency or a background daemon; keep the backend usable on a minimal Arch host.
- Preserve cancellation statuses 129, 130, and 143 and the existing failure contract for refresh errors.
- Update GUIDE and any tips that describe the per-call database at their ownership level.

## Acceptance criteria

- [ ] Repeated inventories in a short window do not perform a full repository sync each time, or the refresh policy is explicit and bounded.
- [ ] The same policy applies to `upkg`, `upkg outdated`, and `upkg plan`.
- [ ] The live pacman database is never the sync target.
- [ ] Freshness and cache labeling remain accurate for both the fresh and cached paths.
- [ ] A refresh failure is still a failure, with no silent success.
- [ ] A regression asserts the refresh policy rather than the per-call `mktemp` behavior.

## Validation plan

Extend the pacman fixture in `scripts/test-package-audit.zsh` to record every `CHECKUPDATES_DB` value across two consecutive inventories and assert the chosen policy (reuse versus refresh), including inode and permission checks if the database persists. Keep an assertion that the live database path is never passed. Run `zsh scripts/run-tests.zsh`. Optional timings on an Arch host are informative but must not become a required fixture.

## References

- [checkupdates manual](https://man.archlinux.org/man/checkupdates.8.en)
- Related: [ZSH-026](026-guide-optional-integration-table-missing-checkupdates.md), [ZSH-029](029-pacman-checkupdates-fakeroot-guard.md)
- [GUIDE.md](../../GUIDE.md) pacman inventory section and the "never run `pacman -Sy` alone" boundary
