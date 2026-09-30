# ZSH-018: Nix search replays captured evaluation progress to the terminal

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `upkg search` with Nix; `_upkg_run_search_nix` |
| Evidence | Reproduced with native Nix on this host, end-to-end through the repository function |

## Summary

`_upkg_run_search_nix` captures the native command's stderr and then prints it back to the terminal. `nix search` writes one progress line per evaluated attribute to stderr, so a single search replays tens of thousands of lines and several megabytes of `evaluating '…'` text. Before this change the captured stderr fed the row parser only and was never echoed.

## Affected code and documentation

- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): `_upkg_run_search_nix` and the `[[ -z $diagnostic ]] || print -u2 -r -- "$diagnostic"` replay that the search backends share.
- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): `_upkg_capture_query`, which captures both streams and returns them to the caller.
- [GUIDE.md](../../GUIDE.md): search diagnostics are documented as remaining visible on stderr.

## Trigger and reproduction

Native volume, with a working Nix installation and network access:

```
nix --extra-experimental-features 'nix-command flakes' search nixpkgs ripgrep
```

Observed on this host: 25 stdout lines and 123,088 stderr lines totalling 8,681,733 bytes.

Repository behavior, in a fresh `zsh -f` shell at the repository root:

1. `source init.zsh`, then load the package domain.
2. `_upkg_run_search_nix ripgrep >/tmp/out 2>/tmp/err`, then measure both files.

Observed at the baseline: `stdout 0 lines`, `stderr 123088 lines (8681733 bytes)`. Expected: native diagnostics preserved, evaluation progress not replayed.

## Current behavior and impact

The user's terminal is flooded with evaluation progress that they never saw before the change, pushing the actual search results off screen and making the command appear to hang or malfunction. The text is emitted on stderr, so it does not corrupt the result rows or a piped stdout, but it dominates any interactive use of `upkg search --only nix` and inflates logs. The same unconditional replay applies to every other captured backend diagnostic, which is appropriate for short warnings and inappropriate for per-attribute progress.

## Root cause

The fix for diagnostics-as-package-data separated the two streams, then treated the whole captured diagnostic buffer as text worth showing. `nix search` uses stderr as a progress channel, not only as an error channel, so "non-empty stderr implies a message worth reprinting" does not hold for this backend.

## Fix goal and expected behavior

Legitimate short diagnostics must remain visible on stderr. Per-attribute evaluation progress must not be replayed. When the native command fails, its error output must still reach the user. When the native command succeeds, the command must produce results without emitting progress noise.

### Review comment — 2026-09-30

**Assessment:** Confirmed progress-output defect; preserve actual errors.

**Evidence:** A small native Nix 2.34.8 search using a local expression emitted one result on stdout and per-attribute evaluation messages on stderr. The backend replays that stderr. This independently confirms the mechanism without reevaluating the full nixpkgs catalogue or verifying the report’s exact volume.

**Reviewed scope and expected behavior:** Zero direct stdout from this internal backend is expected: it populates `_UPKG_SEARCH_ROWS`, and the public command renders those rows later. It is not evidence of lost results. Prefer native progress/verbosity control where available; arbitrary truncation must not hide genuine errors. The [Nix search source](https://raw.githubusercontent.com/NixOS/nix/master/src/nix/search.cc) emits per-attribute activities at talkative level.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep diagnostics off the package-record path; stdout parsing must not regress.
- Keep the existing no-match detection, which already matches against the combined captured text.
- Do not discard the error text for a genuine failure.
- Prefer a bounded or filtered replay over an unconditional dump, and keep it cheap: no per-line subshell or external process for a 100,000-line buffer.
- Document the resulting behavior in GUIDE.md alongside the other backend notes.

## Acceptance criteria

- [ ] A successful Nix search prints no evaluation progress and no more than a small bounded diagnostic volume.
- [ ] A failing Nix search still surfaces its error text on stderr.
- [ ] Package rows and the search state are unchanged by the filtering.
- [ ] The no-match classification still uses the native text it depends on.
- [ ] A regression fixture with a large synthetic stderr stream asserts the printed volume, not only the parsed rows.

## Validation plan

Add a fixture in `scripts/test-package-audit.zsh` whose fake `nix search` writes many progress lines plus a short warning to stderr, then assert the parsed rows, the state, the presence of the warning, and the absence of the progress lines. Run `zsh scripts/run-tests.zsh`, and optionally re-measure with a real `nix search`.

## References

- [nix search documentation](https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-search.html)
- [GUIDE.md](../../GUIDE.md) search diagnostics notes
