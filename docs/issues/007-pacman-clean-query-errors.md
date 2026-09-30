# ZSH-007: Pacman cleanup classifies orphan-query errors as successful cleanup

| Field | Value |
| --- | --- |
| Status | Open; not fixed by this documentation change |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `12e276a` |
| Affected surface | upkg clean --only pacman |
| Evidence | Reproduced during audit; independently checked by a review subagent |

## Summary

Pacman's orphan query uses status 1 for an empty selection, but can also fail with that status and an error on stderr. The cleanup backend treats every status-1, empty-stdout result as no orphans, allowing a failed cleanup phase to become an overall successful cleanup.

## Affected code and documentation

- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): `_upkg_run_clean_pacman` and `_upkg_finish_cleanup_result` calls.
- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): query capture and summary state helpers.
- [scripts/test-upkg.zsh](../../scripts/test-upkg.zsh): cleanup failure and empty-query cases.
- [GUIDE.md](../../GUIDE.md): cleanup phases, status, and partial failures.

## Trigger and reproduction

Use a PATH-stubbed Pacman binary in a temporary test directory; do not run cleanup against the real package database.

1. Load the package domain with `source 60-functions.zsh` and `upkg help`.
2. Make fake `pacman -Qtdq` emit `error: failed to read local package database` on stderr, emit nothing on stdout, and exit 1.
3. Make fake `pacman -Sc` exit 0 and record that it was called.
4. Override manager detection to select only Pacman. Override `_upkg_is_root` to return 0 inside the test shell so privilege logic cannot invoke real sudo.
5. Run `upkg clean --only pacman` and inspect its exit status and `_UPKG_SUMMARY_STATE[pacman]`.

Audit result: the error was printed, but cleanup returned 0 and the summary state was `cleaned`.

## Current behavior and impact

A genuine local database error is followed by `No orphaned packages found` and successful overall cleanup. Users and automation receive a false success signal even though unused-package discovery failed. Cache cleanup may still succeed, but it must not erase the failed phase from the result.

## Root cause

The command substitution captures stdout only. The status-1 branch checks only whether that stdout is empty. The backend never classifies the accompanying stderr before incrementing its successful-phase count.

## Fix goal and expected behavior

A valid empty orphan query is successful; a query error is a failed cleanup phase. Preserve the backend's documented continue-on-ordinary-error policy for independent cache cleanup, but return nonzero and report partial or failed cleanup when discovery fails. Preserve native diagnostics on stderr.

## Implementation constraints

- Reuse separate stdout/stderr capture where appropriate.
- Do not treat every nonempty stderr message as fatal; distinguish supported benign warnings from actual errors.
- Preserve interrupt handling and never continue after cancellation.
- Keep orphan package arguments separate and retain the native removal confirmation.
- Do not change privilege authorization or cache-cleanup scope.

## Acceptance criteria

- [ ] Status 1 with a real error diagnostic is not reported as no orphans.
- [ ] If cache cleanup succeeds after query failure, the summary records partial cleanup and returns nonzero.
- [ ] A genuine empty query remains successful.
- [ ] Supported warning-only empty results do not become fabricated package names.
- [ ] Successful orphan lists are passed as separate removal operands.
- [ ] Cancellation stops later cleanup phases.

## Validation plan

Extend `scripts/test-upkg.zsh` with empty success, documented no-match status, benign warning, database error, populated success, and cancellation fixtures. Assert stderr, summary state, return status, and command order. Run `zsh scripts/run-tests.zsh`.

## References

- [Pacman manual](https://man.archlinux.org/man/pacman.8.en)
- [Current cleanup workflow](../../GUIDE.md)
