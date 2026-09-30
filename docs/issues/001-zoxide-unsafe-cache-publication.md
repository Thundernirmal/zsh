# ZSH-001: Zoxide publishes and sources through a rejected cache directory

| Field | Value |
| --- | --- |
| Status | Open; not fixed by this documentation change |
| Priority | P1 |
| Audit date | 2026-09-30 |
| Audited baseline | `12e276a` |
| Affected surface | Shell startup; zoxide integration |
| Evidence | Reproduced during audit; independently checked by a review subagent |

## Summary

A rejected persistent cache directory is still used for publication and activation. Falling back to a private temporary file does not prevent the generated integration from being moved into the unsafe destination and sourced there.

## Affected code and documentation

- [30-zoxide.zsh](../../30-zoxide.zsh): `_zsh_zoxide_cache_file_is_safe`, the cache-miss branch, and `_zsh_zoxide_activate_file`.
- [scripts/test-init.zsh](../../scripts/test-init.zsh): zoxide initialization and persistent-cache fixtures.
- [GUIDE.md](../../GUIDE.md): guarded integration and startup behavior.
- [AGENTS.md](../../AGENTS.md): owner-only, non-symlinked, validated cache requirements.

## Trigger and reproduction

Use a fresh `zsh -f` shell and a temporary directory. Do not alter the real cache.

1. Create `scratch/bin`, `scratch/cache/zsh`, and `scratch/shared`.
2. Make `scratch/cache/zsh/zoxide` a symlink to `scratch/shared`.
3. Put an executable fake `zoxide` in `scratch/bin`. For `init zsh`, it must print valid definitions: `z() { :; }`, `__zoxide_zi() { :; }`, and `zi() { __zoxide_zi "$@"; }`.
4. Prepend the fake binary directory to `PATH`, set `XDG_CACHE_HOME` to the absolute temporary cache path, and source `30-zoxide.zsh` in the fresh shell.
5. Inspect `scratch/shared` for `init-*.zsh` files. Optionally add a harmless marker assignment to the generated integration to verify activation.

Audit result: a generated cache file appeared in the symlink target and the integration was activated from that persistent location. Only benign generated code was used; no injected attack payload was necessary.

## Current behavior and impact

The directory is rejected for temporary-file creation, but still receives the published integration. If the target directory permits another user to replace files, that user can replace the integration before it is sourced. The existing syntax check applies to the earlier temporary file and does not establish that the later source path is private. This is a shell-code execution exposure under an unsafe-cache-path configuration.

## Root cause

The persistent cache filename remains populated after the directory safety checks fail. Later publication tests only whether that filename is nonempty and whether `mv` succeeds. Publication and sourcing are therefore detached from the result of the directory validation.

## Fix goal and expected behavior

Generated integration may be persisted only into a verified private cache directory. If directory eligibility cannot be established safely, validate and activate the private temporary file directly, then remove it. Fallback handling must not publish, source, or delete integration files through a rejected directory. An invalid or unsafe cache file inside a verified private directory may be replaced with newly validated integration; rejecting that file does not by itself prohibit safe directory-based cache repair.

## Implementation constraints

- Preserve executable-fingerprint cache keys, fixed absolute cache roots, syntax validation, atomic publication, and quiet non-prompt startup.
- Carry an explicit successful-persistence eligibility result to publication; a nonempty filename is insufficient.
- Keep fallback files private and clean them up on success and failure.
- Preserve existing rollback of public functions and hook arrays if activation fails.
- Do not introduce `eval`, runtime downloads, or arbitrary integration discovery.

## Acceptance criteria

- [ ] A symlinked cache directory receives no generated files and is never used for activation.
- [ ] A rejected directory ownership or permission condition cannot reach persistent publication or deletion.
- [ ] With an unsafe persistent path, valid generated code can still initialize through the private temporary fallback.
- [ ] Temporary fallback files are removed after activation or failure.
- [ ] A safe cold cache is published privately; a safe warm cache avoids regeneration.
- [ ] An invalid cache file inside a verified private directory can be repaired without bypassing file validation or following a destination symlink.
- [ ] Malformed or runtime-failing integration leaves no partial functions or hooks.

## Validation plan

Extend `scripts/test-init.zsh` with rejected-directory fixtures and record both the publication destination and activation path. Use fake zoxide output, isolated caches, and existing strict-shell cases. Test a non-owner directory only where a fixture can create one without privileged host changes. Run `zsh scripts/run-tests.zsh` after the fix.

## References

- [Repository integration requirements](../../AGENTS.md)
- [Zoxide shell setup](https://github.com/ajeetdsouza/zoxide#step-2-add-zoxide-to-your-shell)
- [Zsh source builtin](https://zsh.sourceforge.io/Doc/Release/Shell-Builtin-Commands.html)
