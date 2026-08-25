# Ox Performance Review — `~/.config/zsh`

**Date:** 2026-08-25 · **Scope:** startup-path cost anatomy, guard-rule compliance, hot-path hazards, benchmark adequacy. Findings verified against source; no code was executed or modified during review.

## 1. Startup anatomy (what actually runs)

`init.zsh` sources 13 modules in numeric order. Reading the top level of each:

| Module | Top-level work beyond definitions | Verdict |
|---|---|---|
| `10-history.zsh` | option/size assignments only | ✅ pure |
| `20-aliases.zsh` | `$+commands` guards **plus 3 external executions** (see F2) | ⚠️ |
| `25-theme.zsh` | `typeset` declarations, re-source flags, pure param-exp dir derivation, one env-string resolver call | ✅ pure |
| `30-zoxide.zsh` | guarded `eval "$(zoxide init zsh)"` (1 fork + eval) | ✅ acceptable |
| `40-fzf.zsh` | cache-keyed bootstrap; warm path is pure Zsh via `zmodload zsh/stat` stat keys | ✅ well-engineered |
| `50-completion.zsh` | `zstyle` only | ✅ pure |
| `55-ui-helpers.zsh` | function definitions only | ✅ pure |
| `60-functions.zsh` | 90 funcdefs, fpath prepend, 2 autoloads, UI stub guards, **1 top-level `command -v nix`** | ❌ F1 |
| `62-cgm.zsh` | skipped entirely without `secret-tool` (`init.zsh:29`) | ✅ |
| `65-help.zsh`, `66-compdefs.zsh`, `70-globals.zsh`, `80-tips.zsh` | definitions + `$+commands` guards | ✅ pure |

## 2. Findings

### F1 · HIGH — Top-level PATH walk on every start
`60-functions.zsh:3782`
```zsh
if command -v nix >/dev/null 2>&1; then
```
This wraps ~857 lines of `npkg` definitions and runs a `command -v` PATH scan on **every shell start** — the exact hazard AGENTS.md forbids ("a `command -v` miss walks the whole `PATH`, which dominates startup time on long `PATH`s such as WSL2"). Every sibling guard uses `(( $+commands[nix] ))`. Double penalty when nix is absent: full PATH miss, nothing gained.

**Fix:** `if (( $+commands[nix] )); then` — or better, move the block to an autoloaded `functions/npkg` (pattern already exists via `functions/ztheme`), which removes both the guard question and the parse cost.

### F2 · MEDIUM — Unconditional process forks at startup
`20-aliases.zsh:10` `command ls --color=auto .` · `:42` `print -r -- x | command grep --color=auto -e x` · `:46` `command diff --color=auto /dev/null /dev/null`

Three external executions per startup probing `--color` support. Cost is small (~few ms) but always paid, unlike F1 which is PATH-length dependent. `--color=auto` support is near-universal on systems where these aliases matter.

**Fix:** replace with `$+commands[grep]` / `$+commands[diff]`; simplify or drop the `ls` probe in the non-lsd fallback branch.

### F3 · LOW — Subshell forks in render loops
`55-ui-helpers.zsh:176` (`<<< "$(_ui_status_metadata …)"`), `:260` (`local text=$(_ui_truncate …)`), and `_upkg_print_summary`'s per-manager metadata calls. Each `$()` is a fork; rich `upkg` summaries spawn dozens of short-lived subshells. User-invoked only — never prompt-time — so cosmetic.
**Fix (optional):** have `_ui_status_metadata`/`_ui_truncate` set `REPLY` instead of printing.

### F4 · LOW (by design) — Cold fzf bootstrap spawns
On cache miss/stale, `40-fzf.zsh:228,470,488–495,514` spawns `fzf --version`, `fzf --zsh`, `mkdir/chmod/mktemp`, a `zsh -fn` check (~6–7 execs). Mitigated by the stat-keyed persistent cache (`_fzf_cache_file_for_path`, :341–362) so steady-state boots take the pure-Zsh path. Documented here only so cold-start isn't mistaken for steady-state cost.

### F5 · INFO — No prompt-time work at all
No `chpwd`/`precmd`/`preexec`/`add-zsh-hook`/`periodic` anywhere. Zero process spawns per prompt cycle. All caches are keyed by resolved tool path or reset per invocation — **no unbounded-growth risk found**.

## 3. Guard audit table

Startup = top of module (must use `$+commands`); in-function = body (must keep `command -v`); preview strings = fzf-spawned shell (must keep `command -v`).

| Location | Guard | Context | Verdict |
|---|---|---|---|
| `init.zsh:29` | `$+commands[secret-tool]` | startup skip gate | ✅ |
| `20-aliases.zsh:4,20,38` | `$+commands[...]` | startup | ✅ |
| `20-aliases.zsh:10,42,46` | executes binary | startup | ❌ F2 |
| `25-theme.zsh` | none needed | — | ✅ pure |
| `30-zoxide.zsh:33` | `$+commands[zoxide]` | startup | ✅ |
| `40-fzf.zsh:550` | `$+commands[fzf]` | startup | ✅ |
| `40-fzf.zsh:79–81` | embedded `command -v lsd/tree/bat` | preview strings | ✅ required by rule |
| `55-ui-helpers.zsh:15,31` | `command tput` | function bodies | ✅ |
| `60-functions.zsh` (in-function ×~15 sites) | `command -v … >/dev/null 2>&1` | function bodies | ✅ |
| **`60-functions.zsh:3782`** | `command -v nix` | **top level** | ❌ **F1** |
| `62-cgm.zsh:12` | `command -v secret-tool` | function body | ✅ |
| `65-help.zsh:152–204` | various | function bodies | ✅ |
| `80-tips.zsh:40–111` | `$+commands[...]` ×~15 | startup | ✅ |

## 4. Benchmark adequacy (`scripts/benchmark-startup.zsh`)

Measures median/p95/min/max wall-clock for `zsh -df` and `zsh -dfi` sourcing `init.zsh`. Gaps:

1. **No PATH-length variation** → cannot detect F1-class regressions, the exact scenario AGENTS.md names.
2. Warmups absorb first-run fzf cache generation → cold-boot cost invisible.
3. Wall-clock includes zsh fork/exec (~3–8 ms), swamping sub-ms module deltas; no per-module attribution (zprof/xtrace).
4. Interactive mode never renders a prompt/ZLE loop; costs outside the repo (OMZ compinit, starship) are excluded by design.

**Recommended additions:** long-PATH variant, cold-vs-warm cache modes, optional `-P` per-module profile mode.

## 5. Prioritized recommendations

1. Fix `60-functions.zsh:3782` → `$+commands[nix]` *(one line, restores rule compliance)*
2. De-exec the three `20-aliases.zsh` probes
3. Lazy-load npkg into an autoloaded helper (removes ~857 lines of parse cost)
4. Extend benchmark: long-PATH scenario, cold/warm modes, per-module attribution
5. REPLY-style returns in UI helpers to kill render-loop forks *(optional)*
