# ZSH-029: Pacman inventories choose checkupdates without verifying fakeroot

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `upkg`, `upkg outdated`, `upkg plan` with pacman; `_upkg_run_outdated_pacman` |
| Evidence | Source inspection of the capability guard and the dependency checker; native confirmation on an Arch host was not available |

## Summary

`_upkg_run_outdated_pacman` selects `checkupdates` whenever `command -v checkupdates` succeeds. `checkupdates` aborts unless `fakeroot` is installed, and `fakeroot` is only an optdepend of `pacman-contrib`. On a host that has `pacman-contrib` but not `fakeroot`, every pacman inventory is recorded as a failed backend and the cached `pacman -Qu` query is never attempted, although that query still works on the same host.

## Affected code and documentation

- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): `_upkg_run_outdated_pacman` — the `command -v checkupdates` guard, the `CHECKUPDATES_DB=… checkupdates` invocation, and the `failed` branch that runs before any cached fallback. The `pacman -Qu` path is reachable only when the helper is absent entirely.
- [scripts/check-deps.sh](../../scripts/check-deps.sh): the pacman optional-tool check verifies `checkupdates` but never `fakeroot`, so the same incomplete assumption is reported as a healthy setup.
- [GUIDE.md](../../GUIDE.md): the pacman inventory section documents the `checkupdates` preference, the private per-call database, and the failure contract, but not the helper's own runtime requirement.

## Trigger and reproduction

Prerequisites: an Arch-family host with `pacman-contrib` installed and `fakeroot` absent. The reproduction does not need that host: a PATH stub is sufficient.

1. In a fresh `zsh -f` shell at the repository root, source `init.zsh` and load the package domain.
2. Place a stub `checkupdates` on `PATH` that exits `1` with `Cannot find the fakeroot binary` on stderr, and ensure no `fakeroot` is on `PATH`.
3. Run `upkg outdated --only pacman` and inspect the recorded state, the summary, and the exit status.

Observed at the baseline by inspection: the state is `failed` with `checkupdates failed`, the cached-query fallback never runs, and the aggregate status is nonzero. Expected: either a capability guard that also requires `fakeroot`, falling back to the cached inventory with the documented cached-metadata labeling, or an unmet-dependency diagnostic that names `fakeroot`.

Evidence limit: `checkupdates` requiring `fakeroot` is established from the pacman-contrib helper and its optdepend; no Arch host was available to run the native command during this audit.

## Current behavior and impact

A user with a working pacman setup loses the entire pacman inventory when `fakeroot` is missing, which is a regression against the cached `pacman -Qu` path that still succeeds on the same host. The failure is also misdiagnosed: the message names `checkupdates`, not the missing dependency. Because `scripts/check-deps.sh` reports the same setup as healthy, the user gets no hint about the missing optdepend.

## Root cause

The capability check tests that the helper exists on `PATH`, not that it can execute. The fallback decision is driven by the helper's absence rather than by its ability to run, so a helper that is present but non-functional displaces a working query.

## Fix goal and expected behavior

`checkupdates` is used only when it can actually run. When `fakeroot` is unavailable, the backend falls back to the cached `pacman -Qu` inventory with the labeling already documented for the no-helper case, or, if a fallback is judged inappropriate, fails with a diagnostic that names the missing dependency. A genuine refresh failure with a working `checkupdates` stays a failure; the no-silent-fallback contract is unchanged. `scripts/check-deps.sh` names `fakeroot` as the requirement behind `checkupdates`.

### Review comment — 2026-09-30

**Assessment:** Dependency/setup guidance gap; failure diagnostic already works.

**Evidence:** Native checkupdates requires fakeroot. A PATH-stubbed missing-fakeroot diagnostic was preserved on stderr, with state failed and nonzero status. The repository does not currently advertise that dependency in its checkupdates setup hints. See [checkupdates source](https://raw.githubusercontent.com/archlinux/pacman-contrib/master/src/checkupdates.sh.in) and [Arch package metadata](https://archlinux.org/packages/extra/x86_64/pacman-contrib/).

**Reviewed scope and expected behavior:** The claim that this failure is not visibly explained is incorrect. The goal already permits a clear failure, whereas the acceptance criteria mandate cached fallback; those requirements conflict. Add setup/dependency guidance and, if desired, a capability check. A cached fallback must remain explicitly stale and labelled; do not silently replace the documented fresh query with cached data.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep the guard style required by [AGENTS.md](../../AGENTS.md): `command -v` inside function bodies.
- Preserve the documented separation between a fresh separate database and cached metadata, including the wording that distinguishes them.
- Do not weaken the existing rule that a failed refresh is a failure; do not make the live pacman database the refresh target.
- Preserve cancellation statuses 129, 130, and 143 on all paths.
- Update GUIDE and the tips catalogue at their ownership level if the chosen behavior changes user-visible text.

## Acceptance criteria

- [ ] A host with `checkupdates` present but `fakeroot` absent no longer records a bare failed pacman inventory.
- [ ] The fallback produces the cached-inventory labeling already documented for a missing helper.
- [ ] When both are absent, behavior is unchanged from the current no-helper path.
- [ ] A genuine `checkupdates` refresh failure with `fakeroot` present still records a failure.
- [ ] `scripts/check-deps.sh` reports the `fakeroot` requirement alongside `checkupdates`.
- [ ] The regression suite reproduces the missing-`fakeroot` case against the audited behavior.

## Validation plan

Add a fixture to `scripts/test-package-audit.zsh` that stubs `checkupdates` to exit nonzero with the fakeroot diagnostic and omits `fakeroot` from `PATH`, then asserts the selected path, the recorded state, and the aggregate status. Assert the no-helper path is unaffected. Run `zsh scripts/run-tests.zsh`. Optional isolated native check on an Arch host with `pacman-contrib` installed and `fakeroot` removed.

## References

- [checkupdates manual](https://man.archlinux.org/man/checkupdates.8.en)
- Related: [ZSH-026](026-guide-optional-integration-table-missing-checkupdates.md) (GUIDE's optional-integration table), [ZSH-030](030-checkupdates-resyncs-repositories-per-run.md) (the same helper's per-call refresh cost)
- [AGENTS.md](../../AGENTS.md) guard rules for startup-time and function-body probes
