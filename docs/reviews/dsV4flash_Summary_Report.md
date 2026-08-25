# dsV4flash_Summary_Report

Consolidated findings from the full performance, project, and code review of the Zsh config repo (`~/.config/zsh`), run by three dedicated subagents on 2026-08-25. Companion docs: `dsV4flash_Performance_Report.md`, `dsV4flash_Project_Report.md`, `dsV4flash_Code_Report.md`.

## Overall verdict

Healthy, unusually well-tested repo. All 11 AGENTS.md verification steps pass (926 assertions, 0 failures). No Critical or High code defects found; docs and code are exceptionally well synchronized; startup discipline is real (~27 ms total, verified by three independent timing methods). Findings are edge drift and optimization opportunities.

## Consolidated findings

### The one real defect (all three reviewers converged)

**`60-functions.zsh:3782` — top-level `command -v nix`.** The only startup-time guard in the repo violating AGENTS.md's `$+commands` rule (commit `d90ed98` missed it). Costs one full PATH walk per shell start on nix-less machines (dominates on WSL2-style long PATHs). Either fix to `(( $+commands[nix] ))` (+ regression test) or document the deliberate exception, since test-upkg stubs `nix` via PATH.

### Performance (biggest addressable wins)

| Finding | Location | Impact |
|---|---|---|
| H1: grep pipeline + diff probes run every startup | 20-aliases.zsh:42-48 | **−2.6 ms** (~10%) with single-process probe + presence gates |
| H2: `command -v nix` at top level | 60-functions.zsh:3782 | PATH walk per shell start |
| M1: zoxide fzf-opts refresh outside guard | 30-zoxide.zsh:31 | **−2.2 ms** on zoxide-less machines |
| M2: eager zhelp catalog + tips pool | 65-help.zsh:55-115, 80-tips.zsh:4-111 | **−6.6 ms** (~24%) via lazy-lib pattern |

Combined addressable: **~9–12 ms of ~27 ms (30–40%)**. Irreducible: 60-functions parse (+5.7 ms) and zoxide's required eval.

### Project (drift, not defects)

- GUIDE.md:316-325 completion list missing 15 of 23 `compdef` registrations (incl. headline `ztheme`).
- CI missing `zsh -n benchmark-startup.zsh` and the step-11 smoke test; workflow never triggers on the active `chore/25` branch.
- Zero test coverage: `10-history.zsh`, `50-completion.zsh`, `70-globals.zsh`; 8 functions untested behaviorally (`ports`, `fanprofile`, `croot`, `gitcount`, `headers`, `weather`, `extract`, `peek`); dead fake-`ss` fixture (test-upkg.zsh:402).
- Spec ledger mismatch: theming spec T8 claims 39-row qa-features.csv, file has 13.
- Housekeeping: ~45 stale branches, 5 untracked `muse_*.md` files, theming release untagged.

### Code (hardening)

- M2: `_upkg_record_cleanup_result` (60-functions.zsh:1624-1639) relies on invisible dynamic scoping.
- M3: live edits to `FZF_DEFAULT_OPTS`/`_ZO_FZF_OPTS` are silently dropped when a theme change re-exports from frozen snapshots (40-fzf.zsh:18-27, 30-zoxide.zsh:3).
- L1: dead code `_ui_has_truecolor`/`_ui_has_icons`.
- Security: no injection, no unguarded `rm -rf`, cgm credential handling is exemplary (no plaintext on disk, no eval, xtrace-safe, TOCTOU-hardened).

## Suggested execution order

1. Guard fix + AGENTS.md note (60-functions.zsh:3782) — 1 line
2. Startup probe optimization (20-aliases.zsh:42-48) — ~10% startup
3. Lazy-load 65-help + 80-tips — ~24% startup
4. zoxide refresh inside guard (30-zoxide.zsh:31)
5. Docs sync: GUIDE.md completion list, spec ledger, CI steps
6. Test-gap closure + `_upkg_record_cleanup_result` hardening
7. Housekeeping: branches, muse files, tag, spec status flip