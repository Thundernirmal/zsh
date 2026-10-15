# Performance implementation plan

All items are open. This plan implements the decisions in [the consolidated review](./README.md); it is not permission to weaken behavior for a timing target. Land isolated changes and measure the actual result before proceeding. Do not add the individual gains or project the prototype's combined startup total onto production code.

## Sequence and release gates

1. **C01 → C02 → C03:** three separate small changes with byte/state characterization. C01 has broad runtime reach; C02 and C03 have narrow implementations.
2. **C07a and C04:** per-build color-role reuse and completion union caching, independently. C04 is the highest priority for users with large Nix indexes. Measure it as a helper and, separately, in interactive completion.
3. **C05 → C06:** reduce local Nix decoding overhead, then change scheduling in a separate commit. Scheduling must not obscure decoding or cancellation regressions.
4. **C07b, C08, C09:** arithmetic/cache and selected row/registry work only where fresh profiles justify it. C08 benefits from the C01/C03 characterization but is not required for them.
5. **C10 and C11:** design spikes first, implementation only when the gates below are satisfied. C11 may reuse C10's publication tests; integration-cache coherence does not solve alias semantics for editable sources.
6. **C12/D01:** reconsider only with new in-situ evidence. D02 retains the existing design.

For each implemented item, require exact outputs, exit statuses, state, and deterministic work-count assertions before wall-clock results. Use 30 or more interleaved warm samples for final startup claims, multiple samples at representative workload sizes for runtime claims, and report cold first use separately. The audit's smaller or single-batch probes are sufficient to locate work, not to set universal budgets. No timing threshold is added to CI by this report.

Every implementation runs `zsh scripts/run-tests.zsh`. Use targeted tests while developing, then the complete runner. Test rich TTY, plain/piped and captured output, `NO_COLOR`, `TERM=dumb`, narrow/resized terminals, UTF-8 and non-UTF-8 locales, and ANSI/256/truecolor where relevant. Preserve runtime `command -v` guards, startup `$commands` guards, and the separate preview-shell checks.

## C01: Rich checks and metadata

**Files:** [55-ui-helpers.zsh](../../55-ui-helpers.zsh). **Gate:** small width-only change first; metadata conversion separately if justified.

Read a valid numeric `COLUMNS` directly in `_ui_is_rich_terminal`; retain the existing width fallback for absent/invalid values. A reply-returning core is an alternative if its interface and dynamic scratch scope are characterized. Keep printing helpers available. Do not cache eligibility across calls or add startup/prompt work.

Acceptance:

- Compare exact panel, section, and status-icon transcripts across themes/depths and output modes. Check widths 59/60 and changes between calls, missing/invalid dimensions, failed `tput`, and fallback defaults.
- Prove valid-width rich checks do not invoke the printing width helper; retain one-per-render public width/height calls and existing test overrides.
- Compare `REPLY`/`reply` effects with baseline. Localize new scratch use; do not mistake existing color side effects for a new regression.
- For status metadata, preserve every key/default, tab framing, glyph tier, and printing wrapper. Run `test-theme`, `test-command-ux`, `test-functions`, and `test-upkg`, plus the full runner.

## C02: Bounded fallback previews

**Files:** [40-fzf.zsh](../../40-fzf.zsh), [test-init.zsh](../../scripts/test-init.zsh), relevant PTY fixtures.

Use the characterized GNU `Q` candidate in both plain-preview strings. Preserve placeholder quoting, filenames with spaces/leading dashes, directory previews, `bat` preference, and runtime guards.

Acceptance:

- Exact stdout/stderr/status for empty, short, 199/200/201 lines, unterminated line 200, and NUL/control bytes. Characterize missing/unreadable files separately; the normal fixture does not exercise permissions.
- Prove bounded consumption with a controlled input producer or read-count fixture, not only timing. State the deliberate late-read-error boundary.
- Exercise both color branches without `bat`, directory selection, and real-fzf preview rendering. Run `test-init`, the real-fzf PTY suite, and the full runner.

## C03: ASCII sanitization

**Files:** [lib/functions-common.zsh](../../lib/functions-common.zsh), formatter and command-UX tests.

Reuse the `*[^ -~]*` pattern already present in `_ui_display_width`; assign printable ASCII directly to `REPLY`, otherwise use the existing implementation. Keep `MULTIBYTE` semantics. Do not combine this with code-point arithmetic or truncation changes.

Acceptance: empty/short/long ASCII, all C0/C1 controls and DEL, tabs/newlines/escapes, combining sequences, CJK/emoji, invalid bytes, and supported locales. Compare full fbr rows and canonical identities, including worktree paths and hostile subjects. Assert slow-path avoidance for ordinary ASCII. Measure short strings and 100/1,000/3,000-row batches; retain real-fzf branch/worktree checks.

## C04: Completion union cache

**Files:** [66-compdefs.zsh](../../66-compdefs.zsh), [test-completions.zsh](../../scripts/test-completions.zsh).

Build a signature of the ordered eligible paths and their identities, then retain the final ordered, deduplicated array. Reuse it only when membership, eligibility, and identity are unchanged. Remove obsolete path/data entries. Bulk assembly is allowed after characterizing empty records and first-occurrence ordering; preserve the unterminated-final-record behavior for this optimization, or fix it in a distinct documented change.

Acceptance:

- Multiple overlapping files, unchanged warm access, additions/removals, same-path replacement, empty files, unreadable files, symlinks, stat failure, and unterminated records.
- Exact ordered arrays and return behavior. Separate no-reparse and no-union-rebuild counters; warm calls may still discover/stat files and copy the final array.
- No Nix execution, refresh, network query, or write to the index. Measure 10k/30k/60k candidate sets and interactive listing separately. Document the retained filesystem-identity granularity; do not claim detection beyond it.

## C05: Batch Nix decoding

**Files:** [lib/functions-nix.zsh](../../lib/functions-nix.zsh), Nix cases in [test-upkg.zsh](../../scripts/test-upkg.zsh) and [test-package-audit.zsh](../../scripts/test-package-audit.zsh).

Fold extraction/validity into the whole-profile jq transformation; choose lossless framing with explicit handling for empty strings, separators, embedded NUL, and trailing newlines. Batch result validation/version/path normalization without weakening malformed-input handling. Keep jq compatibility at the existing undeclared minimum unless dependency policy is deliberately changed.

Acceptance:

- Prove initial decode jq count is constant with entry count, replacing the current `2 + 7N`. Account separately for explicit-output evaluation and post-evaluation processing.
- Compare output, status, totals, changed/unknown counts, and `_NPKG_OUTDATED_*` state for object/array profiles; active/inactive, empty, malformed, partial records; fallback names; versions; path order/duplicates; locked/current results; wildcard/explicit/invalid output sets.
- Include control characters, embedded delimiters/NUL, trailing newlines, and invalid framing. Reject parse failures visibly; never reinterpret them as an empty successful inventory.
- Keep fresh queries, the upkg bridge state contract, supervisor boundaries, and cancellation behavior unchanged. Measure 0/20/100/large fixtures; do not use live package mutations to benchmark.

## C06: Incremental worker replenishment

**Files:** Nix scheduler plus supervisor interfaces if needed. **Prerequisite:** C05 landed and measured; preserve a separately reviewable scheduler diff.

Keep at most eight owned workers, detect completed workers, reap statuses, refill available slots, and render in profile order after the final drain. Evaluate completion tokens with liveness fallback or bounded `zsh/zselect` polling. Zsh 5.9's `wait` does not provide Bash's `-n`; do not assume it does. Do not use broad process kills, PID existence alone, or a new global `TRAPCHLD` strategy without ownership analysis.

Acceptance:

- A controlled fast worker frees a slot and entry 9 starts before slow entry 1 completes. Active count never exceeds eight; every child is reaped and output order is stable.
- Success, failure, immediate exit, failed identity handshake, PID reuse protection, cancellation during launch/refill/drain, INT/TERM/HUP statuses 130/143/129, owner death, descendant cleanup, unrelated jobs, and private storage cleanup.
- Run `test-package-audit`, `test-query-ownership`, `test-query-launcher`, Nix/upkg cases, and the full runner. The review's stubbed scheduler probe alone cannot satisfy these gates. Measure skewed and uniform durations; reject changes that trade away cancellation correctness.

## C07: Color resolution in two stages

**Files:** [25-theme.zsh](../../25-theme.zsh), [lib/theme-color.zsh](../../lib/theme-color.zsh), [test-theme.zsh](../../scripts/test-theme.zsh).

**C07a:** local role-to-value map per fzf build. Assert 40 targets still produce the same ordered string while resolving only 13 distinct roles, including roomy/no-color behavior. Compare all built-ins and custom overrides across color depths, failure/rollback paths, and finder refreshes. Keep startup pure Zsh.

**C07b:** closed-form RGB conversion as a separate change. Retain strict tie behavior and the final gray-versus-cube distance comparison. The audit's exhaustive component proof must be accompanied by production-Zsh comparison across all built-in colors, threshold boundary grids, gray diagonals/neighborhoods, invalid inputs, and uppercase/lowercase forms. Characterize both `REPLY` and `reply`.

Memoization is optional. If used, bound it or justify lifetime growth with arbitrary custom palettes; preserve validation and scratch outputs on hits and misses. Do not claim that “a few hundred palette colors” bounds user-defined inputs. Benchmark with `_ZSH_UI_COLOR_DEPTH` and a hex-valued active theme explicitly set; record first and repeated builds independently.

## C08/C09: Secondary runtime work

**C08:** inventory captured helpers by actual implementation and call context. Start with `_ui_safe_text_reply` reuse, status metadata, or KiB formatting. `_ui_safe_truncate`, `_ui_truncate`, glyphs, and colors are excluded from mechanical conversion because capture changes their terminal view. An explicit pure core with a passed rendering policy is possible, but must reproduce the old captured policy exactly. Preserve printing interfaces and caller scratch variables; compare full commands in PTY, pipe, and capture modes. Choose call sites by measured frequency.

**C09:** establish fresh single-load time and 53 registration calls before changing `_zsh_help_register`. Optimize field validation/local copies only with rejection/status and option-state parity. Preserve empty-field and duplicate rules, field defaults, control-character rejection, order, all arrays, and canonical/mutation metadata. Do not remove `emulate -L zsh` without tests under hostile caller options. Keep every registration on one line with eight literal fields and recognized checks. No percentage gain is promised.

## C10: Generated-integration wordcode design gate

**Status:** defer production implementation. A design may use immutable generation-specific text/wordcode pairs, or serialization plus generation verification; it must prove the following properties before choosing an implementation.

- Every automatically selected wordcode artifact is validated, not only the text. Reject symlinks, wrong owners, unsafe modes, corruption, incompatible Zsh version, and mismatched generation. Preserve executable fingerprints and `zsh -fn` validation. Mode 600 is consistent with the current cache policy.
- Text and wordcode form a coherent published generation. Test two shells racing to generate/compile, an older compiler finishing last, interrupted publication, same-second changes, pruning during use, and compile failure. Delete-before-publish alone is insufficient.
- Warm startup performs no compiler/permission subprocesses. Missing or rejected wordcode has a verified text fallback; a failed removal must not allow `source` to silently select the suspect sibling.
- Existing activation failure restores functions, options, widgets, and keymaps. Owner-only private temporary files, signal cleanup, cache reset, and pruning cover both artifacts.

Extend both persistent-cache suites in `test-init`, including default compiler permissions, hostile siblings, cold/warm invocation counts, and failed writable storage. Measure cold generation, one-time compilation, warm startup, and fallback with safety checks active. Do not alter the permission mask's policy as an incidental optimization.

## C11: Repository wordcode design gate

**Status:** defer production implementation. Decide whether the project will preserve parse-time user aliases or explicitly disable them for trusted sources in a separate behavior change. `zcompile -U` cannot silently replace current text semantics. Verify ordinary/global aliases, parsing options, function bodies, `${(%):-%N}`, `$0`, autoload helpers, direct module sourcing, and library loading after startup.

Freshness must cover equal-second and timestamp-preserving edits, edits during compilation, lazy-file changes after startup, invalidation failure, removed sources, corrupt/incompatible wordcode, and concurrent refreshes. A compile delay is not invalidation. Decide whether to use content/generation identity, enforce a narrower documented update model, or decline the feature; do not conceal the limitation behind mtime comparisons.

Only after those decisions, design a fixed-file-list compiler, atomic publication, cleanup, and an opt-out whose meaning covers existing artifacts as well as new compilation. Prefer an explicit maintenance operation initially; automatic background jobs need their own bounded single-flight/cleanup justification and user-facing documentation. Keep source discovery fixed, theme startup pure Zsh, and CGM optional with no Secret Service access.

Run the full suite on text and compiled layouts, including fixed-path smoke tests and runtime edits. Benchmark complete safety overhead and lazy first use. Gitignore generated files and never commit them. Refuse the optimization if the residual benefit does not justify the maintenance cost.

## Documentation, website, and completion criteria

For every user-facing alias/function/completion/workflow change, update `README.md`, `GUIDE.md`, and `80-tips.zsh` at their owned level as required by [AGENTS.md](../../AGENTS.md), plus affected help/completion/tips catalogue entries. Do not copy implementation details into tips. Internal-only changes need accurate references and no fabricated behavior claims. The source Opus plan's blanket “no README/tips change” statements do not override this contract.

Keep guide section headings/anchors stable. Changes to source locations, helper structures, registration forms, guards, or exported preview formats require checking the companion extractor. After committing a clean shell revision, follow the companion repository's README/AGENTS instructions, sync, inspect generated output, run `npm run verify` and `npm run test:e2e`, and review affected mobile topics/anchors/availability. Do not claim compatibility based only on shell tests, or push merely to satisfy a snapshot step without authorization. For this local-only consolidation, website sync remains unperformed.

Each C item is complete only when implemented or declined with evidence, its relevant correctness gates pass, actual performance is measured, required documentation is reconciled, and affected website contracts are verified or explicitly pending. Remove completed/stale recommendations instead of maintaining a second current-behavior reference.
