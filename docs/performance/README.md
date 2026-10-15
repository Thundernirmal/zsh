# Consolidated performance review and plan

Prioritize interactive latency: rich rendering, bounded previews, ASCII sanitization, and Nix completion. Batch Nix decoding before changing its worker scheduling. Reduce repeated color work independently. Keep compiled wordcode behind correctness and publication gates; its measured startup benefit does not establish safe equivalence.

This is the active implementation handoff for the two reviews below. **No optimization is implemented by this change.** Current behavior remains documented in [GUIDE.md](../../GUIDE.md). [The implementation plan](./plan.md) defines ordering, acceptance tests, and documentation requirements; [validation](./validation.md), [raw results](./results.json), and [the repeatable harness](./validate.py) separate reproduced evidence from proposals.

## Provenance and scope

Reviewed on 2026-10-15 against `a6605d20eecd32ff9609a01c750f9516185feda1`, the common runtime baseline of both source branches and this consolidation branch.

| Input | Committed review used | Local worktree |
| --- | --- | --- |
| `t3/performance-review` | `cea3afead7ae548ae7aae290dd9c023468c849d9` | `/home/nirmal/.t3/worktrees/zsh/t3-1d1fca17` |
| `t3/validate-opus55-performance` | `f1297bcaf188d1c51fdce9780e618a2d7604d7b0` | `/home/nirmal/.t3/worktrees/zsh/t3-fb5064ff` |

The first input contains the Astra review plus its independent validation. The second contains the Opus review, benchmarks, and corrected plan. Its README/review still contain claims corrected only in its plan; this consolidation resolves those inconsistencies instead of copying them.

Both branches' committed changes are documentation-only. The Opus worktree additionally has uncommitted prototypes in `25-theme.zsh`, `30-zoxide.zsh`, `40-fzf.zsh`, `55-ui-helpers.zsh`, and `lib/theme-color.zsh`. Those diffs were inspected as design evidence, not imported or treated as landed code. Neither source worktree is modified by this review. Reproduction extracts the baseline commit into temporary directories, so those prototypes cannot contaminate measurements.

Retrieve the original reports locally without switching branches:

```sh
git show cea3afe:docs/performance/astra/README.md
git show f1297bc:docs/performance/opus55/review.md
git show f1297bc:docs/performance/opus55/plan.md
git show f1297bc:docs/performance/opus55/benchmarks.md
```

Scope includes startup, generated integrations, lazy loading, renderers, previews, completion, Nix inventories, query supervision, and command discovery. It excludes personal `.zshrc`, OMZ/Starship configuration, live package/network performance, real credential operations, and website rendering. No package mutations or secret retrieval were performed.

## Consolidated disposition

IDs below are local to this handoff. All accepted items remain open. “Confirmed” means the current cost exists, not that a production implementation has passed its acceptance tests. Risk and effort include correctness work, not merely editing the hot line.

| ID | Source findings | Decision | Effort / risk |
| --- | --- | --- | --- |
| C01 | Astra 04; Opus F5/P1 | Accept: remove repeated width capture in rich checks; metadata capture separately | Small / low–medium |
| C02 | Astra 01 | Accept: bound the plain file preview at 200 lines | Small / low |
| C03 | Astra 03 | Accept: printable-ASCII sanitizer fast path | Small / low |
| C04 | Astra 02 | Accept: cache the final ordered completion union | Medium / medium |
| C05 | Astra 05 | Accept: batch Nix decoding and result validation | Medium / medium |
| C06 | Astra 06 | Accept after C05: replenish completed worker slots | Medium–large / high |
| C07 | Opus F3/P2; Astra color investigation | Accept: per-build role reuse; separate arithmetic/cache change | Small–medium / medium |
| C08 | Opus F7/P7; Astra 04 follow-up | Conditional: convert proven context-independent row helpers | Medium / medium |
| C09 | Opus F6/P6 | Low priority: optimize registration only after fresh profiling | Small / low–medium |
| C10 | Opus F4/P4; part of F2 | Defer rollout: generated-integration wordcode safety design | Large / high |
| C11 | Opus F1/P5 | Defer rollout: repository wordcode semantics and invalidation | Large / high |
| C12 | Opus F8/P8 | Defer: duplicate export detection needs isolated benefit | Small / medium |
| D01 | Opus F2/P3 | Defer keymap snapshot rewrite: no demonstrated startup win | — |
| D02 | Opus F9–F11; Astra extra laziness | Retain upstream code, eager CGM availability, and command guards | — |

Small is a focused change plus characterization; medium spans several fixtures/interfaces; large needs a design checkpoint and failure/concurrency tests. These are relative sizing estimates, not delivery dates.

## Validated findings and corrections

### C01: Rich checks repeat width capture

[`_ui_is_rich_terminal`](../../55-ui-helpers.zsh) captures `_ui_term_width` on every rich eligibility check. Panel rows repeat that check through mode, color, prefix, and reset helpers. An isolated in-memory numeric-`COLUMNS` fast path preserves the 100-row transcript and materially reduces elapsed time; see the fresh measurements in [validation](./validation.md).

Keep live TTY, locale, `TERM`, `NO_COLOR`, resize, and fallback behavior. Do not globally cache rich/plain mode. The original Opus prototype's conversion of low-frequency width/height callers broke test overrides; its corrected version keeps `_ui_section_break` and `_ui_visible_count` on the public printing helpers. This takes precedence over Astra's suggestion to convert all width captures together.

`REPLY` and `reply` are dynamically scoped scratch variables. New helpers must not accidentally overwrite caller state. The existing `_ui_color` can already modify `REPLY` through theme resolution, so a blanket “every UI helper preserves a sentinel” assertion is not an established baseline contract. Characterize actual before/after effects and localize new internal scratch use.

### C02: Plain previews read beyond the displayed prefix

Both fallback preview strings in [40-fzf.zsh](../../40-fzf.zsh) use `sed -n "1,200p"`, which scans the entire file. The GNU `sed -n '1,200p;200Q'` candidate matches seven byte fixtures, including an unterminated line 200; lowercase `q` does not. This is a GNU/Linux-targeted recommendation. Do not label the `--` form of the alternative `head` command universally POSIX-portable.

Early termination intentionally stops detecting read errors after the preview prefix. Validate ordinary file errors and special-file policy explicitly; the measured speedup is for a regular file and does not characterize every input type.

### C03: Printable ASCII still takes the sanitizer's character loop

[`_ui_safe_text_reply`](../../lib/functions-common.zsh) calculates code points for ordinary ASCII. The same pure-Zsh printable range already used by `_ui_display_width` can skip that work. A fresh 166-fixture comparison passes, and a 1,000-row formatter batch improves. This is component evidence; it excludes Git enumeration and picker latency. Keep Unicode/control handling unchanged. Arithmetic replacement of the remaining code-point conversion is a separate, unvalidated follow-up.

### C04: Completion caches parsing, not the assembled result

[`_zsh_npkg_cached_attributes`](../../66-compdefs.zsh) reconstructs the deduplicated array even when no file needs parsing. Fresh 10k/30k/60k fixtures retain parse count 1 on warm calls but still show substantial warm latency. Cache the union, not only file strings.

The current reader drops an unterminated final record; a bulk split would retain it. This is reproduced and must be an explicit compatibility decision. Device/inode/size/whole-second-mtime identity also cannot detect every same-size, same-inode, same-second edit; retaining that policy is not a promise of content-perfect invalidation. Improving it is separate work.

### C05: Nix launches seven jq processes per profile entry

[`_npkg_outdated`](../../lib/functions-nix.zsh) performs two whole-profile jq calls, then six field extractions and one structural check per active entry. The fresh scratch PATH wrapper counts exactly **2, 142, and 702 jq processes** for 0, 20, and 100 unevaluable entries. Result decoding adds more work for evaluable entries. This confirms local overhead without contacting Nix.

Batching is accepted, but a lossless format is still a design requirement. Raw NUL delimiters preserve empty/tab/newline fields only when embedded NULs are excluded or escaped. JSON strings can encode NUL. Astra's proposed NUL framing therefore needs an explicit encoding policy, length framing, or validated escaping, plus field-count checks. Do not use `eval`, unescaped TSV, or a new undeclared jq-version requirement.

### C06: Worker batches drain before replacement

The actual Nix scheduler starts at most eight workers and calls `_npkg_wait_workers` to drain the whole batch. A fresh 16-entry fixture confirms entry 9 starts only after slow entry 1 ends, despite fast workers completing earlier. The supervisor boundary is stubbed in this timing probe; it does **not** verify ownership or cancellation.

A continuously replenished pool remains a proposal. Do not present the earlier projected improvement as a measured implementation. Ownership, PID reuse protection, result order, signal status, and reaping make this higher risk than the original effort table suggests.

### C07: Repeated color roles and conversion work

Instrumenting the fully loaded theme registry confirms 40 resolutions for 13 roles (compact layout). The roomy layout adds one existing role. Per-build reuse avoids cross-theme invalidation complexity. `_zsh_theme_fzf_color_args` reads depth from `_ZSH_UI_COLOR_DEPTH`; an argument such as `... truecolor` does not select depth. Future timing must set the global and active theme explicitly. Terminal-theme timing alone does not measure hex-to-256 conversion.

The closed-form cube choice matches all 256 channel values. Gray-distance minimization depends only on the channel sum; its closed form matches all 766 sums. These exhaustive component checks establish the arithmetic selection when the final distance comparison and tie rule stay unchanged. They do not prove the prototype's Zsh state, validation, or memoization behavior. Its cache is **not inherently bounded**: arbitrary custom colors can accumulate. It also skips the original `reply` RGB assignment on a cache hit. Preserve or explicitly narrow that helper contract; a cache is optional, not a prerequisite for role reuse.

### C08/C09: Runtime captures and registry load need narrower claims

Both `_ui_safe_truncate` and `_ui_truncate` reach `_ui_ascii_mode`; neither is a pure truncation helper in the current code. A fresh `_ui_safe_truncate 5 abcdefgh` probe produces `a...h` when captured and `ab…gh` when called directly on a rich TTY. A mechanical REPLY conversion changes visible output. Start with safe-text escaping, status metadata, and KiB formatting after checking each call's state contract.

The registry has **53 records**, confirmed by a fresh load. The Opus review's 106 calls and its 7.7 ms attribution cannot serve as the single-load baseline. Fresh timings are recorded separately; no 30–40% improvement has been established. Keep literal registration records and caller-option isolation unless replacement behavior is demonstrated.

### C10/C11: Wordcode benefit is real; feature parity is not established

Compiling only startup modules and three eager libraries in a scratch checkout reduces startup time in the fresh interleaved probe. However, equal-second source/wordcode timestamps execute old code, and a sentinel alias affects text-loaded startup functions but not `zcompile -U` functions. Therefore the original Opus summary's “no change in behavior” and combined 53% claim cannot be treated as a validated feature-preserving outcome.

Generated integration caches and editable repo sources need separate designs. Existing cache guards inspect text, while `source` can select a `.zwc` sibling. A compiler adds a second executable artifact to validate. Mode, owner, symlink, Zsh version, fingerprint, integrity, text/wordcode coherence, and failure fallback all matter. The existing `0022` arithmetic mask is decimal 22 under these functions' option state; do not silently relax it as part of performance work.

Deleting wordcode before publishing text does not alone resolve concurrency: an older compiler may publish old wordcode after a newer text publication. Require a coherent generation/publication protocol and a race regression. For editable sources, timestamp-preserving changes and direct/lazy sourcing need explicit handling; a two-second compile delay or end-of-startup background job cannot protect already-loaded code. Re-measure with the complete safety path included.

### Deferred and rejected ideas

- D01: Keep the keymap snapshot and rollback clones. The earlier in-situ snapshot cost was 0.63 ms and its A/B showed no startup benefit. This consolidation verifies the source but does not repeat that historical A/B; there is no evidence to promote it.
- D02: Do not rewrite upstream generated fzf code, replace command guards, or move optional CGM implementations just to reduce parsing. Preserve startup's no-secret-access boundary, lazy helper trust, and website discovery contracts. CGM and first-command-hash costs remain historical observations, not fresh module benchmarks.
- C12: Repeated export detection is visible in source but the claimed sub-millisecond gain is not independently established. Any future reuse must observe theme settings, layout, glyph settings, `NO_NERD_FONT`, locale, terminal/color variables, and finder extras; the original proposed signature was incomplete.
- Reject removing ownership checks, caching inventories across requests, truncating candidate sets, disabling Unicode, adding prompt hooks, or parallelizing package mutations as performance shortcuts.

## Status and maintenance

This handoff replaces parallel active recommendations on this branch; the originals remain in their commits. Resolve each C item with its own measured implementation or evidence-backed decline. Once resolved, move current behavior to the guide and remove stale plan material and links; Git history retains the review.

The consolidation changes no guide headings, module paths, registration records, dependency guards, or shell runtime interfaces. No website sync, website verification, or remote push is part of this change. Future source refactors must follow the companion-repository checks in [AGENTS.md](../../AGENTS.md); shell tests alone cannot establish website compatibility.

## Implementation ledger

The review and plan above are preserved as the original baseline. Subsequent implementation status, commits, measurements, and pending checks are recorded in the append-only [ledger](./ledger.md). At the user's request, performance documents are retained rather than removed when an item is resolved. All implementation commits remain local unless separately authorized.
