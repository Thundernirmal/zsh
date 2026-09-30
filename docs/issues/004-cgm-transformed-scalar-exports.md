# ZSH-004: CGM exports can transform or truncate credential values

| Field | Value |
| --- | --- |
| Status | Open; not fixed by this documentation change |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `12e276a` |
| Affected surface | cgm env; cgm env --all |
| Evidence | Reproduced during audit; independently checked by a review subagent |

## Summary

Credential export validation accepts scalar parameters whose attributes transform assignments. Exporting into a left-justified, right-justified, uppercase, or lowercase parameter can change the retrieved value while CGM reports successful loading.

## Affected code and documentation

- [62-cgm.zsh](../../62-cgm.zsh): `_cgm_validate_export_name`, `_cgm_export_one`, and `_cgm_env`.
- [scripts/test-cgm.zsh](../../scripts/test-cgm.zsh): fake Secret Service, parameter validation, and atomic batch loading.
- [GUIDE.md](../../GUIDE.md): credential loading and parameter safety.

## Trigger and reproduction

Use the fake `secret-tool` fixture pattern from `scripts/test-cgm.zsh`; never query a real stored credential.

1. Start a fresh Zsh shell and source the CGM module with a mock backend and an isolated name catalogue.
2. Configure mock lookup of `TOKEN` to return the synthetic single-line value `supersecret`.
3. Declare `typeset -L4 TOKEN=old` in the caller shell.
4. Run `cgm env TOKEN`, capture the status and success message, and compare the resulting value against the synthetic fixture.
5. Repeat in a separate fresh shell with `typeset -u TOKEN=old`.

Audit result: the width-limited parameter became `supe`; the uppercase parameter became `SUPERSECRET`. Both calls returned success. A minimal cause-level check is `_cgm_validate_export_name TOKEN` followed by `_cgm_export_one TOKEN supersecret` with those parameter attributes.

## Current behavior and impact

Applications receive a different credential from the one stored in the backend, causing authentication failures. CGM's success message hides the corruption. A batch containing a transforming parameter also violates the expectation that every exported value equals its validated lookup result.

## Root cause

The name validator rejects readonly, special, and non-scalar parameters but allows every kind beginning with `scalar`. The export helper uses `typeset -gx` without rejecting or neutralizing existing value-transforming attributes.

## Fix goal and expected behavior

A successful credential load must export exactly the validated single-line backend value. Choose and document one policy: reject incompatible existing attributes before any lookup, or safely remove those attributes while preserving batch atomicity. Rejection is the narrower policy and avoids silently changing caller declarations. Unsupported parameters must remain unchanged and must not produce a success message.

## Implementation constraints

- Validate the complete requested batch before lookups or mutations.
- Keep readonly, special, and non-scalar rejection intact.
- Preserve ordinary exported scalars, duplicate-name handling, and name-only catalogues.
- Keep xtrace disabled throughout secret retrieval and assignment.
- Do not print credential values in errors or production diagnostics.

## Acceptance criteria

- [ ] Width, justification, uppercase, lowercase, and other assignment-transforming attributes cannot cause a successful corrupted export.
- [ ] Ordinary scalar exports exactly match the backend fixture.
- [ ] One incompatible parameter in a batch leaves every requested parameter unchanged.
- [ ] Under the rejection policy, no lookup occurs for a rejected batch.
- [ ] Error messages identify the parameter and reason without exposing its value.
- [ ] Existing single-line, empty-value, subshell, and xtrace protections still pass.

## Validation plan

Add attribute-matrix cases to `scripts/test-cgm.zsh`, checking parameter metadata, exact synthetic values, backend call counts, status, and all-or-nothing batch behavior. Keep values synthetic and the catalogue temporary. Run `zsh scripts/run-tests.zsh`.

## References

- [Zsh typeset and parameter attributes](https://zsh.sourceforge.io/Doc/Release/Shell-Builtin-Commands.html)
- [Repository credential safety requirements](../../AGENTS.md)
