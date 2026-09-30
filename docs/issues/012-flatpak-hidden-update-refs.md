# ZSH-012: Flatpak update inventory hides installed extension and secondary-architecture updates

| Field | Value |
| --- | --- |
| Status | Open; not fixed by this documentation change |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `12e276a` |
| Affected surface | upkg outdated --only flatpak; Flatpak update inventory |
| Evidence | Official manual and upstream source inspection; regression fixture specified |

## Summary

The Flatpak backend calls `remote-ls --updates` without `--all`. Flatpak's default presentation hides locale/debug extensions and some secondary-architecture refs even when they have updates. An inventory containing only such updates can therefore be reported as up to date.

## Affected code and documentation

- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): `_upkg_run_outdated_flatpak`.
- [scripts/test-upkg.zsh](../../scripts/test-upkg.zsh) and [scripts/test-package-audit.zsh](../../scripts/test-package-audit.zsh): Flatpak query fixtures.
- [GUIDE.md](../../GUIDE.md): Flatpak inventory and native upgrade scope.

## Trigger and reproduction

The audit confirmed this filtering in the official manual and upstream implementation; it did not alter a live Flatpak installation.

For a deterministic regression fixture:

1. Model an installed locale/debug extension with an available newer commit and its parent ref present in the remote.
2. Make fake `flatpak remote-ls --updates` return empty stdout and status 0, matching native default hiding.
3. Make the same mock return the extension row when `--all` is included.
4. Run the inventory backend and inspect its query arguments and state.

Current result: the query lacks `--all`, receives empty output, and reports up to date.

For an optional real integration check, use a disposable installation and local remote with differing installed/remote commits. Compare `flatpak remote-ls --updates` against `flatpak remote-ls --updates --all`; do not update or reconfigure the user's installation.

## Current behavior and impact

The preview is narrower than the installed refs that native upgrade can process. Users may skip upgrades based on a false up-to-date summary. Hidden refs can also include end-of-life entries in current upstream code; presentation filters should not be treated as complete update inventory semantics.

## Root cause

The backend assumes that empty default `remote-ls --updates` output means no installed refs need updates. Upstream first checks whether a ref has an update, then independently applies the `!opt_all` hiding rules. `--updates` does not override those rules.

## Fix goal and expected behavior

Inventory must include installed updatable refs across the currently supported installation scope, including locale/debug extensions and installed supported secondary architectures. Add `--all` to the update query or use an equivalent complete native inventory. A true empty inventory remains up to date. Keep native transaction policy distinct from a list of available remote changes.

## Implementation constraints

- Preserve separate stdout/stderr handling and interrupt behavior.
- Keep installation scope aligned with the existing upgrade backend; named installation support is a separate scope decision.
- Prefer explicit ref columns if necessary to distinguish architecture, branch, and extension identities.
- Do not claim the inventory is a dependency-resolved transaction plan or guarantees an upgrade can succeed.
- Keep this query non-installing and non-removing.

## Acceptance criteria

- [ ] The native query explicitly includes hidden update refs, normally via `--all`.
- [ ] An extension-only update results in updates available.
- [ ] An installed secondary-architecture update is not suppressed by the primary architecture's presence.
- [ ] A genuinely empty complete inventory results in up to date.
- [ ] Query errors and warnings retain correct status and stream handling.
- [ ] The inventory still uses the documented installation scope.

## Validation plan

Add exact-argument assertions and extension-only/secondary-architecture fixtures to package tests. Keep live repository setup optional and isolated; upstream source review supports the native filtering expectation. Run `zsh scripts/run-tests.zsh`.

## References

- [Flatpak remote-ls manual, --all and --updates](https://docs.flatpak.org/en/latest/flatpak-command-reference.html)
- [Upstream filtering implementation](https://github.com/flatpak/flatpak/blob/main/app/flatpak-builtins-remote-ls.c)
