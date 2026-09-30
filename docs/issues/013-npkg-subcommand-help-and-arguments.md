# ZSH-013: Nix helper subcommands perform work for help and ignore unsupported arguments

| Field | Value |
| --- | --- |
| Status | Open; not fixed by this documentation change |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `12e276a` |
| Affected surface | npkg refresh; npkg find/pick/fzf; npkg outdated/check/diff |
| Evidence | Reproduced during audit; independently checked by a review subagent |

## Summary

Some helper-owned Nix subcommands do not parse their arguments. `refresh --help` invokes refresh, picker help becomes a search query, and outdated arguments are silently discarded. A request for help can therefore evaluate Nix or refresh caches instead of explaining usage.

## Affected code and documentation

- [lib/functions-nix.zsh](../../lib/functions-nix.zsh): `npkg`, `_npkg_pick_installables`, refresh dispatch, and outdated dispatch.
- [66-compdefs.zsh](../../66-compdefs.zsh): `_zsh_npkg` help and argument descriptions.
- [scripts/test-command-ux.zsh](../../scripts/test-command-ux.zsh), [scripts/test-upkg.zsh](../../scripts/test-upkg.zsh), and [scripts/test-completions.zsh](../../scripts/test-completions.zsh).
- [GUIDE.md](../../GUIDE.md): Nix helper commands, cache refresh, and native argument boundaries.

## Trigger and reproduction

Load the Nix domain directly with `source 60-functions.zsh` and `_zsh_functions_load nix` in a fresh test shell. This entry point loads the catalogue before loading the domain. Stub work functions before dispatch so no real Nix command runs.

1. Override `_npkg_refresh_index` to append `refresh` to a temporary call log and return 0.
2. Call `npkg refresh --help`. Audit result: refresh was called and the command printed `Refreshed nixpkgs attribute cache`.
3. Override `_npkg_pick_installables` to record its arguments. Call `npkg find --help`. Current dispatch forwards `--help` as a query. With a permitted picker, the implementation can request or refresh the attribute index.
4. Override `_npkg_outdated` to record invocation. Call `npkg outdated --profile /fixture/other`. Current dispatch invokes it with no arguments; the requested profile is ignored.

The helper never claimed support for arbitrary profile flags on every action. The defect is performing work for help or silently accepting unsupported input, rather than rejecting it.

## Current behavior and impact

Help can trigger network/cache work or a picker. Unsupported arguments appear accepted while the helper uses its ordinary current-profile scope. This is especially misleading for a profile-selection-looking argument. Completion advertises help, but dispatch does not consistently honor it.

## Root cause

Top-level help is handled only when the first word is a help command. Refresh and outdated call their implementations without checking remaining arguments. Picker dispatch joins remaining arguments into a search query without recognizing helper help.

## Fix goal and expected behavior

Helper-owned commands must handle `-h` and `--help` before backend calls, cache reads/writes, evaluation, or picker launch. Subcommands accepting no operands must reject extra arguments clearly and return nonzero. Picker query arguments must remain supported. Native passthrough subcommands must preserve their documented argument forwarding instead of having flags silently swallowed by a blanket parser.

## Implementation constraints

- Define help behavior per subcommand and alias, including refresh, outdated/check/diff, and find/pick/fzf.
- Do not introduce unsupported arbitrary-profile behavior as a side effect of fixing validation.
- Preserve direct native forwarding for list, search, add/remove, and upgrade where documented.
- Keep Nix optional and completion free of evaluation/network access.
- Update guide, completion, shared help, README, and tips at their intended detail level when behavior changes.

## Acceptance criteria

- [ ] Help for refresh, outdated aliases, and picker aliases returns usage with status 0 and no work calls.
- [ ] Help does not read or refresh attribute caches, run Nix, or launch fzf.
- [ ] Extra refresh/outdated operands and unsupported flags return nonzero before work.
- [ ] Picker queries still reach the picker unchanged under the documented help/option rules.
- [ ] Native passthrough commands retain the expected operands and flags.
- [ ] Completion and help descriptions match the implemented argument contract.

## Validation plan

Add backend-call-log and cache-mutation assertions to command UX/Nix fixtures, including every alias, both help flags, unsupported arguments, valid picker queries, and native forwarding cases. Verify completion performs no work. Run `zsh scripts/run-tests.zsh`.

## References

- [Current Nix helper contract](../../GUIDE.md)
- [Nix command manual](https://nix.dev/manual/nix/latest/command-ref/new-cli/nix)
