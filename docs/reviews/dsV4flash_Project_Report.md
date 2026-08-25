# dsV4flash_Project_Report

Full project review of the Zsh config repo (`~/.config/zsh`), run by a dedicated subagent on 2026-08-25.

## 1. Methodology

- Read every module (`10-`…`80-`), `init.zsh`, `lib/theme-*.zsh`, `functions/ztheme`, `functions/_fbr_format_entry`, `AGENTS.md`, `README.md`, `GUIDE.md` (831 lines), all 8 scripts, both specs in `docs/specs/`, `.github/workflows/checks.yml`, `qa-features.csv`, `skills-lock.json`, `.gitignore`.
- Ran the complete 11-step verification sequence from AGENTS.md, capturing exit codes and assertion counts.
- Cross-checked every user-facing alias/function/flag against GUIDE.md and README.md (modules as ground truth per GUIDE.md:3).
- Grep-audited guard usage vs AGENTS.md guard rules; audited CI vs local verification; audited specs' status markers and links; reviewed git history, tags, branches, ignored/untracked files.

## 2. Verification run results (AGENTS.md sequence)

| # | Command | Result |
|---|---|---|
| 1 | `zsh -n *.zsh lib/*.zsh functions/ztheme functions/_fbr_format_entry` | **PASS** |
| 2 | `zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh` | **PASS** |
| 3 | `sh -n scripts/check-deps.sh` | **PASS** |
| 4 | `zsh scripts/test-init.zsh` | **PASS** (199 ok) |
| 5 | `zsh scripts/test-theme.zsh` | **PASS** (40 ok) |
| 6 | `zsh scripts/test-functions.zsh` | **PASS** (79 ok) |
| 7 | `zsh scripts/test-cgm.zsh` | **PASS** (107 ok) |
| 8 | `zsh scripts/test-upkg.zsh` | **PASS** (403 ok) |
| 9 | `zsh scripts/test-completions.zsh` | **PASS** (57 ok) |
| 10 | `zsh scripts/test-help.zsh` | **PASS** (41 ok) |
| 11 | `zsh -fc 'source "$HOME/.config/zsh/init.zsh"'` | **PASS** |

All 11 pass — **926 assertions, 0 failures**.

## 3. Documentation sync audit

**Overall: excellent.** Every alias, function, cgm command, upkg flag/state/backend, npkg subcommand, theme setting, and fzf binding is documented in GUIDE.md. Layout heights/widths (GUIDE.md:206-212 vs 25-theme.zsh:254-330), option precedence (GUIDE.md:216-223 vs 40-fzf.zsh:73-143), cache keying (GUIDE.md:451 vs 40-fzf.zsh:341-362), custom-palette contract (GUIDE.md:202 vs lib/theme-registry.zsh:13-29), and cgm secrecy rules all match the code precisely. Findings are edge drift:

1. **GUIDE.md:316-325 completion list incomplete (minor drift).** Presented as exhaustive with 8 entries, but 66-compdefs.zsh:319-330 also registers `ztheme`, `peek`, `mkcd`, `ft`, `dusage`, `bigfiles`, `headers`, `fbr`, `croot`, `path`, `ports`, `myip`, `gitcount`, `fanprofile`, `tips` (15 more). `ztheme` is a headline feature and its completion is undocumented.
2. **AGENTS.md:23 guard rule contradicted by code.** `60-functions.zsh:3782` guards the whole `npkg` block at module top level with `command -v nix >/dev/null 2>&1`. Commit `d90ed98` missed this one. The deviation is *deliberate* — test-upkg stubs `nix` via PATH (test-upkg.zsh:458, 416-456) and `$commands` would defeat it — but the docs don't record the exception.
3. **`qa-features.csv` spec claim stale.** theming-and-fzf-ui-plan.md:759 (T8 ledger) says "Created the required **39-row** `qa-features.csv` locally", but the file has **13 rows**.
4. **qa-features.csv coverage thin vs AGENTS.md:63.** No rows for prompt startup, aliases (`ll`/`la`/`mkdir`/`cp`…), global aliases, completion UI, cgm flows, upkg `upgrade`/`clean`, `ztheme`, `zhelp` palette, `weather`/`ports`/`headers`, or rich dashboards. All 13 rows are fzf/glob/npkg-focused.
5. **`upkg help` output** (60-functions.zsh:1204-1248) matches GUIDE.md:598-708 state table exactly.
6. **No other drift** in history options, aliases tables, fzf keybindings, preview behavior, no-color contract, zoxide `_ZO_FZF_OPTS` ordering, npkg outdated semantics, or cgm scope.

## 4. Test coverage matrix

| Module | Covered by | Gaps |
|---|---|---|
| `init.zsh` | test-init: clean smoke, alias-collision, glob policy (272-335) | Option table not asserted individually |
| `10-history.zsh` | **none** | HISTSIZE/SAVEHIST/HISTFILE + 6 setopts never asserted |
| `20-aliases.zsh` | test-functions: probe quietness (248-273); test-init: gcount collision | No assertion of `ll`/`cat`/`mkdir -p`/`weather`/`lt` expansions |
| `25-theme.zsh` | test-theme: 10 groups | — |
| `30-zoxide.zsh` | test-init: fake `zoxide init` + `_ZO_FZF_OPTS` + `zi` (148-169, 421) | `init` failure path untested |
| `40-fzf.zsh` | test-init: startup gate, cache, quiet modes, guards, path cache, dep checker | — |
| `50-completion.zsh` | **none** | zstyles never asserted |
| `55-ui-helpers.zsh` | test-theme renderer; test-upkg fallbacks/TERM (465-483) | `_ui_bar`/`_ui_human_bytes` math indirect only |
| `60-functions.zsh` | test-functions; test-upkg | `fanprofile`, `croot`, `gitcount`, `headers`, `ports`, `weather`, `extract`/`peek` untested. **Dead fixture:** fake `ss` at test-upkg.zsh:402-407 never used |
| `upkg` | test-upkg: 403 assertions | — |
| `npkg` | test-upkg: outdated state machine, worker-reaping (216-307, 1371-1530) | non-interactive `add`/`remove` source-asserted only |
| `62-cgm.zsh` | test-cgm: 11 groups, fake secret-tool | — |
| `65-help.zsh` | test-help: catalogue, matching, availability, palette, no-subprocess | — |
| `66-compdefs.zsh` | test-completions: 7 groups | — |
| `70-globals.zsh` | **none** | Global aliases G/L/W/H/T/NE/NUL never asserted |
| `80-tips.zsh` | test-help: pool concise/actionable (262-286) | `tips()` output never invoked |
| helpers/lib | test-theme, test-functions | — |
| `check-deps.sh` | test-init: fzf block/accept + optional exit-0 (818-861) | Non-fzf required-tool missing paths untested |

**Biggest holes: `10-history.zsh`, `50-completion.zsh`, `70-globals.zsh` have zero coverage; `ports`/`fanprofile`/`croot`/`gitcount`/`headers`/`weather`/`extract`/`peek`/`tips` have no behavioral tests.**

## 5. CI review (.github/workflows/checks.yml)

- **Matches:** syntax checks, `sh -n check-deps.sh`, all 7 test scripts (checks.yml:24-70).
- **Missing vs local sequence:**
  1. `zsh -n scripts/benchmark-startup.zsh` (AGENTS.md step 2) — never checked in CI.
  2. Final step 11 smoke test `zsh -fc 'source init.zsh'` — absent (partially covered by test-init).
- **Trigger gap:** workflow fires only on PRs and pushes to `main`/`master` (checks.yml:3-8). Development happens on `chore/25` (currently at HEAD, identical to master), so pushes to the active branch never run CI; no `workflow_dispatch`/tag triggers.
- Nit: `actions/checkout@v4` unpinned by SHA.

## 6. Specs staleness (`docs/specs/`)

1. **high-priority-ux-remediation.md** — properly marked **Implemented** (line 5, implemented `b2301a2`, released `v2026.08.04`; tag verified), links GUIDE.md correctly (line 11). **Not stale.**
2. **theming-and-fzf-ui-plan.md** — status "Implementation complete and audited through PF-03 — Nix-host visual signoff remains blocked" (line 3). All work packages T1-T14 and PF-01..03 marked Completed (lines 430-663, 972-1014); release gates at 945-956 remain formally unclosed due to the T8 Nix-host visual QA. **Not stale but:** (a) should flip to Implemented once the final visual gate passes (AGENTS.md:16); (b) T8 ledger's 39-row qa-features.csv claim no longer matches the 13-row file.

## 7. Repo hygiene

- **Untracked cruft:** five `muse_*.md` reports at repo root — agent-generated, not gitignored, not part of the doc surface. (Note: `dsV4flash_*` reports are in the same category.)
- **Branch naming:** `chore/25` is effectively the trunk (30+ commits, features #26-#30). `master` == `origin/master` == HEAD (all `71fce91`), so the branch is fully merged; name no longer reflects content. ~25 local and ~20 remote stale branches (`cat`, `failure`, `sol`, `flatfix`, `feature-install`, `fix/qa-shell-helpers`, `upkg`, `agent/*`, `t3code/*`, `spec/high-critical-ux-fixes`, …).
- **Tags:** last tag `v2026.08.12` at `d77c486` (#27); theming release work (#28-#30) untagged — consistent with the spec's unclosed release gate.
- **Symlink:** `CLAUDE.md -> AGENTS.md` committed in `71fce91` — valid, matches convention.
- **.gitignore:** covers `qa-features.csv` and `.gemini/` — correct; CSV confirmed ignored.
- **skills-lock.json:** locks only the `documentation` skill (sha256 pinned), but `.agents/skills/` and `.claude/skills/` contain ~25 more skills; nothing documents the lock file or its purpose.
- **Commit style:** conventional commits with PR refs on recent history; older commits unformatted — acceptable.

## 8. Recommendations (ranked)

1. **Fix or document the `npkg` startup guard** (60-functions.zsh:3782): either switch to `(( $+commands[nix] ))` and make test-upkg rehash, or — since the suite depends on PATH stubs — document the deliberate exception in AGENTS.md:23-24 so the rule matches the code. Only code-vs-AGENTS.md contradiction found.
2. **Add missing CI steps:** `zsh -n scripts/benchmark-startup.zsh` and step-11 smoke test in checks.yml; consider triggering on the dev branch or `workflow_dispatch`.
3. **Close test gaps:** assert `10-history.zsh` options, `70-globals.zsh` alias expansions, `50-completion.zsh` zstyles, `ports()` (fixture already exists at test-upkg.zsh:402); behavior tests for `extract`/`peek`/`croot`/`gitcount`/`fanprofile`/`tips()` are cheap (sourceable in-process).
4. **Complete GUIDE.md:316-325** with the 15 missing `compdef` registrations (at minimum `ztheme`).
5. **Reconcile the qa-features.csv ledger** (theming spec:759 says 39 rows, file has 13) and expand the CSV per AGENTS.md:63 with alias/keybinding/completion/cgm/upkg/ztheme/zhelp rows, defaulting Status to `Not Run`.
6. **Housekeeping:** delete or archive ~25 stale local + ~20 stale remote branches; remove or gitignore the five untracked `muse_*.md` files; rename/rebase `chore/25` if it stays the trunk; tag the theming release once visual signoff closes.
7. **Mark theming spec Implemented** when the final gate passes (AGENTS.md:16); mention `skills-lock.json` in AGENTS.md or remove it if unused.

## Verdict

The repo is in strong health: docs and code exceptionally well synchronized, test suite deep (926 assertions), all 11 verification steps pass. Findings are drift at the edges — one real guard-rule contradiction, two doc lists, two spec/CSV ledger mismatches, CI gaps, and housekeeping debt — rather than core defects.
