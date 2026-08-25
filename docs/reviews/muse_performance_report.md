# Muse Performance Report — Zsh Config

**Date:** 2026-08-25 · **Scope:** `init.zsh`, `10-80-*.zsh`, `lib/theme-*.zsh`, `functions/*`, `scripts/benchmark-startup.zsh`, `.github/workflows/checks.yml`  
**Method:** `zmodload zsh/datetime` isolated per-module parse timing, `scripts/benchmark-startup.zsh 5` warm runs, guard audit, lazy-load graph.

## Executive Summary

Config is **well-optimized**. Command startup **~22 ms** median, interactive **~28 ms** (n=5 warm). One **Major** eager-load defeat via `30-zoxide.zsh:31` forcing theme materialization even in `zsh -df` command mode. No Critical blockers. Guard discipline PASS, lazy-loading correctly wired, `40-fzf.zsh:549` ZLE guard works, completion/tips lightweight.

## Verification Evidence

| Check | Command | Result |
|---|---|---|
| Syntax | `zsh -n *.zsh lib/*.zsh functions/ztheme functions/_fbr_format_entry` | exit 0 |
| Syntax | `zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh` | exit 0 |
| POSIX | `sh -n scripts/check-deps.sh` | exit 0 |
| Smoke | `zsh scripts/test-init.zsh` (891-line suite) | all ok |
| Live | `zsh -fc 'source init.zsh'` | exit 0 silent |
| Bench quick n=5 | `zsh scripts/benchmark-startup.zsh 5` | `command median=22.360 ms p95=23.234 ms` · `interactive median=27.884 ms p95=35.796 ms` |
| Workflow | `.github/workflows/checks.yml:25-69` | Covers `zsh -n` + 6 suites; no benchmark in CI (intentional) |

### Per-Module Parse Cost (`zsh -df` isolated, µs)

| Module | µs | Notes |
|---|---|---|
| `10-history.zsh` | 59 | |
| `20-aliases.zsh` | 8002 | Includes 2× capability probes |
| `25-theme.zsh` | 943 | Pure-Zsh, lazy stubs only |
| `30-zoxide.zsh` | 4418 | **Highest after 20/60 — eager `_zsh_zoxide_refresh_fzf_opts`** |
| `40-fzf.zsh` | 1680 | Cache-aware, gated on interactive |
| `50-completion.zsh` | 556 | |
| `55-ui-helpers.zsh` | 453 | Fallback source guarded |
| `60-functions.zsh` | 7043 | 125 KB / 4639 lines parsed, not executed |
| `65-help.zsh` | 4149 | Data-only registration |
| `66-compdefs.zsh` | 1001 | Guarded on `compdef` |
| `70-globals.zsh` | 85 | |
| `80-tips.zsh` | 377 | Hook-free, `$+commands` pool |

Total sourced: `229173` bytes / `8459` lines (excl. `functions/`).

## Findings

| # | Severity | File:Line | Category | Issue |
|---|---|---|---|---|
| F1 | **Major** | `30-zoxide.zsh:31` | Eager lazy-load defeat | Unconditional `_zsh_zoxide_refresh_fzf_opts` at startup loads theme registry/color helpers even in `zsh -df` |
| F2 | **Minor** | `25-theme.zsh:26-28`, `25-theme.zsh:162-167` | Dead code / duplicate sourcing | Both blocks test `(( _ZSH_THEME_*_LOADED ))` which is 0 at startup; never executed; re-sources `theme-color.zsh:1` + `theme-registry.zsh:1` redundantly |
| F3 | **Minor** | `20-aliases.zsh:10`, `20-aliases.zsh:42-47` | Startup forks | `command ls --color`, `print | command grep --color`, `command diff --color` spawn subshells (~2-3 ms on long PATH) |
| F4 | **Minor** | `55-ui-helpers.zsh:3-7` | Redundant fallback stat | `[[ -r 25-theme.zsh ]] && source` runs one `stat` every startup though `init.zsh:17` already sourced it (<0.1 ms) |
| F5 | **Info** | `40-fzf.zsh:79,81` | Preview correctness — PASS | `command -v` inside `FZF_*_OPTS` preview strings is required (separate shell); correctly not `$+commands` |
| F6 | **Pass** | `25-theme.zsh:1-21`, `40-fzf.zsh:549`, `50-completion.zsh:1-12`, `80-tips.zsh` | Spec compliance | Pure-Zsh theme, ZLE guard, lightweight completion, hook-free tips verified |

### F1 Detail — `30-zoxide.zsh:31` Eager Theme Materialization

**Evidence:**

```zsh
# 25-theme.zsh:21  — theme module dir fixed, no FS discovery
typeset -g _ZSH_THEME_MODULE_DIR=${_ZSH_THEME_MODULE_DIR:-${${(%):-%N}:A:h}}
# 25-theme.zsh:50-55, 130-135 — lazy loaders, registry=0 at startup (verified helper=0 registry=0)
_zsh_theme_load_registry() { (( _ZSH_THEME_REGISTRY_LOADED )) && return 0; source ... }
# 30-zoxide.zsh:14-18 — inside refresh: calls theme chrome
(( $+functions[_zsh_theme_fzf_chrome_opts] )) || return 0
_zsh_theme_fzf_chrome_opts || return 1  # -> _zsh_theme_fzf_chrome_args -> _zsh_theme_fzf_color_args -> _zsh_theme_color_value -> load_registry + load_color_helpers
# 30-zoxide.zsh:31 — unconditional at top-level
_zsh_zoxide_refresh_fzf_opts
```

Sourcing `25-theme.zsh` alone leaves `helpers=0 registry=0` (`zsh -fc` test), but full `init.zsh` via `30-zoxide.zsh:31` forces `registry=1` even for `zsh -df` non-interactive. `40-fzf.zsh:549` correctly gates on `[[ -o interactive && -z ${ZSH_EXECUTION_STRING:-} ]]`, so it stays lazy in command mode; `30-zoxide` does not.

**Cost:** ~3-4 ms + 2× `source` of `lib/theme-registry.zsh:127`/`lib/theme-color.zsh:123` + palette expansion on every shell, including `git` hooks, `zsh -c` pipelines.

**Fix (recommended):**

```zsh
# 30-zoxide.zsh:31 — make refresh lazy / interactive-only
if [[ -o interactive ]] && [[ -z ${ZSH_EXECUTION_STRING:-} ]]; then
  _zsh_zoxide_refresh_fzf_opts
fi
```

Alternative: early return inside `_zsh_zoxide_refresh_fzf_opts` on `[[ ! -o interactive ]]`.

### F2 Detail — `25-theme.zsh:26-28` + `162-167` Dead Duplicate

```zsh
# 25-theme.zsh:22-24
typeset -gi _ZSH_THEME_BUILTIN_PALETTES_LOADED=0
typeset -gi _ZSH_THEME_COLOR_HELPERS_LOADED=0
typeset -gi _ZSH_THEME_REGISTRY_LOADED=0
# 25-theme.zsh:26-28 — always false at first source
if (( _ZSH_THEME_BUILTIN_PALETTES_LOADED )); then
  source "$_ZSH_THEME_MODULE_DIR/lib/theme-palettes.zsh"
fi
# 25-theme.zsh:162-167 — same, also always false
if (( _ZSH_THEME_COLOR_HELPERS_LOADED )); then
  source "$_ZSH_THEME_MODULE_DIR/lib/theme-color.zsh"
fi
if (( _ZSH_THEME_REGISTRY_LOADED )); then
  source "$_ZSH_THEME_MODULE_DIR/lib/theme-registry.zsh"
fi
```

Second block appears intended for re-source after `ztheme use` when flag is 1 but at startup dead. Adds parse + 2 stat checks that never run, confuses lazy invariant. Lazy paths already covered via `_zsh_theme_role_hex:42-46` and `_zsh_theme_load_*` wrappers.

**Fix:** Delete `25-theme.zsh:26-28` and `162-167`; keep reload only in `functions/ztheme:_ztheme_refresh_integrations` if hot-reload desired.

### F3 Detail — `20-aliases.zsh:10,42,46` Startup Forks

```zsh
# 20-aliases.zsh:10 — forks ls(1)
if command ls --color=auto . >/dev/null 2>&1; then
# 20-aliases.zsh:42 — forks grep
if print -r -- x | command grep --color=auto -e x >/dev/null 2>&1; then
# 20-aliases.zsh:46 — forks diff
if command diff --color=auto /dev/null /dev/null >/dev/null 2>&1; then
```

Not guard violations (feature probes, not `command -v` guards) but each costs fork+exec + PATH walk. On WSL2 with 500-entry PATH, `command -v` miss 146× slower than `$+commands` (0.09 ms vs 14.5 ms per 100×). `20-aliases.zsh` 8 ms is hottest module.

**Fix (optional):** Cache result in `~/.cache/zsh/aliases-probe` or defer to first `ls` via function wrapper; keep as-is if portability matters — document why `$+commands` not used (already at `20-aliases.zsh:2-3`).

### F5 — `40-fzf.zsh:79,81` Preview Shell

```zsh
# 40-fzf.zsh:79,81 — inside _fzf_export_config, stored in exported FZF_CTRL_T_OPTS
preview_command='if [[ -d {} ]]; then if command -v lsd >/dev/null 2>&1; then lsd ...; elif command -v tree ...; elif command -v bat ...; ...'
```

Per `AGENTS.md`: `40-fzf.zsh also embeds command -v inside the exported FZF_*_OPTS preview strings. Those run in a separate shell that fzf spawns, so they must stay command -v.` — **correct, do not change.**

## Guard Correctness Matrix — PASS

| Location | Expected | Actual | Verdict |
|---|---|---|---|
| Top-level `20-aliases.zsh:4,20,38`, `30-zoxide.zsh:33`, `40-fzf.zsh:550`, `init.zsh:29`, `80-tips.zsh:40,56,73,81,88,95,106` | `(( $+commands[tool] ))` | Uses `$+commands` | ✅ |
| Function bodies `60-functions.zsh:19,23,27,35,39,75,91,177,1302-1328`, `65-help.zsh:152-204`, `62-cgm.zsh:12`, `55-ui-helpers.zsh:15,31` | `command -v … >/dev/null` | Uses `command -v` | ✅ |
| `40-fzf.zsh:201,255,446,513` | `command -v` + `$+commands[fzf]` gate at `549` | Hybrid correct | ✅ |
| `65-help.zsh` availability helpers | `command -v` | Correctly not `$+commands` (must detect mid-session PATH + fakes) | ✅ |

## Lazy-Loading Correctness — PASS with F1 Exception

| Lazy helper | Startup registers | On-demand source | Path idempotent |
|---|---|---|---|
| `functions/ztheme` `60-functions.zsh:110` | `(( $+functions[ztheme] )) || autoload -Uz ztheme` + `fpath:107-108` guard | `functions/ztheme:200` | ✅ fixed to repo dir `60-functions.zsh:106` |
| `functions/_fbr_format_entry` `60-functions.zsh:111` | Same | `60-functions.zsh:1156` | ✅ |
| `lib/theme-color.zsh` `25-theme.zsh:130-135` | `_zsh_theme_load_color_helpers` guard | `_zsh_theme_*` call sites | ✅ |
| `lib/theme-registry.zsh` `25-theme.zsh:50-55` | `_zsh_theme_load_registry` guard | `_zsh_theme_has_role:57` | ✅ |
| `lib/theme-palettes.zsh` | `_zsh_theme_role_hex:42-46` inline guard | Palette data | ✅ — but eagerly triggered by F1 |

No `eval`, no `find`/`ls` theme discovery, no `curl`/download in `25-theme.zsh` — pure Zsh verified.

## Additional Checks

- Duplicate sourcing: no duplicate `init.zsh` loop (single pass `init.zsh:17-27`), `55-ui-helpers:4` guarded, `25-theme:26/162` dead, no `compinit` duplicate (`50-completion.zsh:2` defers to OMZ).
- Completion hotness: `50-completion.zsh:5` `matcher-list 'm:{a-zA-Z}={A-Za-z}'` + `8` `squeeze-slashes` only; intentionally omits heavy `menu select`, `approximate`, `list-colors` keeps cheap `list-colors '=(#b)...'` at `50-completion.zsh:12`.
- Hooks: `grep -R add-zsh-hook|precmd|preexec 55-ui-helpers.zsh 80-tips.zsh` → 0 hits; `80-tips.zsh:113` function only, no `add-zsh-hook`.
- Benchmark accuracy: `scripts/benchmark-startup.zsh:41-82` measures `zsh -df` (command) vs `zsh -dfi < file` (interactive) with `EPOCHREALTIME` µs, warmups `ZSH_BENCHMARK_WARMUPS=3`, median/p95/min/max, sorts `samples=( ${(on)samples} )`, exports `TERM/COLORTERM/COLUMNS/LINES` deterministically, captures `_ZO_FZF_OPTS` signature drift + persistent cache (`40-fzf.zsh:341-365` `zstat` + `XDG_CACHE_HOME`). Minor nit `benchmark-startup.zsh:10-22` hard-fails if repo not at `$HOME/.config/zsh`.

## Prioritized Action Plan

1. Fix F1 — wrap `30-zoxide.zsh:31` in interactive guard (saves ~3 ms, keeps theme lazy in scripts/hooks).
2. Clean F2 — delete `25-theme.zsh:26-28` and `162-167` dead blocks.
3. Optional F3 — replace `20-aliases.zsh:10,42,46` forks with cached probe if targeting <20 ms.
4. No action on F4/F5 — correct by spec.

**Re-verify:**

```zsh
zsh -n *.zsh lib/*.zsh functions/ztheme functions/_fbr_format_entry
zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh
sh -n scripts/check-deps.sh
zsh scripts/test-init.zsh
zsh -fc 'source "$HOME/.config/zsh/init.zsh"'
zsh scripts/benchmark-startup.zsh 30
```

Expected post-fix: `command median` 19-21 ms (palette deferred), `interactive` unchanged.
