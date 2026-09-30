# ZSH-003: Extraction follows input symlinks and removes their targets

| Field | Value |
| --- | --- |
| Status | Open; not fixed by this documentation change |
| Priority | P1 |
| Audit date | 2026-09-30 |
| Audited baseline | `12e276a` |
| Affected surface | extract on symlinked inputs |
| Evidence | Reproduced during audit; independently checked by a review subagent |

## Summary

The extraction helper resolves input symlinks before selecting and invoking a decompressor. This changes native bare-compression behavior: an input link that native gunzip refuses can cause the wrapper to decompress and remove the link target instead.

## Affected code and documentation

- [lib/functions-files.zsh](../../lib/functions-files.zsh): `archive=${archive_arg:A}` and the format dispatch.
- [scripts/test-command-ux.zsh](../../scripts/test-command-ux.zsh): temporary extraction fixtures.
- [GUIDE.md](../../GUIDE.md): native bare-compression semantics and source retention.

## Trigger and reproduction

Run in a fresh Zsh shell from the repository root; all source files are disposable fixtures.

```zsh
source "$PWD/60-functions.zsh"
scratch=$(mktemp -d /tmp/zsh-issue-symlink.XXXXXX) || exit 1
trap 'command rm -rf -- "$scratch"' EXIT
print -r -- sample > "$scratch/target"
command gzip "$scratch/target"
command ln -s "$scratch/target.gz" "$scratch/link.gz"
command gunzip "$scratch/link.gz"
print -r -- "native-status=$?"
extract "$scratch/link.gz"
print -r -- "wrapper-status=$?"
[[ -e "$scratch/target.gz" ]] || print compressed-target-removed
[[ -L "$scratch/link.gz" && ! -e "$scratch/link.gz" ]] && print dangling-link
```

Audit result: native gunzip returned `1` and retained the target; the wrapper returned `0`, removed `target.gz`, created `target`, and left `link.gz` dangling.

## Current behavior and impact

Extraction can modify a target outside the input link's directory even though the caller supplied only the link. The original compressed target disappears in the reproduced case. Resolving the input also makes suffix dispatch depend on the target name rather than the filename supplied by the user, so a valid archive-named link to a differently named target can select the wrong format or be rejected.

## Root cause

Zsh's `:A` modifier resolves symlinks. It is used before suffix dispatch and before the external tool sees the input, bypassing the tool's own treatment of symlink operands.

## Fix goal and expected behavior

The wrapper must not silently turn a symlink operand into a destructive operation on its target. Preserve a logical absolute input path for format selection and native dispatch, or reject unsupported input links explicitly before changing files. Bare-compression defaults must retain native link refusal. Any supported keep/destination link behavior must retain the target and have a defined output name and location.

## Implementation constraints

- Separate path normalization from symlink resolution; consider Zsh `:a` for a logical absolute path.
- Keep leading-dash filename handling safe.
- Do not replace native archive overwrite or path policies with an undocumented policy.
- Keep destination resolution separate from input identity.
- Define input-link handling for gzip, bzip2, and compress backends; do not assume identical native behavior.

## Acceptance criteria

- [ ] Default extraction of a gzip input symlink does not remove or alter its target.
- [ ] A rejected link returns nonzero before creating any output.
- [ ] Format dispatch uses the supplied filename under the chosen documented policy.
- [ ] Ordinary relative and absolute non-link inputs continue to work.
- [ ] Keep/destination behavior for links is either explicitly rejected or tested to retain the target and publish at the defined location.
- [ ] Existing-output refusal and leading-dash filename support remain intact.

## Validation plan

Extend extraction tests with links inside and outside the fixture directory, a target with a different suffix, dangling links, and ordinary files. Compare default bare-compression handling with the native decompressor. Keep every file under a temporary test root. Run `zsh scripts/run-tests.zsh`.

## References

- [Zsh path modifiers, including :a and :A](https://zsh.sourceforge.io/Doc/Release/Expansion.html)
- [GNU gzip manual](https://www.gnu.org/software/gzip/manual/gzip.html)
