# PR #32 Final Verdict — Validated remediation: correctness, startup performance, and test coverage

| Field | Value |
| --- | --- |
| PR | [#32](https://github.com/Thundernirmal/zsh/pull/32) · head `chore/25` @ `f3623ab`, base `master` @ `3c3df4f` |
| Commits reviewed | `526dd6f` complete validated remediation · `b2e3d20` close stable release review gaps · `f3623ab` complete post-remediation follow-ups |
| Independent verification | `zsh scripts/run-tests.zsh` at HEAD — exit 0, **1,049 assertions, 0 failures** |

## Verdict: YES — approved for merge

### Follow-up closure (F1–F3 of post-remediation-follow-ups.md)

| Item | Commit | Evidence |
| --- | --- | --- |
| N-01 Linux-only color stance documented | `f3623ab` | GUIDE alias section states the zero-probe policy scope explicitly |
| N-02 Runner aborts on signals | `b2e3d20` + refined `f3623ab` | `handle_signal` cleans up, resets traps, re-raises (`kill -s NAME $$`) with conventional 130/143/129 fallback; `test_runner_signal_exit` asserts exit 130 and that exactly one suite call happened |
| N-03 npkg diagnostic to stderr | `b2e3d20` | `print -u2 -r --`; test-upkg now asserts stdout stays empty on profile-read failure |

Also verified in these commits:

- AGENTS.md/GUIDE.md documentation ownership updated for the lazy catalogue architecture (`65-help.zsh`/`80-tips.zsh` loaders + `lib/help-catalogue.zsh`, `lib/tips-catalogue.zsh`, `lib/upkg-registry.zsh`) — closes the docs-sync obligation from PR #32's first commit.
- Validated spec header corrected (no longer references an untracked local input path) and honestly annotated: "Implemented (batches 1–6); CR-26 deferred by its interface gate."
- Post-remediation follow-ups spec committed with status flip limited to F1–F3; Low backlog explicitly unscheduled.

### Regression scan

Both commits are surgical (one-line stderr fix, runner trap rework, docs, tests). No startup-path, guard-policy, secret-handling, or public-contract changes. Signal semantics verified by new fixtures (`dusage preserves SIGINT status`, runner SIGINT tests). No regressions found.

### Residual notes (non-blocking, on record)

1. Benchmark before/after sequencing for CR-12 remains self-attested; equivalence fixtures are real.
2. N-08 (live-CLI `--` grammar check for apt/brew/npm/flatpak) belongs in the next manual QA pass.
3. Low backlog N-04…N-10 tracked in `docs/specs/post-remediation-follow-ups.md`.

## CR-26 — required fast-follow

CR-26 (lazy upkg/npkg decomposition) is agreed to be addressed as soon as possible. It must still enter through its R13 gate, which can be satisfied quickly:

1. **Measure** — record `60-functions.zsh` parse cost with two consecutive ≥30-run sets on the same host per the spec's performance policy; publish medians/p95 in the CR-26 design note.
2. **Design the boundary first** — `upkg`/`npkg` stay the only public entry points; internals move behind fixed-path repo-local lazy helpers (pattern proven by `lib/help-catalogue.zsh`); manager detection stays live inside function bodies so PATH-stub tests keep working.
3. **Parity proof** — all existing test-upkg assertions run unchanged and green before and after; no interface surface growth.

Expected payoff per the recorded evidence: ~4–5 ms of the ~15.5 ms measured startup plus retirement of the last monolithic-module risk.
