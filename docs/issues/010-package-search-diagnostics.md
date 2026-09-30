# ZSH-010: Package search backends parse stderr diagnostics as package data

| Field | Value |
| --- | --- |
| Status | Open; not fixed by this documentation change |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `12e276a` |
| Affected surface | upkg search with APT, Pacman, Paru, Homebrew, Flatpak, or npm |
| Evidence | Reproduced during audit; independently checked by a review subagent |

## Summary

Several search backends merge stdout and stderr before parsing package records. A successful command that emits a warning can create fabricated package rows. Homebrew treats warning words as package candidates and can turn a successful search into a failed metadata lookup.

## Affected code and documentation

- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): `_upkg_run_search_apt`, `_upkg_run_search_pacman`, `_upkg_run_search_paru`, `_upkg_run_search_brew`, `_upkg_run_search_flatpak`, and `_upkg_run_search_npm`.
- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): `_upkg_capture_query`, row aggregation, and search result state.
- [scripts/test-upkg.zsh](../../scripts/test-upkg.zsh) and [scripts/test-package-audit.zsh](../../scripts/test-package-audit.zsh): search fixtures.
- [GUIDE.md](../../GUIDE.md): search results and diagnostics.

## Trigger and reproduction

Use temporary fake binaries; do not search real registries.

1. Load the package domain using `source 60-functions.zsh` followed by `upkg help`.
2. Stub each of `apt`, `pacman`, `paru`, `flatpak`, and `npm` to write only `warning: optional configuration is deprecated` to stderr and return 0.
3. Clear `_UPKG_SEARCH_ROWS=()` before each backend call and run `_upkg_run_search_<manager> example`.
4. Inspect row count and row contents. Audit result: each backend returned success with one fabricated row. APT/Arch rows used `warning:` as a package name; Flatpak/npm used the whole warning line as an identifier.
5. For Homebrew, stub both search calls to emit `Warning: optional setting deprecated` on stderr and return 0. Make fake `brew info` log arguments and return 1.
6. Run `_upkg_run_search_brew example`. Audit result: it invoked `info --formula Warning: optional setting deprecated` and reported failure.

## Current behavior and impact

Warnings appear as installable-looking search entries or descriptions. The result count and successful-search state become false. Homebrew additionally makes metadata requests using diagnostic tokens as names. Real matches can coexist with the corrupted rows, making the defect harder to notice.

## Root cause

The affected commands use `2>&1`. Their parsers assume nonempty lines or tokens are records, often without checking native record structure. APT removes one known warning string, which does not cover other legitimate diagnostics. DNF search already separates streams and is a useful local pattern.

## Fix goal and expected behavior

Only validated stdout records may become search rows. Preserve stderr diagnostics on stderr, including successful-command warnings. A successful empty search with warnings must remain no matches. For Homebrew, only actual package candidates may be passed to metadata lookup.

## Implementation constraints

- Preserve each backend's documented no-match exit convention and cancellation handling.
- Separate streams using the shared query helper where compatible.
- Validate expected fields before creating rows; do not discard legitimate package names through an overly narrow schema.
- Keep PATH-based function-body guards working with test stubs.
- Audit Homebrew metadata output and Nix search separately for the same stream-merging pattern; the confirmed fabricated-row fixtures cover the six backends listed above.

## Acceptance criteria

- [ ] Warning-only success produces zero package rows for every affected backend.
- [ ] Warnings remain visible on stderr and never become descriptions or identifiers.
- [ ] Valid matches plus warnings preserve exactly the valid rows.
- [ ] Homebrew metadata calls contain only stdout-derived package candidates.
- [ ] Empty native searches keep their documented successful no-match state.
- [ ] Native errors and interrupts retain correct status and diagnostics.

## Validation plan

Add a common warning-only/valid-plus-warning/error matrix across affected backends in `scripts/test-upkg.zsh` or `scripts/test-package-audit.zsh`. Assert row contents, counts, stderr, state, and Homebrew argument logs. Run `zsh scripts/run-tests.zsh`.

## References

- [APT search manual](https://manpages.debian.org/stable/apt/apt.8.en.html)
- [Pacman manual](https://man.archlinux.org/man/pacman.8.en)
- [Paru manual source](https://github.com/Morganamilo/paru/blob/master/man/paru.8)
- [Homebrew manual](https://docs.brew.sh/Manpage)
- [Flatpak command reference](https://docs.flatpak.org/en/latest/flatpak-command-reference.html)
- [npm search output](https://docs.npmjs.com/cli/v11/commands/npm-search/)
