# Performance implementation ledger

Append-only record for the staged [plan](./plan.md). Original reviews, plans, harnesses, and baseline results remain intact. An entry names its commit subject (searchable with `git log --grep`) and parent; the following stage records the preceding commit hash so entries do not depend on their own hash. No remote push is authorized.

## Stage 1 — C01 numeric-width rich checks

- Parent: `45c2bd5`; commit subject: `perf(C01): avoid repeated width capture in rich checks`.
- Change: read live numeric `COLUMNS` in the hot predicate; retain `_ui_term_width` for absent/invalid dimensions and all low-frequency public width/height calls. No global eligibility cache, new scratch variable, or metadata conversion.
- Coverage: PTY/pipe presentation and scratch-state comparison against the pre-change predicate over terminal/nord themes, ANSI/256/truecolor, widths 59/60/120, NO_COLOR, dumb terminal, and C locale. Explicit resize, no-width-capture, fallback, and height-override checks.
- Validation and measurements: recorded below before commit.
- Website: helper locations, printing interfaces, command records, and guide structure unchanged; companion snapshot checks remain pending. No website compatibility claim.

Stage 1 validation: full `zsh scripts/run-tests.zsh` passed (1,963 `ok:` lines, real-fzf PTY included); `git diff --check` passed. Five interleaved 100-row PTY batches measured median **717.88 → 145.53 ms**; [raw C01 samples](./C01-results.json). These are local observations, not CI thresholds. Metadata conversion is intentionally left for C08; this commit completes C01's width-only gate. README/GUIDE/tips behavior remains accurate because this changes only an internal implementation, not the documented terminal eligibility policy.

## Stage 2 — C02 bounded plain previews

- Previous stage commit: `cf29e5d` (C01). Parent: `cf29e5d`; commit subject: `perf(C02): stop plain file previews after 200 lines`.
- Change: both exported Ctrl+T color branches use GNU sed `200Q` after printing line 200. Preserves a missing final newline; deliberately stops observing errors beyond the preview prefix.
- Coverage: execute the actual exported preview strings with controlled PATH, seven byte fixtures, quotes/spaces/leading-dash filenames, missing/unreadable files, directory fallback, and bat selection/color arguments. A FIFO held open after exactly 200 lines proves bounded reading without waiting for EOF. The full native-fzf suite continues to cover picker rendering.
- Documentation: README summary, GUIDE preview boundary, and tips-loader ownership note updated together. No guide heading or command registration changes. Website snapshot/semantic checks are pending; no remote push.

Stage 2 validation: full runner passed (1,964 `ok:` lines, UI and real-fzf PTY included). FIFO bounded-read and both exported preview branches passed. Five interleaved 256 MB runs measured median **255.69 → 1.64 ms**; [raw C02 samples](./C02-results.json). Missing/unreadable-file diagnostics and statuses match the previous sed command. `git diff --check` passed.

## Stage 3 — C03 printable ASCII sanitization

- Previous stage commit: `e14f1a0` (C02). Parent: `e14f1a0`; commit subject: `perf(C03): fast-path printable ASCII sanitization`.
- Change: `_ui_safe_text_reply` returns printable ASCII unchanged using the same range as display-width calculation. All other input retains the existing character loop, escape spellings, and MULTIBYTE handling. No truncation or canonical-ref changes.
- Coverage: C0/C1/DEL and named controls in UTF-8, printable Unicode, combining text, invalid byte, empty/short/4 KiB ASCII in C and UTF-8; a printf counter proves ASCII skips per-character conversion. Existing hostile-path and full fbr row/canonical-ref regressions remain active. This internal optimization does not change the documented escaping policy.
- Website: source location/helper interface unchanged; no snapshot sync or compatibility claim.

Stage 3 validation: full runner passed (1,965 `ok:` lines, real-fzf PTY included); focused function regressions passed. Three interleaved batches at 100/1,000/3,000 rows measured baseline/current medians 150.95/71.09 ms, 1645.54/715.68 ms, 4703.37/2196.76 ms; [raw C03 samples](./C03-results.json). `git diff --check` passed.

## Stage 4 — C07a per-build color-role reuse

- Previous stage commit: `47ddbf7` (C03). Parent: `47ddbf7`; commit subject: `perf(C07a): resolve each finder color role once per build`.
- Change: a local role cache reduces 40/41 target resolutions to 13 per build. Explicitly restores REPLY on cache hits, preserving the prior final scratch result. No persistent cache or RGB arithmetic change.
- Coverage: frozen pre-change output digest across all five built-ins, four depths, and three layouts, including final REPLY; resolver counts (13 compact/roomy, zero no-color), failure propagation, existing custom-palette/atomic-refresh tests, and pure-Zsh startup probes.
- Website: mapping targets, literal registrations, helpers, and documentation behavior unchanged. Snapshot checks remain pending; no remote push.

Stage 4 validation: full runner passed (1,967 `ok:` lines), focused theme tests and byte-for-byte matrix comparison passed. Median per-build times: truecolor 4.582 → 2.227 ms, 256 26.358 → 9.279 ms; [raw C07a samples](./C07a-results.json). `git diff --check` passed.

## Stage 5 — C04 ordered completion union cache

- Previous stage commit: `073ffe9` (C07a). Parent: `073ffe9`; commit subject: `perf(C04): reuse the ordered Nix completion union`.
- Change: cache the final unique array behind a NUL-framed ordered path/identity signature. Eligibility and identities are still checked on every request. Missing stat identities disable reuse. Bulk array deduplication preserves first occurrence order; the existing cold line reader retains its unterminated-record semantics. Rebuilds retain only current per-file identities/data.
- Coverage: independent parse/build counters; warm caller-mutation isolation; overlapping files, replacements, additions, empty files, symlinks, readability changes, stat failure, and removal cleanup. Existing tests retain no-Nix/no-refresh assertions.
- Documentation: README/guide/tips-loader synchronized. The guide states the retained identity/timestamp granularity; completion remains offline. No guide headings or public registration changes. Companion snapshot and interactive host completion-framework timing remain pending; helper measurements do not claim end-to-end Tab latency.

Stage 5 validation: focused completion tests passed. The first full run failed in the existing real-fzf branch picker after Enter arrived while filtering still showed 2/2 candidates; no completion-union failure occurred. An isolated complete PTY retry and then the complete runner passed (1,979 `ok:` lines). No test timing or assertion was weakened. Warm helper medians at 10k/30k/60k names: 134.13 → 3.07 ms, 755.06 → 7.86 ms, 2436.35 → 14.46 ms; [raw C04 samples](./C04-results.json). Cold reading remains unchanged in semantics; bulk deduplication also reduces cold cost. `git diff --check` passed.

## Stage 6a — C05 initial Nix profile decoding

- Previous stage commit: `7dba0ea` (C04). Parent: `7dba0ea`; commit subject: `perf(C05a): decode Nix profile fields in one batch`.
- Scope: split C05 into initial-profile decoding and evaluation-result processing, each independently validated and committed before C06 scheduling. This entry completes only the initial decoder.
- Change: move six scalar extractions and structural validity into the existing whole-profile jq transform. Escaped TSV plus an explicit NUL escape feeds a fixed seven-field decoder without eval. Preserve the original command substitutions' trailing-newline trimming after lossless transport decoding. Initial jq count is now two, independent of active entry count.
- Coverage: exact empty/tab/newline/CR/NUL/backslash/Unicode/trailing-newline transport, invalid escapes, 0/20/100-entry process counts, incomplete-row state and status, visible escaping, malformed profiles, and existing object/array/inactive/output-selection fixtures. Native queries and the supervisor are unchanged.
- Documentation: README, GUIDE, and tips-loader notes retain fresh checks and explicit unknown/error boundaries. The new private helper remains in the existing Nix source file; companion extraction/snapshot verification is pending.

Stage 6a validation: full runner passed (1,982 `ok:` lines, real-fzf PTY included), with focused Nix and package fixtures. Three interleaved 0/20/100-entry calls matched complete stdout, status, and totals; median baseline/current times 11.32/14.31 ms, 552.16/40.91 ms, 2748.84/136.75 ms; [raw C05a samples](./C05a-results.json). Two jq calls are asserted independently of timing. `git diff --check` passed. C05 evaluation-result work remains next, before worker scheduling.

## Stage 6b — C05 evaluation-result decoding

- Previous stage commit: `3f618ff` (C05a). Parent: `3f618ff`; commit subject: `perf(C05b): combine Nix evaluation result decoding`.
- Change: normal current/locked records each use one jq pass for validation, version extraction, and (current) normalized path-set comparison, replacing four/two passes. Records and installed sets travel on stdin, avoiding argv size limits. Escaped fields reuse the tested decoder. Multi-record JSON streams explicitly retain the original decode path, including joined-version behavior.
- Coverage: exact jq invocation counts, reordered/duplicate paths, missing/invalid versions, malformed/empty paths, NUL/control/backslash version text, trailing-newline compatibility, and a multi-record fallback. Existing package/cancellation fixtures remain active.
- Scope: no scheduler changes, no cached native inventory, no mutation changes, no new dependency. Documentation semantics from C05a remain unchanged. The additional private helper stays in the existing Nix file; companion checks remain pending.

Stage 6b validation: full runner passed (1,984 `ok:` lines); focused package and decoder tests passed. Three interleaved 20/100-entry current+locked fixtures matched stdout/status/state; median C05a/C05b times 526.62/286.73 ms, 2577.95/1372.55 ms; [raw C05b samples](./C05b-results.json). C05 initial and result decoding are complete; explicit-output evaluation selection retains its existing validation. `git diff --check` passed.

## Stage 7 — C06 incremental Nix worker replenishment

- Previous stage commit: `264b350` (C05b). Parent: `264b350`; commit subject: `perf(C06): refill completed Nix evaluation slots`.
- Change: inspect at most eight recorded workers with the existing parent/start-identity check, reap completed statuses, and refill available slots. Use optional builtin `zsh/zselect` polling at 10 ms; if unavailable, retain full batch draining. Final output still follows profile order. Signal forwarding, supervisor ownership, and native queries remain unchanged.
- Coverage: a deterministic first-worker barrier requires entry 9 to start before entry 1 can finish; event accounting verifies the eight-worker ceiling and all 16 completions. Missing polling-module fallback and cancellation statuses 129/130/143 in entry 9 are tested. Existing foreign-process, identity, supervisor, descendant-cleanup, and launcher suites remain required.
- Measurements: three interleaved 16-entry fixtures with full stdout/status/state parity. Skewed work (entries 1 and 9 take 300 ms; others 20 ms) improved median 998.50 → 738.14 ms. Uniform 20 ms work measured 382.58 → 404.02 ms, a small regression from polling/bookkeeping in this short-job fixture. This is a throughput tradeoff for uneven native evaluations, not a universal speedup. [Raw C06 samples](./C06-results.json).
- Validation observations: the first full run encountered an unchanged supervisor `/proc` readability/read race during an npm stderr assertion. The second reached a wrapper cancellation assertion with one descendant still running at observation time. Four subsequent isolated package-audit runs passed all signal/cleanup checks, without weakening assertions or changing supervisor code. These intermittent failures are retained here rather than erased by retries.
- Documentation: README, GUIDE, and tips-loader describe bounded evaluation concurrency and ordered results. Companion website extraction/snapshot validation remains pending. No remote push.

Stage 7 additional validation observation: the third full run stopped in the unchanged npm unsupported-subcommand classification fixture (`npx cache listing failed` instead of the expected unsupported classification). This path does not call the modified Nix scheduler. The separate package-audit retries above passed; the complete runner remains the commit gate.

Stage 7 final validation: the fourth full runner passed (1,987 `ok:` lines), including query ownership, launcher, completion, and real-fzf PTY checks. Focused decode/scheduler and package-audit suites passed. `git diff --check` passed; all pre-existing performance documents are unchanged or extended by append-only text. The intermittent observations above remain follow-up risks, not claimed fixes.

## Stage 8 — C07b closed-form RGB quantization

- Previous stage commit: `2bb1bf7` (C06). Parent: `2bb1bf7`; commit subject: `perf(C07b): replace RGB palette searches with exact arithmetic`.
- Change: choose the nearest cube channel and gray ramp index arithmetically, retaining lower-index midpoint ties and the final strict gray-versus-cube distance comparison. No memoization, cache growth, validation change, or scratch-output change.
- Coverage: 3,087 production-Zsh comparisons against the frozen original search, covering a Cartesian cube-boundary grid, all gray values and neighboring diagonals, all built-in role colors in both hex cases, and invalid inputs. Compare return status, REPLY, and reply; existing full-theme output digest and pure-startup checks remain active.
- Validation repair: the first full run reached real-fzf PTY tests, where the existing branch fixture accepted before asynchronous filtering finished (query shown but 2/2 rows still present). The test now waits for the actual 1/2 result count before toggling/accepting. It retains the same branch/worktree assertions, timeout, real terminal, and native binary; no fixed delay or weakened expectation. The isolated complete PTY suite passed after this repair.
- Measurement: five interleaved fresh shells with NO_COLOR unset, nord active, and explicit 256 depth; first color build and 50 repeated builds measured separately. First-build median 21.88 → 11.72 ms; warm median 20.91 → 10.09 ms. [Raw C07b samples](./C07b-results.json). No startup-total claim.
- Documentation/website: internal conversion only; palette policy, helper interfaces and locations, guide anchors, literal registrations, and documented behavior remain unchanged. Companion snapshot verification remains pending.

Stage 8 final validation: full `zsh scripts/run-tests.zsh` passed, including the corrected real-fzf PTY synchronization, RGB reference comparisons, theme output digest, and ownership/launcher suites. `git diff --check` passed. Prior performance content remains intact; only this ledger was extended and a new result artifact added.

## Stage 9 — process-read race correction before C08

- Previous stage commit: `89e5577` (C07b). Parent: `89e5577`; commit subject: `fix: handle disappearing process records during query cleanup`.
- Evidence: C08 full-command byte comparison repeatedly found extra `_npkg_outdated: error when reading /proc/.../stat: no such process` diagnostics from immediate evaluation workers. The eligibility/read gap also explains the specific supervisor read diagnostic recorded in stage 7; it does not prove that every intermittent signal or npm-classification observation had this cause.
- Change: check each fallible read of another process's stat record, suppress only that internal read diagnostic, and take the existing absent-process path on failure. This covers worker bookkeeping/liveness, group-stop identity checks, launcher identity capture, and supervisor child/owner checks. Parent/start/group identity requirements and signal targets are unchanged; no missing identity authorizes a new signal.
- Scope: pause C08 and commit this correction independently. Native stderr and exit statuses remain observable; only vanished-process bookkeeping is handled quietly. No timing claim. The documented ownership boundary remains unchanged.
- Coverage: three 100-entry inventories with immediately exiting workers assert successful totals and empty stderr. Existing query ownership, launcher failure, PID identity, owner-death, descendant, cancellation, and unrelated-process tests remain the gate.
- Website: internal process bookkeeping only; no source relocation, command registration, guide structure, or public interface changes. Companion snapshot checks remain pending.

Stage 9 validation: the complete runner passed on the first run after this correction, including all process ownership/launcher/cancellation checks, immediate-worker stderr assertions, and real-fzf PTY tests. `git diff --check` passed. This corrects the reproducible process-read diagnostic; other intermittent observations remain recorded rather than retrospectively declared fixed.

## Stage 10 — C08 pure Nix text sanitization calls

- Previous stage commit: `b6e985f` (process-read correction). Parent: `b6e985f`; commit subject: `perf(C08): sanitize Nix rows without command substitution`.
- Change: call the existing pure `_ui_safe_text_reply` core directly for names, current/locked versions, and diagnostics. The caller already scopes REPLY locally. Keep the printing wrapper, truncation, glyph/color capture, and other command renderers unchanged. This removes up to three sanitizer command substitutions per normal profile entry.
- Coverage: complete command stdout/stderr/status/summary/caller-REPLY parity against the corrected pre-C08 implementation at 20/100 entries, including tab/NUL/Unicode. Six additional PTY comparisons cover narrow/wide output, ANSI/256/truecolor, NO_COLOR, and C locale. A failing printing-wrapper sentinel proves Nix rows and diagnostics no longer invoke it; caller scratch state remains unchanged. Existing stream fallback and control-character regression cases remain active.
- Measurement: the initial three-pair run was noisy (100-entry samples varied from 3.2 to 6.7 seconds); retain [initial samples](./C08-results.json), including their unfavorable independent medians. A seven-pair follow-up alternated baseline/current order and measured 20-entry medians 752.48 → 634.85 ms and 100-entry medians 2107.19 → 1514.17 ms; [follow-up samples](./C08-followup-results.json). These are local workload observations, not stable latency budgets or startup claims.
- Scope decision: C08 completes only the measured Nix safe-text call sites. Broad status-metadata, KiB, truncation, and glyph/color rewrites are declined for this pass; they add state/rendering contracts beyond the demonstrated workload. No general capture-to-direct conversion is authorized by this result.
- Documentation/website: no public behavior or printing interface changed. Existing escaping documentation remains accurate. Helpers stay in the same source files; companion extraction/snapshot validation remains pending.

Stage 10 final validation: full `zsh scripts/run-tests.zsh` passed after rebasing the sanitizer change onto the process-read correction, including immediate-exit workers, sanitizer-wrapper avoidance, caller scratch state, ownership/launcher checks, and real-fzf PTY tests. Complete pipe/PTY byte parity and `git diff --check` passed.
