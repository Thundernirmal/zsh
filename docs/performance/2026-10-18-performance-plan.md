# Performance plan: 2026-10-18

Implemented in [PR #49](https://github.com/Thundernirmal/zsh/pull/49) against baseline `348906d`.

## Goal

Remove avoidable shell overhead in five hot paths without changing behavior.

## Rules

- Output bytes, ordering, exit statuses, glyphs and truncation markers, and caller-visible `REPLY`/`reply` stay identical.
- No new features, row limits, dependencies, prompt hooks, network access or secret access.
- Fixed lazy loading and function-body `command -v` guards stay as they are.
- Each change has a frozen-oracle test that compares the new code with the pre-change implementation.
- A change is kept only if paired, same-host benchmarks against the baseline meet its gate with identical output.

## Changes

| Area | Change | Gate | Result |
| --- | --- | --- | --- |
| Measurement | Optional paired benchmark driver: `scripts/benchmark-workloads.py` | — | — |
| Package search parsing | Reply helpers replace per-field command substitutions | ≥30% faster at 1,000 rows | 7.3x faster |
| Text width and truncation | Printable ASCII is measured and sliced directly; per-character width lookups only for non-ASCII | ≥2x on mixed text; short ASCII ≤10% slower | Mixed text 2.4–107x faster; short ASCII between 4% slower and 2x faster |
| `dusage`/`bigfiles` scan reading | 64 KiB `sysread` chunks replace per-byte `read` | ≥2x at 100k records | 24x faster; peak RSS 17.5 → 17.7 MiB |
| npkg completion | Cache path comes from a lazily loaded reply helper; cache files are read in chunks | ≥2x first use; no warm slowdown | First Tab 2.6 s → 0.14 s; warm Tab faster |
| Rich search table | Cells use an explicit-marker truncation core instead of five captures per row | ≥30% faster on a real terminal | 3x faster; output byte-identical |

## Not done

- Declined: a width-table cache, which was slower when its cap was exceeded.
- Declined: skipping npkg's `reply` copy, which would change caller-visible state.
- Deferred: caching terminal checks for the duration of a render. It would freeze capability mid-render and needs a separate, narrow change.

## Verification

- `zsh scripts/run-tests.zsh` passes.
- `python3 scripts/benchmark-workloads.py --self-test` passes.
- Paired benchmarks: `python3 scripts/benchmark-workloads.py --workload <name> --baseline-ref 348906d`.
- The companion website sync and checks were not run.

The detailed plans and raw benchmark evidence are kept in Git history at commit `9abde1e`.
