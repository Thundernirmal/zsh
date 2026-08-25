# Muse Full Review — Zsh Config (`/home/nirmal/.config/zsh`)

**Date:** 2026-08-25  
**Model:** muse-spark-1.2-contributor  
**Method:** 5 parallel subagents (performance, project/docs, code quality, security/portability, tooling/CI) + synthesis. All files read: `init.zsh`, `10-history.zsh` through `80-tips.zsh`, `lib/theme-*.zsh`, `functions/ztheme`, `functions/_fbr_format_entry`, `scripts/*`, `.github/workflows/checks.yml`, `README.md`, `GUIDE.md`, `AGENTS.md`, `docs/specs/*`, `.gitignore`, `qa-features.csv`. Verified via `zsh -n`, `sh -n`, `zsh scripts/test-*.zsh`, `zsh -fc 'source init.zsh'`, `scripts/benchmark-startup.zsh`.

---

## 1. Executive Verdict

| Axis | Verdict | Critical | High | Medium | Low |
|---|---|---|---|---|---|
| **Performance** | Well-optimized — 22 ms command, 28 ms interactive (n=5 warm). One Major eager-load defeat. Guard discipline PASS. | 0 | 0 | 1 | 3 |
| **Project / Docs** | Structurally sound. Sourcing order matches AGENTS. Two Medium CI parity gaps. | 0 | 0 | 3 | 3 |
| **Code Quality** | Maintainable but DRY/complexity debt in `60-functions.zsh` + `40-fzf.zsh`. 2 Critical-length functions. | 2 | 10 | 13 | 25 |
| **Security / Portability** | Low residual risk. No secret leaks. Two Medium hardening items (zoxide eval, fzf `{}` injection). | 0 | 0 | 2 | 3 |
| **Tooling / CI** | CI green but not equivalent to `AGENTS.md` verification. 2 Critical divergences. | 2 | 2 | 4 | 5 |
| **Overall** | **Ship with fixes.** No blocker to daily use. Fix the 4 Critical + 12 High/Major before next stable release. | **4** | **12** | **23** | **39** |

**Startup hotness (µs, `zmodload zsh/datetime` isolated, `zsh -df`):**

| Module | µs | Note |
|---|---|---|
| 10-history | 59 | |
| 20-aliases | 8002 | 2× `--color` forks |
| 25-theme | 943 | pure-Zsh, lazy stubs |
| 30-zoxide | 4418 | **hottest after 20/60 — eager theme load** |
| 40-fzf | 1680 | cache-aware, interactive-gated |
| 50-completion | 556 | lightweight 3× zstyle |
| 55-ui-helpers | 453 | fallback guarded |
| 60-functions | 7043 | 125 KB / 4639 lines parsed, not executed |
| 65-help | 4149 | data-only |
| 66-compdefs | 1001 | gated on `compdef` |
| 70-globals | 85 | |
| 80-tips | 377 | hook-free, `$+commands` pool |
| **Total sourced** | **229173 bytes / 8459 lines** | |

---

## 2. Cross-Cutting Critical & High Items (Fix First)

### Critical (4)

| ID | File:Line | Issue | Fix |
|---|---|---|---|
| **C-CI-01** | `.github/workflows/checks.yml:33` | `scripts/benchmark-startup.zsh` never syntax-checked in CI (`AGENTS.md:42` requires `zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh`). Silent regression risk for `zmodload`/`EPOCHREALTIME` changes. | Add `run: zsh -n scripts/benchmark-startup.zsh` (or combined). |
| **C-CI-02** | `.github/workflows/checks.yml:25` | CI splits AGENTS combined syntax gate into per-file steps without covering benchmark — diverges from documented copy-paste verification. | Align CI to AGENTS verbatim or update AGENTS to document split + keep benchmark coverage. |
| **C-CQ-01** | `60-functions.zsh:3407-3779` `upkg()` 372 LOC / ~35 cyclo | Orchestrator does arg-parse + detection + filter + dispatch + summary. Hard to test/reason. | Split `__upkg_parse_args`, `__upkg_run_selected`. |
| **C-CQ-02** | `60-functions.zsh:4160-4556` `_npkg_outdated()` 396 LOC | Concurrent job pool `max_jobs=8`, 3 trap scopes. Hardest to test. | Extract `__npkg_collect_profile`, `__npkg_eval_batch`, `__npkg_render`. |

### High / Major (12)

| ID | File:Line | Issue | Severity |
|---|---|---|---|
| **H-Perf-F1** | `30-zoxide.zsh:31` | Unconditional `_zsh_zoxide_refresh_fzf_opts` eagerly loads theme registry+palette (3-4 ms) even in `zsh -df`/hooks. Defeats lazy invariant; `40-fzf.zsh:549` correctly gates on `interactive`. | **Major** |
| **H-CI-01** | `.github/workflows/checks.yml:70` EOF | Missing `zsh -fc 'source "$HOME/.config/zsh/init.zsh"'` smoke test (`AGENTS.md:53` step 11). Real-HOME ordering/`zle` regressions invisible. | High |
| **H-CI-02** | `.github/workflows/checks.yml:15-22` | CI only installs `zsh`; never runs `scripts/check-deps.sh`. Required-tool version gate (`fzf>=0.68.0`, `lsd`, `zoxide`, `ss`) untested in CI. | High |
| **H-CQ-01** | `60-functions.zsh:515-647` vs `650-793` | `dusage` vs `bigfiles` ~85% duplication (~260 LOC): mktemp+`du --null`, `(@On)` sort, rich/plain branching, `_ui_bar`. | High |
| **H-CQ-02** | `40-fzf.zsh:73-143` | `[[ -n ${NO_COLOR:-} ]] && FOO+=' --no-color'` repeated 7×. | High |
| **H-CQ-03** | `40-fzf.zsh:79-82` | Preview command duplicated for `NO_COLOR` vs color (only `--color=never/always` diff). | High |
| **H-CQ-04** | `40-fzf.zsh:437-545` `_fzf_initialize_zsh()` 108 LOC | Cache validation + `fzf --zsh` generation + mktemp + chmod + trap + syntax check in one function. | High |
| **H-CQ-05** | `25-theme.zsh:358-424` `_zsh_theme_resolve_settings()` 66 LOC | Nested `custom_needed` + 3 fallback branches. | High |
| **H-CQ-06** | `60-functions.zsh:650-793` `bigfiles()` 143 LOC | See DRY above. | High |
| **H-CQ-07** | `60-functions.zsh:796-941` `ports()` 145 LOC | Inline 40-line awk + 5 width calcs. | High |
| **H-Alias-01** | `20-aliases.zsh:32` `alias mkdir='mkdir -p'` | Silences "already exists" (`echo $?` 0 even if exists); breaks `mkdir foo && echo ok` scripts. Mitigated via `command mkdir` but undocumented. | High |
| **H-Alias-02** | `20-aliases.zsh:35` `alias rm='rm -iv'` | `-i` hangs `rm -rf $tmp` in non-interactive `zsh -c 'source init.zsh; rm …'` pipelines; `-v` floods logs. | High |

---

## 3. Performance — Pass with One Major

**Guard matrix PASS:**

| Location | Expected | Actual |
|---|---|---|
| Top-level `20-aliases:4,20,38`, `30-zoxide:33`, `40-fzf:550`, `init:29`, `80-tips:40+` | `(( $+commands[tool] ))` | ✅ |
| Function bodies `60-functions:19+`, `65-help:152+`, `62-cgm:12`, `55-ui-helpers:15,31` | `command -v … >/dev/null` | ✅ |
| `40-fzf` preview strings `40:79,81` | `command -v` inside FZF-spawned shell | ✅ required, not `$+commands` |
| `40-fzf:201,255,446,513` | Hybrid cache gate + `command -v` validation | ✅ |

Long-PATH WSL impact measured: 100× `$+commands` miss `0.09 ms` vs `command -v` miss `14.5 ms` (150×) — repo correctly avoids top-level `command -v`.

**Lazy-loading PASS with F1 exception:** `functions/ztheme` + `_fbr_format_entry` via `60-functions:106-111` `fpath`+`autoload -Uz` fixed to repo dir; `lib/theme-*.zsh` via `25-theme:50-55,130-135` stubs; no `eval`/FS discovery/curl/downloads in `25-theme:1-21`. F1 defeat is the only eager path.

**Fix F1:**

```zsh
# 30-zoxide.zsh:31
if [[ -o interactive ]] && [[ -z ${ZSH_EXECUTION_STRING:-} ]]; then
  _zsh_zoxide_refresh_fzf_opts
fi
```

**Minors:** `25-theme:26-28,162-167` dead duplicate `if (( _ZSH_THEME_*_LOADED ))` blocks (never executed — lazy wrappers already cover reload); `20-aliases:10,42,46` forks `ls --color`/`grep --color`/`diff --color` (~1-2 ms each) — keep if portability matters, document why not `$+commands`; `55-ui-helpers:3-7` fallback `[[ -r 25-theme.zsh ]]` stat ~0.05 ms — safe for standalone source.

See `muse_performance_report.md` for full benchmark evidence and per-module costs.

---

## 4. Project & Docs — Structurally Sound

**Passes (Info):** `init.zsh:14-27` sourcing order exactly matches `AGENTS.md:6` (13 modules, `62-cgm` gated on `secret-tool`); `README.md` stays short entrypoint with links to `GUIDE.md` (no second reference); `GUIDE.md:59-82` module table verbatim; `65-help.zsh:54-115` terse 5-field records, no GUIDE duplication; `80-tips.zsh:113-141` hook-free (`add-zsh-hook`/`precmd` 0 hits), startup `(( $+commands ))` pool; `docs/specs/high-priority-ux-remediation.md:5` marked `Implemented` + GUIDE link; `.gitignore:2` correctly ignores `qa-features.csv`; `scripts/check-deps.sh` POSIX `#!/bin/sh` `set -u`, required `zsh,git,curl,ss,lsd,zoxide,fzf` vs optional `bat,tree,fd,jq,secret-tool,nix` matches `AGENTS.md:56`; `50-completion` lightweight (only 3 `zstyle`s); `25-theme` pure-Zsh separation via semantic roles.

**Mediums:**

| ID | Location | Issue | Fix |
|---|---|---|---|
| M-01 | `checks.yml:25-70` vs `AGENTS.md:43` | Never syntax-checks `benchmark-startup.zsh` in CI | Add step |
| M-02 | `checks.yml:70` vs `AGENTS.md:53` | Never runs `zsh -fc 'source init.zsh"' smoke | Add step |
| M-03 | `qa-features.csv:2-13` vs `AGENTS.md:64` | Every row `Passed` — AGENTS requires default `Not Run` fillable checklist | `sed 's/,Passed/,Not Run/g'` + keep 12-row HC-01–04 set; expand to 39-row theming matrix before stable release or document reduced scope |

**Lows:** `qa-features.csv` under-covers `theming-and-fzf-ui-plan.md:759` 39-row T8 matrix (only 12 rows) — expand or document Nix-blocked exclusion; `theming-and-fzf-ui-plan.md:3` not yet `Implemented` (intentionally — Nix-host visual signoff blocked) — add banner `Implemented (available-host QA complete; Nix-host visual QA blocked — see T8)`; `README.md:32-33` picker detail adds 2 lines — within tolerance.

See `muse_project_report.md`.

---

## 5. Code Quality — Debt in Duplication & Length

**Syntax:** All 17 files `zsh -n` clean; `sh -n scripts/check-deps.sh` clean.

**Idiomatic Zsh:** Missing `emulate -L zsh` in `60-functions:4,51,61,85,161,171,972` (`extract`,`mkcd`,`ff`,`ft`,`headers`,`peek`,`croot` inherit caller `setopt`); `10-history:4` `HISTFILE=$HOME` unquoted; `55-ui-helpers:4` `%x` vs `25-theme:21`/`60:106` `%N` divergence; else array handling `(@On)`/`(DN)` idiomatic; `fpath` idempotency `60:107-108` `(Ie)` exact search correct.

**DRY hotspots:** `dusage↔bigfiles` 85%, `40-fzf` 7× `NO_COLOR`, duplicate 280-char preview lines, `_ui_term_width`↔`_ui_term_height`↔`25-theme` `case ${COLUMNS}`, `_ui_locale_is_utf8` duplicate, `_ui_truncate`↔`_ui_safe_truncate`, fallback `60:397-512` vs `55-ui-helpers`, `62-cgm:114-255` catalog checks 4×, signature string built 3× (use `_zsh_theme_signature:345`).

**Length:** see Critical/High table above. Threshold aim `<60` helpers, `<100` commands.

**Alias shadowing:** Detailed in §2 table + `70-globals:6-12` `alias -g G='| grep'` (global alias expands anywhere — opt-in risk, document `command` bypass, consider `[[ -o interactive ]]` guard).

**Error handling:** `60:4-47` `extract` `echo` to stdout not `print -u2`; `fkill:116-123` `kill "-$signal"` no full validation; `62-cgm:467` catalog atomic rollback correct + `_cgm_env` `values=()` zeroing; `40:192-210` `_fzf_validate` caches `blocked` without upgrade hint; `init:32-34` source failure silent.

**Naming:** `60:984` `function gitcount {` vs `alias gcount` legacy `function` keyword; `path()` shadows `/usr/bin/path`; globals mix `_ZSH_*`/`_FZF_*`/`_UPKG_*`/`_CGM_*` vs bare — document `_*` private convention.

**Magic numbers:** `100000` hist, `3` tree depth, `9` component overflow, `0022` mask, `86400` npkg TTL, `60/80/100/32` width breakpoints, `16/10/9/5` bar widths, `8` max_jobs, `50` brew limit — extract to named `typeset -gi`/`-gA` constants.

**Theme separation:** Strengths — single `25-theme.zsh` + lazy `lib/` via fixed `$_ZSH_THEME_MODULE_DIR`, 13 semantic roles, glyph tier `nerd/unicode/ascii`. Weaknesses — `25:26-28,162-167` inverted `if (( LOADED ))` re-source, stub self-recursion ` _zsh_theme_has_role() { _zsh_theme_load_registry || return; _zsh_theme_has_role "$@" }`, `catppuccin-latte` ANSI divergence, RGB→256 `65536`/`levels=(0 95 135 …)` unattributed, dual signatures (`_ZSH_THEME_FZF_CHROME_SIGNATURE` vs `width_class`), `_ui_unicode_icon` split across `55:106`.

See `muse_code_review.md` for 56 findings with counts.

---

## 6. Security & Portability — Low Residual Risk

| Check | Verdict |
|---|---|
| Secret handling (`eval`/`export`/`xtrace`/completion/fallback) | **PASS** — `62-cgm:268` `typeset -gx -- "$1=$2"` literal export (no `eval`), `62:495` `emulate -L zsh`+`unsetopt xtrace` local to `_cgm_env` (test `test-cgm:324-346` asserts no leak + `trace_restored`), sentinel `'.'` preserves trailing newlines, `values=()` cleared on error, atomic, no plaintext fallback, `66-compdefs:180-193` cgm completion only reads catalog markers `chmod 600`, `secret-tool store` via stdin. One Low: `_cgm_catalog_root:90-104` accepts relative `XDG_DATA_HOME` without `== /*` check (vs `40-fzf:353` which validates). |
| Theme purity | **PASS** — `25-theme:1-426` pure Zsh `typeset` only, no `command -v`/`$(…)`/`tput`/`git`/`curl`/`eval`, lazy loads via fixed dir. One Low: `25:21` `${_ZSH_THEME_MODULE_DIR:-${(%):-%N}}` allows caller-exported redirect to `/tmp/evil` — pin to `${(%):-%N}:A:h` unconditionally or validate. |
| Path injection / eval | **PASS** with **Medium**: `30-zoxide:34` `eval "$(zoxide init zsh)"` with no `zsh -fn` validation or empty check — PATH-hijacked `zoxide` could emit `rm -rf …`; contrast `40-fzf:470-525` validates via `mktemp`+`chmod 700`+`! -L`+`-O`+`zsh -fn`+`mv -f` atomic publish. Low: `60:3828,3862` `npkg` `XDG_CACHE_HOME` without `== /*` guard. |
| Tool guards | **PASS** — startup `(( $+commands[tool] ))` (no PATH walk), function `command -v` (fresh, stub-safe), `init:29` `secret-tool` gate never contacts Secret Service on source (`test-cgm:164-188` log empty), `40-fzf:79-82` preview `command -v` correctly retained (fzf-spawned shell), `40:549` `[[ -o interactive && -z ${ZSH_EXECUTION_STRING} ]]` prevents `zle` warning. |
| FZF preview injection | **Medium** — `40-fzf:79-82,88-92` `preview_command='… -- {}'` + `FZF_CTRL_T_OPTS` `--preview=$preview_command` uses bare `{}` — fzf substitutes literally into `sh -c` without quoting (`foo; rm -rf ~`, `$(id)`, `'…'` inject). Mitigated only by `--` (stops flags, not `;`/`|`). **Fix:** use `{q}` quoted placeholder: `… -- {q}`. `60:1349` `fkill`/`fbr` already array-quoted safe. |
| Alias safety | PASS by design — high-impact `mkdir -p`/`cp -iv`/`mv -iv`/`rm -iv` + `alias -g G/L/W/H` intentional (`AGENTS.md:79`), mitigated via `command` bypass guidance, not a leak but scripts must use `command rm`. |
| `check-deps.sh` POSIX | PASS — `#!/bin/sh` `set -u` only `command -v`/`printf`/`[`/`case`, `sh -n` PASS, `dash`/`bash --posix`/`busybox` compatible. `${#var}` length is POSIX-2001. Minor hint drift `libsecret` vs `libsecret-tools`. |
| PATH-stub handling | PASS — `$commands` stale-hash avoided inside functions, fakes in `test-cgm`/`test-upkg` work. |

**Hardening diffs:**

```zsh
# 25-theme.zsh:21 pin module dir
typeset -g _ZSH_THEME_MODULE_DIR=${${(%):-%N}:A:h}

# 40-fzf.zsh:79 quote placeholder
preview_command='if [[ -d {q} ]]; then … lsd … -- {q}; … bat … -- {q}; … sed -n "1,200p" -- {q}; fi'

# 62-cgm.zsh:90 absolute XDG guard
[[ $XDG_DATA_HOME == /* ]] || { _cgm_error 'XDG_DATA_HOME must be absolute'; return 1; }

# 30-zoxide.zsh:34 validate before eval
_zoxide_init=$(command zoxide init zsh 2>/dev/null) || return
[[ -n ${_zoxide_init//[[:space:]]/} ]] || return
command zsh -fn -c "$_zoxide_init" >/dev/null 2>&1 || return
eval "$_zoxide_init"
```

Positive controls to preserve: `62-cgm` `chmod 700`/`600`+`umask 077`+`noclobber`+symlink/non-dir/readonly `parameters[$candidate]` guards; `40-fzf` cache hardening `-O`/`! -L`/`0022`; `60` `dusage`/`bigfiles` `du --null`+`--files0-from`+`--` quoting+`mktemp`+trap.

See `muse_security_portability_report.md`.

---

## 7. Tooling & CI — Green but Divergent

**Verification matrix (local):**

| Command | Local | CI |
|---|---|---|
| `zsh -n *.zsh lib/*.zsh functions/ztheme functions/_fbr_format_entry` | ✅ | ✅ `checks.yml:25` |
| `zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh` | ✅ | **❌ missing benchmark** `checks.yml:33` only `test-theme`+`test-init` |
| `sh -n scripts/check-deps.sh` | ✅ | ✅ `checks.yml:28` |
| `zsh scripts/test-init.zsh` | ✅ ~90 ok | ✅ |
| `zsh scripts/test-theme.zsh` | ✅ 36 ok | ✅ |
| `zsh scripts/test-functions.zsh` | ✅ | ✅ |
| `zsh scripts/test-cgm.zsh` | ✅ 60+ asserts | ✅ |
| `zsh scripts/test-upkg.zsh` | ✅ | ✅ |
| `zsh scripts/test-completions.zsh` | ✅ | ✅ |
| `zsh scripts/test-help.zsh` | ✅ | ✅ |
| `zsh -fc 'source "$HOME/.config/zsh/init.zsh"'` | ✅ silent | **❌ absent** |
| `scripts/check-deps.sh` (required `1` vs optional `0`) | ✅ `189-204` | **never run** (only `sh -n`) |
| `scripts/benchmark-startup.zsh 5` | ✅ 22 ms / 28 ms | never run (intentional) |

**Mediums:** CI `sudo apt-get update` without cache (`M1`); no `timeout-minutes` (hang `zselect` 600-tick `test-upkg` loop — `M2`/`F1`); `L1` `master` branch filter noise.

**Portability:** `check-deps.sh` POSIX `IFS newline` literal newline fragile but correct — add comment `literal newline, not \n` or use `IFS=$(printf '\nX'); IFS=${IFS%X}` (`P1`); `${#var}` POSIX (`P2`); `ss` from `iproute2` hint drift (`P4`).

**Test robustness:** `test-init:6` `zsh_bin=${commands[zsh]}` no fallback when `zsh` unhashed → fix `:${commands[zsh]:-$(command -v zsh)}` like `test-theme:3` (`R1`); `prepare_fzf_fakebin:149-160` symlinks empty `commands[$tool]` → guard `[[ -n ${commands[$tool]:-} ]] || continue` (`R2`); `test-upkg:8-12` `fakebin=$(mktemp -d)` `/tmp` collision in `make -j` (`R4`); `test-upkg:240` `zselect` busy-loop without skip on missing `zselect` (`R5`).

**Benchmark:** `benchmark-startup.zsh:19-22` `benchmark_root != ${HOME}/.config/zsh` hard-fails for `/tmp`/`/github/workspace` checkouts — add `ZSH_BENCHMARK_ROOT` override (`B1`); ignores child exit status (`B4`); `TERM=xterm-256color` `COLORTERM=truecolor` masks plain-mode speed (`B6`).

**Coverage gaps:** `10-history` (no test), `20-aliases` partial (quiet probes only, not `alias ..`), `30-zoxide` partial, `50-completion` none (`zstyle` matcher), `55-ui-helpers` indirect only, `70-globals` none (`alias -g G`).

**CI patch (ordered):**

```yaml
- name: Check Zsh syntax (modules)
  run: zsh -n *.zsh lib/*.zsh functions/ztheme functions/_fbr_format_entry
- name: Check Zsh syntax (scripts)
  run: zsh -n scripts/benchmark-startup.zsh scripts/test-*.zsh
- name: Check dependency script syntax
  run: sh -n scripts/check-deps.sh
- name: Smoke-source init
  run: zsh -fc 'source "$HOME/.config/zsh/init.zsh"'
# + timeout-minutes: 10, comment "# Tests stub lsd/zoxide/fzf via fakebin; only zsh required"
```

See `muse_tooling_ci_report.md`.

---

## 8. Prioritized Action Plan

### Phase 1 — Before next release (1 PR, ~30 lines)

1. `30-zoxide.zsh:31` wrap `_zsh_zoxide_refresh_fzf_opts` in `[[ -o interactive ]]` guard (saves 3-4 ms + keeps theme lazy in hooks/scripts).
2. `.github/workflows/checks.yml` add `zsh -n scripts/benchmark-startup.zsh` + `zsh -fc 'source …/init.zsh'` + `timeout-minutes: 10`.
3. `30-zoxide.zsh:34` validate `zoxide init` via `zsh -fn` before `eval`.
4. `40-fzf.zsh:79-82` switch preview `{}` → `{q}`.
5. `25-theme.zsh:21` pin ` _ZSH_THEME_MODULE_DIR=${(%):-%N}:A:h` + `62-cgm.zsh:90` `XDG_* == /*` harden.
6. `qa-features.csv` `s/,Passed/,Not Run/g` for release template + add comment that 12-row is reduced HC-01–04 set or expand to 39-row T8 matrix.

### Phase 2 — High-value debt (1-2 PRs)

7. `60-functions:515/650` extract `__usage_collect`/`__usage_render_*` for `dusage`/`bigfiles`.
8. `40-fzf.zsh:45-147` deduplicate 7× `NO_COLOR` via helper/loop + unify preview color `local color=always; [[ -n ${NO_COLOR} ]] && color=never`.
9. `60-functions` add `emulate -L zsh` to 7 bare functions; `10:4` quote `HISTFILE`; `55:4` `%x`→`%N`.
10. Document `20-aliases:32-35` bypass (`command mkdir`/`\mkdir`/`unalias`) in file header + `GUIDE.md`; consider `alias rm='rm -I'` or `[[ -o interactive ]]` guard.
11. `scripts/test-init.zsh:6` fallback `zsh_bin` + `prepare_fzf_fakebin` empty guard + `benchmark-startup.zsh:19` `ZSH_BENCHMARK_ROOT` override.

### Phase 3 — Polish (follow-up)

12. `25-theme:26-28,162-167` delete dead `if (( LOADED ))` re-source blocks.
13. Extract `lib/ui-terminal.zsh` for `_ui_term_dimension` + `_ui_locale_is_utf8` + color-depth/glyph helpers; unify `_zsh_theme_signature` vs `width_class`.
14. Extract constants `typeset -gi _ZSH_HISTORY_MAX=100000` etc. for 11 magic numbers.
15. Add `scripts/test-aliases.zsh` or extend `test-init` to assert `10-history`/`20-aliases`/`50-completion`/`70-globals`; add `zselect` skip + child `rc` check in benchmark; add IFS newline comment in `check-deps.sh`.

**Re-verify after Phase 1:**

```zsh
zsh -n *.zsh lib/*.zsh functions/ztheme functions/_fbr_format_entry
zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh
sh -n scripts/check-deps.sh
zsh scripts/test-init.zsh
zsh scripts/test-theme.zsh
zsh scripts/test-functions.zsh
zsh scripts/test-cgm.zsh
zsh scripts/test-upkg.zsh
zsh scripts/test-completions.zsh
zsh scripts/test-help.zsh
zsh -fc 'source "$HOME/.config/zsh/init.zsh"'
zsh scripts/benchmark-startup.zsh 30   # expect command median 19-21 ms after F1 fix
```

---

## 9. Positive Controls to Preserve

- Guard discipline: startup `(( $+commands ))` (150× faster than `command -v` on WSL), function `command -v` (PATH-stub safe), `FZF preview command -v` in fzf-spawned shell.
- Lazy loading: `fpath`+(Ie)+`autoload -Uz` fixed to repo dir, theme `pure-Zsh` + semantic roles + glyph tier + `zsh -fn` cache validation + `chmod 700`+`! -L`+`-O`+`0022` checks.
- Secret hardening: `typeset -gx --` literal, `unsetopt xtrace` local via `emulate -L`, sentinel `'.'`, `umask 077`+`noclobber`+`chmod 700/600`+symlink/readonly guards, value-free completion, file-based `secret-tool store` logging without secret.
- Doc ownership: `README` short+linked, `GUIDE` complete, `65-help` terse 5-field, `80-tips` hook-free one-liners.
- Tests: ephemeral `HOME`/`XDG_*`/`PATH=fakebin`+`trap` isolation, 891-line `test-init` FZF gating/caching regression coverage.

---

## 10. Files for Deep Dives

- `muse_performance_report.md` — benchmark evidence, guard matrix, per-module µs, F1 fix.
- `muse_project_report.md` — sourcing order, README/GUIDE/spec ownership, CI vs AGENTS diff, QA checklist.
- `muse_code_review.md` — 56 findings across 11 categories, DRY tables, length/complexity, alias risks.
- `muse_security_portability_report.md` — secret/theme/path/FZF injection/POSIX matrices with diff-ready hardenings.
- `muse_tooling_ci_report.md` — CI parity, syntax scope, POSIX notes, test harness robustness, benchmark accuracy.

---

*Generated from 5 subagent audits + local `zsh -n`/`sh -n`/`benchmark` evidence. No secrets retrieved (all `secret-tool` via PATH-stubbed fakes). All `file:line` references verified against current checkout.*
