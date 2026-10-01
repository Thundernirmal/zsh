# ZSH-048: zdoctor reports a blocked fzf integration as healthy

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 — incorrect setup diagnostics and success status |
| Audit date | 2026-10-01 |
| Audited baseline | b5b0af5b7718e9cdbe62b472552a901399fae8a2 |
| Affected surface | `zdoctor`, failed fzf initialization, guided setup |
| Evidence | Reproduced isolated interactive shell and command-mode fixture |
| GitHub issue | [#42](https://github.com/Thundernirmal/zsh/issues/42) |

## Summary

A supported fzf binary can fail shell-integration generation while still reporting a valid version. The shared layer correctly blocks fuzzy workflows, but `zdoctor` marks that blocked integration `ok`, prints `healthy`, and returns zero. The setup check therefore approves a shell whose required interactive integration is unavailable.

## Affected code and documentation

- [lib/functions-system.zsh](../../lib/functions-system.zsh): `zdoctor`, especially baseline line 769 and the final failure-count decision.
- [40-fzf.zsh](../../40-fzf.zsh): `_fzf_initialize_zsh`, `_fzf_block_integration`, and `_fzf_require_ready` correctly retain/refuse the blocked state.
- [scripts/test-doctor.zsh](../../scripts/test-doctor.zsh): healthy/missing-tool tests do not cover a valid binary with failed integration.
- [README.md](../../README.md#quick-start), [GUIDE.md](../../GUIDE.md#zdoctor), and [tips catalogue](../../lib/tips-catalogue.zsh): recommend `zdoctor` for setup/integration diagnosis. The guide says real failures return nonzero.

## Trigger and reproduction

Prerequisites: GNU/Linux, Zsh, supported real fzf, and the normal required tools. Use a private temporary HOME and cache. No packages or credentials are changed.

In Zsh, from the configuration repository:

```zsh
repo_dir=$PWD
fixture=$(mktemp -d /tmp/zsh-doctor-repro.XXXXXX)
real_fzf=$(command -v fzf)
mkdir -p "$fixture/.config" "$fixture/bin"
ln -s "$repo_dir" "$fixture/.config/zsh"
cat > "$fixture/bin/fzf" <<'SH'
#!/bin/sh
if [ "$1" = --zsh ]; then
  exit 42
fi
exec "$QA_REAL_FZF" "$@"
SH
chmod +x "$fixture/bin/fzf"
HOME="$fixture" XDG_CACHE_HOME="$fixture/cache" \
  QA_REAL_FZF="$real_fzf" PATH="$fixture/bin:$PATH" \
  zsh -fic '
    autoload -Uz compinit; compinit -i
    source "$HOME/.config/zsh/init.zsh"
    _fzf_initialize_zsh "$commands[fzf]"
    zdoctor
    print -r -- "doctor_status=$? fzf_state=$_FZF_STATE"
  '
# Remove only this fixture after inspecting the result:
command rm -rf -- "$fixture"
```

`-i -c` intentionally does not run normal prompt integration automatically, so the reproduction explicitly invokes the same initializer. A separate fresh normal-prompt session with this wrapper produced the same result. In that session, `fbr` also refused to launch and returned 1.

Observed decisive output with fzf 0.74.4:

```text
ok: required tool: fzf 0.74.4 (minimum 0.68.0)
ok: fzf integration state: blocked (found: integration generation failed)
zdoctor: healthy (1 warning(s))
doctor_status=0
fzf_state=blocked
```

Warning counts can vary with optional tools and settings. The contradictory `ok`/`healthy` and zero status are stable.

## Current behavior and impact

The integration itself fails safely: required pickers refuse the blocked binary. The defect is the diagnostic result. Users following the quick start receive a successful health check despite unavailable Ctrl+T/Ctrl+R/Alt+C and guarded picker workflows. Scripts that preserve `zdoctor` status also receive false success. This is a P2 correctness issue; no data loss, secret exposure, or unsafe picker execution was observed.

## Root cause

`zdoctor` checks the installed fzf version independently, then unconditionally calls `_zdoctor_report ok` for `_FZF_STATE`. A valid version passes the binary check, and the blocked integration never increments `failures`. The final failure-count check consequently returns zero and prints `healthy`.

## Fix goal and expected behavior

A recorded blocked fzf integration must be a failed diagnostic with its retained reason and nonzero aggregate status, even when the installed binary version is supported. Ready integration remains successful. An unchecked command-mode shell must not be mislabeled blocked or force initialization just to diagnose it; describe its state accurately and retain the intended non-prompt startup behavior.

## Implementation constraints

Keep diagnosis local and read-only by default. Do not regenerate/source integration, contact the network, query Secret Service, alter widgets, or repair caches as a side effect of `zdoctor`. Preserve function-body `command -v` guards, lazy domain loading, plain/rich output, and normal startup gating. Any behavior repair must synchronize README, GUIDE, and `80-tips.zsh` at their intended ownership levels.

## Acceptance criteria

- [ ] A supported fzf with failing `--zsh` produces a failed integration diagnostic and nonzero `zdoctor` status.
- [ ] A failed generated-integration activation is also reported as failure, with its reason.
- [ ] Ready integration with a supported binary remains healthy.
- [ ] Unchecked non-prompt integration is accurately described without initializing it or changing shell state.
- [ ] Missing/old/prerelease fzf still fails, without contradictory `ok: ... blocked` output.
- [ ] Default diagnosis remains free of network/Secret Service calls and cache/widget mutations.

## Validation plan

Extend the isolated cases in `scripts/test-doctor.zsh` to cover blocked, ready, and unchecked integration state plus supported-version generation/activation failures. Assert diagnostic labels, aggregate status, retained reason, and unchanged state. Repeat the normal-prompt wrapper reproduction. Run `zsh scripts/run-tests.zsh`, and obtain subagent review during the repair workflow described by the issue index. This report records a defect; it does not implement the repair.

Baseline verification passed: the required runner completed with 1,890 assertions, and the native picker PTY suite passed 107 cases with both fzf 0.68.0 and 0.74.4. Those existing checks do not catch this diagnostic defect.

## References

- [Issue report contract](README.md#report-structure-and-verification)
- [Repository maintenance rules](../../AGENTS.md)
- [Doctor user reference](../../GUIDE.md#zdoctor)
- [Non-prompt fzf startup boundary](../../GUIDE.md#fzf-requirement-and-startup)
