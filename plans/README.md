# Consolidated performance improvement plan

Status: **implemented on branch `performance/implementation` (commits `0adfb91`..`0da03a2`, including review follow-ups)**; see [implementation results](./evidence/results.md). Planned and reviewed against `348906d0fa8e87f6d3198a63a0a832a4deeffbe1` on 2026-10-18. Branch: `performance/validated-consolidation`, in the original checkout, without another worktree.

The strongest remaining opportunities are package-result parsing, large scan-record ingestion, cold Nix completion, and text width/truncation. Rich rendering is also expensive, but replacing captures is a medium-risk compatibility change: terminal-sensitive helpers currently produce different results inside command substitutions. Preserve those results.

This is the authoritative active plan for the three October 18 audits. [Validation and dispositions](./validation.md) accounts for every numbered proposal and secondary finding. [Evidence and reproduction](./measurements.md) separates new observations from original measurements and forecasts. [Source manifest](./evidence/sources.json) identifies all 46 input files, including uncommitted documents, by SHA-256. Do not merge the three original audit folders as competing plans.

## Execution order

All statuses below mean future work. Effort includes characterization and regression checks; S means hours, M about one or two days. Confidence concerns the observed cost/pattern, not a candidate speedup.

| Order | Plan | Priority | Effort / risk | Confidence | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | [001: retain comparable workload evidence](./001-measurement.md) | Enabler | S–M / low | High | DONE `0adfb91` |
| 2 | [002: remove pure parser captures](./002-package-parsing.md) | P1 | M / medium | High | DONE `f3e0ed8` |
| 3 | [003: optimize width and ASCII truncation](./003-text-width.md) | P1 | M / medium | High | DONE `e5a9162` |
| 4 | [004: accelerate scan-record ingestion](./004-scan-records.md) | P1 | M / medium | High for reader cost | DONE `fdd640e` |
| 5 | [005: improve offline completion preparation](./005-offline-completion.md) | P1 | M / medium | High for source structure | DONE `0d8bca1` (step 4 declined) |
| 6 | [006: preserve rich rendering while removing captures](./006-rich-rendering.md) | P1, gated | M / medium–high | High for cost | DONE `e37e8fe` (step 3 deferred) |

001 supplies comparable evidence for the others. Plans 002–005 can proceed independently afterward. Plan 006 follows 002 and 003; first characterize all captured-mode differences. Implement one narrow logical change at a time. Bounded disk selection, process supervision, cross-manager concurrency, and session caches are **not approved implementation steps**; their dispositions explain missing evidence and required decisions.

## Compatibility contract

Every future candidate must preserve current feature behavior: command signatures/options, full result sets and ordering, raw/plain/rich output bytes, glyphs and truncation markers, freshness, availability, failure and signal statuses, diagnostics and timing semantics. There is no new row limit, parallel workflow, background hook, dependency, network access, secret cache, or command-guard policy in this plan. No proposed timing target is a demonstrated speedup.

Keep fixed trusted lazy loading, pure-Zsh theme startup, fzf/zoxide cache validation and activation rollback, optional no-secret-access CGM startup, live function-body `command -v` guards, bounded Nix workers, sequential package mutations, and identity-pinned process cleanup. Do not weaken a safeguard to meet a benchmark.

Only planning documents/evidence are added now. README, GUIDE, tips, registration records, module locations and runtime code are unchanged. Future public behavior changes are outside this brief. If an implementation needs one, stop and obtain a separate scope decision; synchronize README/GUIDE/80-tips at their intended ownership levels and validate companion website contracts before publication.

## Verification and retirement

The repository gate is `zsh scripts/run-tests.zsh`, including docs-only edits. See [review and verification record](./review.md) for actual results and limitations. `git diff --check` and document link/coverage checks are separate checks; correctness tests do not prove candidate speedups. No companion website sync, verify, E2E or mobile review is claimed. This branch changes no guide heading, registered interface or extractor source.

After implementation, retain enduring behavior in GUIDE, remove completed plan sections/files and their links, and let Git history preserve audits. Do not add performance implementation notes to user tips.
