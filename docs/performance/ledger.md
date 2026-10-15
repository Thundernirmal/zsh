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
