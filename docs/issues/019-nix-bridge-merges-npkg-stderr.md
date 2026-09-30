# ZSH-019: The upkg Nix bridge merges npkg diagnostics into update-inventory stdout

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `upkg outdated --only nix`; the upkg Nix bridge |
| Evidence | Reproduced with a stubbed `npkg` writing to stderr; established by source inspection |

## Summary

`_upkg_run_outdated_nix` redirects the `npkg outdated` bridge with `2>&1` into one buffer and then prints that buffer to stdout. Diagnostics that npkg writes to stderr become report data on the inventory stream. This contradicts the stream-separation contract the same series established for the other backends and the behavior GUIDE now documents.

## Affected code and documentation

- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): `_upkg_run_outdated_nix` — the `npkg outdated >"$output_file" 2>&1` invocation and the subsequent `print -r -- "$output"` replay.
- [lib/functions-nix.zsh](../../lib/functions-nix.zsh): `_npkg_outdated`, which owns the internal `current` / `changed` / `partial` state and writes its own diagnostics to stderr.
- [GUIDE.md](../../GUIDE.md): the statement that query diagnostics stay on stderr and are kept separate from package rows.
- [scripts/test-package-audit.zsh](../../scripts/test-package-audit.zsh): Nix update-inventory fixtures.

## Trigger and reproduction

In a fresh `zsh -f` shell at the repository root:

1. `source init.zsh`, then load the package domain.
2. Define a stub: `npkg() { print -u2 'npkg: Failed to read Nix profile.'; return 1 }`.
3. Run `_upkg_run_outdated_nix` with stdout and stderr separated.

Observed at the baseline: the captured stdout contains `==> Nix (npkg)` followed by `npkg: Failed to read Nix profile.`, and the captured stderr is empty. Expected: the diagnostic appears on stderr and never in the inventory stream.

## Current behavior and impact

Any consumer of the inventory stream — a pipe, a redirect, an editor, or a script — receives error text where package rows are expected. `upkg outdated --only nix 2>/dev/null` hides the real diagnostic while still showing it as data. A warning on an otherwise successful run is likewise promoted into the report body. The result is a mixed stream that cannot be parsed reliably and that contradicts the documented contract, making the Nix backend the one exception to a rule the rest of the series enforces.

## Root cause

The bridge predates the stream-separation work and was not updated with the other backends. It needs a single merged buffer because the internal npkg state is consumed from the same invocation, so the merge was convenient, and the replay inherited stdout as its destination.

## Fix goal and expected behavior

Package inventory rows and bridge progress belong on stdout. npkg diagnostics belong on stderr and must remain visible there. A successful run must produce no error text on stdout. A failing run must preserve both the diagnostic on stderr and the existing internal state handling driven by `_NPKG_OUTDATED_STATE`.

### Review comment — 2026-09-30

**Assessment:** Confirmed stream-separation defect; correct the state explanation.

**Evidence:** A mocked `npkg outdated` diagnostic reached stdout through `_upkg_run_outdated_nix` because the bridge uses `>"$output_file" 2>&1`. This reproduces the contamination without package operations.

**Reviewed scope and expected behavior:** Keeping `npkg` in the current shell preserves its result globals; merging its streams does not preserve those globals. Separate stdout and stderr capture while retaining the current-process invocation, partial-result state, diagnostics, and exit status.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Preserve the internal state contract: the bridge consumes `current`, `changed`, or `partial` rather than matching display text.
- Preserve cancellation propagation for statuses 129, 130, and 143.
- Keep the temporary-file handling and its cleanup on every path.
- Do not lose diagnostics: moving them to stderr must not make them disappear when stderr is not redirected.
- Update the GUIDE wording only if the observable contract changes; GUIDE already states the intended separation.

## Acceptance criteria

- [ ] A stubbed `npkg` writing only to stderr produces no diagnostic text on the bridge's stdout.
- [ ] The same diagnostic remains visible on stderr.
- [ ] Successful inventories preserve their rows and state exactly.
- [ ] Cancellation and failure statuses are unchanged.
- [ ] The temporary file is removed on success, failure, and cancellation.
- [ ] A regression asserts the stream of the diagnostic, not only its presence.

## Validation plan

Extend the Nix inventory fixtures in `scripts/test-package-audit.zsh` with a stderr-only diagnostic case and a valid plus diagnostic case, asserting stdout contents, stderr contents, state, and status separately. Run `zsh scripts/run-tests.zsh`.

## References

- [GUIDE.md](../../GUIDE.md) diagnostics and Nix bridge notes
- Related: ZSH-009 and ZSH-010 (npm and search diagnostics, repaired at this baseline) — the same contract for the other backends
