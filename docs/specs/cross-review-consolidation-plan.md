# Cross-Review Consolidation and Remediation Plan

| Field | Value |
| --- | --- |
| Status | Proposed |
| Audit date | 2026-08-25 |
| Sources | 18 review documents in `docs/reviews/` from 4 independent suites (Ox, dsV4flash, Gemini/Antigravity, Muse) |
| Scope | All consolidated, deduplicated findings across performance, security, correctness, architecture, docs, CI, and tests; remediation batches with acceptance criteria |
| Companion artifact | [`docs/reviews/index.html`](../reviews/index.html) (human-readable synthesis site) |

> This is a planning specification. It proposes work; nothing in it is implemented yet.
> For current setup, usage, and gotchas of shipped behavior, use [`GUIDE.md`](../../GUIDE.md).

## Summary

Between 2026-08-24 and 2026-08-25 four independent review suites audited this repository and produced eighteen documents covering code correctness, performance, project/docs hygiene, security/portability, and tooling/CI. This specification consolidates those outputs into a single deduplicated findings register (27 findings, IDs `CR-01` … `CR-27`), records where the suites converged and where they disputed one another, and defines prioritized remediation batches with acceptance criteria.

The suites' verdicts agree in substance:

- The repository is healthy: all four suites passed the full 11-step verification sequence locally (926 assertions, 0 failures), startup is ~22–29 ms with zero prompt-time hooks, Secret Service handling (`62-cgm.zsh`) passes every AGENTS.md constraint, and documentation surfaces are synchronized.
- Exactly one clear-cut standards defect exists: the top-level `command -v nix` guard at `60-functions.zsh:3782`.
- One systemic process gap exists: CI does not execute the documented verification sequence, because that sequence is hand-maintained in three places.
- Everything else is hardening, duplication debt, test-gap closure, or measured optimization opportunity (~30–40% of startup addressable; a 190× runtime win available in `fbr`).

## Goals

- Provide one authoritative, deduplicated register of every actionable finding across all eighteen source documents.
- Preserve attribution (which suite flagged what) so future re-reviews can measure improvement against this baseline.
- Define fix batches small enough to land as single PRs, each with objective acceptance criteria.
- Record disputed findings honestly (e.g., fzf preview placeholder safety) instead of silently picking a side.
- Keep every user-facing behavior contract intact while applying fixes.

## Non-goals

- Re-litigating severity labels assigned by individual suites; this spec uses its own tier taxonomy defined below.
- Implementing any fix in this change; each batch lands separately after this plan is agreed.
- Decomposing `60-functions.zsh` opportunistically (CR-26 is explicitly scheduled last).
- Changing intentionally interactive aliases (`mkdir -p`, `cp/mv/rm -iv`); CR-18 documents their bypass rather than weakening them.
- Modifying user-owned `~/.zshrc`, Oh My Zsh, Starship, or machine-local wiring.

## Severity taxonomy

This register uses four tiers. Where a suite's label differs, the mapping rationale is recorded per finding.

| Tier | Meaning | Count |
| --- | --- | --- |
| **T0 — Fix as soon as possible** | Correctness or standards violations with concrete failure modes, safety gaps, and release-integrity gaps | 6 |
| **T1 — High-value performance wins** | Measured wins, mostly trivial effort | 4 |
| **T2 — Medium** | Hardening, robustness, doc/test gaps worth scheduling soon | 10 |
| **T3 — Backlog & polish** | Contested items, style, long-term refactors, hygiene | 7 |

## Findings register

Locations reference the current checkout (`71fce91`). "Flagged by" uses: Ox, dsV4, Gemini, Muse; ◐ marks partial or variant framing.

### Tier 0 — fix as soon as possible

#### CR-01 · Top-level `command -v nix` PATH walk
- **Location:** `60-functions.zsh:3782`
- **Flagged by:** Ox (High), dsV4 (Med), Gemini (P2); Muse's guard matrix marked the module PASS (missed)
- **Detail:** The only startup-time guard violating the AGENTS.md `$+commands` rule (commit `d90ed98` missed it). Full PATH walk per shell start on nix-less machines; dominates on WSL2-length PATHs (measured 35–416× slower than hash lookup).
- **Fix:** `if (( $+commands[nix] )); then`; optionally move the npkg block to an autoloaded helper (see CR-26).
- **Constraint:** `scripts/test-upkg.zsh` stubs `nix` via PATH (:416–458); switching requires a test-side `rehash` or a documented exception in AGENTS.md.
- **Acceptance criteria:**
  1. No top-level `command -v` remains in any module.
  2. A regression assertion proves no `command -v` executes at module top level during source (e.g., stub `command -v` in test-init), or AGENTS.md documents the exception.
  3. Full verification sequence passes.

#### CR-02 · CI diverges from documented verification
- **Location:** `.github/workflows/checks.yml`
- **Flagged by:** all four suites (Muse rated Critical)
- **Detail:** Missing from CI: step 2 (`zsh -n scripts/benchmark-startup.zsh`), step 11 smoke (`zsh -fc 'source "$HOME/.config/zsh/init.zsh"'`), execution of `check-deps.sh`, job `timeout-minutes`, and triggers for the active dev branch / `workflow_dispatch`. Root cause: the 11-step order is hand-maintained in AGENTS.md, GUIDE.md, and checks.yml.
- **Fix:** Add `scripts/run-tests.sh` encoding the documented order; checks.yml calls it verbatim; add timeout + triggers.
- **Acceptance criteria:**
  1. One runner script owns the sequence; AGENTS.md/GUIDE.md reference it instead of duplicating commands.
  2. CI runs benchmark syntax check and final smoke test on every PR and push to trunk branches.
  3. Job completes within an explicit timeout.

#### CR-03 · Env-overridable theme module dir
- **Location:** `25-theme.zsh:21`
- **Flagged by:** Ox (Med), Muse (Low)
- **Detail:** `${_ZSH_THEME_MODULE_DIR:-…}` lets an exported value redirect every lazy theme-lib source away from the repository — violates the fixed-lazy-sources rule. Contrast `60-functions.zsh:106` (unconditional).
- **Fix:** `typeset -g _ZSH_THEME_MODULE_DIR=${${(%):-%N}:A:h}`
- **Acceptance criteria:** Sourcing with `_ZSH_THEME_MODULE_DIR=/tmp/evil` exported still resolves libs from the repo directory; test-theme asserts this.

#### CR-06 · Temp-file leaks on signals/failures
- **Location:** `dusage` :545–554, `bigfiles` :674–696, `_npkg_refresh_index` :3868–3879
- **Flagged by:** Ox, Gemini (Med); Muse ◐ (listed a trap as strength; interrupt paths leak regardless)
- **Detail:** Ctrl+C during scans orphans mktemp files; refresh leaks `.tmp`/`.err` on specific failure paths; INT/TERM trap coverage inconsistent across the module.
- **Fix:** `setopt localtraps` + `trap 'command rm -f -- …' EXIT INT TERM` at each temp section.
- **Acceptance criteria:** Tests send SIGINT mid-scan (fixture-driven) and assert no leftover files matching the temp patterns.

#### CR-07 · Missing `--` option terminators
- **Location:** `mkcd`:57, `extract`:14–45, `croot`:980, `_fbr_activate`:1077–1086, apt/brew/npm/flatpak search backends :2081/2255/2376/2462
- **Flagged by:** Ox, Gemini
- **Detail:** Hyphen-prefixed arguments misparse as options. pacman/paru backends already protected.
- **Acceptance criteria:** Every external invocation taking a user-supplied path/query passes `--`; tests cover a `-leading-dash` argument for extract, mkcd, and one search backend.

#### CR-09 · Duplicated completion registries
- **Location:** `66-compdefs.zsh:26–42`
- **Flagged by:** Ox (Med); Muse ◐ (idempotency note only)
- **Detail:** Theme names, manager whitelist, and extract extensions are hand-copied from their owners; drift fails silently.
- **Fix:** Derive at load time from the owners, or add a drift-detection sync test.
- **Acceptance criteria:** Adding a theme/manager/extension to the owner updates completion without a second edit, or a test fails when the copies diverge.

### Tier 1 — high-value performance wins

#### CR-04 · Startup capability-probe subprocesses
- **Location:** `20-aliases.zsh:10,42,46`
- **Flagged by:** all four suites; impact −2.6 ms ≈ 10% of startup
- **Fix:** Single-process grep probe (`</dev/null`, exit-code semantics); gate probes behind `$+commands[grep/diff]`; simplify ls probe.
- **Acceptance criteria:** No external process spawns from `20-aliases.zsh` at source (test-init already asserts probe quietness; extend to count forks); aliases behave identically.

#### CR-05 · Eager zoxide fzf-chrome refresh
- **Location:** `30-zoxide.zsh:31`
- **Flagged by:** dsV4 (−2.2 ms), Muse (Major — lazy-invariant defeat); Gemini ◐
- **Fix:** Gate on `[[ -o interactive ]] && [[ -z ${ZSH_EXECUTION_STRING:-} ]]` or defer to first `zi`; also move inside the zoxide presence guard.
- **Acceptance criteria:** Sourcing init non-interactively leaves `_ZSH_THEME_REGISTRY_LOADED=0`; `_ZO_FZF_OPTS` still correct in interactive shells; test-init asserts both.

#### CR-12 · fbr formatter subshell storm
- **Location:** `functions/_fbr_format_entry`
- **Flagged by:** Gemini only (305 ms → 1.6 ms, 190×, 48 branches)
- **Caution:** Current `[WT] ` prefix surgery verified correct by Ox for width ≥ 5; output contract pinned by tests.
- **Fix:** Pure-Zsh `printf -v`/parameter-expansion rewrite setting `REPLY`; keep raw-name selection via `--accept-nth=5`.
- **Acceptance criteria:** Byte-identical row output vs. old implementation across a fixture matrix (short names, wide glyphs, `[WT]` rows, width boundaries 5/31/32/33); picker-open time measured before/after.

#### CR-13 · Lazy-load zhelp catalogue + tips pool
- **Location:** `65-help.zsh:55–115`, `80-tips.zsh:4–111`
- **Flagged by:** dsV4 (−6.6 ms ≈ 24%), Gemini ◐ (help only)
- **Fix:** Move data to `lib/` files sourced on first use by `zhelp`, `tips`, and the compdef loader (fallback already graceful).
- **Acceptance criteria:** Startup cost of both modules ≤ parse-of-loader; first `zhelp`/`tips` invocation renders identical output; test-help and the tips lint pass unchanged.

### Tier 2 — medium

#### CR-08 · Missing `emulate -L zsh` in nine utilities
- extract, mkcd, ff, ft, fkill, headers, peek, croot, gitcount (also normalize `function gitcount {` → `gitcount() {`). Flagged by Gemini, Muse.
- Acceptance: functions behave correctly with hostile caller options set (test with `setopt ksharrays shwordsplit nounset` around invocation).

#### CR-10 · Validate `eval "$(zoxide init zsh)"`
- Flagged by Ox (Low), Muse (Medium). Capture, reject empty, `zsh -fn` validate, then eval. Acceptance: fake `zoxide` emitting garbage/empty is refused; valid output still installs.

#### CR-11 · Require absolute XDG paths (cgm catalogue, npkg cache)
- `62-cgm.zsh:93–95`, `60-functions.zsh:3828,3862`; create dirs under `( umask 077; mkdir -p )`. Flagged by Ox, Gemini, Muse. Acceptance: relative `XDG_DATA_HOME` rejected with clear error; fzf-parity test added.

#### CR-14 · Re-capture inherited FZF opts before re-export
- `40-fzf.zsh:18–27`, `30-zoxide.zsh:3`. Flagged by dsV4. Acceptance: editing `FZF_DEFAULT_OPTS` then running `ztheme use` preserves the edit in re-exported options.

#### CR-15 · Make cleanup-result coupling explicit
- `60-functions.zsh:1624–1639`. Flagged by dsV4, Ox ◐. Pass explicit args or document the dynamic-scoping contract. Acceptance: works under `set -u` from a fresh call site lacking the locals.

#### CR-16 · Batch dusage input past ARG_MAX
- `60-functions.zsh:546`. Flagged by Gemini. Use `--files0-from` or chunked expansion. Acceptance: synthetic tree >50k entries completes.

#### CR-17 · Route errors to stderr
- Nine `echo` sites (extract, mkcd, ff, ft, fkill, headers, peek, croot, gitcount) → `print -u2 -r --`. Flagged by Gemini, Muse. Acceptance: `var=$(peek missing)` captures nothing; message visible on terminal.

#### CR-18 · Document alias bypass
- `20-aliases.zsh:32–35`. Flagged by Muse. Header comment + GUIDE gotcha for `command mkdir`/`\mkdir`/unalias; evaluate `rm -I` or interactive-only `-i` guard as follow-up. Acceptance: GUIDE documents bypass; alias-expansion tests updated if `-i` handling changes.

#### CR-19 (disputed) · fzf preview bare `{}` placeholder
- `40-fzf.zsh:79–92`. Muse: Medium injection risk; dsV4/Gemini ◐: safe modulo embedded-single-quote edge (upstream fzf#1586); Ox: safe by design. **Disposition:** optional hardening behind a targeted adversarial-filename test; do not block release on it. Decision recorded here so the dispute isn't relitigated blind.

#### CR-20 · Close test gaps
- Zero-coverage modules `10-history`, `50-completion`, `70-globals`; untested functions `ports`, `fanprofile`, `croot`, `gitcount`, `headers`, `weather`, `extract`, `peek`, `tips()`. Flagged by Ox, dsV4, Muse. Acceptance: each module has at least option/definition assertions; each listed function has one behavioral test.

### Tier 3 — backlog & polish

- **CR-21** GUIDE completion list missing 15 of 23 registrations incl. `ztheme` (dsV4). Complete list.
- **CR-22** `qa-features.csv` ledger mismatch (spec claims 39 rows, file has 13) and `Passed`→`Not Run` template reset (dsV4, Gemini, Muse). Reconcile before stable-release QA pass.
- **CR-23** Dead code sweep: `_ui_has_truecolor`/`_ui_has_icons` + fallback twins, unreachable skip branch `60-functions.zsh:3704–3708`, dead theme re-source blocks `25-theme.zsh:26–28,162–167` (dsV4, Ox, Muse). Delete or wire up.
- **CR-24** `ft` rg `--color=always` breaks pipes → `--color=auto` (Gemini).
- **CR-25** `fkill` header double-SIG ("SIGSIGTERM") (Gemini). Strip existing prefix.
- **CR-26** Deliberate decomposition of `60-functions.zsh`: extract upkg/npkg into lazy modules (proven `functions/ztheme` pattern), split `upkg()`/`_npkg_outdated()` into testable sub-helpers (Gemini, Muse; Ox/dsV4 ◐ not short-term). Schedule last; removes ~4–5 ms parse cost and the CR-01 guard question entirely.
- **CR-27** Quality backlog: extract shared dusage/bigfiles scaffolding; deduplicate NO_COLOR appends + preview lines; unify term-dimension/locale helpers and dual signature schemes; name flagged magic numbers; `ZSH_BENCHMARK_ROOT` override + child-exit detection in benchmark; test-harness fallbacks (`zsh_bin`, empty fakebin guard, zselect skip); prune stale branches (~45); tag theming release once T8 visual signoff closes; document `skills-lock.json`.

## Remediation batches

| Order | Batch | Findings | Rationale |
| --- | --- | --- | --- |
| 1 | Standards batch (one PR) | CR-01, CR-03, CR-09 | One line/small derivation each; restores full AGENTS.md compliance |
| 2 | CI integrity | CR-02 (+ run-tests.sh) | Unblocks confident merging of everything else |
| 3 | Safety batch | CR-06, CR-07, CR-08 | Mechanical, low-risk; closes all Medium-safety items |
| 4 | Performance batch | CR-04, CR-05, CR-13, CR-12 | ~30–40% startup + 190× fbr; land after CI parity so benchmarks prove gains |
| 5 | Hardening & docs | CR-10, CR-11, CR-14, CR-15, CR-16, CR-17, CR-18, CR-20–23 | Independent; batch freely |
| 6 | Deliberate refactor | CR-26 (+ CR-27 backlog) | Only with prior batches banked |

Per AGENTS.md, any batch touching user-facing aliases, functions, completions, or workflows must update `80-tips.zsh`, `README.md`, and `GUIDE.md` in the same change, and `scripts/check-deps.sh` if dependencies change.

## Verification

Each batch must pass the full sequence (via the new `scripts/run-tests.sh` once CR-02 lands):

1. `zsh -n *.zsh lib/*.zsh functions/ztheme functions/_fbr_format_entry`
2. `zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh`
3. `sh -n scripts/check-deps.sh`
4. `zsh scripts/test-init.zsh`
5. `zsh scripts/test-theme.zsh`
6. `zsh scripts/test-functions.zsh`
7. `zsh scripts/test-cgm.zsh`
8. `zsh scripts/test-upkg.zsh`
9. `zsh scripts/test-completions.zsh`
10. `zsh scripts/test-help.zsh`
11. `zsh -fc 'source "$HOME/.config/zsh/init.zsh"'`

Batch-specific additions:
- Performance batch: `scripts/benchmark-startup.zsh 30` before/after; expect command-mode median improvement consistent with the ledger; record numbers in the PR.
- fbr rewrite: row-format equivalence fixture matrix must pass before merge.

## Risks and notes

- **CR-01 × test-upkg interplay:** the suite depends on PATH-stubbed `nix`; the fix must either add `rehash` after stubbing or AGENTS.md must document the deliberate exception. Do not merge the one-liner alone.
- **CR-12 behavioral pinning:** the fbr formatter has an exact-output contract; the rewrite is mechanical but the equivalence test is the deliverable, not just the new formatter.
- **CR-05 semantics:** gating the zoxide refresh changes when `_ZO_FZF_OPTS` materializes; confirm `_fzf_export_config` signature caching still warms correctly on fzf+zoxide machines.
- **Severity inflation caveat:** Muse counts two "Critical" complexity findings (function length) that no other suite treats as defects; this register files them under CR-26 backlog. Conversely, Muse was the only suite to miss CR-01 while being strictest elsewhere — treat any single suite as necessary but insufficient evidence.

## Sign-off

This plan is adopted when the Tier-0 batch merges. It may be marked **Implemented** once batches 1–4 land and the full verification sequence plus batch-specific checks pass on the trunk branch; remaining tiers track through normal PR flow.
