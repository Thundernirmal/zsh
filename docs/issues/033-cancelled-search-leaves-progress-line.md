# ZSH-033: A cancelled search leaves the rich progress line on screen

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `upkg search` in rich/theme mode with every manager except DNF |
| Evidence | Source inspection of every search backend comparing the interrupt check with the progress-line clear |

## Summary

Each search backend prints a transient `\r… Searching <manager>…` progress line and clears it with `_upkg_search_progress_clear` when the query returns. In every backend except DNF, the new `_upkg_check_interrupt "$rc" || return $?` line was inserted before the clear, so a cancelled query returns without erasing the line. The summary that is printed after the loop is then appended to the leftover progress text.

## Affected code and documentation

- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): `_upkg_run_search_apt`, `_upkg_run_search_pacman`, `_upkg_run_search_paru`, the Homebrew search paths, `_upkg_run_search_flatpak`, `_upkg_run_search_nix`, and `_upkg_run_search_npm`, where the interrupt check precedes `_upkg_search_progress_clear`. `_upkg_run_search_dnf` is the exception: it clears before checking.
- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): `_upkg_search_progress`, `_upkg_search_progress_clear`, and the post-loop summary printing that lands on the uncleared line.
- [55-ui-helpers.zsh](../../55-ui-helpers.zsh): the rich status metadata consulted when the summary is rendered.

## Trigger and reproduction

Prerequisites: a PATH stub for one manager and rich output enabled.

1. In a fresh `zsh -f` shell at the repository root, source `init.zsh`, load the package domain, and enable the theme/rich presentation used by the progress line.
2. Stub a non-DNF selected backend to exit `130` with no output while the progress line is active.
3. Run `upkg search sample --only <manager>` and inspect the final screen.

Observed at the baseline by inspection: the progress line is never cleared, so the summary text is written onto the same line, producing concatenated and misaligned output. Expected: the progress line is removed on every return path, cancelled or not, and the summary starts on a clean line.

Evidence limit: established by source inspection of the call ordering; the visual result in a real terminal was not captured during this audit.

## Current behavior and impact

Interrupting a search in rich mode corrupts the display: the stale `Searching …` fragment remains and the summary, failed-manager list, or cancellation notice is appended to it. DNF behaves correctly, so the same command behaves differently depending on which manager was interrupted. Plain mode is unaffected, which means the defect appears only for users of the rich presentation.

## Root cause

The interrupt check was added mechanically at the point where the captured result becomes available, ahead of the existing cleanup call. Because the check returns directly on cancellation, it bypasses the line-clearing step that assumed every path continued into the accounting code. The ordering is uniform in the other direction only for DNF, so the sequence was not applied consistently.

## Fix goal and expected behavior

`_upkg_search_progress_clear` runs on every return path, including cancellation and unexpected early returns, before any summary output. Ordering is consistent across all search backends. The cancelled state, the exit status, and the recorded result are unchanged.

### Review comment — 2026-09-30

**Assessment:** Confirmed rich-progress cleanup defect.

**Evidence:** A cancelled non-DNF search returned before clearing its progress line. The independent reviewer reproduced `Searching APT...No matches found across selected managers.` on one line; a progress stub recorded start without clear. DNF already clears before the interrupt check.

**Reviewed scope and expected behavior:** Clear started progress on every exit path, including cancellation, without changing the exit status. Keep this display fix distinct from ZSH-020’s summary classification.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep the progress line transient and absent in plain mode; do not add output in non-interactive runs.
- Preserve the existing cancellation statuses and the `cancelled` state; coordinate with [ZSH-020](020-interrupted-search-omitted-from-summary.md) and [ZSH-021](021-cancelled-counted-as-failed-in-rich-ui.md).
- Prefer a structure that cannot drift, such as clearing in an `always` block or in the caller, rather than repeating the ordering in each backend.
- Keep cursor and line handling safe when the terminal is not a TTY.

## Acceptance criteria

- [ ] A cancelled search leaves no progress-line text on screen in rich mode.
- [ ] The summary and cancellation notice begin on a clean line.
- [ ] Every search backend follows the same ordering, with no DNF-only exception.
- [ ] Plain-mode output is unchanged.
- [ ] Cancellation status and recorded state are unchanged.
- [ ] A regression covers at least one non-DNF backend with a stubbed cancellation.

## Validation plan

Add a fixture to `scripts/test-package-audit.zsh` that stubs a non-DNF backend to return `130` and asserts the progress line was cleared before the summary, using the same rich-mode harness the existing interface tests use. Run `zsh scripts/run-tests.zsh`. When a real fzf and PTY are available, the interface suite is not required for this change, but a manual rich-mode check is worth recording.

## References

- Related: [ZSH-020](020-interrupted-search-omitted-from-summary.md), [ZSH-021](021-cancelled-counted-as-failed-in-rich-ui.md), [ZSH-031](031-cancellation-inferred-from-child-status.md)
- [GUIDE.md](../../GUIDE.md) rich-output section
