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
