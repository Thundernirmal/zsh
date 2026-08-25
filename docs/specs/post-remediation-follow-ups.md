# Post-Remediation Follow-Ups Specification

| Field | Value |
| --- | --- |
| Status | Implemented 2026-08-25 (F1–F3); accepted Low backlog remains unscheduled |
| Review date | 2026-08-25 |
| Baseline | `526dd6f` on `chore/25` (PR #32) |
| Inputs | Local PR #31/#32 review records and the 18-document cross-review corpus; the actionable findings are preserved below |
| Prior spec | [`validated-cross-review-remediation.md`](validated-cross-review-remediation.md) — marked **Implemented** by PR #32; this document covers only what that remediation surfaced or left open |

> This specification tracks follow-ups discovered while re-reviewing the two remediation PRs. It does not reopen adjudicated findings.

## Summary

PRs #31 and #31+#32 fixed 21 of the 27 consolidated cross-review findings, closed 5 as no-fix by adjudication, deferred CR-26 behind its measurement gate, and split CR-27. The full ordered verification passes (1,046 assertions, 0 failures) and both axes of an independent re-review found **no High or Critical regressions**. Three Medium items and a Low backlog remain. All are small, independently shippable, and none blocks daily use.

## Goals

- Restore colored `ls`/`grep`/`diff` behavior documentation (and optionally capability detection) for non-Linux Tier-2 platforms without reintroducing startup subprocesses.
- Make the shared test runner honor interrupts like every other signal-correct component in this repository.
- Close the last stdout diagnostic leak so R6's acceptance is fully met.
- Record the accepted Low backlog in one place so it is not re-derived by future reviews.

## Non-goals

- Revisiting adjudicated no-fix findings (CR-14, CR-15, CR-18, CR-19, CR-22).
- Starting the CR-26 lazy upkg/npkg refactor outside its R13 measurement gate.
- Re-running the fbr formatter optimization or any completed performance batch.
- Duplicating alias-bypass or QA-checklist work already adjudicated.

## Requirements

### F1. Document (or later cache) non-Linux alias color stance — N-01 · Medium

**Origin:** CR-04 fix (`20-aliases.zsh:10,42–45`, commit `526dd6f`) replaced probes with `[[ $OSTYPE == linux* ]]`. BSD `ls` lacks `--color=auto`; BSD `grep`/`diff` support it but now go uncolored on macOS/BSD.

- Add a GUIDE platform-notes entry stating that `ls`/`ll`/`la`, `grep`, and `diff` colorization applies on Linux only under the zero-probe policy, and that plain behavior is unchanged elsewhere.
- Optional (only with evidence): design a cached, invalidation-aware capability probe per validated-spec R8 constraints before/after benchmarks; do not restore unconditional source-time probes.

**Acceptance:** GUIDE documents the Linux-only color scope; no module-top-level process spawn exists in `20-aliases.zsh`; existing probe-quietness tests still pass.

### F2. Runner must abort on SIGINT/SIGTERM — N-02 · Medium

**Origin:** `scripts/run-tests.zsh:13` traps `EXIT INT TERM HUP` for cleanup only, so Ctrl-C continues into the next suite.

- Keep `EXIT` for cleanup.
- On `INT`/`TERM`: run cleanup, restore default disposition, and re-raise (`trap - INT; kill -s INT $$`) so the runner dies with the conventional status instead of continuing.
- Add a regression assertion if practical: interrupting the runner mid-sequence exits nonzero promptly without starting further suites.

**Acceptance:** interrupted runs stop immediately with a signal-derived exit status; no suite after the interruption starts; cleanup still removes `smoke_home`.

### F3. Route the last npkg diagnostic to stderr — N-03 · Medium

**Origin:** residual from CR-17; `60-functions.zsh:4307` prints `"Diagnostic: …"` via stdout inside `_npkg_outdated`.

- Change to `print -u2 -r --`.
- Extend test-upkg to assert profile-error diagnostics never appear in captured stdout while normal outdated output remains byte-identical.

**Acceptance:** command substitutions over `npkg outdated` failure paths capture no diagnostic prose; all suites pass.

## Accepted low backlog (no schedule committed)

| ID | Item | Note |
| --- | --- | --- |
| N-04 | Extract one shared trap/signal scaffold used by `dusage`, `bigfiles`, `_npkg_refresh_index` | Deduplicate three copies of subtle trap logic; requires a deep-module interface proposal first |
| N-05 | Late-interrupt window can execute `break` outside its loop (~`60-functions.zsh:835`) | Guard flag or restructure; cosmetic spurious error before status return |
| N-06 | Unify fallback `_ui_truncate` with REPLY-style real implementation (L4 divergence repeated) | Only visible when `55-ui-helpers.zsh` absent; add fallback-parity assertions when touched |
| N-07 | `zi` chrome-refresh failure returns before the fzf-version diagnostic | Reorder so the actionable message wins |
| N-08 | Verify apt/brew/npm/flatpak `--` terminators against real CLIs once, record results | Manual QA item; npm grammar quirkiest |
| N-09 | Adversarial fzf placeholder fixture skips without `script(1)` | CI image includes util-linux; note only |
| N-10 | Zoxide init stderr suppressed even interactively | Consider surfacing captured stderr after the generic interactive diagnostic |
| N-11 | CR-26 lazy upkg/npkg decomposition | Stays behind R13's two-consecutive-benchmark gate; parse-proxy evidence recorded in the validated spec |

## Explicit non-work

- No re-capture of live `FZF_DEFAULT_OPTS` exports (CR-14 adjudication stands).
- No registry refactors beyond the landed `lib/upkg-registry.zsh` owner (CR-09 is done).
- No QA execution or tracked `qa-features.csv` artifact in this follow-up. The next stable-release pass was opened separately; its reset checklist remains ignored and local-only under CR-22.
- No bare-placeholder changes to fzf preview strings (CR-19); the adversarial fixture added in PR #32 is the agreed defense-in-depth.

## Verification

Each item ships through `zsh scripts/run-tests.zsh` plus the item-specific acceptance above. Documentation items require the AGENTS.md sync rule (module + README + GUIDE + tips where user-facing).

## Implementation outcome

- **F1 completed:** GUIDE now states that the zero-probe policy limits the built-in `ls` fallbacks and the `grep`/`diff` color aliases to Linux. `20-aliases.zsh` remains process-free at module scope, and `lsd` remains the guarded cross-platform preference when installed.
- **F2 completed:** the ordered runner keeps its `EXIT` cleanup trap, handles INT/TERM/HUP by cleaning up, restores the caught signal's default disposition, and re-raises it. The init regression suite proves SIGINT returns 130 and no later runner command starts.
- **F3 completed:** the residual Nix profile-read diagnostic uses stderr. The upkg/npkg regression suite captures the streams separately and proves the failure leaves stdout empty while the existing normal-output fixtures remain unchanged.
- **Verification:** `zsh scripts/run-tests.zsh` and `git diff --check` pass after the implementation. The N-04 through N-11 backlog remains intentionally unscheduled.

## Completion condition

This specification is **Implemented** because F1–F3 landed and verified. The low backlog may remain open indefinitely; it should be cited — not re-discovered — by future reviews.
