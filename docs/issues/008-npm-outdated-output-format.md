# ZSH-008: Configured npm output formats break update inventory

| Field | Value |
| --- | --- |
| Status | Open; not fixed by this documentation change |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `12e276a` |
| Affected surface | upkg outdated --only npm; npm update inventory |
| Evidence | Reproduced during audit; independently checked by a review subagent |

## Summary

The npm inventory assumes native table output, but npm configuration can select JSON or parseable output. An empty JSON object is classified as updates available, and legitimate non-table update output can be classified as a command failure.

## Affected code and documentation

- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): `_upkg_run_outdated_npm`.
- [lib/functions-upkg.zsh](../../lib/functions-upkg.zsh): `_upkg_npm_outdated_looks_valid`.
- [scripts/test-upkg.zsh](../../scripts/test-upkg.zsh): npm output fixtures.
- [GUIDE.md](../../GUIDE.md): npm inventories and result summaries.

## Trigger and reproduction

Use an isolated empty global npm directory. It contains no packages, so this reproduction does not need package-registry queries. Use two distinct empty config files; npm rejects loading the same path as both user and global configuration.

```zsh
source "$PWD/60-functions.zsh"
upkg help >/dev/null
scratch=$(mktemp -d /tmp/zsh-issue-npm.XXXXXX) || exit 1
trap 'command rm -rf -- "$scratch"' EXIT
command mkdir -p "$scratch/prefix/lib/node_modules"
: > "$scratch/user.npmrc"
: > "$scratch/global.npmrc"
export npm_config_prefix="$scratch/prefix" npm_config_cache="$scratch/cache"
export npm_config_userconfig="$scratch/user.npmrc"
export npm_config_globalconfig="$scratch/global.npmrc"
export npm_config_json=true
command npm outdated -g --depth=0
print -r -- "native-status=$?"
_upkg_run_outdated_npm
print -r -- "wrapper-status=$? state=$_UPKG_LAST_STATE"
```

Audit result with npm 11.19.1: native output `{}` and status 0; wrapper status 0 and state `updates available`.

## Current behavior and impact

The wrapper reports pending updates where none exist. Conversely, status-1 JSON or parseable update output lacks the table header required by the validator, so valid update inventories can be marked failed. Inventory behavior depends on unrelated user-level formatting preferences.

## Root cause

The command does not explicitly choose an output format. Status 0 treats any nonempty stdout as an update inventory, while status 1 validates only the table header. Neither branch parses semantic emptiness for JSON.

## Fix goal and expected behavior

Select one supported output format explicitly and classify its contents consistently, independent of npm's inherited formatting settings. An empty successful inventory must be up to date; a valid nonempty inventory must show updates; genuine command failure must remain failed. Keep the selected format readable or render it into the existing UI.

## Implementation constraints

- Either force table settings explicitly or select and parse structured output; document the choice in the implementation.
- Do not add an unguarded dependency solely for parsing.
- Preserve the user's registry, global prefix, authentication, and non-format configuration.
- Preserve npm's legitimate status-1 update convention.
- Coordinate diagnostic handling with [ZSH-009](009-npm-outdated-diagnostics.md).

## Acceptance criteria

- [ ] Empty inventory under inherited `json=true` is classified up to date.
- [ ] Valid updates under inherited JSON, parseable, and color preferences are classified correctly.
- [ ] Malformed output and genuine command errors are not classified as updates.
- [ ] The command uses the configured global prefix and registry.
- [ ] Default-format behavior remains correct.
- [ ] Format selection does not hide diagnostics or alter native upgrade behavior.

## Validation plan

Add format-preference matrix cases to `scripts/test-upkg.zsh`, asserting exact command flags and empty/nonempty/error states. Retain the isolated real-npm empty-prefix check as an optional environment integration check; network-facing results should remain mocked. Run `zsh scripts/run-tests.zsh`.

## References

- [npm outdated: JSON and parseable configuration](https://docs.npmjs.com/cli/v11/commands/npm-outdated/)
- [npm configuration precedence](https://docs.npmjs.com/cli/v11/using-npm/config/)
