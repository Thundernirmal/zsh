# Implementation results

Branch `performance/implementation`. Host: Intel i5-8300H (4 cores / 8 threads, `powersave` governor), zsh 5.9, Fedora 44, 2026-10-18. All runs are paired and alternate same-host baseline/candidate samples against `348906d0fa8e87f6d3198a63a0a832a4deeffbe1` unless a row says otherwise. Each group has 5 samples with lower-middle medians, and output hashes are identical in every compared group. Raw JSON/TXT files beside this note are the authoritative records. An unplanned reboot during implementation erased `/tmp` scratch evidence, so 002–004 were re-measured.

| Plan | Commit | Gate | Result | Evidence |
| --- | --- | --- | --- | --- |
| 001 | `0adfb91` | Driver usable | `scripts/benchmark-workloads.py`, plus self-test | — |
| 002 | `f3e0ed8` | ≥30% at 1,000 rows | 1,000 rows 1365 → 187 ms (7.3x); 100 rows 6.4x; 3,000 rows 7.8x | `002-parser.*` |
| 003 | `e5a9162` | ≥2x mixed; short ASCII ≤10% slower | Mixed 2.4x–107x. With the final code, short ASCII truncate is 2.0x faster, pad 1.5x faster, safe 0.96x, width 0.97x. CJK flat at 40 and 1.35x–1.65x at 1,000 | `003-text-*`, `006-text-recheck.*` (final code) |
| 004 | `fdd640e` | ≥2x reader at 100k; RSS recorded | 100k records 8129 → 337 ms (24x), peak RSS 17.5 → 17.7 MiB. Real-tree `bigfiles` 3.0x (2k files) and 6.1x (20k files) | `004-records.*`, `004-bigfiles-tree.*` |
| 005 | `0d8bca1` | ≥2x cold; no warm regression | Helper at 60k names: cold 2689 → 97 ms (27.8x), warm 17.8 → 12.3 ms. Real PTY Tab pinned to CPU 3: cold 2644 → 139 ms, warm pooled median 60.6 → 54.7 ms. Native nix never ran | `005-completion.*`, `005-tab-pty.*` |
| 006 | `e37e8fe` | ≥30% real PTY; identical hashes | Real PTY 100/1,000 rows 3.0x vs 348906d and 2.2x/2.3x vs the previous commit. A 363-render PTY+pipe matrix is byte-identical | `006-formatter-*`, `006-characterization.*` |

## Declined, deferred and notable findings

- **003, width cache:** declined. A capped cache was 4.5x faster on hits but 44% slower when thrashing above its cap. Converting width tables to decimal gained only about 17%.
- **005 step 4, skipping the union copy into `reply`:** declined. Warm Tab already improved, and skipping the copy would change the global `reply` contract.
- **005, warm Tab measurement:** in exploratory runs that were not retained, unpinned warm Tab times were bimodal in both trees, and the candidate more often landed in its slower mode, so it looked slower than the baseline. A 3 s gap before each warm Tab did not remove that bias. Pinning both shells to CPU 3 reversed it, and the candidate was faster within each mode (retained in `005-tab-pty.*`). One possible explanation is CPU-state or scheduling bias after the baseline's 2.6 s cold Tab. That is a hypothesis: frequency, migration and placement were not measured. The supported claim is limited to the pinned comparison and the unpinned helper-level `005-completion.*` results.
- **006 step 3, render-local SGR/capability context:** deferred. After conversion, `_ui_is_rich_terminal` is about 31% and SGR work about 15% of a 100-row PTY render. A context would freeze the per-call terminal checks for the duration of a render, and it would need `_zsh_theme_sgr` reply side-effect parity. Pursue it as a separate narrow change if wanted.
- **Pre-existing behavior, preserved:** an INT during scan ingestion leaves the collector with `signal_status=130` and partial records, but plain-mode `dusage`/`bigfiles` still return 0. This is true at HEAD and the candidate alike, and the new signal test documents it.
- **Prototype incident:** the expansion `${content%$'\n'*}` on a 1.6 MB string exhausted the heap (about 9.5 GB). That prototype was never committed, and the shipped readers split chunks and drop the last element instead.

## Provenance of the timings

The timing files were measured during the session on working trees, mostly uncommitted, before each commit existed. The driver then recorded only the HEAD SHA and a dirty flag; the Tab harness recorded no candidate identity. No retained content hash binds a timing file to a commit. The mapping below is reconstructed from the session's edit/run order, not mechanically proven:

| Evidence | Measured on | Runtime sources measured |
| --- | --- | --- |
| `002-parser.*` | f3e0ed8 plus uncommitted 003/004 edits | Parser code equals f3e0ed8; only the formatter in `lib/functions-upkg.zsh` changed later |
| `003-text-*` | f3e0ed8 plus uncommitted 003 edits | The 003 helpers, before 006 changed the `_ui_truncate_reply` wrapper; superseded by `006-text-recheck.*` |
| `004-*` | f3e0ed8 plus uncommitted 003/004 edits, after the `builtin sysread` edit | `lib/functions-files.zsh` equals fdd640e (unchanged through e37e8fe) |
| `005-completion.*`, `005-tab-pty.*` | fdd640e plus uncommitted 005 edits | 005 runtime files equal 0d8bca1 (unchanged through e37e8fe) |
| `006-formatter-*`, `006-text-recheck.*`, `006-characterization.*` | 0d8bca1 plus uncommitted 006 edits | No runtime edits after these runs before committing e37e8fe |

Independent review re-validated output compatibility of e37e8fe (the whole-tree PTY and pipe matrix, completion, and recorded statistics) but did not re-measure speed. From the follow-up on, the driver records `tracked_content_sha256` for every run. It is a digest of each tracked path's working-tree bytes, symlink target and stored owner-execute bit (read with `lstat`, matching Git's 100755/100644 distinction rather than effective access). Files are read directly, so diff drivers, textconv and diff settings cannot change it. Untracked files are excluded. It identifies future measured content only; it cannot retroactively prove the runs above.

## Memory criterion for 004 (retrospective)

Plan 004 asked for an explicit memory bound. None was fixed before measuring; this is a retrospective review criterion.

- **Structural expectation, not a proven peak bound:** the old and new readers both hold the full `records` array. The new reader additionally holds one 64 KiB `sysread` chunk, its split `parts` and `irregular` arrays, and one carried partial record, and it loads `zsh/system`. Transient concatenation and array copies and allocator behaviour add overhead that this inventory does not quantify. The intent is that extra memory scales with the chunk, not with input size.
- **Measured peak RSS (VmHWM), maximum over each group's 5 samples, baseline → candidate:** 1k records 4920 → 5524 KiB (+604), 10k 5880 → 6904 KiB (+1024), 100k 17492 → 17696 KiB (+204).
- **Acceptance decision:** candidate peak RSS no more than baseline + 1.5 MiB at each measured size. All three sizes meet it.
- **Qualification:** a single record longer than 64 KiB grows the carry to that record's size. Real du paths are not expected to approach this.

## Reproducing retained harnesses

- **Workload driver:** `python3 scripts/benchmark-workloads.py --workload <name> --size <n> --baseline-ref 348906d0fa8e87f6d3198a63a0a832a4deeffbe1 --output <file>`. Each evidence JSON records the workload, size, kind and sample count of every group; the retained runs used the default 5 samples.
- **006 matrix:** `python3 -I plans/evidence/006-characterization.py "$PWD" plans/evidence/006-legacy-format.zsh <out-dir> full`. It reads the sibling `006-characterization-render.zsh`; pass a fifth argument to use another render script. `006-legacy-format.zsh` is the frozen 348906d formatter.
- **005 Tab:** `PINCPU=3 WARMN=5 WARMGAP=0.5 python3 -I plans/evidence/005-tab-pty.py "$PWD" <work-dir> 348906d0fa8e87f6d3198a63a0a832a4deeffbe1 8`.

## Verification and corrections

The full `zsh scripts/run-tests.zsh` gate and `git diff --check` passed three times: after 002, on the combined 003–005 working tree, and on the final 006 tree. Narrower suites ran per plan. Website sync, verify, E2E and mobile review were not run. No guide heading, registered interface or extractor source changed.

**Correction from review:** at e37e8fe, `python3 scripts/benchmark-workloads.py --self-test` failed. Its interrupt case sent SIGINT after a fixed 1 s, and 005 made completion-cold finish sooner. My earlier summary wrongly implied the driver self-test passed. The follow-up commits fix this and the other review findings; see the follow-up section below.

## Review follow-up

These commits address an independent review of e37e8fe, which found no runtime regression.

- `5f1ab68` (`test(bench)`):
  - The interrupt self-test now signals inside a running sample, using a fake zsh that blocks only on the sample invocation.
  - Children run the zsh resolved from the invoking PATH.
  - Text workloads are checked against exact expected outputs.
  - Shell paths written into generated scripts are quoted, so TMPDIR may contain spaces or quotes.
  - A content digest that git diff settings cannot change is recorded.
  - Optimized Python is refused for `--self-test`.
  - GUIDE wording is corrected.
- `0da03a2` (`test(files)`): the scan-signal test signals inside the ingestion window via `/proc/<pid>/fdinfo`, retries a missed window at most three times, and skips without fdinfo.
- Declined: a distinct watcher-error marker for a hypothetical pipe-based collector.

Verification on the final tree:

- Full `zsh scripts/run-tests.zsh`: exit 0, 2287 ok lines.
- `--self-test` passes; it exits 2 under `-O` and `PYTHONOPTIMIZE`.
- Driver runs under a TMPDIR containing spaces and quotes and with a nonstandard zsh path pass.
- The exact validators reject known bad outputs.
- The saved 006 harness reproduces hashes `a15ed426…` (PTY) and `9b05b923…` (pipe).
- The reviewer independently confirmed these results.
