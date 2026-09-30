# ZSH-038: The worker-wait fixture can hang the entire regression runner

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2, blocking — a hang, not a failure, so the required verification command never returns on affected hosts; P1 is reserved for safety-contract failures |
| Audit date | 2026-09-30 |
| Audited baseline | 4b87a775dbba959d24f6cb12824958e06aad4978 |
| Affected surface | `scripts/run-tests.zsh`, `scripts/test-package-audit.zsh`, `lib/functions-nix.zsh` `_npkg_wait_workers` |
| Evidence | Reproduced on the audit host; isolated reproduction; host PID probe; patched-fixture rerun |

## Summary

`zsh scripts/run-tests.zsh` stops making progress at `scripts/test-package-audit.zsh` on the audit host and never returns. The new fixture "Reaped workers must leave the cancellation set before a later worker cancels" hardcodes PIDs `9001 9002 9003`; when any of those numbers belong to an unrelated live process, `_npkg_wait_workers`'s inner retry loop never terminates and spins at ~100% CPU. The runner has no per-suite timeout and `ERR_EXIT` only reacts to failures, so a hang blocks the repository's required verification indefinitely instead of reporting a result. The same loop has no termination guard in production code, so the fixture is exposing a real robustness gap rather than only a fixture defect.

## Affected code and documentation

- `scripts/test-package-audit.zsh:616-617` — `local -a job_pids=(9001 9002 9003)` / `local -A job_identities=(9001 first 9002 second 9003 third)`, with `wait() { [[ $1 == 9002 ]] && return 130; return 0; }` and `assert test "$signalled" = 9003` immediately below.
- `lib/functions-nix.zsh:438-461` — `_npkg_wait_workers`, in particular the inner `while true` loop around `wait "$pid"` and `(( interrupted )) && builtin kill -0 "$pid" 2>/dev/null && continue`.
- `scripts/run-tests.zsh:44` — the suite invocation with no per-suite timeout; the runner relies on suites terminating.
- `AGENTS.md` "Verification" — `zsh scripts/run-tests.zsh` is the executable source of truth after edits.
- The commit that added the fixture (`4b87a77`) records "Full runner passed"; that claim is not reproducible on a host where those PIDs are live.

## Trigger and reproduction

Preconditions: any Linux host where `9001`, `9002`, or `9003` names a live process that is not a child of the test shell. On the audit host the ChatGPT desktop helper occupies them:

```console
$ for p in 9000 9001 9002 9003 9004; do [ -d /proc/$p ] && echo "$p: $(tr '\0' ' ' < /proc/$p/cmdline)"; done
9000: /usr/lib/chatgpt/resources/cua_node/bin/node ./server.mjs
9001: /usr/lib/chatgpt/resources/cua_node/bin/node ./server.mjs
9002: /usr/lib/chatgpt/resources/cua_node/bin/node ./server.mjs
9003: /usr/lib/chatgpt/resources/cua_node/bin/node ./server.mjs
```

1. `zsh scripts/run-tests.zsh` — the run prints every `ok:` line up to `ok: rich cancellation has its own aggregate bucket and preserves cleanup layout`, then a forked `zsh ./scripts/test-package-audit.zsh` child sits at ~99% CPU for minutes without producing output or an exit status. Two independent runs reached the same point.
2. Isolated reproduction with the loop's real code and the fixture's `wait` stub: `job_pids=(9001 9002 9003)` never returns (`timeout 5` → `rc=124`), while `job_pids=(910001 910002 910003)` returns immediately with `rc=0`.
3. A copy of the suite with only `9001→9101`, `9002→9102`, `9003→9103` completes: 32 `ok:` lines, exit `0`.

No credentials, no live package-manager mutation, and no network access are required.

## Current behavior and impact

- On an affected host, `zsh scripts/run-tests.zsh` hangs instead of passing or failing; every following suite (`test-completions`, `test-help`, `test-doctor`) and the fixed-install-path smoke test never run.
- The hang consumes a full core indefinitely and must be killed by hand.
- CI currently passes because a fresh runner container does not have those PIDs occupied; the defect therefore only appears on long-lived hosts, including this repository's own audit host.
- A hang also defeats `setopt ERR_EXIT`: the runner aborts on the first failing suite, but never on a suite that stops making progress.

## Root cause

`_npkg_wait_workers` re-waits for a worker only while `interrupted` is nonzero and `builtin kill -0 "$pid"` succeeds:

```zsh
wait "$pid" 2>/dev/null
worker_status=$?
(( interrupted )) && builtin kill -0 "$pid" 2>/dev/null && continue
break
```

`kill -0` is intended to answer "the worker is still running after a wait that a signal interrupted". It cannot distinguish that case from "an unrelated live process happens to own this PID number". The fixture's `wait` stub returns instantly without reaping anything, so the synthetic PID `9003` stays in `job_pids` while `interrupted` is already `130`; as long as something on the host owns PID 9003, `kill -0` succeeds and the loop spins forever. Nothing bounds the retry count.

In production the tracked PIDs come from `$!` and are children of the same shell, so the pathological pair (unreapable yet live PID) was not reproduced; the loop is fragile rather than demonstrably broken there. This report records that evidence limit explicitly.

## Fix goal and expected behavior

- The fixture must not depend on host PID availability: use PIDs that cannot collide with a real process, or stub the liveness probe instead of relying on `/proc`.
- `_npkg_wait_workers` must terminate even when a tracked PID exists but can never be reaped: bound the interrupted-wait retry (escalating to `_zsh_stop_owned_jobs` and then `kill -KILL`) and/or confirm the PID is still a child of the current shell before waiting again.
- Preserve current semantics: cancellation still reaps owned workers, unrelated background jobs survive, worker statuses `129`/`130`/`143` still propagate, and completed workers leave the ownership set before later workers are cancelled.
- `zsh scripts/run-tests.zsh` must complete on a host where PIDs `9001`–`9003` are occupied by unrelated processes.

## Implementation constraints

- Keep the fixed repository-local layout: no new runtime dependency, no user-controlled discovery.
- Keep `_npkg_wait_workers` cheap; it runs once per batch of evaluation workers.
- Keep the weak-`kill`/`wait` interactions inside `emulate -L zsh` semantics and the existing `setopt NO_MONITOR NO_NOTIFY` context.
- Follow the documentation ownership rules only if user-visible behavior changes; this fix should not require README/GUIDE edits because the command surface is unchanged.
- Do not weaken the existing cancellation coverage in `scripts/test-upkg.zsh` or `scripts/test-package-audit.zsh`.

## Acceptance criteria

- [ ] A regression case that tracks a PID occupied by an unrelated live process terminates promptly and asserts the expected bookkeeping instead of spinning.
- [ ] `zsh scripts/run-tests.zsh` completes on the audit host with the fixture's PIDs live (or the fixture no longer uses host-visible PID numbers).
- [ ] The existing worker-cancellation regressions (`completed workers leave the cancellation ownership set immediately`, `wrapper INT/TERM/HUP stop owned query/profile/evaluation descendants only`) still pass unchanged.
- [ ] No new dependency and no change to the documented `npkg`/`upkg` command surface.

## Validation plan

- Run the isolated `_npkg_wait_workers` reproduction with both colliding and free PIDs; the colliding case must now finish.
- Run `zsh scripts/test-package-audit.zsh` and then the full `zsh scripts/run-tests.zsh` on the audit host without patching the fixture.
- Keep `scripts/test-upkg.zsh` cancellation coverage green.
- Optional isolated check: confirm an unrelated background job started by the surrounding shell survives the worker wait.

## References

- [`docs/issues/TEMPLATE.md`](TEMPLATE.md)
- [`AGENTS.md`](../../AGENTS.md) — "Verification" (the runner is the executable source of truth)
- [`scripts/run-tests.zsh`](../../scripts/run-tests.zsh) — suite order and `ERR_EXIT`
- [`lib/functions-nix.zsh`](../../lib/functions-nix.zsh) — `_npkg_wait_workers`
- [`lib/functions-common.zsh`](../../lib/functions-common.zsh) — `_zsh_stop_owned_jobs`, `_zsh_run_owned_query`
- Commit `4b87a77` — "Full runner passed" claim that this reproduction contradicts on the audit host
