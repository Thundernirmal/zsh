# ZSH-016: A stale widget-name key binding aborts fzf integration activation

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | Shell startup; fzf integration, Ctrl-R, Ctrl-T, Alt-C, and every fzf picker |
| Evidence | Reproduced in a real PTY against fzf 0.74.4; independently established by source inspection |

## Summary

The activation snapshot introduced for rollback iterates every key in `$widgets` and calls `zle -A` on it. Zsh also lists key-binding-only names in `$widgets` — names that appear in a `bindkey` table without a corresponding `zle -N` definition — and `zle -A` fails for those. A single stale binding naming an undefined widget therefore aborts activation for the whole session, and the failure is reported as an outdated fzf version.

## Affected code and documentation

- [40-fzf.zsh](../../40-fzf.zsh): `_fzf_activate_integration_file` — the `${(k)widgets}` snapshot loop, its `builtin zle -A "$name" "$backup" || return 1`, and the `_fzf_export_config || return 1` commit path.
- [40-fzf.zsh](../../40-fzf.zsh): `_fzf_block_integration` and `_fzf_startup_diagnostic`, which produce the user-visible message.
- [scripts/test-init.zsh](../../scripts/test-init.zsh): fzf integration activation fixtures.
- [GUIDE.md](../../GUIDE.md): fzf version requirements and startup diagnostics.

## Trigger and reproduction

In a real interactive shell, before this configuration is loaded:

1. `bindkey -M emacs '^Y' fzf-file-widget` — a binding that names a widget which is not defined at that point.
2. Source the repository `init.zsh`.
3. Inspect `_FZF_INTEGRATION_STATE_BY_PATH` and `_FZF_INTEGRATION_REASON_BY_PATH`.

Observed at the baseline, with fzf 0.74.4 installed:

```
_fzf_activate_integration_file:zle:44: no such widget `fzf-file-widget'
zsh config: fzf 0.68.0 or newer is required (found: integration initialization failed). Upgrade fzf and restart the shell.
state=blocked  reason=integration initialization failed
```

Without the stale binding in the same environment: `state=ready`, and `fzf-file-widget` is defined as a user widget. The rollback path cannot delete the phantom name either, so it survives and re-blocks every later activation attempt in that shell.

## Current behavior and impact

Ctrl-R, Ctrl-T, Alt-C, and all fzf-backed pickers are silently unavailable for the affected session. The user is told that their fzf build is too old and to upgrade it and restart the shell; the installed fzf already satisfies the documented minimum, so the suggested remedy cannot work. Because the module re-runs the snapshot on every interactive startup, the failure repeats indefinitely until the stale binding is removed by hand. The misleading diagnostic sends users toward the wrong fix.

## Root cause

`$widgets` is treated as an authoritative list of defined widgets. It also carries phantom entries for key-binding-only names, and the snapshot loop does not test whether the name resolves to an actual widget before cloning or deleting it. The activation abort is indistinguishable from a genuine validation failure, so it reuses the version-diagnostic path.

## Fix goal and expected behavior

Snapshot and restore only names that resolve to real widgets. A phantom key-binding-only name must be skipped without aborting activation. Integration must reach `ready` and bind its widgets in an environment that contains stale bindings naming undefined fzf-related widgets. A genuine activation failure must still roll back and must not be reported as a version problem.

### Review comment — 2026-09-30

**Assessment:** Confirmed defect; narrow the widget trigger.

**Evidence:** The independent reviewer reproduced activation failure when a key binding names an undefined `fzf-file-widget`. Snapshotting fails before integration runs; rollback can also emit a widget-deletion error.

**Reviewed scope and expected behavior:** The snapshot filters widget names to fzf-related names; it does not clone every widget. An arbitrary undefined non-fzf widget is not the demonstrated trigger. The integration is not silently skipped: it prints a failure diagnostic. Snapshot only defined matching widgets, while preserving and restoring their key bindings. The [Zsh ZLE documentation](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html) documents checking defined widgets with `zle -l -a name`.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep the existing rollback contract: partial activation must leave no new or overwritten functions, widgets, keymaps, options, or aliases.
- Do not introduce `eval` of generated shell text; the snapshot deliberately parses `bindkey -lL` output.
- Preserve the interactive-only guard so non-prompt startup paths stay unaffected.
- Keep the snapshot cost proportional and avoid adding a `command -v` probe to a startup path.
- Keep the existing diagnostic message for real version failures; distinguish integration failure from version failure if the two remain textually separate.

## Acceptance criteria

- [ ] Activation reaches `ready` with a pre-existing binding naming an undefined fzf-related widget.
- [ ] Phantom names are never passed to `zle -A` or `zle -D`.
- [ ] Rollback still restores or removes genuinely defined widgets, functions, keymaps, options, and aliases.
- [ ] A real activation failure still blocks integration and reports accurately.
- [ ] The regression exercises the phantom-binding case in a real interactive shell and fails against the audited snapshot loop.

## Validation plan

Extend `scripts/test-init.zsh` with a phantom-binding case and assert the resulting integration state and reason. Cover the rollback path with a deliberately failing integration file to confirm no regression. Run `zsh scripts/run-tests.zsh` and `python3 scripts/test-fzf-pty.py` with a supported real fzf.

## References

- [Zsh ZLE widget documentation](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html)
- [fzf shell integration](https://github.com/junegunn/fzf#shell-integration)
- Related: ZSH-005 (fzf partial integration rollback, repaired at this baseline)
