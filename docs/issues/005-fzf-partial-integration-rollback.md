# ZSH-005: Failed fzf initialization leaves partial integration installed

| Field | Value |
| --- | --- |
| Status | Open; not fixed by this documentation change |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `12e276a` |
| Affected surface | fzf startup integration; generated widgets and completion entry points |
| Evidence | Reproduced during audit; independently checked by a review subagent |

## Summary

Runtime failure while sourcing generated fzf integration does not undo changes made before the failure. The integration can be marked blocked while new public functions, widgets, or bindings remain usable without the normal guards.

## Affected code and documentation

- [40-fzf.zsh](../../40-fzf.zsh): `_fzf_activate_integration_file`, `_fzf_initialize_zsh`, and `_fzf_block_integration`.
- [scripts/test-init.zsh](../../scripts/test-init.zsh): generated integration and runtime-guard fixtures.
- [scripts/test-fzf-pty.py](../../scripts/test-fzf-pty.py): interactive terminal checks.
- [GUIDE.md](../../GUIDE.md): guarded fzf integration and keybindings.

## Trigger and reproduction

Use a fresh non-interactive Zsh shell and a temporary integration file. Sourcing `40-fzf.zsh` in this mode does not initialize the real fzf integration.

```zsh
source "$PWD/40-fzf.zsh"
scratch=$(mktemp -d /tmp/zsh-issue-fzf.XXXXXX) || exit 1
trap 'command rm -rf -- "$scratch"' EXIT
print -r -- 'fzf-file-widget() { print UNGUARDED_WIDGET; }
false' > "$scratch/integration.zsh"
_FZF_STATE=blocked
_fzf_activate_integration_file "$scratch/integration.zsh" /fixture/fzf 0.70.0
print -r -- "activation-status=$? state=$_FZF_STATE"
fzf-file-widget
```

Audit result: activation failed, but calling `fzf-file-widget` printed `UNGUARDED_WIDGET`. The startup-level reproduction uses the same body as fake `fzf --zsh` output: initialization reports blocked while the definition remains installed.

## Current behavior and impact

Blocked state does not describe the actual shell state. A partial integration can shadow existing functions or retain keybindings and widgets that invoke unguarded generated code. Existing runtime-failure tests using only `false` cannot detect these side effects.

## Root cause

The generated file is sourced into the current shell before its completion markers and runtime status are checked. Guard wrappers are installed only after success. No snapshot or rollback restores functions, widgets, and bindings on failure.

## Fix goal and expected behavior

Failed activation must leave the shell's relevant functions, widgets, bindings, and finder configuration as they were before the attempt, apart from the intended blocked-state diagnostic. Successful activation must install the full guarded integration. No entry point from a failed attempt may remain callable as an unguarded generated function.

## Implementation constraints

- Snapshot the finite generated integration surfaces and restore them on failure, or stage installation so it can be committed atomically.
- Preserve pre-existing user definitions and bindings; merely deleting names is insufficient.
- Keep command-mode startup free of ZLE initialization warnings.
- Apply failure handling to cold generation and cached activation.
- Retain syntax validation, version guards, private caching, and option inheritance.

## Acceptance criteria

- [ ] A generated function followed by failure leaves no new public definition.
- [ ] A pre-existing function with the same name is restored exactly.
- [ ] Interactive fixtures restore prior widgets and keybindings after partial failure.
- [ ] Failed cold and warm activation both leave coherent blocked state.
- [ ] Initialization with valid generated code in a fresh shell succeeds with normal guards; preserve the existing restart requirement after a cached per-session failure unless retry support is separately specified.
- [ ] Non-interactive startup remains quiet and avoids ZLE errors.

## Validation plan

Extend `scripts/test-init.zsh` with side-effecting failure bodies rather than only a final `false`. Inspect functions, widget registrations, keymaps, and exports before and after failure. Run `zsh scripts/run-tests.zsh`; run `python3 scripts/test-fzf-pty.py` where a supported real fzf is available.

## References

- [fzf shell integration](https://github.com/junegunn/fzf#setting-up-shell-integration)
- [Zsh ZLE widgets and keymaps](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html)
