# ZSH-022: cgm unset and delete refuse attributed scalar credentials

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P1 — a user cannot remove a credential from the shell through the tool, and `cgm delete` can clear storage while leaving the value live |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `cgm unset`; `cgm delete` |
| Evidence | Reproduced end-to-end against the real `cgm unset` path on this host; established by source inspection for `cgm delete` |

## Summary

The attribute allowlist tightened for the credential-storing path is shared by the removal paths. It accepts only the exact parameter kinds `scalar`, `scalar-export`, `scalar-local`, and `scalar-local-export`, so any parameter carrying another attribute — case conversion, justification, padding, uniqueness, or a trace attribute — is rejected. A credential the user declared with such an attribute can no longer be unset, and `cgm delete` clears the Secret Service entry before discovering the same rejection, leaving the value live in the shell while reporting a partial failure.

## Affected code and documentation

- [62-cgm.zsh](../../62-cgm.zsh): `_cgm_validate_export_name`, which now enumerates exact parameter kinds; `_cgm_require_export_name`, which reports the rejection; `_cgm_unset`; and `_cgm_delete`, whose unset step runs after the Secret Service clear.
- [scripts/test-cgm.zsh](../../scripts/test-cgm.zsh): the attribute fixtures, which cover the store and export paths.
- [GUIDE.md](../../GUIDE.md): `cgm unset`, `cgm delete`, and the parameter-shape requirements for credential variables.

## Trigger and reproduction

`cgm unset`, on a host with a working `secret-tool`:

1. In a fresh shell with this configuration loaded, declare `typeset -u CGM_TOKEN=abc`.
2. Run `cgm unset CGM_TOKEN`.

Observed at the baseline:

```
kind: scalar-upper
cgm: refusing to replace a non-scalar, special, read-only, or attributed Zsh parameter: CGM_TOKEN
cgm unset rc=1
still set? 1
```

Expected: the attribute is unrelated to credential storage, so the unset proceeds.

`cgm delete`, by source inspection: `secret-tool clear` runs first, then the unset step calls the same validator. On rejection the shell prints `deleted … from Linux Secret Service, but could not unset it from this shell.` and adds the name to the retained list.

Isolation: use a synthetic variable name and a synthetic value. Do not touch a real credential store when reproducing the delete path.

## Current behavior and impact

A user who declared a credential with a shell attribute cannot remove it from the shell using the tool, and gets a message describing the value as non-scalar or attributed, which does not explain that the removal path is the problem. For `cgm delete`, storage and shell state diverge: the credential is gone from Secret Service but still present in the environment, which is the opposite of what a delete is expected to achieve, and the nonzero status arrives after the irreversible step. The user cannot remediate through the documented interface and must unset the parameter by hand.

## Root cause

The allowlist was written to protect a specific operation: storing a value must not let zsh transform the assigned bytes, so a case-converting or padding parameter would corrupt or truncate what is saved. That requirement belongs to the store path. It was implemented in `_cgm_validate_export_name`, which is also the validator consulted by unset and delete, where no assignment from user input occurs and only the attribute-based transformation of the cleared value matters. Tightening the shared helper therefore widened the rejection surface beyond the operation it was designed for.

## Fix goal and expected behavior

Removal must work for any parameter that can hold a credential value, regardless of presentation attributes. `cgm unset` must clear the parameter and report success. `cgm delete` must not clear storage unless it can also clear the shell state, or must clear the shell state first; a partial outcome must be reported before the irreversible step, not after it. The store path must keep rejecting parameters whose attributes would transform the value being saved.

### Review comment — 2026-09-30

**Assessment:** Confirmed removal restriction; revise severity and deletion policy.

**Evidence:** The independent reviewer reproduced rejection of ordinary attributed scalar credentials in both `cgm unset` and the shell-removal stage of `cgm delete`. Attribute restrictions needed for assignment/export were reused unnecessarily for ordinary unset.

**Reviewed scope and expected behavior:** P2 is supported; the report does not establish P1 severity. Its all-or-nothing deletion goal conflicts with the existing documented and tested partial-deletion contract: storage may be deleted while a readonly/unsafe current-shell variable is retained, with a diagnostic and nonzero status. See GUIDE’s cgm deletion notes and the readonly partial-deletion regression in `scripts/test-cgm.zsh`. Separate removal validation from assignment validation, retain protection for unsafe parameters, and preserve that contract unless a policy change is explicitly chosen. The assignment protection concerns credential export, not transformation of the backend’s stored value.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep the store-path protection intact: a parameter that would transform an assigned credential value must still be refused before any lookup or write.
- Do not add a plaintext fallback, a reveal command, or an `eval`-based export path.
- Keep the unset path free of value expansion: inspect parameter attributes without printing or expanding the value.
- Preserve the existing refusal for read-only, special, and non-scalar parameters.
- Do not leave `xtrace` enabled on any path.
- Update GUIDE.md so the documented requirement is scoped to the operation it describes.

## Acceptance criteria

- [ ] `cgm unset` clears a credential declared with `-u`, `-L`, `-R`, `-Z`, or a similar non-storage attribute.
- [ ] `cgm delete` removes the shell value as well as the stored entry for such a parameter.
- [ ] `cgm delete` never clears storage while the shell value remains, or reports the divergence before clearing.
- [ ] The store path still refuses a parameter whose attribute would transform the saved value.
- [ ] Read-only, special, and non-scalar parameters remain refused on every path.
- [ ] No path expands or prints a credential value.

## Validation plan

Extend `scripts/test-cgm.zsh` with removal cases across the attribute families already used for the store-path fixtures, asserting both the shell state and the reported status, and a delete case asserting that storage and shell state stay consistent. Use synthetic values and a fake Secret Service backend. Run `zsh scripts/run-tests.zsh`.

## References

- [GUIDE.md](../../GUIDE.md) credential workflow
- [Zsh parameters and attributes](https://zsh.sourceforge.io/Doc/Release/Parameters.html)
- Related: ZSH-004 (transformed scalar exports, repaired at this baseline) — the store-path requirement this change extended too far
