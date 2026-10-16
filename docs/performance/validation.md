# Consolidated review validation

The fresh probes confirm the main costs in both input reviews, reproduce two wordcode compatibility failures, and narrow several proposed fixes. They do not establish that any complete optimization is production-ready. [The plan](./plan.md) lists the acceptance work still required.

## Reproduction and isolation

Run from the repository root:

```sh
python3 docs/performance/validate.py > /tmp/zsh-performance-results.json
zsh scripts/run-tests.zsh
git diff --check
```

The non-gating [validation harness](./validate.py) defaults to the exact reviewed baseline `a6605d20eecd32ff9609a01c750f9516185feda1`. It also accepts a Git revision argument, but its structural assertions intentionally characterize this baseline; later implementations may require updating those assertions. It does not measure uncommitted changes. Do not run Python with `-O`, which disables its assertions.

The harness extracts two scratch trees with `git archive`, creates isolated HOME/cache/data directories and fixed-path `.config/zsh` symlinks, and removes them on completion. Only the scratch compiled tree receives `.zwc` files. Width and sanitizer candidates exist in child-shell memory only. Nix profile data/evaluations are fixtures; the owned-query call boundary is stubbed. No real Nix invocation, package mutation, or credential access is needed. The jq counter wraps the actual binary in a private PATH directory.

Requirements are GNU/Linux, Python 3, git, tar, Zsh, GNU sed, jq, fzf, and zoxide, plus standard userland tools. This is maintainer audit tooling, not a new shared runtime dependency. It writes a 256 MB preview fixture and scratch checkouts under the system temporary directory. Run without competing benchmarks or suites; wall-clock results are observations, never correctness thresholds.

The checked-in [results.json](./results.json) records the successful run started at **2026-10-15 12:03:14 UTC**, including every timing sample, tool versions, the baseline commit, and startup-source hashes. Environment:

- Intel Core i5-8300H at nominal 2.30 GHz; Linux `7.2.10-200.fc44.x86_64`.
- Zsh 5.9, fzf 0.74.4 (Fedora), zoxide 0.9.8, jq 1.8.1, GNU sed 4.9.
- Explicit `/usr/bin:/bin` PATH; `LC_ALL=C.UTF-8`, `TERM=xterm-256color`, `COLORTERM=truecolor`, terminal theme, 120 columns and 40 lines. The jq-count probe prepends only its scratch wrapper.
- One-minute load average 1.25 at start and 1.60 at finish. CPU frequency, scheduling, and filesystem cache state were not pinned. No repository test suite ran concurrently with the successful benchmark.

## Fresh timing evidence

All durations below are rounded from the raw artifact. The measurements have different boundaries and must not be added together.

| Probe | Baseline | Candidate / warm result | Samples and boundary |
| --- | ---: | ---: | --- |
| Startup, text vs compiled modules | 27.45 ms | 17.15 ms | 20 warm samples each; medians, interleaved |
| Startup p95 | 41.91 ms | 23.05 ms | Same samples; nearest-rank p95 |
| 100 rich panel rows | 692.38 ms | 142.30 ms | Median of 3 batches each; width-only prototype |
| Plain preview, 256 MB | 257.93 ms | 1.63 ms | Median of 5 runs each; GNU `sed` full scan vs `Q` |
| 1,000 fbr formatter rows | 1,570.93 ms | 656.04 ms | One batch each; ASCII sanitizer prototype |
| 10,000 completion names | 326.46 ms cold | 122.97 / 123.43 ms warm | Actual helper, one cold and two warm calls |
| 30,000 completion names | 1,664.31 ms cold | 680.56 / 702.07 ms warm | Actual helper, one cold and two warm calls |
| 60,000 completion names | 5,547.32 ms cold | 2,470.11 / 2,449.60 ms warm | Actual helper, one cold and two warm calls |
| Nix decode, 0 active entries | 13.76 ms | 2 jq processes | One fixture call |
| Nix decode, 20 active entries | 735.30 ms | 142 jq processes | One fixture call |
| Nix decode, 100 active entries | 3,745.34 ms | 702 jq processes | One fixture call |
| Nix scheduler, 16 entries | 1,204.06 ms evaluation span | 570.82 ms from fast entry 2's end to entry 9's start | One controlled-duration fixture |
| Command registry, fresh load | 6.89 ms | 53 records | Median of 10 fresh-shell loads |

Startup times measure `source init.zsh` inside `zsh -dfi script.zsh`, with stdout attached to a PTY and stdin `/dev/null`. Three interleaved warmups precede 20 recorded rounds. This activates the interactive integration path without `ZSH_EXECUTION_STRING`; `-i -c` would skip relevant work. It is not a full controlling-terminal prompt/keystroke benchmark. Process launch, user rc files, compinit, and prompt frameworks are excluded. Caches are warm; compilation cost is outside the timer. Only 13 startup modules and `upkg-registry`, `theme-palettes`, and `theme-registry` are compiled, not the generated integration caches. The prototype omits proposed production freshness/publication guards.

Rich rendering uses stdout on a PTY, verifies rich eligibility, and compares transcripts after normalizing the PTY's CRLF translation. All **4,200 bytes** match for this fixture. It does not prove every theme or fallback. Plain preview timing includes sed process launch; output comparison covers seven separate byte fixtures. The formatter timing excludes Git enumeration, fzf, and preview execution; it is deliberately reported as a single batch, not a median.

Completion uses one newline-terminated file per size, a stub `compdef`, and the real cache helper. It measures file handling/array assembly, not the completion framework or terminal list. The parse counter remains **1** on all three calls, confirming repeated warm assembly rather than rereading.

Nix decode includes jq wrapper overhead, sanitization, temporary storage, and plain rendering; profiles lack evaluable sources, so all active rows remain unknown. The worker fixture instead has 16 valid entries, empty locked URIs, and stubbed current evaluation durations of 0.6 seconds for entries 1/9 and 0.03 seconds for the others. Evaluation span excludes earlier decoding and later rendering. It verifies scheduling order, not production supervision or cancellation.

## Deterministic characterization

The successful harness run asserts:

- GNU `Q` matches the original preview bytes for seven boundary fixtures; lowercase `q` differs on the unterminated line-200 fixture.
- The ASCII candidate matches 166 sanitizer fixtures, including C0/C1 controls, Unicode, combining marks, an invalid byte, and escapes.
- Completion returns the expected candidate count with parse count 1, and drops the unterminated final record in `a\nb\nlast`.
- Nix initial jq counts are exactly `2 + 7N`; total/unknown state matches the supplied fixture. Entry 9 starts after entry 1 ends in the actual scheduler.
- Fresh registry load has 53 records. A fully loaded theme helper resolves 40 targets from 13 roles.
- Cube closed-form choices match all 256 channel values; gray choices match all 766 channel sums. The minimizing gray expression is `constant - 2*g*(r+g+b) + 3*g*g`, so channel sum suffices. This verifies the selection mathematics, not the full Zsh memoization implementation.
- Raw NUL framing collides for the two different two-field arrays `["a\u0000b", "c"]` and `["a", "b\u0000c"]`. Even a fixed field count alone cannot recover those inputs.
- `_ui_safe_truncate 5 abcdefgh` yields `a...h` in capture versus `ab…gh` directly on a rich TTY.
- A changed text source with equal-second source/wordcode mtimes executes old wordcode. Default compilation creates mode `0444` in this environment.
- `alias print=AUDIT_SENTINEL` appears in **35** text-loaded startup function bodies and **0** compiled bodies. The probe inspects bodies; it does not claim normal command behavior under the deliberately hostile alias.

The source review additionally verifies the repeated width/metadata captures, seven per-entry jq calls and further result parsing, batch drain, runtime guards, cache trust checks, fixed loaders, and extractor contracts. The old Opus claim of universally bounded color memoization and the suggested pure truncation conversion are rejected by the current interfaces.

## What remains unverified

Historical results are retained only as context in the input commits. This consolidation does not reproduce the Opus combined 13.3 ms startup, generated-cache-only compilation gains, keymap A/B, all per-module timings, lazy-library speedups, or the Astra optimized completion-copy component. It provides fresh evidence for the underlying accepted costs instead. No production batching, union-cache, worker-pool, role-deduplication, or wordcode implementation is shipped or certified here.

The whole-source wordcode race, corruption, invalidation-failure, and alias-policy gates remain open. The mathematical RGB proof does not certify cache effects or full output/state parity. The small UI/sanitizer candidates still need the full mode/error matrix before landing. Single-batch and small-sample timings should be remeasured for implementation decisions.

No live Nix daemon/network comparison, WSL PATH benchmark, personal shell/prompt benchmark, complete interactive manual QA, or companion website sync/verification was performed. Only the installed fzf 0.74.4 is covered locally; the CI-specific 0.68.0/0.74.3 matrix was not rerun.

## Repository verification

`zsh scripts/run-tests.zsh` completed successfully (exit 0), including syntax checks, all ordered regression suites, the fixed-install-path smoke test, and real-fzf PTY checks. Its log contained **1,962 `ok:` lines** and no failure/skip lines. This is an output count, not an independently enumerated assertion total.

The validation harness completed with exit 0. Python syntax, JSON parsing, all 41 relative file links across the new documents and root README, and the 14 runtime-source hashes were checked. `git diff --check` passed. Source worktree status was rechecked before committing; the five pre-existing Opus prototype files remain uncommitted and untouched by this work.

The harness is separate from the runner because its performance probes and 256 MB fixture are unsuitable as ordinary correctness gates. Passing the baseline suite verifies this documentation/audit change; it does not discharge the future implementation gates in the plan.
