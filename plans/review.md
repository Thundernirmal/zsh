# Review and verification record

Baseline: `348906d0fa8e87f6d3198a63a0a832a4deeffbe1`, 2026-10-18. Planning-only branch `performance/validated-consolidation`, in the original checkout. Runtime, user documentation and extractor inputs are unchanged. Added files are Markdown planning documents and JSON evidence only; they remain uncommitted for review.

## Source review

Three independent read-only reviewers each read a complete input corpus (Sun, Earth, Sea), the Performance/Finding format audit playbook, relevant runtime code and historical dispositions. They returned item-by-item dispositions and short semantic evidence. The consolidating reviewer checked cited hot paths, safeguards and source excerpts directly and incorporated corrections into validation.md and the six plans. Reviewers made no source/Git/document edits and performed no live backend actions.

The ledger accounts for all 34 numbered source proposals (four Sun, sixteen Earth, fourteen Sea), five Sun secondary findings, dispersed inventory sketches and retained historical decisions. Duplicate opportunities map to a single plan or backlog disposition. Coverage is claim review, not dynamic profiling of every function. Forecasts are explicitly excluded from validated results.

Corrections include the keymap-dump premise, distinct narrow truncator behavior, capture-dependent glyphs, discarded nested memo writes, tab/unterminated-record handling, practically unbounded Unicode caches, full-record natural ordering, fbr benchmark context, builtin-versus-fork classification and unsafe process/timing assumptions. No candidate gain is claimed.

## Independent consolidated-document review

A source reviewer then performed a separate cold read of the consolidated plans, ledger, recipes and evidence. The following findings were resolved:

- P2: parser conversions must preserve caller-visible REPLY/reply, not only output arrays. Plans now freeze unset/set/outer-local state, localize pure printing-wrapper scratch and isolate new writes without hiding pre-existing progress/theme side effects.
- P2: safe-truncate ASCII fast paths must reproduce legacy REPLY effects and fallback behavior; they may not simply localize that intentionally changed state.
- P3: the exact 388 inventory count includes 387 named declarations plus the _fbr_format_entry autoload body. The ztheme entry body is assessed with its named replacement.
- Executable drift commands now contain real paths, and the completion recipe retains full setup/private environment plus JSON provenance.

The reviewer re-read the corrections and returned **Pass: no remaining actionable objections**. This is plan review, not approval of a future implementation or performance claim.

## Verification results

- Fresh `zsh scripts/run-tests.zsh`: exit 0, including ordered syntax/regression checks, UI parity, exported preview behavior, real-fzf PTY, package timing PTY and fixed-install startup smoke. Full first-run log was retained locally under /tmp/zsh-consolidation-evidence/tests.log. [Final verification summary](./evidence/verification.json) records the confirmation after document review.
- Markdown checks: ten files, balanced fences, no trailing whitespace, twenty-one relative file links resolve. Tables and code snippets were read during review; no site-rendered/mobile QA is claimed.
- Coverage checks: all E01–E16 and SEA-01–SEA-14 rows exist; all four Sun numbered and five secondary findings have dispositions.
- Provenance/evidence checks: all 46 source-document SHA-256 hashes and byte sizes match; baseline documented script hash matches JSON; five accepted samples per group and every median recompute; completion medians recompute and no native nix invocation occurred.
- `git diff --check` passes. A separate check includes whitespace in the untracked documentation (ordinary git diff alone would omit it). No tracked changes exist outside plans; no runnable files are added.

No live package or network performance, real Secret Service, end-to-end OMZ Tab latency, candidate speedup/RSS gain, or companion website sync/verify/E2E/mobile compatibility is claimed. Guide sections, registrations and runtime discovery structures are unchanged. Future implementation gates remain mandatory even though this planning branch's regression suite passes.
