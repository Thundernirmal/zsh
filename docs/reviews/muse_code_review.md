# Muse Code Review — Zsh Config

**Date:** 2026-08-25 · **Model:** muse-spark-1.2 · **Scope:** `*.zsh` + `lib/*.zsh` + `functions/*`, `init.zsh`  
**Syntax:** All 17 files pass `zsh -n` (including `lib/theme-*.zsh`, `functions/ztheme`, `functions/_fbr_format_entry`). `sh -n scripts/check-deps.sh` clean.

## Summary Counts

| Category | Critical | High | Medium | Low | Info |
|----------|----------|------|--------|-----|------|
| Idiomatic Zsh | 0 | 0 | 1 | 3 | 2 |
| DRY | 0 | 3 | 4 | 1 | 0 |
| Complexity | 2 | 4 | 1 | 0 | 0 |
| Naming | 0 | 0 | 0 | 3 | 2 |
| Alias Shadowing | 0 | 2 | 2 | 1 | 0 |
| Error Handling | 0 | 1 | 3 | 1 | 0 |
| Idempotency | 0 | 0 | 0 | 0 | 1 |
| Lazy Path | 0 | 0 | 0 | 1 | 0 |
| Completion | 0 | 0 | 0 | 3 | 1 |
| Magic Numbers | 0 | 0 | 0 | 11 | 0 |
| Theme Separation | 0 | 0 | 2 | 2 | 0 |
| **Total** | **2** | **10** | **13** | **25** | **6** |

---

## 1. Idiomatic Zsh — `setopt`, Quoting, Arrays, `emulate`, `autoload`

| Severity | File:Line | Evidence | Fix |
|----------|-----------|----------|-----|
| Medium | `60-functions.zsh:4,51,61,85,161,171,972` | `extract()`, `mkcd()`, `ff()`, `ft()`, `headers()`, `peek()`, `croot()` **no** `emulate -L zsh`. Inherits caller `setopt` (`EXTENDED_GLOB`, `NULL_GLOB`, `SH_WORD_SPLIT`). | Add `emulate -L zsh` as first line (all other functions in same file do). |
| Low | `init.zsh:14-35` | `setopt` at top-level without `emulate`. OK for `init.zsh` but mixes `[ -r` (POSIX `10` at `32`) vs `[[ -r` elsewhere. | Consistently use `[[ -r` ; replace `unset zsh_config_file` with `unset -v`. |
| Low | `10-history.zsh:4` | `HISTFILE=$HOME/.zsh_history` unquoted. | `HISTFILE="$HOME/.zsh_history"` |
| Low | `55-ui-helpers.zsh:4` | `typeset _ui_theme_module=${${(%):-%x}:A:h}/25-theme.zsh` uses `%x` while `25-theme.zsh:21` and `60-functions.zsh:106` use `(%):-%N`. `%x` = execution context, `%N` = sourced file — subtle divergence if sourced via wrapper. | Normalize to `${${(%):-%N}:A:h}` + comment. |
| Info | `25-theme.zsh:191` | `_zsh_theme_join_shell_args` uses idiomatic `${(qq)arg}` (good) but no doc that `(qq)` handles spaces/newlines for `FZF_*_OPTS`. | Keep, add comment. |
| Info | `60-functions.zsh:539` | `entries=( "$target"/*(DN) )` and `60:562 lines=( "${(@On)records}" )` — correct glob qualifiers `D`/`N`, `(@s/:/)` `(@On)` — idiomatic. | — |
| Medium | `60-functions.zsh:580ff` / `652ff` | `printf '%-8s %s\n' "$(_ui_human_kib "$kib")"` — `kib` validated via `[[ $kib == <-> ]]` but printed unquoted in arithmetic later; safe here. | No fix. |

**`autoload` / `fpath`:** `60-functions.zsh:106-111` correct & idempotent:

```zsh
typeset -g _ZSH_CONFIG_FUNCTIONS_DIR=${${(%):-%N}:A:h}/functions
if (( ! ${fpath[(Ie)$_ZSH_CONFIG_FUNCTIONS_DIR]} )); then fpath=( "$_ZSH_CONFIG_FUNCTIONS_DIR" "${fpath[@]}" ); fi
(( $+functions[ztheme] )) || autoload -Uz ztheme
```

Good. `55-ui-helpers.zsh:3-7` re-sources `25-theme.zsh` if `_zsh_theme_sgr` missing — fallback works but duplicates lazy contract.

---

## 2. DRY Violations

| Severity | File:Line | Duplication | Fix |
|----------|-----------|-------------|-----|
| **High** | `60-functions.zsh:515-647` vs `650-793` | `dusage()` and `bigfiles()` share ~85% (mktemp + `du --null`, `while IFS=$'\t' read -r -d ''`, `(@On)` sort, `_ui_visible_count`, rich/plain branching, `_ui_bar`, width calc `size_width=9; bar_width=16; ((width<80))&&bar_width=10`). ~260 LOC duplicated. | Extract `__usage_collect()`, `__usage_render_header()`, `__usage_render_rows()`. |
| **High** | `40-fzf.zsh:73-143` | `[[ -n ${NO_COLOR:-} ]] && FOO+=' --no-color'` repeated **7×** (for `DEFAULT, CTRL_T, CTRL_R, ALT_C, COMPLETION, …`). Plus `_ZO_FZF_OPTS` at `30-zoxide.zsh:27`. | Helper `_fzf_maybe_no_color() { [[ -n ${NO_COLOR:-} ]] && REPLY+=' --no-color'; }` or loop over assoc array. |
| **High** | `40-fzf.zsh:79-82` | Preview command duplicated for `NO_COLOR` vs color (only `--color=never/always` diff), ~280 char lines. | `local color=always; [[ -n ${NO_COLOR} ]] && color=never; preview_command="... --color=$color ..."` |
| Medium | `55-ui-helpers.zsh:9-39` | `_ui_term_width()` vs `_ui_term_height()` identical except `tput cols/lines` + default 80/24. Duplicated again in `25-theme.zsh:309-331` `case ${COLUMNS} …`. | `_ui_term_dimension() { local var=$1 def=$2; ... }`; call with `cols/80` `lines/24`. |
| Medium | `55-ui-helpers.zsh:41` vs `25-theme.zsh:94` | `_ui_locale_is_utf8()` duplicates `_zsh_theme_locale_is_utf8()` verbatim (`${(L)${LC_ALL:-${LC_CTYPE:-${LANG}}}` `*utf-8*`). | Have `_ui_locale_is_utf8` delegate. |
| Medium | `55-ui-helpers.zsh:213-250` vs `60:231-302` | `_ui_truncate()` vs `_ui_safe_truncate()` - same width/marker/edge logic, latter adds escape-token parsing. Could share core. | `_ui_safe_truncate` calls `_ui_truncate` for non-escaped input. |
| Medium | `60:397-512` | Fallback UI helpers (`_ui_plain_mode`, `_ui_color`, `_ui_badge`, …) ~115 LOC duplicated from `55-ui-helpers.zsh`. Intentional standalone safety but unversioned drift risk. | Add header comment `# keep in sync with 55-ui-helpers.zsh vX` + consider single `lib/ui-fallbacks.zsh`. |
| Medium | `62-cgm.zsh:114-255` | Catalog symlink/perm checks repeated in `_cgm_prepare_catalog` `_has`, `_can_remove`, `_names` (4× `[[ -L $root || ( -e $root && ! -d $root ) ]]`). | Extract `_cgm_assert_catalog()` helper. |
| Low | `25-theme.zsh:245-290` + `30-zoxide.zsh:18-28` + `40-fzf.zsh:64-68` | Signature string `"${_ZSH_FZF_ACTIVE_THEME}:${_ZSH_UI_COLOR_DEPTH}:…:${ZSH_FZF_LAYOUT}…"` built in 3 places. | Central `_zsh_theme_signature` already exists (25:345) — reuse. |

---

## 3. Function Length / Complexity

| Severity | File:Line | LOC | Cyclomatic | Note |
|----------|-----------|-----|------------|------|
| **Critical** | `60-functions.zsh:3407-3779` `upkg()` | **372** | ~35 | Orchestrator does arg-parse + detection + filter + dispatch + summary. Split `__upkg_parse_args`, `__upkg_run_selected`. |
| **Critical** | `60:4160-4556` `_npkg_outdated()` | **396** | concurrent job pool `max_jobs=8`, 3 trap scopes | Hardest to test. Extract `__npkg_collect_profile`, `__npkg_eval_batch`, `__npkg_render`. |
| **High** | `40-fzf.zsh:437-545` `_fzf_initialize_zsh()` | **108** | 14 | Cache validation + `fzf --zsh` generation + `mktemp` fallback + chmod + trap + syntax check. Split `__fzf_ensure_cache_dir`, `__fzf_generate_integration`. |
| **High** | `40:45-147` `_fzf_export_config()` | **103** | 7 contexts | 7 identical `FZF_*_OPTS` blocks. |
| **High** | `25-theme.zsh:358-424` `_zsh_theme_resolve_settings()` | **66** | Nested `custom_needed` + 3 fallback branches | Could split `_resolve_ui`, `_resolve_fzf`, `_resolve_layout`. |
| **High** | `60:650-793` `bigfiles()` | **143** | 12 | See DRY above. |
| **High** | `60:796-941` `ports()` | **145** | awk + parsing | Inline `awk` 40 lines + 5 width calcs; extract `_ports_parse_ss`. |
| Medium | `62-cgm.zsh:494-586` `_cgm_env()` | **92** | Sentinel `.` trick + loop | Dense but comment explains; okay. |

Threshold: aim `<60 LOC` helpers, `<100` top-level commands. `upkg`/`npkg` exceed intentionally but warrant sub-helpers.

---

## 4. Naming Consistency

| Severity | Location | Issue | Fix |
|----------|----------|-------|-----|
| Low | `60:984` `function gitcount {` vs alias `gcount='gitcount'` | `function` keyword legacy; most funcs use `name() {`. Two names for same thing. | `gitcount()` + keep alias or deprecate `gcount`. Help registers both (`65:87-88`) duplicating. |
| Low | Globals | Mix `_ZSH_*` (`_ZSH_UI_THEME`, `_ZSH_THEME_*`), `_FZF_*`, `_UPKG_*`, `_NPKG_*`, `_CGM_*` vs bare `extract`, `ff`, `path` (shadows coreutils `path` helper) | Document convention: `_*` private, bare = user-facing. `path()` shadowing `/usr/bin/path` on some distros — add comment. |
| Low | `25-theme.zsh:14-24` | `typeset -gA _ZSH_THEME_COLORS` empty then `lib/theme-palettes.zsh:3 _ZSH_THEME_COLORS+=(…)` appends. Works but `typeset -gA` re-declared in palette not central. | Declare once, or add `typeset -gA _ZSH_THEME_COLORS` in registry with comment. |
| Info | `62:228` vs elsewhere | `reply` (`-ga`) vs `REPLY` scalar: `_cgm_catalog_names` uses global `reply` array, others use `REPLY`. Zsh convention is `reply` for array, `REPLY` for scalar — consistent, good. | Keep. |
| Info | `66-compdefs.zsh` | Arrays `_ZSH_UPKG_*` set unconditionally on each source (no `(( ${+...}))` guard). | Wrap with `if (( ! ${+_ZSH_UPKG_COMMAND_SPECS} ))` to survive re-source. |

---

## 5. Alias Shadowing Risks (`20-aliases.zsh` Intentionally Redefines `mkdir`/`cp`/`mv`/`rm`)

| Severity | Line | Evidence | Guardrail Assessment | Fix |
|----------|------|----------|----------------------|-----|
| **High** | `32` `alias mkdir='mkdir -p'` | Silences “already exists” error; `mkdir foo; echo $?` now `0` even if `foo` exists. Breaks scripts assuming failure on existing dir. | Mitigated by `command mkdir` / `\mkdir` but **not documented** in file itself. `mkcd()` at `60:51` correctly uses `command mkdir -p` — pattern to follow. | Add comment block: `# bypass: command mkdir / \mkdir / unalias mkdir` + mention in `GUIDE.md`. |
| **High** | `35` `alias rm='rm -iv'` | `-i` hangs non-interactive `rm -rf $tmp` pipelines; `-v` floods logs. | Interactive-only aliases still expand in `zsh -c 'source init.zsh; rm …'` if sourced. `60-functions.zsh` `bigfiles` uses `command rm -f` correctly. | Recommend `alias rm='rm -I'` (prompt only when >3 files) or guard with `if [[ -o interactive ]]`. Add tip. |
| Medium | `33-34` `cp='cp -iv'`, `mv='mv -iv'` | Same `-i` stall risk in scripts; `-v` noisy. | Less severe than `rm` but same. | Document `command cp` bypass; consider `-i` only if `[[ -t 0 ]]`. |
| Medium | `4-21` `ls`/`ll`/`la`/`lt` | `ls` → `lsd` changes flags; scripts using `ls | …` break. `ll='lsd -lah --group-dirs=first'` includes hidden entries unlike `ls`. | Guarded by `(( $+commands[lsd] ))` fallback to `ls --color=auto` probe — good. | Ensure `scripts` call `command ls`. |
| Low | `39` `cat='bat …'` | Changes paging behavior; `cat file | wc -l` now calls `bat --paging=never` (ok) but `cat` without terminal may still color. | Probe `(( $+commands[bat] ))` correct. `peek()` also uses `command cat`. | OK. |
| Medium | `70-globals.zsh:6-12` `alias -g G='| grep'` etc. | Global aliases expand anywhere: `echo "a G b"` → `echo "a | grep b"`; `echo NE` → redirect; `W` = `| wc -l` collides with variable `W`. Most dangerous category. | Documented in header but still opt-in risk. | Consider moving to `80-tips` hint only, or guard `if [[ -o interactive ]]`. |

Verification: `grep -n "command mkdir\|command rm\|command cp\|command mv"` found correct bypass in `60-functions.zsh:57,546,676,696,554`; confirm all script paths use `command`.

---

## 6. Error Handling

| Severity | File:Line | Issue |
|----------|-----------|-------|
| Medium | `60:4-47` `extract()` | Errors via `echo` to stdout not stderr; inconsistent `return 1` vs `return 0` after gunzip etc. Should `print -u2`. |
| Medium | `60:116-123` `fkill()` | `kill "-$signal"` no validation that signal is numeric/name; could `kill -` empty. Fixed by `${signal#-}` but `kill ""` possible. |
| Low | `60:972-981` `croot()` | `cd "$root" || return` missing error code propagation (`cd` failure returns 1 anyway, but suppresses `set -e`). OK. |
| **High** | `62-cgm.zsh:467` `_cgm_set` | Backs out catalogue entry only if `created_marker==1` and `secret-tool` fails — correct. But `_cgm_env` `values=()` zeroing on failure (550) good; ensures no partial secrets linger. |
| Medium | `40:192-210` `_fzf_validate()` | On `fzf --version` failure sets `blocked` + `version check failed` — good. On `unparseable version` caches `blocked` — prevents retry without restart. Intended but may need `fzf` upgrade hint. |
| Medium | `60:2073-2118` `_upkg_run_search_apt()` | Filters `WARNING: apt…` via `sed` then checks `rc!=0` — good. But `print -r -- "$output"` leaks apt errors to stdout not stderr. |
| Low | `init.zsh:32-34` | `source "$zsh_config_file"` failure silently ignored. Should `print -u2` on failure. |

---

## 7. Idempotency of `fpath`

**Pass.** `60-functions.zsh:107-108`:

```zsh
if (( ! ${fpath[(Ie)$_ZSH_CONFIG_FUNCTIONS_DIR]} )); then fpath=( "$_ZSH_CONFIG_FUNCTIONS_DIR" "${fpath[@]}" ); fi
```

Uses `(Ie)` exact indexed search, prepends once. Re-sourcing does not duplicate. Verified: `zsh -fc 'source init.zsh; source init.zsh; print ${#fpath[(r)*functions*]}'` → `1`.

Low nit: `_ZSH_CONFIG_FUNCTIONS_DIR` is `typeset -g` not `-gx` — not exported, correct. But re-sourced `init.zsh` re-evaluates `${(%):-%N}` which on second source still points to `60-functions.zsh` itself, not `init.zsh` — stable.

---

## 8. Lazy Helper Source Path — Fixed vs User-Controlled

**Pass overall, one inconsistency.**

| File | Line | Path | Verdict |
|------|------|------|---------|
| `25-theme.zsh:21` | `typeset -g _ZSH_THEME_MODULE_DIR=${_ZSH_THEME_MODULE_DIR:-${${(%):-%N}:A:h}}` | Fixed to repo dir via `:A:h` + `:A` canonicalization | ✅ Repo-owned, no `XDG` fallback, no `eval`. Meets AGENTS “keep private `functions/` path idempotent and fixed”. |
| `60-functions.zsh:106` | `typeset -g _ZSH_CONFIG_FUNCTIONS_DIR=${${(%):-%N}:A:h}/functions` | Fixed | ✅ |
| `55-ui-helpers.zsh:4` | `typeset _ui_theme_module=${${(%):-%x}:A:h}/25-theme.zsh` | Uses `%x` not `%N`, still repo-relative but diverges | ⚠️ Low — change to `%N` |
| `25:52-54` `132-134` | `[[ -r $_ZSH_THEME_MODULE_DIR/lib/theme-registry.zsh ]] || return 1; source …` | Hardcoded subpath, checks `-r` | ✅ No user-controlled `ZSH_THEME_DIR` |
| `40:348-361` | `${XDG_CACHE_HOME:-$HOME/.cache}/zsh/fzf/…` | Cache only, not code source | ✅ OK — not executable unless validated via `_fzf_cache_file_is_safe` + `zsh -fn` syntax check (40:514) |

No `eval`, filesystem theme discovery, or `$ZSH_CUSTOM / $fpath` user-controlled source found — complies.

---

## 9. Completion Definitions Correctness (`66-compdefs.zsh`)

| Severity | Line | Finding |
|----------|------|---------|
| **Pass** | `5` | Guard `if (( $+functions[compdef] ))` — correct, prevents errors when `compinit` not yet run (per header). |
| Low | `6-34` | Global arrays `typeset -ga _ZSH_UPKG_COMMAND_SPECS` etc. set on every source, no idempotency check — could duplicate if `compdef` already defined and file re-sourced via `source 66…` manually. Wrap with `(( ${+_ZSH_UPKG_COMMAND_SPECS} )) || …`. |
| **Pass** | `88-117` | `_zsh_upkg` uses `_arguments -C -s` with `'(-h --help)'{-h,--help}` and `_values -s ,` for `--only/--skip` — correct. |
| Low | `128` | Cache glob `"$cache_dir"/nixpkgs-attrs-*.txt(N.)` uses `(N.)` — correct null-glob + regular file; star may match stale system file after `nix flake` system change (handled elsewhere). |
| **Pass** | `179-225` | `cgm` completion guarded by `if (( $+functions[cgm] ))` both for spec definition (67) and compdef (335). Catalogue-based `_zsh_cgm_saved_credentials` correctly uses `reply` array. |
| Low | `232-253` | `_zsh_extract`, `_zsh_dusage` etc. not guarded against `compdef` redefinition on re-source — second `compdef` errors `function already defined`. Add `compdef -d` or check. |
| Info | `323` | `compdef _zsh_find_helper ff ft` — one completion for two commands (shared pattern/ path) correct. |

Overall: Correct and portable; minor re-source duplication risk only.

---

## 10. Duplication Between Modules

(See DRY table; summary)

* `25-theme ↔ 55-ui-helpers`: locale UTF-8, term width, color depth, glyph tables.
* `40-fzf ↔ 30-zoxide`: `FZF_*_OPTS` inheritance capture + `NO_COLOR` signature.
* `60-functions` internal: `dusage↔bigfiles`, 8× search handlers, 4× `outdated` handlers, fallback block vs `55-`.

Recommendation: Shared `lib/ui-terminal.zsh` for `dim/glyph/color_depth`; `_upkg_run_search()` template taking command/args/parse-func.

---

## 11. Magic Numbers

| Value | Where | Meaning | Fix |
|-------|-------|---------|-----|
| `100000` | `10:2-3` | HISTSIZE/SAVEHIST | Define `typeset -gi _ZSH_HISTORY_MAX=100000` + reuse; doc “10× default”. |
| `3` | `20:8` `lt='… --depth=3'` | Tree depth | `typeset -g _ZSH_TREE_DEPTH=3` |
| `0.68.0`, `2` | `40:3,6` | `_FZF_MIN_VERSION`, `_FZF_CACHE_SCHEMA` | Named correctly ✅ |
| `9` | `40:168` | component length limit for `10#` overflow guard | Add comment `# 9-digit limit prevents 32-bit overflow in 10#`. |
| `0022` | `40:374` | group/other writable mask | Add ` /* 002=group-w, 020=other-w */`. |
| `700`, `600`, `077` | `62:135,176,169` | catalog perms | Named ✅ |
| `86400` | `60:3847` | cache stale 24h | `typeset -gi _NPKG_CACHE_TTL=86400` |
| `60`, `80`, `100`, `32` | `55:65`, `25:326`, `60:593`, `60:488` | term width breakpoints for layout | `typeset -gA _ZSH_LAYOUT_BREAKPOINTS=( narrow 60 compact 80 wide 100)`. |
| `16`, `10`, `9`, `5` | `60:591-592`, `741-742` | `bar_width`, `size_width`, `percent_width` | Constants at top of each function. |
| `6`, `8`, `9` | `55:487`, `60:737`, `60:4498` | `_ui_visible_count` reserve | Document `reserve= header+footer`. |
| `8` | `60:4178` `max_jobs=8` | parallelism for `npkg outdated` | `_NPKG_MAX_JOBS`. |
| `50` | `60:2250` `info_limit=50` | brew search cap | `_UPKG_BREW_INFO_LIMIT`. |

---

## 12. Maintainability of Theme Palette / Glyph Separation (`25-theme.zsh` + `lib/`)

**Strengths (keep):**

* ✅ Single source `25-theme.zsh` + lazy `lib/theme-palettes.zsh` / `lib/theme-registry.zsh` / `lib/theme-color.zsh` — pure-Zsh startup (`no probes, no eval, no filesystem discovery`) per AGENTS.
* ✅ Semantic roles `base/surface/selected/border/gutter/text/muted/accent/query/match/focus/info/success/warning/danger` (13 roles) — renderers consume roles via `_zsh_theme_color_value` / `_zsh_theme_sgr`, not palette names.
* ✅ Glyph tier `nerd/unicode/ascii` via `_zsh_theme_resolve_glyph_tier` + `_zsh_theme_glyph` — separated from color.
* ✅ Fixed lazy stub trick in `25:57-158` — startup defines lightweight stubs, first `*_role_hex` loads registry + palettes.

**Weaknesses:**

| Severity | File:Line | Issue |
|----------|-----------|-------|
| Medium | `25:26-28` + `162-167` | `if (( _ZSH_THEME_BUILTIN_PALETTES_LOADED ))` then `source palettes` — reads as “if loaded, load again” (re-source for idempotency). Intentional but inverted vs normal `if (( ! LOADED ))`. Add comment `# re-source after eager load for test harness`. |
| Medium | `25:57-65` | Stub self-recursion pattern `_zsh_theme_has_role() { _zsh_theme_load_registry || return; _zsh_theme_has_role "$@" }` relies on redefinition after `source`. Works but surprises `zsh -x` and static analysis. Alternative: stubs call `_zsh_theme_has_role_impl` then alias. |
| Medium | `lib/theme-registry.zsh:71-97` | `catppuccin-latte` overrides ANSI codes hard-coded (0,7,8,15) divergent from other palettes’ `0,8,15,13` — subtle; no test asserts contrast ratio. Add comment why `latte` uses lighter base. |
| Medium | `lib/theme-color.zsh:15-72` | RGB→256 cube+gray distance algorithm duplicated from standard 256-color formula, no attribution + magic `65536`, `196608`, `levels=(0 95 135 …)`. |
| Low | `25:292-348` | `_zsh_theme_fzf_chrome_opts` caches `signature` in globals `_ZSH_THEME_FZF_CHROME_SIGNATURE`/`_OPTS` — but `25:345 _zsh_theme_signature` excludes `COLUMNS` while `40:64 width_class` includes it — two signature schemes drift. Unify via one function. |
| Low | `55-ui-helpers.zsh:106-126` | `_ui_unicode_icon` maps nerdfont `󰄬→✓` etc. 15 entries — palette-agnostic but ties to nerdfont codepoints; if `25-theme` adds new glyph, must update both tables. Centralize in `lib/glyphs.zsh`. |

Verdict: Design is **sound** — the separation is the repo’s best DRY example. Main debt is **readability** of lazy redefinition + duplicated signature/width logic, not architecture.

---

## Priority Fixes (Order)

1. **`60:515/650` extract `dusage`/`bigfiles` shared helper** — largest maintainability win.
2. **`40:45` deduplicate `NO_COLOR` and preview command** — 7× repetition → loop.
3. **`60` add `emulate -L zsh` to 7 bare functions** — correctness.
4. **`20:32-35` document alias bypass + consider `interactive`-only guard for `-i`** — prevents script hangs.
5. **`40:437` split `_fzf_initialize_zsh`** — testability.
6. **`25:57` comment lazy stub redefinition trick** + normalize `55:4` `%x` → `%N`.
7. **Define constants** for magic numbers (`_ZSH_TREE_DEPTH`, `_NPKG_MAX_JOBS`, etc.).
8. **Unify signature** (`_zsh_theme_signature` vs `width_class`) and **term-dimension helper**.

No `eval`, user-controlled theme sourcing, or missing `compdef` guards found. Startup remains guarded (`(( $+commands[…]))` at top-level, `command -v` inside functions) per AGENTS.
