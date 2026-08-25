# Ox — Full Review Report

**Date:** 2026-08-25 · **Repo:** `~/.config/zsh` @ `71fce91`
**Method:** Three independent review passes (performance, project, code), each executed by a dedicated subagent, then key findings re-verified directly against the source before publication.

## Verdict at a glance

The repo is in **good shape**: zero prompt-time process spawns, a pure-Zsh theme startup path, a passing security posture for the Secret Service module, and unusually consistent guard discipline. The findings below are real but mostly small; one is an explicit violation of the repo's own AGENTS.md rules.

| Area | Health | Headline finding |
|---|---|---|
| Performance | 🟢 Good | One top-level `command -v nix` PATH walk on every startup (`60-functions.zsh:3782`) |
| Project / docs / CI | 🟡 Fair | CI has drifted from the documented verification order; no single test runner |
| Code correctness | 🟢 Good | Env-controllable lazy-source dir (`25-theme.zsh:21`) deviates from repo's fixed-path rule |

## Top issues (cross-review priority order)

1. **[Perf · High] Startup `command -v nix` PATH walk** — `60-functions.zsh:3782`. The only top-level non-function construct in the 4,639-line module. Violates AGENTS.md's startup-guard rule; worst case on long PATHs (WSL2). Fix: `(( $+commands[nix] ))`, or better, move the ~857-line npkg block into an autoloaded helper.
2. **[Project · Med] CI ≠ documented verification** — `.github/workflows/checks.yml` skips step 2 (`zsh -n scripts/benchmark-startup.zsh`) and step 11 (final source smoke). Root cause: the 11-step sequence is hand-maintained in three places with no runner script.
3. **[Code · Med] `_ZSH_THEME_MODULE_DIR` honors pre-set env** — `25-theme.zsh:21` uses `${_ZSH_THEME_MODULE_DIR:-…}`, so an exported value redirects all lazy theme-helper sources away from the repo directory. Contrast `60-functions.zsh:106` which sets unconditionally.
4. **[Code · Med] Hand-duplicated registries** — theme names, manager whitelists, and extension tables are duplicated between `66-compdefs.zsh` and their owners; drift fails silently.
5. **[Perf · Med] Three unconditional process forks at startup** — capability probes in `20-aliases.zsh:10,42,46` execute external binaries every shell start.

## Full reports

- [`Ox_PERFORMANCE_REVIEW.md`](Ox_PERFORMANCE_REVIEW.md) — startup cost anatomy, guard audit table, benchmark gaps
- [`Ox_PROJECT_REVIEW.md`](Ox_PROJECT_REVIEW.md) — repo inventory, docs-sync matrix, test coverage, CI drift
- [`Ox_CODE_REVIEW.md`](Ox_CODE_REVIEW.md) — correctness findings, 62-cgm security verdict, quality notes

## Recommended fix batch (one PR)

1. `60-functions.zsh:3782` → `if (( $+commands[nix] )); then` *(one line)*
2. `25-theme.zsh:21` → drop the `${_ZSH_THEME_MODULE_DIR:-}` fallback wrapper
3. Add `scripts/run-tests.sh` encoding the documented 11-step order; make `checks.yml` call it
4. Replace `20-aliases.zsh:42/:46` exec probes with `$+commands` checks
5. Derive or sync-test the `66-compdefs.zsh` duplicate lists
