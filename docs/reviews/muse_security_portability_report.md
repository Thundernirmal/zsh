# Muse Security & Portability Report — Zsh Config

**Date:** 2026-08-25 · **Scope:** `62-cgm.zsh`, `25-theme.zsh`, `lib/theme-*.zsh`, `functions/ztheme`, `functions/_fbr_format_entry`, `init.zsh`, `20-aliases.zsh`, `30-zoxide.zsh`, `40-fzf.zsh`, `60-functions.zsh`, `70-globals.zsh`, `scripts/check-deps.sh`, `scripts/test-cgm.zsh`, `scripts/test-upkg.zsh`  
**Rules:** `AGENTS.md` — `62-cgm.zsh` fully optional / no Secret Service contact on source / no plaintext fallback / no reveal / no `eval`-export / no value-retrieving completion / no `xtrace` leak; `25-theme.zsh` startup pure-Zsh; `functions/` fixed to repo & idempotent; external tools guarded.

**Verification:** `zsh -n *.zsh lib/*.zsh functions/ztheme functions/_fbr_format_entry` **PASS**, `sh -n scripts/check-deps.sh` **PASS**, `zsh scripts/test-cgm.zsh` **PASS** (60+ asserts), `zsh scripts/test-init.zsh` **PASS**, `zsh -fc 'source init.zsh'` **PASS** (no `secret-tool` invocation on source).

## 1. Summary Matrix

| Check | Verdict | Severity of Open Items |
|---|---|---|
| Secret handling (`eval`/`export`/`xtrace`/completion/fallback) | **PASS** with 1 Low note | Low |
| Theme purity (`25-theme`) | **PASS** with 1 Low note | Low |
| Path injection / `eval` / user-controlled discovery | **PASS** with 2 Low/Medium notes | Medium |
| External-tool guards & fallbacks / portability | **PASS** | Info |
| Alias safety (`rm` etc) | **PASS by design** | Info |
| `check-deps.sh` POSIX `sh` portability | **PASS** | Info |
| PATH-stub handling (`$commands` vs `command -v`) | **PASS** | — |
| FZF preview injection | **FLAG** | **Medium** |

Overall residual risk: **Low**. No Critical/High secret-leak vectors. Two Medium hardening items (zoxide `eval` validation gap, fzf `{}` quoting).

## 2. Detailed Findings

### 2.1 Secret Handling — `62-cgm.zsh`

| Severity | File:Line | Evidence | Fix |
|---|---|---|---|
| **PASS** | `62-cgm.zsh:268-270` | `typeset -gx -- "$1=$2"` — literal export, not `eval`/`export $name=$value`/`eval "export $name=..."`. Preserves shell metachars as data. Verified by `scripts/test-cgm.zsh:286` injection fixture `token $(touch …); * [x] = spaced` leaves `SAFE_TOKEN` literal, `assert_not_exists` injection marker. | None — keep. |
| **PASS** | `62-cgm.zsh:495-496` | `emulate -L zsh` + `unsetopt xtrace` at `_cgm_env` entry. `emulate -L` implies `localoptions`, so `xtrace` disabled only for this call and restored on return. `scripts/test-cgm.zsh:324-346` enables caller `xtrace`, asserts trace file contains no secret and `trace_restored==on`. | None. |
| **PASS** | `62-cgm.zsh:538-551` | `secret-tool lookup` output captured via `command substitution + sentinel '.'` to preserve trailing newlines, validated for empty/multiline before any export. `values=(); value=''` cleared on every error path; atomic loop — no partial export. `test_env_all_is_atomic` confirms earlier vars unchanged on later lookup failure. | None. |
| **PASS** | `66-compdefs.zsh:180-193` | `_zsh_cgm_saved_credentials` calls only `_cgm_catalog_names` (reads `XDG_DATA_HOME/cgm/entries/*` markers) + `_values`. Never calls `secret-tool lookup`. Catalog markers are `chmod 600` empty files (`62-cgm.zsh:168-173`). | None. |
| **PASS** | `62-cgm.zsh:3-5,467,539,654` | No plaintext fallback file, no reveal subcommand, values passed via stdin to `secret-tool store` not argv. Log asserts `assert_not_contains "$log" "$secret"` for set/env. | None. |
| Low | `62-cgm.zsh:90-104` | `_cgm_catalog_root` accepts any `XDG_DATA_HOME` (relative, empty, `::` injection) without absolute-path check. Later `mkdir -p -- "$entries"` is quoted/safe but creates relative to `cwd` if `XDG_DATA_HOME=rel`. Contrast `40-fzf.zsh:353-355` which validates `XDG_CACHE_HOME == /*`. | Harden: `if [[ -n ${XDG_DATA_HOME:-} ]]; then [[ $XDG_DATA_HOME == /* ]] || { _cgm_error "XDG_DATA_HOME must be absolute: $XDG_DATA_HOME"; return 1; }; print -r -- "$XDG_DATA_HOME/cgm";` |

### 2.2 Theme Purity — `25-theme.zsh`

| Severity | File:Line | Evidence | Fix |
|---|---|---|---|
| **PASS** | `25-theme.zsh:1-426` | Startup path is `typeset` / pure-Zsh color/glyph helpers. No `command -v`, `$(…)`, `tput`, `git`, filesystem scan, `curl`/`git clone`, or `eval`. Lazy loads only `$_ZSH_THEME_MODULE_DIR/lib/theme-registry.zsh` / `theme-color.zsh` / `theme-palettes.zsh` via fixed dir. Registry consumes semantic roles (`base, surface…`) not palette names. | None. |
| Low | `25-theme.zsh:21` | `typeset -g _ZSH_THEME_MODULE_DIR=${_ZSH_THEME_MODULE_DIR:-${${(%):-%N}:A:h}}` allows caller-exported `_ZSH_THEME_MODULE_DIR=/tmp/evil` to redirect all lazy `source`es. `60-functions.zsh:106` fixes equivalent via `typeset -g _ZSH_CONFIG_FUNCTIONS_DIR=${${(%):-%N}:A:h}/functions` (unconditional). Violates “keep lazy helper sources fixed to repo directory, not user-controlled”. | Change to unconditional: `typeset -g _ZSH_THEME_MODULE_DIR=${${(%):-%N}:A:h}` + idempotent guard `(( ${_ZSH_THEME_MODULE_DIR:+1} )) || …` or document as test-only override with `[[ -o interactive ]]` gate. If override needed for tests, validate `[[ -d $_ZSH_THEME_MODULE_DIR && -O $_ZSH_THEME_MODULE_DIR && ! -L $_ZSH_THEME_MODULE_DIR ]]` before source. |

Also verified `lib/theme-registry.zsh:43-45` and `lib/theme-color.zsh:7-71` contain no probes/`eval`; `lib/theme-palettes.zsh` static data.

### 2.3 Path Injection / `eval` / User-Controlled Discovery

| Severity | File:Line | Evidence | Fix |
|---|---|---|---|
| **Medium** | `30-zoxide.zsh:34` | `eval "$(zoxide init zsh)"` executed unconditionally after `(( $+commands[zoxide] ))` guard, with **no** `zsh -fn` syntax validation or empty-output check. Contrasts `40-fzf.zsh:470-525` which validates `fzf --zsh` output via `zsh -fn`, checks `rc==0` & non-empty, uses `mktemp` + `mv -f` with `chmod 700` / `! -L` / `-O` checks before `source`. PATH-hijacked `zoxide` could emit `rm -rf …`. | Mirror fzf pattern: `local generated; generated=$(command zoxide init zsh 2>/dev/null); [[ -n ${generated//[[:space:]]/} ]] || return; print -r -- "$generated" | command zsh -fn >/dev/null 2>&1 || return; eval "$generated"` or at minimum `command zoxide init zsh > $tmp && zsh -fn $tmp && source $tmp`. |
| Low | `60-functions.zsh:3828,3862` | `npkg` cache dir uses `cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/npkg` without absolute check (again vs `40-fzf.zsh:353`). | Add same `== /*` guard as fzf cache. |
| Pass | `60-functions.zsh:106-109` | `fpath` idempotent: `if (( ! ${fpath[(Ie)$_ZSH_CONFIG_FUNCTIONS_DIR]} )); then fpath=( "$_ZSH_CONFIG_FUNCTIONS_DIR" "${fpath[@]}" ) fi` + `autoload -Uz` guarded by `$+functions`. | — |
| Pass | `functions/ztheme:42-54,144-156` | `_ztheme_apply` atomic rollback on failed finder refresh (`old_ui`/`old_fzf` restore), `_ztheme_export` prints `typeset -g ZSH_UI_THEME=${(q)theme}` (quoted via `(q)`), never writes `~/.zshrc`. | — |

### 2.4 Tool Guards & PATH-Stub Handling

| Severity | File:Line | Evidence | Fix |
|---|---|---|---|
| **PASS** | `init.zsh:29` | Startup gate `if [[ $zsh_config_file == *62-cgm.zsh ]] && (( ! $+commands[secret-tool] )); then continue; fi` — uses `$+commands` (cached hash, no PATH walk) per AGENTS. Never contacts Secret Service on source (`scripts/test-cgm.zsh:164-188` asserts log empty). | — |
| **PASS** | `62-cgm.zsh:12`, `60-functions.zsh:75-77`, `40-fzf.zsh:201,255` | Inside functions uses `command -v tool >/dev/null 2>&1` (fresh PATH lookup) so PATH-stubbed fakes in `scripts/test-cgm.zsh` / `scripts/test-upkg.zsh` work and `$commands` staleness avoided. | — |
| **PASS** | `40-fzf.zsh:79-82` preview strings | Embedded preview retains `command -v lsd/bat/tree` (not `$+commands`) because preview runs in separate `fzf` spawn shell — correct per AGENTS. Fallbacks: `lsd → tree → ls`, `bat → sed -n "1,200p"`. | — |
| **PASS** | `40-fzf.zsh:549-555` | Normal-prompt `if (( $+commands[fzf] )); then _fzf_initialize_zsh "$commands[fzf]"` guarded by `[[ -o interactive ]] && [[ -z ${ZSH_EXECUTION_STRING:-} ]]` prevents `zsh -i -c` `can't change option: zle` warnings. `66-compdefs.zsh:5` whole file behind `if (( $+functions[compdef] ))`. | — |
| Info | `20-aliases.zsh:4,20,38` | Startup guards correctly use `(( $+commands[lsd/bat/tree] ))`. Capability probe `command ls --color=auto .` and `command grep --color=auto` at top level do walk PATH but are single-shot `ls`/`grep` invocations, not tool-presence guards — acceptable. | No change. |

### 2.5 FZF Preview Command Injection

| Severity | File:Line | Evidence | Fix |
|---|---|---|---|
| **Medium** | `40-fzf.zsh:79-82,88-92` | `preview_command='… lsd … -- {}; … bat … -- {}; … sed … -- {}'` and `FZF_CTRL_T_OPTS` `--preview=$preview_command` use bare `{}`. `fzf` substitutes filename literally into `sh -c` without shell quoting; file named `foo; rm -rf ~` or `$(id)` or `'$(id)'` yields injection. Mitigated only by `--` (stops option parsing, not `;`/`|`). Same pattern in Upstream fzf configs. | Use fzf’s quoted placeholder `{q}` or `{}'`-quoting: `…' -- {q}'` or `' … -- '\''{}'\'' '` is still subject to shell parse — prefer `--preview='… -- {q}'` and test with `touch "a; echo pwned" $'/tmp/$ (id)'` files. Alternatively wrap preview in `sh -c 'file={q}; … "$file"'`. Verify with `fkill`/`fbr`/`dusage` previews which already use `--preview-label` + quoted `{5}`/`{}` via `_fzf_picker_preview_args`. Apply same to `40-fzf.zsh`. |

Note: `60-functions.zsh:1349-1365` (`fkill`/`fbr`) correctly uses array-quoted `command fzf "${fzf_args[@]}"` and safe `sed/awk` pipelines, no injection there.

### 2.6 Alias Safety — `20-aliases.zsh` / `70-globals.zsh`

| Severity | File:Line | Evidence | Fix |
|---|---|---|---|
| Info | `20-aliases.zsh:32-35` | `alias mkdir='mkdir -p'`, `cp/mv/rm='… -iv'` intentionally high-impact (documented in AGENTS:79). Scripts sourcing `init.zsh` would get interactive prompts (`rm -i` hangs non-interactive `rm -rf *` in `scripts/test-init.zsh:307`). Repo mitigates via guidance: automation must use `command rm` or `zsh -fc '…'`. | Keep but ensure `scripts/` never source `20-aliases.zsh` via PATH stub; already uses `command rm -f --`. No code fix. |
| Info | `70-globals.zsh:6-12` | Global aliases `alias -g G='| grep'` etc. Expand anywhere on command line (Zsh global alias). Not a leak but can surprise users pasting commands. | Document in GUIDE. No fix. |

### 2.7 Shell Portability — `scripts/check-deps.sh` (POSIX Sh)

| Severity | File:Line | Evidence | Fix |
|---|---|---|---|
| **PASS** | `scripts/check-deps.sh:1-220` | `#!/bin/sh`, `set -u`, only `command -v`, `printf`, `[`, `case`, `for … in "$@"`, `${var:-}`, `${#var}` (POSIX length). No `[[`, `((`, `local`, `function`, `source`, `&>` bashisms. `sh -n` **PASS**. Version parsing via `IFS='\n'` / `IFS=.` + `set -- $var` is POSIX. `dash`, `bash --posix`, `busybox sh` compatible. | — |
| Info | `scripts/check-deps.sh:111,119` | `${#fzf_major}` etc length expansion requires POSIX-2001 `sh`; ancient Bourne without `${#}` would fail, but `dash`/`bash`/`zsh` all support. If strict 1992 needed, replace with `case` length test. | Optional: `expr length` fallback not needed. Keep as-is; add comment `# requires POSIX ${#var}`. |
| **PASS** | `60-functions.zsh:3828` etc | `60-functions.zsh` is Zsh (uses `emulate -L zsh`, `typeset`, `(s:,:)`, `DN` glob qualifiers) — not required to be POSIX. | — |

## 3. Recommended Fixes (Diff-Ready)

**1. `25-theme.zsh:21` — pin module dir**

```zsh
# before
typeset -g _ZSH_THEME_MODULE_DIR=${_ZSH_THEME_MODULE_DIR:-${${(%):-%N}:A:h}}
# after
typeset -g _ZSH_THEME_MODULE_DIR=${${(%):-%N}:A:h}
```

**2. `40-fzf.zsh:79-82` — quote placeholder**

```zsh
# before
preview_command='… lsd … -- {}; … bat … -- {}; …'
# after
preview_command='if [[ -d {q} ]]; then if command -v lsd >/dev/null 2>&1; then lsd --tree --depth=2 --color=never --group-dirs=first -- {q}; elif command -v tree >/dev/null 2>&1; then tree -L 2 -a -- {q}; else command ls -la -- {q}; fi; elif command -v bat >/dev/null 2>&1; then bat --style=numbers --color=never --line-range=:200 -- {q}; else sed -n "1,200p" -- {q}; fi'
# propagate {q} to FZF_CTRL_T_OPTS generation as well
```

**3. `62-cgm.zsh:90-104` — absolute XDG guard**

```zsh
_cgm_catalog_root() {
  emulate -L zsh
  if [[ -n ${XDG_DATA_HOME:-} ]]; then
    [[ $XDG_DATA_HOME == /* ]] || { _cgm_error 'XDG_DATA_HOME must be absolute'; return 1; }
    print -r -- "$XDG_DATA_HOME/cgm"; return 0
  fi
  # …
}
```

**4. `30-zoxide.zsh:34` — validate before eval**

```zsh
if (( $+commands[zoxide] )); then
  local _zoxide_init
  _zoxide_init=$(command zoxide init zsh 2>/dev/null) || return
  [[ -n ${_zoxide_init//[[:space:]]/} ]] || return
  command zsh -fn -c "$_zoxide_init" >/dev/null 2>&1 || return
  eval "$_zoxide_init"
fi
```

## 4. Positive Controls to Preserve

* `62-cgm.zsh` catalogue hardening: `chmod 700` root/entries, `chmod 600` markers, `umask 077` + `noclobber` (`62-cgm.zsh:132-138,167-173`), symlink / non-dir / non-regular checks (`62-cgm.zsh:122-129,162-164`), `parameters[$candidate]` readonly/special guard (`62-cgm.zsh:61`).
* `40-fzf.zsh` cache hardening: `-O`/`! -L`/`0022` mode checks, `mktemp` + `chmod 700`, `zsh -fn` syntax gate, `mv -f` atomic publish (`40-fzf.zsh:364-415,486-545`).
* `60-functions.zsh` `dusage`/`bigfiles` uses `du --null` / `--files0-from` + `--` array quoting, `mktemp` + `rm -f` trap, no `eval` of user filenames.
* `66-compdefs.zsh` value-free cgm completion; `functions/ztheme` atomic `old_ui` rollback.

## 5. Method

Static read of all in-scope files, `grep` for `eval`, `secret-tool`, `typeset -gx`, `xtrace`, `$+commands` vs `command -v`, `FZF_*_OPTS` preview strings, `XDG_*` handling; POSIX audit of `check-deps.sh`; dynamic run of `zsh -n`, `sh -n`, `scripts/test-cgm.zsh` (62 asserts, all ok), `scripts/test-init.zsh`, `zsh -fc 'source init.zsh'`.

No secrets retrieved; all `secret-tool` interactions via PATH-stubbed fakes in existing tests.
