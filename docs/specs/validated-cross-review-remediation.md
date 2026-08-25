# Validated Cross-Review Remediation Specification

| Field | Value |
| --- | --- |
| Status | Implemented (batches 1–6); CR-26 deferred by its interface gate |
| Validation date | 2026-08-25 |
| Baseline | `71fce91` on `chore/25` |
| Input | Local cross-review consolidation of CR-01 through CR-27; the adjudicated findings are preserved below |
| Current user reference | [`GUIDE.md`](../../GUIDE.md) |

> This specification adjudicates the 27 consolidated cross-review findings against the current source, tests, documentation, and repository rules. The implementation outcome is recorded below; [`GUIDE.md`](../../GUIDE.md) remains the current user reference.

## Implementation outcome

Batches 1–4 are implemented and verified, satisfying this specification's release completion condition. The measured follow-ups in batch 5 and the accepted maintenance work in batch 6 are also implemented. CR-26 remains deliberately unimplemented: two parse-proxy runs confirm that the package block is material, but the current package regression suite directly exercises many private helpers. Moving the block while keeping those tests unchanged would require a wide set of shallow lazy stubs, which would enlarge and scatter the interface instead of creating the required deep module.

Startup measurements used the repository-owned command on the same host and shell:

```sh
zsh scripts/benchmark-startup.zsh 30
```

| Point | Command median / p95 | Interactive median / p95 |
| --- | --- | --- |
| Before batches 4–6 | 20.427 / 22.989 ms | 23.706 / 24.342 ms |
| After zero-probe aliases and deferred zoxide chrome | 18.319 / 20.316 ms | 22.558 / 24.616 ms |
| Final, after lazy help and tips catalogues | 15.501 / 17.651 ms | 19.206 / 20.420 ms |

The isolated fbr fixture ran 15 samples of 200 rows in one shell. Its median fell from 735.058 ms to 128.181 ms, with pinned ordinary, worktree, control-character, Unicode, and width-boundary projections remaining byte-identical. The CR-26 parse proxy was repeated twice: the full function body measured 55.537 and 55.551 ms median per evaluation, while the pre-package core measured 3.592 and 3.715 ms. This establishes potential, but it is not a valid end-to-end before/after result and therefore does not override the failed interface gate.

## Decision summary

The consolidation plan is useful, but not every CR is correct as written and its tiering should not be used as an implementation queue without revision.

- **Required or worthwhile work:** CR-01 through CR-13, CR-16, CR-17, CR-20, CR-21, and CR-23 through CR-27. Several of these need a narrower fix than the original plan proposed.
- **No new fix:** CR-14, CR-15, CR-18, CR-19, and CR-22. They conflict with an intentional contract, are already satisfied, or rely on an incorrect premise.
- **Conditional work:** CR-04, CR-12, CR-13, and CR-26 must be justified by repeatable before/after measurements. CR-27 must be split into independently reviewable items rather than treated as one finding.

The highest-confidence defects are the startup guard violation (CR-01), redirectable theme helper path (CR-03), temporary-file lifecycle and concurrency gaps (CR-06), unsafe leading-dash handling (CR-07), invalid relative XDG paths (CR-11), `dusage` ARG_MAX exposure (CR-16), stdout error leakage (CR-17), and the small correctness defects in CR-24 and CR-25.

## Adjudication register

| CR | Verdict | Finding after validation |
| --- | --- | --- |
| CR-01 | **Fix** | Correct. `60-functions.zsh:3782` is the only module-top-level `command -v` and violates the startup guard rule. |
| CR-02 | **Fix, revised** | CI omits the benchmark syntax check and final source smoke test, and lacks a job timeout. Running the real environment dependency check is explicitly optional and must not be made a blocking CI requirement. |
| CR-03 | **Fix** | Correct. An inherited `_ZSH_THEME_MODULE_DIR` can redirect trusted lazy sources away from the repository. |
| CR-04 | **Optimize after measurement** | The three source-time capability probes are real subprocess cost. The proposed “single-process grep probe” does not meet the stated zero-process acceptance criterion, so the implementation choice must be reworked. |
| CR-05 | **Fix** | Correct. Zoxide fzf presentation is compiled even when zoxide is absent and during command-mode startup where it cannot be used. |
| CR-06 | **Fix, revised** | Correct. Interrupts can leak scan files, and `_npkg_refresh_index` also uses shared `.tmp`/`.err` names that allow concurrent refreshes to interfere. Signal handling must preserve signal status rather than swallowing interrupts. |
| CR-07 | **Fix, revised** | Leading-dash operands are mishandled in several paths. Do not blindly add `--`: archive tools and package-manager CLIs have different option grammars. |
| CR-08 | **Fix** | Correct hardening. The nine public utilities inherit caller options while most substantial functions already use `emulate -L zsh`. |
| CR-09 | **Fix as maintenance debt** | The registries are duplicated and currently synchronized. This is not a Tier-0 runtime defect. Prefer existing owner data where that does not defeat lazy loading; otherwise add drift tests before a larger registry refactor. |
| CR-10 | **Fix, revised** | A failed or empty `zoxide init zsh` is currently treated as successful. Check generation status and non-empty output, but do not add an unconditional `zsh -fn` subprocess to every startup. |
| CR-11 | **Fix, revised** | Relative XDG paths are invalid and currently become paths under `$PWD`. Follow the existing fzf policy: ignore an invalid relative XDG value and use a validated absolute fallback; fail only when no safe absolute base exists. |
| CR-12 | **Optimize after measurement** | The formatter performs multiple command substitutions per branch row. Preserve the exact sanitization and projection contract; the suggested `printf -v` sketch alone does not do that. |
| CR-13 | **Optimize after measurement** | Help records and tips are credible lazy-loading candidates. The lazy loader must remain fixed to the repository and completion must load help data only when completion is invoked, not when `66-compdefs.zsh` is sourced. |
| CR-14 | **No fix — contradicts contract** | `GUIDE.md:216–224` and the theming spec intentionally capture inherited fzf options exactly once. Mid-session edits must use `ZSH_FZF_EXTRA_OPTS` or be made before sourcing. Re-capturing composed values risks duplication. |
| CR-15 | **No fix — already documented** | `_upkg_record_cleanup_result` explicitly documents its caller-local counters. Zsh dynamic scoping is intentional here, and the suite already runs cleanup flows under `set -u`. A private helper need not work from an invalid fresh call site. |
| CR-16 | **Fix** | Correct. `dusage` expands every immediate entry into one `du` argv and can exceed ARG_MAX. `bigfiles` already demonstrates the GNU `--files0-from` pattern. |
| CR-17 | **Fix, broadened** | Correct principle, but the nine-site list is incomplete. Audit every public function and route usage/errors to stderr while retaining successful, informational output on stdout. |
| CR-18 | **No fix — already satisfied** | `GUIDE.md:760–761` already documents `command <name>` and other prompt bypasses. README should remain a short entry point, and tips should not duplicate a long safety explanation. |
| CR-19 | **No code fix** | Bare fzf placeholders are the documented safe form. The cited fzf issue concerns manually quoting a placeholder, which this repository does not do. Add an adversarial regression fixture under CR-20 if practical, but do not replace the current commands without a failing test. |
| CR-20 | **Fix, corrected inventory** | Coverage gaps exist, but `ports` has behavioral coverage and `extract`, `headers`, `peek`, and `tips` have partial coverage. Add missing module assertions and meaningful success/failure behavior, not merely one assertion per name. |
| CR-21 | **Fix** | Correct documentation gap. GUIDE presents eight completion examples after saying coverage “covers,” while `66-compdefs.zsh` registers substantially more commands, including `ztheme`. |
| CR-22 | **No fix — historical/local artifact** | `qa-features.csv` is intentionally ignored and currently records a completed 12-case follow-up QA run. A historical spec truthfully records an earlier 39-row run. Regenerate a `Not Run` checklist only when starting the next full stable-release QA pass. |
| CR-23 | **Fix only confirmed dead code** | `_ui_has_truecolor`, `_ui_has_icons` and its fallback, and the skipped-manager branch are unused/unreachable. The theme re-source blocks are required: `scripts/test-theme.zsh:302–323` proves that re-sourcing must restore already-loaded lazy implementations. |
| CR-24 | **Fix** | Correct. `ft` forces ANSI color with ripgrep even when redirected, unlike its grep fallback. Use `--color=auto`. |
| CR-25 | **Fix** | Correct. Normalize an optional leading `-` and optional `SIG` prefix before rendering and invoking `kill`, and reject an empty result. |
| CR-26 | **Conditional refactor** | Lazy-loading upkg/npkg can reduce parse cost, but this is not a defect. Proceed only with an interface boundary, benchmark, and complete behavior parity tests. |
| CR-27 | **Split; fix selected items** | Benchmark child-status handling and test-harness robustness are concrete. Most deduplication, magic-number, branch-pruning, tag, and signature suggestions are unrelated backlog or require separate design evidence. |

## Required remediation

### R1. Startup trust and guard compliance

**CRs:** CR-01, CR-03

- Replace the top-level Nix guard with `(( $+commands[nix] ))`.
- Keep `command -v` inside function bodies unchanged.
- Pin `_ZSH_THEME_MODULE_DIR` unconditionally to `${${(%):-%N}:A:h}`.
- Extend tests so a hostile exported `_ZSH_THEME_MODULE_DIR` cannot redirect `lib/theme-*.zsh` sources.
- Ensure the PATH-stubbed Nix tests expose `nix` before `60-functions.zsh` is sourced. Add `rehash` only if a focused test proves it is needed; do not preserve the standards violation for a hypothetical stale hash.

**Acceptance:** no module-top-level `command -v`; hostile theme path test passes; Nix fake-binary suite passes.

### R2. CI parity and bounded execution

**CR:** CR-02

- Add `scripts/run-tests.zsh` as the executable owner of the required ordered sequence.
- Add the missing `zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh` and final `zsh -fc 'source .../init.zsh'` coverage through that runner.
- Add `timeout-minutes` to the verify job.
- Add `workflow_dispatch` for manual verification. Keep pull-request and trunk-push coverage; decide branch push policy separately instead of hard-coding the temporary `chore/25` name.
- Exercise the fixed install-path smoke test in CI by placing or linking the checkout at `$HOME/.config/zsh` under an isolated CI home. Do not weaken `init.zsh` with a test-only configurable source root.
- Do **not** run the host environment dependency audit as a blocking repository test. Its syntax and fake-binary behavior remain tested; its live result is machine-specific by repository policy.
- Update AGENTS.md and GUIDE.md together if the runner becomes the source of truth.

**Acceptance:** local and CI entry points execute the same required checks in the same order, a failing child fails the runner, and CI cannot run for the platform default six-hour timeout.

### R3. Temporary files, interruption, and large argument sets

**CRs:** CR-06, CR-16

- Make `dusage` feed NUL-delimited operands through GNU `du --files0-from` or bounded chunks rather than one unbounded argv.
- Give `dusage` and `bigfiles` guaranteed cleanup on normal return, errors, INT, TERM, and HUP.
- Replace `_npkg_refresh_index`'s shared `${cache_file}.tmp` and `${cache_file}.err` with per-call files created in the destination directory. Preserve atomic activation with `mv` only after successful evaluation and parsing.
- Preserve `130` for SIGINT and the appropriate nonzero termination status for other signals. Cleanup traps must not swallow the signal and continue rendering.
- Cover command failure, second-temp creation failure, `mv` failure, and concurrent refreshes in addition to interrupts.

**Acceptance:** no matching temporary files remain after every tested exit path; two simultaneous refresh fixtures cannot overwrite each other's intermediates; a deliberately oversized `dusage` fixture completes without E2BIG.

### R4. Leading-dash operands and function-local shell semantics

**CRs:** CR-07, CR-08

- Add `emulate -L zsh` to `extract`, `mkcd`, `ff`, `ft`, `fkill`, `headers`, `peek`, `croot`, and `gitcount`; normalize `gitcount()` syntax.
- Use `builtin cd --` for user- or Git-derived directories.
- Use the correct safe operand form for each archive backend. For tar formats, prefer unambiguous long options or a tested archive-file option; verify whether `unrar`, `7z`, and each decompressor supports `--` before changing it.
- Protect Git branch arguments and each apt, brew, flatpak, and npm search query using syntax supported by that specific CLI.
- Preserve the existing upkg parser's explicit `--` boundary between wrapper flags and query terms.

**Acceptance:** tests exercise leading-dash directories, archives for each available fake backend, local and remote branch names, and package queries; hostile caller options do not change public function behavior.

### R5. XDG base-directory handling

**CR:** CR-11

- Accept `XDG_DATA_HOME` and `XDG_CACHE_HOME` only when absolute.
- When an XDG variable is relative, ignore it and use the documented absolute HOME fallback, matching `40-fzf.zsh`.
- Reject the operation with a clear stderr diagnostic when neither the XDG value nor HOME yields a safe absolute base.
- Create the CGM catalogue under a `umask 077` subshell before validating final ownership/type/mode. Do not add any plaintext secret fallback.
- Keep npkg cache permissions proportionate to non-secret public package metadata; the important requirements are an absolute base, safe directory operands, and atomic files.

**Acceptance:** relative XDG tests never create `$PWD/cgm` or `$PWD/npkg`; absolute overrides and HOME fallbacks work; CGM safety and completion tests remain secret-value-free.

### R6. Public output and small correctness fixes

**CRs:** CR-17, CR-24, CR-25

- Audit invalid usage, missing dependencies, invalid paths, and failed preconditions across public functions. Send those diagnostics to stderr with `print -u2 -r --`.
- Do not redirect normal results, status dashboards, or intentionally pipeable data to stderr.
- Change ripgrep in `ft` to `--color=auto` and assert redirected output contains no ANSI escapes.
- Normalize `fkill` signals so `15`, `-15`, `TERM`, and `SIGTERM` render one `SIGTERM` label and invoke the same signal. Invalid or empty values fail before fzf opens.
- Because these change user-facing function behavior, synchronize `80-tips.zsh`, README.md, and GUIDE.md within their ownership boundaries as required by AGENTS.md.

**Acceptance:** command substitutions receive no usage/error prose, direct terminal use still shows actionable errors, `ft | command cat` is color-clean, and the fkill header never contains `SIGSIG`.

### R7. Test and documentation gaps

**CRs:** CR-20, CR-21

- Add direct assertions for `10-history.zsh`, `50-completion.zsh`, and `70-globals.zsh`.
- Add behavioral fixtures for `fanprofile`, `croot`, `gitcount`, `weather`, and the success paths of `extract`, `headers`, and `peek`.
- Retain and recognize existing coverage for `ports`, missing-argument behavior, tips linting, and completion registration.
- Exercise `tips()` itself in plain mode with a deterministic pool or controlled RANDOM value.
- Add a supported-fzf adversarial placeholder fixture containing spaces, shell metacharacters, and a single quote. This is defense-in-depth for CR-19, not evidence that the production placeholder command is wrong.
- Make GUIDE's completion section complete or explicitly label its command block as non-exhaustive. Because GUIDE is the full reference, a compact complete list is preferred.

**Acceptance:** each module's owned settings are asserted, each listed public behavior has at least one real success or meaningful failure fixture, and GUIDE agrees with every `compdef` registration.

## Measured optimization and maintenance work

### R8. Source-time subprocess reduction

**CRs:** CR-04, CR-05

- Establish a 30-run command and interactive baseline before changing the probes.
- Remove the unconditional zoxide fzf refresh when zoxide is absent. In command-mode or `zsh -i -c` startup, defer it until a picker-capable path needs it; in a normal interactive prompt, ensure `_ZO_FZF_OPTS` is composed before zoxide's interactive integration can consume it.
- Rework the ls/grep/diff capability strategy so the chosen acceptance criterion matches the implementation. Valid options include a zero-probe GNU/Linux policy with conservative non-GNU fallbacks, or a demonstrably cheap cached capability mechanism. A “single-process probe” cannot claim zero source-time processes.
- Preserve quiet startup with fake unsupported tools and preserve guarded fallbacks.

**Acceptance:** repeatable startup improvement without losing aliases on the supported GNU/Linux target; no theme registry load in command-mode startup solely for zoxide chrome; normal interactive `zi` retains the full shared options.

### R9. Registry drift prevention

**CR:** CR-09

- Reuse `_ZSH_UI_THEME_NAMES` for theme completion rather than copying built-in names.
- Give the upkg manager whitelist one declarative owner that both parsing and completion can consume without external work.
- Keep extract dispatch explicit and safe; if deriving suffix completion from dispatch would require parsing function text or evaluation, retain the static completion list and add a drift test instead.
- Do not eagerly source the lazy theme registry merely to populate completion.

**Acceptance:** a new theme or manager requires one data edit; an added extract format either updates completion from the same data or fails a synchronization test.

### R10. Zoxide initialization failure handling

**CR:** CR-10

- Capture `zoxide init zsh` output once.
- Evaluate it only when generation succeeds and returns non-empty output.
- Keep non-interactive startup quiet; an interactive failure may print one concise diagnostic and must leave `z`/`zi` unavailable rather than half-installed.
- Do not invoke a second Zsh parser on every startup. If syntax validation is still desired, first design a trusted, invalidation-aware cache and demonstrate that it does not regress startup.

**Acceptance:** fake zoxide success, nonzero, empty, and malformed-output cases have deterministic status and definitions; steady-state startup does not gain another subprocess.

### R11. Lazy catalogues and fbr row formatting

**CRs:** CR-12, CR-13

- Benchmark `_fbr_format_entry` separately from fzf and retain a checked-in equivalence fixture before rewriting it.
- Preserve control-character sanitization, centered truncation, `[WT]` styling surgery, tab-delimited five-field projection, raw branch identity, and the existing width behavior. Introduce REPLY-returning helper variants if needed to remove command substitutions without duplicating sanitizer logic.
- Move help records and tips data behind small fixed-path loaders only if the measured startup saving reproduces. Keep top-level registration of `zhelp`/`tips` cheap and keep completion data loading deferred until completion invocation.
- Re-evaluate environment-dependent tips at first use or explicitly preserve startup snapshot semantics; document whichever behavior is chosen.

**Acceptance:** byte-identical fbr fixtures across ordinary, worktree, control-bearing, Unicode, and width-boundary rows; measured picker improvement; first and repeated help/tips calls match their documented behavior; no user-controlled lazy source path.

### R12. Confirmed dead code and focused tooling hardening

**CRs:** CR-23, selected CR-27 items

- Remove `_ui_has_truecolor`, `_ui_has_icons`, its unused fallback, and the unreachable skipped-manager branch after updating tests that stub unused helpers.
- Keep the lazy theme re-source blocks. They restore implementation functions after the module overwrites them with loader stubs, and the existing idempotence test depends on this behavior.
- Make `scripts/benchmark-startup.zsh` fail immediately when a warmup or measured child exits nonzero. A fast failure must never be reported as a performance sample.
- Harden `scripts/test-init.zsh` command-path lookup and fakebin setup against empty command entries.
- Skip only the interrupt fixture, with a clear TAP-style message, when `zsh/zselect` is genuinely unavailable; do not skip the rest of `test-upkg.zsh`.
- Document `skills-lock.json` briefly in maintainer-facing documentation because it is tracked repository metadata.

**Acceptance:** no confirmed-dead function or branch remains; theme re-source idempotence still passes; failed benchmark children fail the benchmark; test harness setup emits a clear failure or targeted skip instead of executing an empty path.

## Conditional architecture work

### R13. Lazy upkg/npkg decomposition

**CR:** CR-26

**Status:** Implemented in the follow-up startup hardening branch. `60-functions.zsh` now exposes one fixed lazy-loader seam for the complete helper graph, while `lib/functions-catalogue.zsh` keeps the interconnected implementations local. The public commands and lightweight package registry remain available at startup; the catalogue is parsed on first command use.

Do not mix this refactor into correctness batches. First record `60-functions.zsh` parse cost and identify a deep interface:

- `upkg` and conditional `npkg` remain the only public package entry points;
- repo-local autoload paths remain fixed and idempotent;
- manager detection remains live inside function bodies so PATH-stub tests and mid-session installations work;
- help, tips, and completions can determine availability without loading command-only implementation;
- all current package regression tests run unchanged before internal test improvements are considered.

Proceed only if two consecutive benchmark sets show a material startup reduction and the proposed split reduces the interface surface rather than scattering the current helper graph across shallow files.

## Explicit non-work

### CR-14 — do not re-capture live fzf exports

The current one-time capture is intentional and documented. Users who need a session override can set `ZSH_FZF_EXTRA_OPTS`; persistent inherited options must be set before `init.zsh` is sourced. A future explicit `ztheme refresh-options` design would be a separate feature, not a bug fix.

### CR-15 — retain the cleanup helper's dynamic scope

The private helper mutates caller-local counters by design. Its contract is already commented, and the public cleanup paths are the correct test boundary. Revisit only as part of a deeper upkg module design.

### CR-18 — do not duplicate alias-bypass documentation

GUIDE already states both the direct `command <name>` bypass and the broader fact that aliases are not a safety boundary. README and tips should retain their assigned concise roles.

### CR-19 — retain bare fzf placeholders

The [fzf manual](https://github.com/junegunn/fzf/blob/master/man/man1/fzf.1) says placeholder expansions are individually shell-quoted, safe as external-command arguments, and should not be manually quoted. The cited [fzf issue #1586](https://github.com/junegunn/fzf/issues/1586) demonstrates the failure caused by adding manual quotes around a placeholder. The repository uses the documented bare form.

### CR-22 — do not rewrite the ignored completed QA record

The CSV is local-only working state and is not a durable repository artifact. Historical specs should continue recording the QA performed at their implementation point. At the start of a future full stable-release QA pass, regenerate the checklist with `Status=Not Run` under the exact AGENTS.md schema.

## Work that must be split out of CR-27

The following are not accepted as one remediation item:

- deduplicating `dusage`/`bigfiles`, NO_COLOR appends, preview strings, terminal dimensions, locale checks, or signature builders;
- naming every numeric literal;
- pruning local or remote branches;
- tagging the theming release before its stated Nix-host visual gate passes;
- deleting historical spec branches or untracked review inputs.

Each code deduplication proposal needs a concrete deep-module interface and evidence that the helper removes more complexity than it adds. Branch deletion is a destructive repository-maintenance action outside this code remediation spec. Release tagging remains governed by the existing theming spec's sign-off condition.

## Recommended delivery order

| Order | Batch | CRs | Outcome |
| --- | --- | --- | --- |
| 1 | Startup trust and standards | CR-01, CR-03 | Implemented |
| 2 | CI and harness integrity | CR-02, selected CR-27 | Implemented |
| 3 | Files, signals, and argument safety | CR-06, CR-07, CR-08, CR-11, CR-16, CR-17 | Implemented |
| 4 | Small correctness and docs | CR-20, CR-21, CR-24, CR-25 | Implemented |
| 5 | Measured startup and picker performance | CR-04, CR-05, CR-12, CR-13 | Implemented after measurement |
| 6 | Maintenance hardening | CR-09, CR-10, confirmed CR-23 | Implemented |
| 7 | Conditional architecture refactor | CR-26 | Deferred: interface gate not met |

CR-14, CR-15, CR-18, CR-19, and CR-22 are closed with no implementation change unless new failing evidence appears.

## Verification policy

Every implementation batch must pass the repository's ordered verification sequence. Once CR-02 lands, the shared runner is the preferred entry point; until then, use the explicit sequence in AGENTS.md and GUIDE.md.

Performance batches additionally require:

1. the same host, shell binary, environment, warmup count, and iteration count before and after;
2. at least 30 measured runs for command and interactive startup;
3. recorded median and p95, plus the raw command used;
4. rejection of any sample whose child shell exits nonzero;
5. a behavior-equivalence test before accepting a speedup.

## Completion condition

This specification is marked **Implemented** because batches 1–4 are complete and verified. Batches 5 and 6 are also complete. Batch 7 remains separately deferred under its original conditional gate. The five no-fix CRs are adjudicated and do not block release.
