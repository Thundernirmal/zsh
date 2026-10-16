# Performance pass disposition

This closes the implementation pass against the preserved [consolidated plan](./plan.md). The [ledger](./ledger.md) records each local commit, measurements, failures, and corrections. Original review text is historical evidence; the status below is the current disposition. No performance documents were removed.

## Implemented scope

| Item | Local commit(s) | Result |
| --- | --- | --- |
| C01 | `cf29e5d` | Live numeric width in rich checks; fallback retained |
| C02 | `e14f1a0` | Plain previews stop after line 200, preserving bytes |
| C03 | `47ddbf7` | Printable ASCII sanitizer fast path |
| C04 | `7dba0ea` | Ordered completion union reused with eligibility/identity checks |
| C05 | `3f618ff`, `264b350` | Batched initial fields and normal evaluation-record decoding |
| C06 | `2bb1bf7` | Refill completed evaluation slots; maximum eight workers |
| C07a | `073ffe9` | Resolve each finder color role once per build |
| C07b | `89e5577` | Exact closed-form RGB quantization; no persistent memoization |
| C08 | `8835142` | Direct pure sanitizer calls in Nix rows and diagnostics |
| Validation correction | `b6e985f` | Quietly handle disappearing process records without weakening ownership checks |

Every implementation commit followed a passing complete shell runner. C07b also repairs a real-fzf test synchronization race by waiting for filtering to finish before accepting. Measurements remain per-workload observations, cannot be added together, and do not establish a combined startup percentage.

## C09: retain registry validation

Thirty fresh shells each loaded exactly 53 records. Median first-source time was **6.10 ms** (range 5.48–10.49 ms); see [raw samples](./C09-results.json). This is an on-demand first load, not work repeated for each row or prompt. The full load, including parsing and array construction, places an upper bound on any savings from field validation alone.

Decline the optional registration rewrite for this pass. Retain local option isolation, required/duplicate/control-character checks, field defaults, ordering, and literal registration records. A future change should first attribute time inside registration and demonstrate material first-command benefit with rejection/status/array/hostile-option parity. No candidate speedup is claimed here.

## C10: generated-integration wordcode remains gated

The existing integration cache publishes validated text. Adding a compiled sibling creates another executable artifact and a publication race; the existing text checks do not prove compiled-artifact integrity or generation coherence.

The preferred design direction is an immutable generation directory containing validated text, matching wordcode, and generation metadata, published only after both artifacts are complete. A reader must validate the chosen generation and pin it for the entire activation. An older compiler must never overwrite a newer published generation. Pruning must not invalidate an active reader. Compilation failure must leave a usable verified text generation.

This is a design direction, not an approved implementation. The following decisions and tests remain necessary:

- Define generation identity over executable fingerprint, generated text, cache schema, and Zsh compatibility; prove text/wordcode coherence rather than relying on mtime.
- Validate owner, mode, non-symlink status, compatibility, and integrity for every executable artifact. Preserve the current permission policy, syntax validation, and activation rollback.
- Choose a text fallback that cannot implicitly select rejected sibling wordcode. Merely removing the sibling is insufficient when removal fails or a concurrent compiler republishes it.
- Prove concurrent generation, older-compiler-last, interrupted publication, compilation failure, same-second updates, unsafe/corrupt siblings, failed storage, and pruning during use.
- Measure cold generation/compilation, warm startup, and fallback with all checks active. Warm startup must not add compiler or permission subprocesses.

Do not enable automatic compilation until this protocol and its regression suite exist. This pass leaves the production cache implementation uncompiled.

## C11: editable repository wordcode remains gated

The preserved consolidation demonstrated two semantic blockers: equal-second text/wordcode freshness can execute stale code, and `zcompile -U` changes parse-time alias behavior. Neither C07's arithmetic gain nor C10's generation concept solves those contracts for editable repository sources.

Decline automatic repository compilation for this pass. A future explicit maintenance operation is a narrower starting point, but still requires a documented decision on alias semantics and a content/generation identity for every fixed source, including lazy libraries edited after startup. An opt-out must also prevent loading existing wordcode. Direct sourcing, `$0`, source filenames, global aliases, parser options, incompatible/corrupt wordcode, concurrent edits, and failed invalidation need text/compiled parity tests. A background compile or timestamp delay is not a freshness solution.

No compiler, background job, generated artifact, new source-discovery mechanism, or alias-policy change is added by this pass.

## Other retained decisions

- **C08 broader helpers:** decline metadata/KiB and terminal-sensitive helper rewrites in this pass. Only measured, pure Nix sanitizer call sites changed. The remaining captures are not mechanically interchangeable with direct calls.
- **C12:** defer repeated export-detection caching. Its gain remains unestablished, and the earlier proposed invalidation signature omits relevant terminal/theme/locale settings.
- **D01:** retain keymap snapshot and rollback behavior. The preserved historical A/B showed no startup benefit from removing it; this pass does not recast that as a fresh measurement.
- **D02:** retain upstream integration code, runtime/startup guard distinctions, fixed trusted helper loading, and optional CGM's no-secret-access startup boundary.

## Validation limits and follow-up

The final shell runner covers syntax, regression suites, real-fzf PTYs, process ownership/launcher behavior, and fixed-install-path startup. It does not validate the companion website. Website extraction, snapshot sync, `npm run verify`, `npm run test:e2e`, and affected mobile topics/anchors/availability remain pending. No guide headings, registration record format, or module locations changed, but preview strings and private helper structure still deserve extractor review.

C04's helper improvement is measured; host-specific Oh My Zsh/completion-framework end-to-end Tab latency remains unmeasured. No live package mutation or network inventory benchmark was performed. Uniform short C06 jobs showed a small polling/bookkeeping cost; skewed workloads improved. Initial C08 timing variance is preserved alongside the larger follow-up sample.

Earlier full runs exposed intermittent npm classification, process-read, descendant-observation, and fzf synchronization failures. The reproducible process-read and fzf synchronization causes were corrected separately and the complete runner passed afterward. The ledger does not claim every earlier intermittent failure had either cause. Further recurrence should retain its full fixture and process identities for diagnosis.

All commits are local. No remote push or website publication was performed.
