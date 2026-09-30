# ZSH-039: An abandoned captured query outlives its owner or hangs it

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2, blocking — two reproduced, unbounded failure modes (a permanent process leak and a call that never returns) in the new supervision machinery |
| Audit date | 2026-09-30 |
| Audited baseline | 1b85d3b04421c1f245d9b8e62fc21da609a16cbc |
| Affected surface | `upkg` search/outdated/plan, `npkg` profile reads and evaluations, and the `clean` probes that use `_upkg_capture_query` |
| Evidence | Reproduced on the audit host (owner SIGKILL; delayed-identity supervisor); corroborated by independent line-by-line, wrapper, and supervisor angles |

## Summary

Captured queries run under a supervised private session: `_zsh_run_owned_query` starts `lib/query-supervisor.zsh` under `setsid`, and the supervisor stays alive until the owner kills its process group. Two failure paths break that ownership contract.

1. **Abandonment.** If the owner shell dies without running its `always` block (SIGKILL, OOM kill, terminal-emulator crash), nothing ever kills the group: the supervisor and the wrapped command keep running, reparented to init, and the supervisor's `while true; do zselect -t 10; done` never exits even after the wrapped command finishes. Verified: after `kill -9` of the owner, the supervisor (`PPID 1`, session leader) and its `sleep 120` child were still alive; two earlier orphans remained for 5m21s and 2m18s after their wrapped commands (`sleep 20`, `sleep 2`) had already completed.
2. **Abort-path hang.** If the identity handshake misses its ~3 s poll budget while the supervisor is alive, the owner TERMs only the launcher and then waits for it without a bound. The launcher *is* the supervisor (the `setsid --wait` job execs in place), and the supervisor traps and swallows TERM, so the wait never returns. Verified: `kill -TERM` on a live supervisor leaves it running, and with a faithful stand-in (TERM ignored, identity withheld) `_upkg_capture_query sh -c true` was still blocked after 10 s in `sigsuspend` and had to be SIGKILLed at 20 s.

## Affected code and documentation

- `lib/query-supervisor.zsh:27-28` — `# Remain an anchor until the owner finishes group shutdown, even after TERM.` / `while true; do zselect -t 10; done` — no owner check, no timeout.
- `lib/functions-common.zsh:369-372` — launcher start and the 300-tick identity poll.
- `lib/functions-common.zsh:386-391` — the `always` block: `_zsh_stop_owned_group` when `owner_pid` is known, otherwise `builtin kill -TERM "$launcher_pid"` followed by an unbounded `wait "$launcher_pid"`.
- `lib/query-supervisor.zsh:7-9` — the TERM/INT/HUP traps that make the supervisor ignore plain TERM.
- [GUIDE.md](../../GUIDE.md) — "A trusted supervisor remains alive through group termination and escalation, including children forked during shutdown" documents the intended lifetime but not the abandoned-owner case.

## Trigger and reproduction

Reproduction 1 (abandonment):

```console
$ zsh -f -c 'source .../60-functions.zsh; upkg help >/dev/null 2>&1; _upkg_capture_query sh -c "sleep 120"' &
$ kill -9 <owner>
$ ps -eo pid,ppid,sid,stat,args | grep -E "query-supervisor|sleep 120"
1413700    1192 1413700 SNs  /proc/1413688/exe -df .../lib/query-supervisor.zsh /tmp/zsh-query-owner.NGc1y7MN command sh -c sleep 120
1413701    1413700 1413700 SN   sleep 120
```

Reproduction 2 (abort-path hang): a supervisor stand-in that keeps the real disposition (`trap '' TERM`) and withholds identity.

```console
$ timeout -s KILL 20 zsh -f -c 'source .../60-functions.zsh; upkg help >/dev/null 2>&1;
    _ZSH_FUNCTIONS_MODULE_DIR=/tmp/slowsup _upkg_capture_query sh -c true; print "returned rc=$?"'
(no output; process still blocked at 10s in sigsuspend with the supervisor alive; killed at 20s, rc 137)
```

```console
$ kill -TERM <live supervisor>; sleep 1; ps -p <pid>
<pid> SNs ... (survived)
```

Evidence limits: normal completion and trapped INT/TERM/HUP clean up correctly (verified separately — prompt 130 returns, no leftovers), and the real supervisor is not known to exceed the identity budget in normal conditions; the hang was reproduced with a stand-in that preserves the supervisor's signal disposition and startup shape.

## Current behavior and impact

- An abnormal owner death leaks the supervisor permanently and leaves the wrapped native query running with its output discarded; when the query is a manager that takes locks or holds cache state, later package operations can be affected until it finishes.
- The abort path converts a transient handshake delay into an unbounded block: interactively a Ctrl+C escapes it, but a script, CI step, or agent calling `upkg`/`npkg` hangs, and the supervisor plus its child then remain alive.
- Both failure modes are unbounded and accumulate: each occurrence adds a process that no later command reaps.
- Leftover control/capture directories under `TMPDIR` are not removed on either path.

## Root cause

The supervisor's lifetime is defined only relative to its owner's successful shutdown sequence (`_zsh_stop_owned_group` with an identity read from the handshake). Two assumptions are unenforced:

- that the owner will always reach its `always` block, and
- that the launcher can be stopped with TERM.

Because `setsid --wait` execs in place here (the backgrounded job's PID is the supervisor and session leader), TERM goes to the supervisor itself, whose traps swallow it by design, so the following `wait` has nothing to reap and blocks indefinitely.

## Fix goal and expected behavior

- The supervisor must not require the owner to exist: it should exit on its own once its owner is gone (for example, record `$sysparams[ppid]` at startup and stop when that process disappears or is reparented, or read from a pipe whose EOF means the owner closed it), and must not keep a wrapped command alive after the owner is gone.
- The handshake failure path must be bounded: after the identity budget expires, verify the session-leader identity and kill the whole group (mirroring `_zsh_stop_owned_group`) rather than TERM-then-unbounded-wait. The call must return a documented failure status promptly.
- Preserve the supervisor's reason for existing: it must still remain alive through the owner's group TERM/KILL escalation and still catch children that outlive the direct query, and cancellation statuses (129/130/143) and existing regressions must stay unchanged.

## Implementation constraints

- Keep `lib/query-supervisor.zsh` a fixed trusted repository-local entrypoint with the same callback allowlist; no user-controlled discovery, no new runtime dependency.
- Keep the private-session/process-group ownership boundary and its documented exceptions (detached children, shared Nix daemons).
- Keep the Linux `/proc` and util-linux `setsid` requirement as documented.
- If the ownership boundary changes in a user-visible way, update GUIDE.md in the same change; `scripts/check-deps.sh` already marks `setsid` optional, consistent with queries-only impact.
- Do not weaken existing coverage in `scripts/test-package-audit.zsh` (wrapper INT/TERM/HUP, non-child wait, prompt return, unrelated-process survival).

## Acceptance criteria

- [ ] A regression that SIGKILLs the owner mid-query shows the supervisor and its wrapped command gone within a bounded time, with control/capture directories removed.
- [ ] A regression whose supervisor withholds identity beyond the budget returns promptly with a nonzero status, with no surviving supervisor and no unbounded `wait`.
- [ ] Existing cancellation, prompt-return, non-child, and unrelated-process regressions stay green, and `zsh scripts/run-tests.zsh` passes on a host where the fixture PIDs are live.

## Validation plan

- Re-run both reproductions; assert bounded completion and no leftover processes (`ps`) or directories (`TMPDIR`).
- Confirm normal completion and Ctrl+C paths still remove everything and return 130 within ~0.1 s.
- Run `zsh scripts/run-tests.zsh` and `zsh scripts/test-package-audit.zsh` on the audit host.
- Optional isolated check: run `upkg outdated --only nix` and confirm no supervisor outlives a SIGKILL of the wrapper.

## References

- [`docs/issues/TEMPLATE.md`](TEMPLATE.md)
- [`AGENTS.md`](../../AGENTS.md) — verification contract
- [`lib/query-supervisor.zsh`](../../lib/query-supervisor.zsh) — supervisor entrypoint
- [`lib/functions-common.zsh`](../../lib/functions-common.zsh) — `_zsh_run_owned_query`, `_zsh_stop_owned_group`
- Commit `f98a63c` — "fix(packages): supervise captured query sessions during cancellation" (introduced the supervisor)
- Commit `1b85d3b` — "fix(nix): verify owned workers before retrying interrupted waits" (current head under review)
