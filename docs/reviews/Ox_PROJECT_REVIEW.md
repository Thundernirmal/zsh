# Ox Project Review — `~/.config/zsh`

**Date:** 2026-08-25 · **Scope:** repo structure, documentation sync across surfaces, test coverage, CI alignment, dependency-check hygiene.

## 1. Repo inventory

```
13 numbered modules (10-history … 80-tips) + init.zsh (37-line loader)
lib/theme-{color,palettes,registry}.zsh   lazy palette/validation helpers
functions/{ztheme,_fbr_format_entry}      lazy autoloads
scripts/  check-deps.sh + 7 test suites + benchmark-startup.zsh
docs/specs/  2 specs, both correctly marked implemented with GUIDE.md pointers
.github/workflows/checks.yml  single "verify" job
qa-features.csv  present locally, gitignored ✓ (git check-ignore exit 0; tree clean)
CLAUDE.md → symlink to AGENTS.md ✓
```

- `init.zsh:14–27` matches the AGENTS.md load order exactly; the `62-cgm` skip gate at `init.zsh:29–31` is correct.
- Specs are properly historical: `docs/specs/high-priority-ux-remediation.md:5` ("Status | Implemented"), `theming-and-fzf-ui-plan.md:3` (complete, with remaining-signoff note and GUIDE link).

## 2. Docs-sync audit

Six features checked across four surfaces (README, GUIDE, `80-tips.zsh`, zhelp catalogue in `65-help.zsh`):

| Feature | README | GUIDE | tips | zhelp | Verdict |
|---|---|---|---|---|---|
| **fbr** | :38 worktree badges | :546 full contract ([WT] badge, undecorated return) | :52–53 fzf-gated tips | :89 deps "git + fzf 0.68.0+" | ✅ consistent |
| **ztheme** | :27, :41 | :226–241 six subcommands, session scope | :11 example only | :114 all six subcommands | ✅ |
| **ft** | grouped under search :38 | :482, :504–509 rg→grep fallback | :15 | :81 "rg or grep" | ✅ matches impl at `60-functions.zsh:91–95` |
| **zhelp** | :30 queue-not-execute | :331–351 flags, plain fallback | :10 | :115 + usage | ✅ |
| **tips** | :26 | :352–360 hook-free | :113–141 impl | :113 | ⚠️ minor gap (B2) |
| **cgm/upkg** | :39–40 | :548–708 exhaustive | :65–111 all guarded | :101,:104 dep labels correct | ✅ |

### Findings

| # | Sev | Finding |
|---|---|---|
| B1 | Low | README.md:32 carries picker-frame internals detail (padding, dividers, 100-col behavior) — GUIDE-density content straddling the ownership boundary (GUIDE.md:204–214 already covers it). Trim README back to entrypoint density. |
| B2 | Low | Rich `tips` rendering (`80-tips.zsh:124–138`: title bar, accent color, section breaks) is undocumented in GUIDE's tips section (:352–360 shows only plain form). One sentence + example closes it. |
| B3 | Info | `lsd` is listed as *required* (README:49, check-deps.sh:193) while the `ls` alias has a documented non-lsd fallback. Defensible policy ("required for intended setup") but easy to misread. |
| B4 | Info | No contradictions found anywhere between surfaces; `test-help.zsh:93`'s expected 50-entry catalogue matches registrations exactly. |

GUIDE scannability at 831 lines is strong (TOC, tables-first, numbered gotchas list). Weak spot: the theming block (:125–245) interleaves settings/palettes/layouts/precedence — consider two H3 subsections.

## 3. Test coverage matrix

All suites are self-contained zsh scripts (`mktemp` + trap cleanup, hand-rolled asserts, subprocess `zsh -dfc`, PATH-stubbed fake binaries).

| Module under test | Suite(s) | Coverage |
|---|---|---|
| init/options/history | test-init (891 ln) | Sources full init but asserts are almost entirely **fzf-focused**; no HISTSIZE/AUTO_PUSHD/shell-option assertions anywhere |
| 20-aliases | test-functions | fallback probes, glob interaction ✓ |
| 25-theme + lib | test-theme | palettes, glyph modes, NO_COLOR/NO_NERD_FONT, custom validation ✓ |
| 30-zoxide | partial (test-init:164–170, :252, :345) | `_ZO_FZF_OPTS`, stubbed `zi`; **no dedicated suite** |
| 40-fzf | test-init | deep ✓ |
| 50-completion | **none** | zero `zstyle` assertions in any suite |
| 55-ui-helpers | fixture only | rendering contract itself untested directly |
| 60-functions | test-functions + test-upkg (1,631 ln, ~378 asserts) | strong ✓ |
| 62-cgm | test-cgm (578 ln) | startup-quiet, xtrace-off, atomicity ✓ |
| 65-help | test-help | catalogue integrity, availability labels ✓ |
| 66-compdefs | test-completions | compdef guard, spec contents ✓ |
| 70-globals | **none** | unreferenced by tests |
| 80-tips | test-help:262–285 | conciseness lint only |

**No single runner exists.** The documented 11-step verification order lives only in AGENTS.md / GUIDE.md / checks.yml — three hand-maintained copies.

## 4. CI drift (`.github/workflows/checks.yml`)

| Documented step (AGENTS/GUIDE) | CI status |
|---|---|
| 1. `zsh -n *.zsh lib/*.zsh functions/…` | ✅ |
| 2. `zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh` | ❌ **benchmark-startup never checked in CI** |
| 3. `sh -n scripts/check-deps.sh` | ✅ |
| 4–10. seven test suites | ✅ same relative order |
| 11. `zsh -fc 'source "$HOME/.config/zsh/init.zsh"'` | ❌ **absent from CI** (partially mitigated: test-init sources init.zsh repeatedly in sandboxed homes) |
| extra: per-test `-n` syntax checks | ⚠️ harmless drift beyond docs |

Job installs only `zsh` — fine, since suites stub externals.

## 5. check-deps.sh

POSIX-clean: `#!/bin/sh`, `set -u`, `printf` throughout, portable IFS version parsing, no bashisms. Required list (`zsh git curl ss lsd zoxide` + fzf≥0.68.0) and optional list (incl. conditional `nix-collect-garbage`) match AGENTS.md exactly. Exit semantics correct (missing required → 1, missing optional → 0). Nit: `detect_manager()` (:139) omits `paru`/`flatpak`, so hint text can suggest pacman/apt lines on paru systems — cosmetic.

## 6. Prioritized recommendations

1. **Add `scripts/run-tests.sh`** encoding the documented 11-step order; have CI call it. Three hand-maintained copies of the sequence have already drifted — this is the root cause of every CI gap.
2. Close the two CI gaps (benchmark syntax check, final source smoke) — subsumed by (1).
3. Cheap regression tests for untested surfaces: shell-option/history assertions in test-init, a small 50-completion `zstyle` dump, a 70-globals expansion test.
4. Rebalance README.md:32 toward entrypoint density (move frame internals fully into GUIDE).
5. Document rich-mode `tips` output in GUIDE; note paru→pacman hint reading in check-deps.
