# ZSH-006: Custom-theme inspection and failed switching mutate the active palette

| Field | Value |
| --- | --- |
| Status | Open; not fixed by this documentation change |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `12e276a` |
| Affected surface | ztheme show custom; ztheme use custom; ztheme export custom |
| Evidence | Reproduced during audit; independently checked by a review subagent |

## Summary

Custom-theme validation writes into the palette used by active renderers. Inspecting a custom theme can therefore change the active palette. A failed switch restores the theme names but can retain the proposed colors while reporting that the theme is unchanged.

## Affected code and documentation

- [functions/ztheme](../../functions/ztheme): `_ztheme_validate_name`, `_ztheme_apply`, and show/export dispatch.
- [lib/theme-registry.zsh](../../lib/theme-registry.zsh): `_zsh_theme_capture_custom`.
- [25-theme.zsh](../../25-theme.zsh): `_zsh_theme_resolve_settings` and palette state.
- [scripts/test-theme.zsh](../../scripts/test-theme.zsh) and [GUIDE.md](../../GUIDE.md): atomic switching and session theme behavior.

## Trigger and reproduction

Use a fresh Zsh shell. This changes only its temporary session state.

```zsh
source "$PWD/25-theme.zsh"
source "$PWD/60-functions.zsh"
typeset -gA ZSH_UI_CUSTOM_COLORS
for role in "${_ZSH_UI_THEME_ROLES[@]}"; do
  ZSH_UI_CUSTOM_COLORS[$role]=111111
done
ztheme use custom
ZSH_UI_CUSTOM_COLORS[accent]=222222
_FZF_STATE=ready
_fzf_export_config() { return 1; }
ztheme use custom
print -r -- "switch-status=$? active-accent=${_ZSH_THEME_CUSTOM_COLORS[accent]}"
ZSH_UI_CUSTOM_COLORS[accent]=333333
ztheme show custom >/dev/null
print -r -- "after-show-accent=${_ZSH_THEME_CUSTOM_COLORS[accent]}"
```

Audit result: the failed switch said `theme unchanged` but active accent became `222222`; inspection then changed it to `333333`. The original committed accent was `111111`.

## Current behavior and impact

Read-only inspection changes rendering state, and failure does not restore the previous palette. Finder exports and renderer colors can disagree after a failed refresh. Restoring only `ZSH_UI_THEME` and `ZSH_FZF_THEME` is insufficient for a custom theme whose underlying values changed.

## Root cause

`_ztheme_validate_name` calls `_zsh_theme_capture_custom`, which writes `_ZSH_THEME_CUSTOM_COLORS` globally. Rollback saves only selector strings; resolving those strings again captures the new caller-supplied colors rather than recovering the old active snapshot.

## Fix goal and expected behavior

Validation, show, and export must read a proposed custom palette without committing it. Applying a theme must commit the palette and related finder configuration only on success. A failed apply must restore the complete previous active state, including palette values, selectors, derived options, and signatures. Caller-supplied proposed colors may remain edited; the committed active palette must remain unchanged.

## Implementation constraints

- Separate proposed palette validation from active palette publication.
- Preserve pure-Zsh startup and semantic role ownership.
- Keep UI and fzf theme selectors independent and respect explicit fzf overrides.
- Do not write `.zshrc` or change an already-open picker.
- Show/export may load trusted helpers, but must not change active presentation state.

## Acceptance criteria

- [ ] `show custom` and `export custom` do not change active palette values or finder options.
- [ ] A failed custom switch preserves the previous active palette byte-for-byte.
- [ ] Finder refresh failure restores selectors, exports, and derived signatures coherently.
- [ ] A successful switch publishes all proposed roles and refreshes future pickers.
- [ ] Built-in switching, explicit fzf overrides, reset, and invalid custom input retain documented behavior.
- [ ] Failure diagnostics accurately describe the resulting state.

## Validation plan

Extend `scripts/test-theme.zsh` with different committed/proposed custom palettes and a forced finder-refresh failure. Compare complete associative arrays and relevant exports, rather than checking theme names alone. Cover show and export separately. Run `zsh scripts/run-tests.zsh`.

## References

- [Current theme behavior](../../GUIDE.md)
- [Repository atomic theme requirements](../../AGENTS.md)
