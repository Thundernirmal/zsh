# Muse Project & Docs Report — Zsh Config

**Date:** 2026-08-25 · **Scope:** `AGENTS.md`, `init.zsh`, `README.md`, `GUIDE.md`, `docs/specs/*`, `.github/workflows/checks.yml`, `65-help.zsh`, `80-tips.zsh`, `scripts/*`, `lib/*`, `functions/*`, `.gitignore`  
**Method:** Ownership boundary audit, sourcing order check, cross-doc link audit, CI vs AGENTS verification parity, QA checklist audit.

## Executive Verdict

Repo is **structurally sound**. Module sourcing, guard discipline, theme ownership, lazy-loading, POSIX `check-deps.sh` all conform to `AGENTS.md`. Documentation ownership respected. Two **Medium** gaps in CI vs documented verification, one Medium QA-template gap, two Low coverage gaps. `theming-and-fzf-ui-plan` not yet marked `Implemented` intentionally pending Nix visual signoff.

## Findings

| # | Severity | Location | Rule | Evidence | Fix |
|---|----------|----------|------|----------|-----|
| M-01 | **Medium** | `.github/workflows/checks.yml:25-70` vs `AGENTS.md:43-44` `GUIDE.md:812-813` | Verification steps accurate; CI must mirror AGENTS ordered suite | AGENTS step 2 is `zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh`. CI splits into `zsh -n scripts/test-init.zsh:31` + `zsh -n scripts/test-theme.zsh:34` and **never syntax-checks `scripts/benchmark-startup.zsh`**. GUIDE lists benchmark in same line. `zsh -n scripts/benchmark-startup.zsh` passes locally but uncovered in CI. | Add `run: zsh -n scripts/benchmark-startup.zsh` or merged line. Keep order identical to AGENTS 1-11. |
| M-02 | **Medium** | `.github/workflows/checks.yml:70` vs `AGENTS.md:53` `GUIDE.md:822` | Verification step 11 missing in CI | AGENTS:11 = `zsh -fc 'source "$HOME/.config/zsh/init.zsh"'` (`GUIDE.md:822`). CI stops at `test-help` and never runs final smoke test. | Add final step: `run: zsh -fc 'source "$HOME/.config/zsh/init.zsh"'` |
| M-03 | **Medium** | `qa-features.csv:2-13` vs `AGENTS.md:64` | Manual QA Checklist: default Status to Not Run | Header `qa-features.csv:1` is `cmd,expected behavior,Status` ✅ but every data row has `Passed`. AGENTS requires `Not Run` default so checklist fillable during manual QA. Current file is completed run, not blank template. | Reset Status to `Not Run` for all rows; keep passed file as `qa-features.passed.csv` if needed. |
| L-01 | **Low** | `qa-features.csv:1-13` vs `docs/specs/theming-and-fzf-ui-plan.md:759`, `docs/specs/high-priority-ux-remediation.md:303` | Historical spec: qa-features.csv local-only, correct columns, adequate coverage | CSV has 12 rows covering glob, fzf gates, plain help, hostile paths, npkg states — satisfies HC-01–04. Theming ledger `759` records **39-row** matrix (theme×layout×glyph×width×no-color×picker). Present 12-row under-covers T8 visual QA (`ztheme`, `zoxide`, `fbr` alignment, footer, 99/100-col responsive). | Before stable release expand to 39-row matrix per T8, or explicitly document host-blocked Nix pickers excluded and list remaining 12 as reduced set. Keep `.gitignore:2` — correctly ignored. |
| L-02 | **Low** | `docs/specs/theming-and-fzf-ui-plan.md:3` vs `AGENTS.md:14` `docs/specs/high-priority-ux-remediation.md:5-7` | Specs marked implemented and linked to GUIDE | `high-priority-ux-remediation.md:5` → `Implemented` + GUIDE link ✅. `theming-and-fzf-ui-plan.md:3` → `Implementation complete and audited through PF-03 — Nix-host visual signoff remains blocked` — **not** `Implemented`. AGENTS requires marked clearly + linked. Spec body `26,577,947` says mark Implemented only after every release gate — intentional (T8 blocked). | No code change pre-release. Optionally amend to `Status: Implemented (available-host QA complete; Nix-host visual QA blocked — see T8 ledger)` or keep as now and ensure `GUIDE.md:3` authoritative. Do not mark Implemented until T8 passes. |
| L-03 | **Low** | `README.md:32-33` vs `AGENTS.md:11-12` | README remains short entrypoint, not second GUIDE | `README.md:32-33` adds 2 lines picker detail: “Preview pickers use Ctrl+P … Ctrl+/”. Within tolerance — GUIDE `444-472` owns full picker reference. No copy-paste violation. | Keep as-is; if expanded move to `GUIDE.md#zoxide-and-fzf`. |
| I-01 | **Info** | `init.zsh:14-27` vs `AGENTS.md:6` | Module sourcing order | Exact match: `10-history,20-aliases,25-theme,30-zoxide,40-fzf,50-completion,55-ui-helpers,60-functions,62-cgm,65-help,66-compdefs,70-globals,80-tips`. All 13 files exist (`ls *.zsh` ✅). Optional `62-cgm` gated at `init.zsh:29` with `(( ! $+commands[secret-tool] ))`. `lib/theme-*.zsh` and `functions/{ztheme,_fbr_format_entry}` correctly not in init list (lazy helpers per AGENTS:7). | — |
| I-02 | **Info** | `README.md:1-67` vs `GUIDE.md:1-831` vs `AGENTS.md:11-17` | README vs GUIDE sync & ownership | `README.md:5` → “complete command reference … live in GUIDE.md” + links to `init.zsh`, `GUIDE.md`, `AGENTS.md`, `docs/specs/` — correct short entrypoint. `GUIDE.md:59-82` module table matches `init.zsh` order verbatim. `GUIDE.md:784-795` ownership table mirrors `AGENTS.md:11-17`. No long-form duplication; surfaces link instead of copy. | — |
| I-03 | **Info** | `65-help.zsh:54-115` vs `AGENTS.md:14` | Help records terse | Each `_zsh_help_register` has 5 fields: id, category, summary (3–6 words), usage, example, deps. E.g. `65-help.zsh:60` `zi … 'Pick a zoxide directory'… 'zoxide and fzf 0.68.0+'`. No GUIDE paragraph copy. `65-help.zsh:117-209` defers `command -v` checks to call time — per AGENTS:24. | — |
| I-04 | **Info** | `80-tips.zsh:1-141` vs `AGENTS.md:15,35` | Tips hook-free, short reminders | `80-tips.zsh:113-141` defines only `tips()`; grep `add-zsh-hook|precmd` → 0. Pools one-line hints (`"Use *(D) when a glob should include hidden entries"`). No implementation history. Startup `(( $+commands[tool] ))` at `80-tips.zsh:40,56,73,81,88,95,106` — correct startup guard. Inside `tips()` `_ui_*` not `command -v` — no staleness risk. | — |
| I-05 | **Info** | `.gitignore:2` vs `AGENTS.md:61` | qa-features.csv ignored | `.gitignore:2` = `qa-features.csv`. `git ls-files | grep qa-features` → 0, `git check-ignore -v` → `.gitignore:2:qa-features.csv` — correctly local-only. | — |
| I-06 | **Info** | Verification suite vs `AGENTS.md:41-53` | Ordered suite passes locally | `zsh -n *.zsh lib/*.zsh functions/ztheme functions/_fbr_format_entry` ✅, `sh -n scripts/check-deps.sh` ✅, `zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh` ✅ locally. Checks.yml covers syntax + execution for `test-init/theme/functions/cgm/upkg/completions/help` — passes, only gaps M-01/M-02. | — |
| I-07 | **Info** | Guard discipline `AGENTS.md:22-25` | `(( $+commands ))` vs `command -v` | Startup top-level: `20-aliases.zsh:4,20,38` `30-zoxide.zsh:33` `40-fzf.zsh:550` `80-tips.zsh:40+` all use `(( $+commands ))`. Function bodies: `60-functions.zsh:19-91`, `65-help.zsh:152-204`, `62-cgm.zsh:12` use `command -v … >/dev/null` — stale-hash safe, stub-safe per `test-upkg`. `40-fzf.zsh:79,81` preview strings embed `command -v` — required (fzf-spawned shell). | — |
| I-08 | **Info** | `25-theme.zsh:1-426` vs `AGENTS.md:26` | Palette & glyph single source, pure Zsh | No `command -v`, `tput`, `eval`, filesystem discovery, downloads at source time. Lazy loads `lib/theme-registry.zsh:1`, `lib/theme-palettes.zsh:1`, `lib/theme-color.zsh:1` via fixed `$_ZSH_THEME_MODULE_DIR` — idempotent (`test-theme.zsh:302-350`). Renderer `55-ui-helpers.zsh` + picker `40-fzf.zsh` consume semantic roles not palette names. | — |
| I-09 | **Info** | `60-functions.zsh:110` `functions/ztheme:1-200` vs `AGENTS.md:27` | ztheme registration & atomicity | `60-functions.zsh:110` registers `autoload -Uz ztheme`; `functions/ztheme:33-54` validates, applies, rolls back on failed `_fzf_export_config` — atomic. `ztheme export` prints assignments, never edits `~/.zshrc`. Fixed `fpath` guard prevents user-controlled discovery. | — |
| I-10 | **Info** | `scripts/check-deps.sh:1-220` vs `AGENTS.md:30-31,56` | POSIX sh, required vs optional | `#!/bin/sh`, `set -u`, only `[`, `case`, `command -v` — portable. `check_fzf:56-135` enforces `0.68.0` floor (supersedes HC-03 `0.52.0` with banner at `high-priority-ux-remediation.md:11`). `check-deps.sh:189-204` required `zsh,git,curl,ss,lsd,zoxide,fzf` and optional `bat,tree,fd/fdfind,jq,secret-tool,nix,nix-collect-garbage` — matches `AGENTS.md:56` + `README.md:45-51` + `GUIDE.md:91-120`. Exit `1` only for required missing, `0` for optional hints. | — |
| I-11 | **Info** | `50-completion.zsh:1-12` `62-cgm.zsh:496` vs `AGENTS.md:33-36` | Lightweight completion, hook-free tips, optional cgm | `50-completion.zsh` only 3 `zstyle`s; assumes `compinit` — matches spec. `62-cgm.zsh:496` does `unsetopt xtrace` inside `_cgm_env`, no plaintext fallback, no `eval` export, completion via name-only catalogue. `init.zsh:29` fully skips sourcing without `secret-tool`. | — |
| I-12 | **Info** | Cross-doc links | Link instead of copy | `README.md:5,63-65` → `GUIDE.md`, `AGENTS.md`, `docs/specs/`; `GUIDE.md:3,5,831` → `README.md`, `AGENTS.md`; `docs/specs/*.md:11,9` → `GUIDE.md` with “For current usage, use GUIDE”. No long duplication. | — |

## Cross-Cutting Checks

- **No missing/extra modules:** `init.zsh:14-27` lists exactly AGENTS 13; `ls *.zsh` confirms 13 `*.zsh` + `init.zsh`; no orphan.
- **`40-fzf.zsh:549-556` zle guard:** `[[ -o interactive ]] && [[ -z ${ZSH_EXECUTION_STRING:-} ]]` prevents `can't change option: zle` warnings for `zsh -i -c …` — per AGENTS:40.
- **Deps sync on alias change:** `20-aliases.zsh` high-impact aliases (`mkdir -p`, `cp -iv` etc.) documented in `GUIDE.md:373-397` + `80-tips` + `README.md:37` — synchronized in same commits per ledger.
- **`.gemini/` in `.gitignore:1`** — not in AGENTS spec but harmless.

## Recommended Fixes (Minimal)

1. **CI parity** — patch `.github/workflows/checks.yml`:

```yaml
- name: Check benchmark syntax
  run: zsh -n scripts/benchmark-startup.zsh
# or merge: zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh
- name: Smoke source init.zsh
  run: zsh -fc 'source "$HOME/.config/zsh/init.zsh"'
```

2. **QA template** — `cp qa-features.csv qa-features.passed.csv; sed -i 's/,Passed/,Not Run/g' qa-features.csv` (restore `Not Run` default; keep 12-row as minimal HC-01–04 set, or expand to 39-row theming matrix before release).
3. **Spec label** — optionally amend `docs/specs/theming-and-fzf-ui-plan.md:3` to `Status: Implemented (available-host QA complete; Nix-host visual QA blocked — see T8 ledger)` to satisfy AGENTS “mark implemented” without claiming blocked gates.

No blocking violation prevents use; CI and QA template fixes should land in one commit with updates to `README.md`/`GUIDE.md` if any user-visible behavior changes.
