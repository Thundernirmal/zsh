# ZSH-002: An empty extraction destination enables input removal

| Field | Value |
| --- | --- |
| Status | Open; not fixed by this documentation change |
| Priority | P1 |
| Audit date | 2026-09-30 |
| Audited baseline | `12e276a` |
| Affected surface | extract -C; extract --destination; extract --dest |
| Evidence | Reproduced during audit; independently checked by a review subagent |

## Summary

The split-form destination options accept an explicitly empty argument. The function treats that value as an omitted destination and falls back to native in-place decompression, which removes a bare compressed input.

## Affected code and documentation

- [lib/functions-files.zsh](../../lib/functions-files.zsh): `extract` option parsing and bare-compression dispatch.
- [scripts/test-command-ux.zsh](../../scripts/test-command-ux.zsh) and [scripts/test-functions.zsh](../../scripts/test-functions.zsh): extraction regression coverage.
- [GUIDE.md](../../GUIDE.md): extraction destinations imply input retention.
- [66-compdefs.zsh](../../66-compdefs.zsh): destination completion.

## Trigger and reproduction

Run this block in a fresh Zsh shell from the repository root. It changes only temporary files.

```zsh
source "$PWD/60-functions.zsh"
scratch=$(mktemp -d /tmp/zsh-issue-extract.XXXXXX) || exit 1
trap 'command rm -rf -- "$scratch"' EXIT
print -r -- sample > "$scratch/input"
command gzip "$scratch/input"
extract --destination '' "$scratch/input.gz"
print -r -- "status=$?"
[[ -e "$scratch/input.gz" ]] && print input-retained || print input-removed
[[ -e "$scratch/input" ]] && print output-created
```

Audit result: status `0`, `input-removed`, and `output-created`. Repeat with `-C ''` and `--dest ''` using fresh inputs. Contrast with `--destination=`, which already rejects an empty value.

## Current behavior and impact

A caller explicitly requesting destination extraction receives in-place behavior instead. The compressed source is removed and an output appears beside it. The decompressed content remains available in the observed case, but the source-retention promise and requested output location are violated.

## Root cause

The split-form branch checks only whether a following argument exists. It does not check whether that argument is nonempty. Downstream decisions use a nonempty-destination test, so explicit emptiness is indistinguishable from omission.

## Fix goal and expected behavior

Every explicitly supplied destination must be nonempty and name an existing directory. Missing, empty, and invalid destinations must fail before any decompressor runs. Valid destination extraction must retain bare compressed inputs and publish output only into the requested directory.

## Implementation constraints

- Apply the same validation to `-C`, `--destination`, `--dest`, and their supported equals forms.
- Preserve documented native in-place behavior when no destination or keep flag is supplied.
- Preserve atomic output publication and refusal to replace existing outputs.
- Keep missing-tool guards and `--` filename handling intact.

## Acceptance criteria

- [ ] Each split-form empty destination returns nonzero with a useful diagnostic.
- [ ] Empty equals-form destinations remain rejected.
- [ ] Invalid destinations invoke no decompressor and leave all inputs untouched.
- [ ] Valid destination extraction retains the source and creates the expected output there.
- [ ] Omitted destination retains existing documented in-place semantics.
- [ ] Existing destination outputs are not overwritten.

## Validation plan

Add table-driven parser cases using a mocked decompressor call log, plus a temporary real gzip fixture for source retention. Cover `.gz`, `.bz2`, and `.Z` where the corresponding backend is available or mocked. Run `zsh scripts/run-tests.zsh` after the fix.

## References

- [Current extraction contract](../../GUIDE.md)
- [GNU gzip manual](https://www.gnu.org/software/gzip/manual/gzip.html)
