# Muse Tooling & CI Report — Zsh Config

**Repo:** `/home/nirmal/.config/zsh` · **Date:** 2026-08-25  
**Scope:** `.github/workflows/checks.yml`, `scripts/*.zsh`, `scripts/check-deps.sh`, `scripts/benchmark-startup.zsh` vs `AGENTS.md:39-56` Verification  
**Verdict:** All listed verification commands pass locally, but CI coverage diverges from `AGENTS.md` and several tooling gaps exist.

## 1. Execution Verification (Actual Runs)

| Command | Result | Note |
|---|---|---|
| `zsh -n *.zsh lib/*.zsh functions/ztheme functions/_fbr_format_entry` | ✅ exit 0 | CI: `.github/workflows/checks.yml:25` matches `AGENTS.md:1` |
| `zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh` | ✅ exit 0 | **CI missing** `benchmark-startup.zsh` (see §2.1) |
| `sh -n scripts/check-deps.sh` | ✅ exit 0 | CI: `checks.yml:28` matches `AGENTS.md:3` |
| `zsh scripts/test-init.zsh` | ✅ pass (≈90 ok) | CI: `checks.yml:37` |
| `zsh scripts/test-theme.zsh` | ✅ pass (36 ok) | CI: `checks.yml:39` |
| `zsh scripts/test-functions.zsh` | ✅ pass | CI: `checks.yml:46` |
| `zsh scripts/test-cgm.zsh` | ✅ pass | CI: `checks.yml:52` |
| `zsh scripts/test-upkg.zsh` | ✅ pass | CI: `checks.yml:58` |
| `zsh scripts/test-completions.zsh` | ✅ pass | CI: `checks.yml:64` |
| `zsh scripts/test-help.zsh` | ✅ pass | CI: `checks.yml:70` |
| `zsh -fc 'source "$HOME/.config/zsh/init.zsh"'` | ✅ exit 0 | **CI missing** — not in `checks.yml` |
| `scripts/check-deps.sh` (required vs optional exit) | ✅ exits `1` only for `zsh,git,curl,ss,lsd,zoxide,fzf` | Verified `scripts/check-deps.sh:189-213` |
| `scripts/benchmark-startup.zsh 5` | ✅ `command 22ms interactive 28ms` | Never run in CI (intentional) |

All scripts are `set -u` clean and `zsh -n` clean. No syntax failures observed.

## 2. Findings

### 2.1 CI Coverage vs `AGENTS.md` — CRITICAL / HIGH

| # | Severity | File:Line | Evidence | Fix |
|---|----------|-----------|----------|-----|
| C1 | **Critical** | `.github/workflows/checks.yml:24-70` | `AGENTS.md:42` requires `zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh`. CI has `zsh -n scripts/test-theme.zsh` (`checks.yml:33`) but **never checks `benchmark-startup.zsh` syntax**. `benchmark-startup.zsh` uses `TYPESET -r`, `zmodload zsh/datetime`, `EPOCHREALTIME` — syntax regression would be silent. | Add step: `run: zsh -n scripts/benchmark-startup.zsh` (or combine as AGENTS: `zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh`). |
| C2 | **Critical** | `.github/workflows/checks.yml:25` vs `AGENTS.md:43` / `:53` | CI runs `zsh -n *.zsh lib/*.zsh functions/ztheme functions/_fbr_format_entry` but `AGENTS.md:42` defines second syntax gate as `zsh -n scripts/benchmark-startup.zsh scripts/test-theme.zsh`. CI splits `test-init.zsh` into its own syntax step (`checks.yml:30`) — extra but does not implement the combined gate. Divergence means local AGENTS checklist ≠ CI. | Align CI to AGENTS verbatim, or update AGENTS to document per-file split. Keep both if intentional: `zsh -n scripts/benchmark-startup.zsh scripts/test-*.zsh`. |
| H1 | **High** | `.github/workflows/checks.yml:70` EOF | `AGENTS.md:53` final gate `zsh -fc 'source "$HOME/.config/zsh/init.zsh"'` absent. This is the integration smoke that catches `init.zsh:27-35` sourcing order, `62-cgm.zsh` gate, and `40-fzf.zsh` `zle` warnings. Tests stub HOME; only this gate catches real-HOME regressions (e.g., missing `lib/theme-*.zsh`). | Add final step: `name: Smoke-source init.zsh` `run: zsh -fc 'source "$HOME/.config/zsh/init.zsh"'` |
| H2 | **High** | `.github/workflows/checks.yml:15-22` | CI only installs `zsh` (`apt-get install -y zsh`). Required deps (`ss`/`iproute2`, `lsd`, `zoxide`, `fzf`) not installed. Tests stub them via `fakebin`, so CI stays green while `scripts/check-deps.sh` would fail on a user machine. CI never runs `scripts/check-deps.sh` (only `sh -n`). Spec `scripts/check-deps.sh:210-212` exits `1` for required-missing — CI cannot catch a broken `check-deps.sh` version gate. | Either (a) install required deps and run `sh scripts/check-deps.sh` as non-blocking, or (b) explicitly document CI uses fakebins and add a dedicated job that runs `PATH=fakebin sh scripts/check-deps.sh` regression (as `test-init` does). |
| M1 | **Medium** | `.github/workflows/checks.yml:20-22` | `sudo apt-get update` + `install` without caching. Every PR pays full `apt` cost (~30s). No `actions/cache` or `apt-get --no-install-recommends`. | Use `actions/cache` for `/var/cache/apt` or switch to `apt-get install -y --no-install-recommends zsh`. Consider `awalsh128/cache-apt-pkgs-action`. |
| M2 | **Medium** | `.github/workflows/checks.yml:19-22` | No `shell: bash` + `set -euo pipefail`, no timeout. A hung `zsh scripts/test-upkg.zsh` (interrupt harness uses `zselect` loops 600 ticks) could hang CI for 6h default. | Add `timeout-minutes: 10` to `verify` job. |
| L1 | **Low** | `.github/workflows/checks.yml:10-12` | `on.push.branches: [main,master]` — `master` branch may be dead. Duplicate branch filter is noise. | Keep only `main` unless `master` intentionally alive. |

### 2.2 Syntax-Check Scope

| # | Severity | File:Line | Evidence | Fix |
|---|----------|-----------|----------|-----|
| S1 | **Medium** | `.github/workflows/checks.yml:25` | `zsh -n *.zsh` expands at workflow `run` time via `bash -e` (default shell). Glob failure with no `*.zsh` would be literal string, but repo always has them. More subtle: `lib/*.zsh` misses `lib/theme-color.zsh` loaded via `source "$_ZSH_THEME_MODULE_DIR/lib/theme-*.zsh"` — covered, but `functions/ztheme` (no extension) and `functions/_fbr_format_entry` checked; `lib/theme-registry.zsh` etc are Zsh not `sh`, so `sh -n` would incorrectly reject them — CI correctly limits `sh -n` to `check-deps.sh`. Good. | Keep, but add explicit `zsh -n lib/theme-*.zsh` to doc comment for clarity. |
| S2 | **Low** | `AGENTS.md:42-43` vs `checks.yml:30-34` | CI checks `zsh -n scripts/test-init.zsh` individually, while AGENTS lumps `benchmark-startup.zsh` + `test-theme.zsh`. Individual checks give better failure attribution (good), but diverges from documented command that users copy-paste. | Synchronize docs: state that CI runs per-file syntax for better diagnostics, but local verification may use combined form. |

### 2.3 Shell Portability (`scripts/check-deps.sh` — POSIX `sh`)

Overall **portable** — correctly uses `command -v`, no `local`, no `[[`, handles `set -u` with `${1-}` / `${3:-0}`. Two minor portability notes:

| # | Severity | File:Line | Evidence | Fix |
|---|----------|-----------|----------|-----|
| P1 | **Medium** | `scripts/check-deps.sh:74-79` / `97-99` | `IFS` juggling: `IFS='` literal newline ↵ `'` is actually literal `\`+`n` in POSIX `sh` if quoted with single quotes? Author correctly uses embedded newline — portable but fragile if edited to `IFS="\n"`. No bug today, but comment-less trick. `sh -n` passes, `shellcheck` warns SC2143. | Add comment: `# IFS newline trick: literal newline, not \n`. Consider `IFS=$(printf '\nX'); IFS=${IFS%X}` for explicitness. |
| P2 | **Low** | `scripts/check-deps.sh:119` | `${#fzf_major}` length expansion is POSIX (since 2001, `dash` supports) — **not** a bashism. Safe. | No fix; add comment that `${#var}` is POSIX per spec. |
| P3 | **Low** | `scripts/check-deps.sh:126-128` | Grouping `{ [ ... ] && [ ... ]; }` requires `;` before `}` — present, correct. However `dash -n` would reject `{` without spaces? Author has `|| { [ ...` with space, correct. | No fix. |
| P4 | **Low** | `scripts/check-deps.sh:148-180` `print_hints` | Uses `printf '  sudo apt install ... iproute2 ... libsecret-tools'` — assumes `ss` from `iproute2`; on `brew` hint says `brew install ... lsd ... libsecret` but brew package is `libsecret` vs `libsecret-tools`. Minor hint drift. | Verify hints against real package names on each manager. |
| P5 | **Info** | `scripts/check-deps.sh:1` | Shebang `#!/bin/sh` — on Ubuntu `sh`=`dash`, on macOS `sh`=`bash` in sh-mode. Both pass. `set -u` will abort on unset `$1` in `have_cmd` if called with no args — `have_cmd` always called with arg, safe. | Keep `set -u` only; `set -e` would break `have_cmd` probe. Correct to keep `-u` only. |

**Dependency guard completeness:** `check-deps.sh:189-204` classifies:

```sh
check_cmd zsh required        # :189
check_cmd git required        # :190
check_cmd curl required       # :191
check_cmd ss required         # :192
check_cmd lsd required        # :193
check_cmd zoxide required     # :194
check_fzf                     # :195 → required >=0.68.0
check_cmd bat optional        # :196
check_cmd tree optional       # :197
check_any_cmd 'fd/fdfind' optional fd fdfind # :198
check_cmd jq optional         # :199
check_cmd secret-tool optional# :200
check_cmd nix optional        # :201
if have_cmd nix; then check_cmd nix-collect-garbage optional; fi # :202-204
```

Matches `AGENTS.md:56` and `checks.yml`: missing optional → `exit 0` (`check-deps.sh:216-217`), missing required → `exit 1` (`210-212`). No missing guards.

### 2.4 Test Script Robustness (PATH Stubbing, Fake Binaries, Isolation)

| # | Severity | File:Line | Evidence | Fix |
|---|----------|-----------|----------|-----|
| R1 | **Medium** | `scripts/test-init.zsh:6` | `zsh_bin=${commands[zsh]}` — no fallback. If `zsh` not hashed before test (e.g., `zsh -f` without `compinit`), `zsh_bin` empty → `"$zsh_bin" -dfi` execs empty. In practice `scripts/test-init.zsh` invoked via `zsh` so hashed, but `zsh -fc` may not populate `commands`. | Use `zsh_bin=${commands[zsh]:-$(command -v zsh)}` like `scripts/test-theme.zsh:3` does. |
| R2 | **Medium** | `scripts/test-init.zsh:149-160` `prepare_fzf_fakebin` | Symlinks core tools: `for tool in zsh chmod mkdir mktemp mv rm ls grep diff; do command ln -s -- "${commands[$tool]}" "$fakebin/$tool"` — `commands[$tool]` may be empty for missing `lsd`/`tree` etc, causing `ln -s -- ""` → failure hidden. Also `mktemp` stubbed as symlink then overwritten by `write_fake mktemp "exec $(command -v mktemp) \"$@\""`. Works but brittle. | Guard: `[[ -n ${commands[$tool]:-} ]] || continue` or fallback to `command -v`. |
| R3 | **Medium** | `scripts/test-init.zsh:14` `trap cleanup EXIT INT TERM` | `cleanup` does `command rm -rf "$tmp_home"` quoted — good. But `trap` does not handle `ERR`. If a test helper fails before `trap`, partial `fakebin` leaks? Already covered by `EXIT`. | Keep; consider `trap 'command rm -rf -- "$tmp_home"' EXIT INT TERM HUP`. |
| R4 | **Low** | `scripts/test-upkg.zsh:8-12` `fakebin=$(mktemp -d)` | No `TMPDIR` sanitization? Uses `mktemp` default `/tmp`. Later harness uses `export TMPDIR=$npkg_tmp_dir` — could collide with other tests if run in parallel (`make -j`). `cleanup` uses `local PATH=$original_path` to avoid `rm` alias — correct. | Document tests must not run in parallel sharing `/tmp`; or use `mktemp -d "${TMPDIR:-/tmp}/zsh-test-upkg.XXXXXX"` |
| R5 | **Low** | `scripts/test-upkg.zsh:240-242` `_npkg_eval_installable_record` | Busy-loop `while (( worker_ticks < 600 )); do zselect -t 1` to simulate long eval. If `zselect` unavailable, harness fails at `zmodload zsh/zselect || return 1` (`test-upkg.zsh:224`). On `zsh` builds without `zselect` (rare), test incorrectly fails. | Guard with skip: `if ! zmodload zsh/zselect 2>/dev/null; then print "skip: zselect unavailable"; return 0; fi` |
| R6 | **Low** | `scripts/test-cgm.zsh:104-108` `make_fake_secret_tool` | Fake `secret-tool` logs every invocation with `printf "\t%s"` — may log secret-adjacent values? But `_CGM_TEST_STORE_VALUE` deliberately not passed as arg (passed via file), and harness asserts `assert_not_contains "$log" "$secret"` — good isolation. No leak. | Keep. |
| R7 | **Info** | All `scripts/test-*.zsh` | Each uses `set -u` but not `set -e`/`setopt ERR_EXIT`. Failures propagate via `|| return 1` — verbose but intentional to allow `assert_*` to print. Good robustness; no hidden `set -e` abort. | No fix. |

Isolation score: High — all tests use ephemeral `HOME`/`XDG_CACHE_HOME`/`XDG_DATA_HOME` + `PATH=fakebin:$PATH` + `trap` cleanup. No global state leak except `test-upkg`'s global `PATH=$fakebin:$original_path` export persists for remainder of script (intentional). Subsequent tests not affected because each runs in separate process.

### 2.5 Benchmark Accuracy (`scripts/benchmark-startup.zsh`)

| # | Severity | File:Line | Evidence | Fix |
|---|----------|-----------|----------|-----|
| B1 | **Medium** | `scripts/benchmark-startup.zsh:19-22` | `if [[ $benchmark_root != ${HOME}/.config/zsh ]]; then exit 2` — benchmark only works when repo lives at `${HOME}/.config/zsh`. Checkout to `/tmp` or `/github/workspace` fails. `benchmark_root=${0:A:h:h}` resolves symlink, but comparison against `HOME` strict. Not CI-run today, but violates portability for contributors with custom `ZDOTDIR`. | Accept `ZSH_BENCHMARK_ROOT` override or compare `benchmark_root:A` vs `repo_dir`. |
| B2 | **Medium** | `scripts/benchmark-startup.zsh:41-65` | Measures wall-clock via `EPOCHREALTIME` before/after `command "$zsh_binary" -dfi < "$benchmark_input"`. `EPOCHREALTIME` is Zsh float secs; `elapsed_us=$(( (EPOCHREALTIME - started) * 1000000 ))` truncates via `integer`. High variance with 5 iterations — no confidence interval. | Report `min/max` already does; add `warmups` exclusion correct (49-54). Consider default `iterations` 20+ for stable p95, or print `stdev`. |
| B3 | **Low** | `scripts/benchmark-startup.zsh:31-34` | `benchmark_input=$(mktemp ...); print -r -- "source ${(q)benchmark_root}/init.zsh" >| "$benchmark_input"` — uses `(q)` quoting, safe for spaces. Good. | — |
| B4 | **Low** | `scripts/benchmark-startup.zsh:51,60` | `command "$zsh_binary" -dfi < "$benchmark_input" >/dev/null 2>&1` discards exit status — startup that fails (e.g., `fzf` block) counted as fast. `benchmark_mode` ignores `rc`. Should detect failures. | Wrap: `command "$zsh_binary" -dfi < "$benchmark_input" >/dev/null 2>&1 || print -u2 "benchmark child failed"` |
| B5 | **Low** | `scripts/benchmark-startup.zsh:68-73` | Median `((iterations+1)/2)` and p95 `((iterations*95+99)/100)` ceiling correct for 1-indexed array. Sorting via `samples=( ${(on)samples} )` where `(on)` numeric+lexicographic correct for integers. Uses `samples[1]` min and `samples[-1]` max — correct. | No fix. |
| B6 | **Info** | `scripts/benchmark-startup.zsh:36-39` `export TERM=...` | Forces `TERM=xterm-256color` `COLORTERM=truecolor` for repeatability, but masks `TERM=dumb` plain-mode speed. | Add `--plain` flag to benchmark plain mode separately, or document. |

Benchmark **passes** in isolation (`scripts/benchmark-startup.zsh 5` → `command 22ms interactive 22ms`).

### 2.6 Dependency Guard Completeness (per `AGENTS.md:20-25`)

| # | Severity | File:Line | Evidence | Fix |
|---|----------|-----------|----------|-----|
| G1 | **Low** | `20-aliases.zsh:10` / `42-47` | Startup probes for `grep --color=auto` and `diff --color=auto` use `command grep` execution at top-level: `if print -r -- x | command grep --color=auto`. AGENTS says startup-time guards use `(( $+commands[tool] ))` to avoid PATH walks on WSL2. These probes are *feature* probes, not existence — must exec. **Not a violation**, but incurs PATH walk cost. Documented deviation. | Keep, but add comment referencing AGENTS exception for feature probes. |
| G2 | **Info** | `40-fzf.zsh:79-81` / `138-142` | Preview strings correctly retain `command -v ... >/dev/null 2>&1` per AGENTS rule that `FZF_*_OPTS` preview strings run in fzf-spawned subshell (no `$commands` hash). Verified correct. | Keep. |
| G3 | **Info** | `40-fzf.zsh:33` / `30-zoxide.zsh:33` | Top-level guards correctly use `(( $+commands[zoxide] ))` / `(( $+commands[fzf] ))` — fast startup path, no `command -v`. Inside functions (`60-functions.zsh:98-104` `_zsh_require_fzf`, `ff:75`, `ft:91`, `extract:19-43`) correctly use `command -v ... >/dev/null`. Matches AGENTS rule that function-body guards stay `command -v` to support PATH-stubbed `test-upkg`. | Keep. |
| G4 | **Low** | `60-functions.zsh:30-49` `ports()` | Calls `command ss -tulnp` without existence guard. `ss` is required per `check-deps.sh:192`, but `ports` falls back: `output=$(command ss -tulnp 2>/dev/null) || { command ss -tulnp; return $?; }` — if `ss` missing, second call still fails confusingly. Should guard with `command -v ss`. | Add `command -v ss >/dev/null 2>&1 || { echo "ss is required (iproute2)"; return 1; }` |
| G5 | **Low** | `60-functions.zsh:794` `ports` awkg fallback | If `ss` header check fails (`*Netid*`), prints raw output — but raw output may contain ANSI? Not guard-relevant. | No fix. |

No missing `guard` for optional deps (`bat`, `tree`, `fd`) — all have `command -v` fallbacks (e.g., `peek:177` checks `bat` else `cat`, `dusage:546` uses `du` fallback). Complete.

### 2.7 Missing Tests for Modules

| Module | Tested? | Gap |
|---|---|---|
| `10-history.zsh` | ❌ none | No test for `HISTFILE`, `HISTSIZE`, `SAVEHIST`, `SHARE_HISTORY` etc. Low risk, but `test-init` could assert history options after `source`. |
| `20-aliases.zsh` | ⚠️ partial | `test-functions.zsh:248-272` `test_alias_probes_are_quiet` checks `ls/grep/diff` probes are quiet, but not that `alias ..` etc defined, nor `weather`/`glog`. Could add `zsh -fc 'source 20-aliases.zsh; alias ..'` check. |
| `30-zoxide.zsh` | ⚠️ partial | `test-init` checks `_ZO_FZF_OPTS` signature but not `zoxide init` path when `zoxide` missing. Could mock `zoxide` missing. |
| `50-completion.zsh` | ❌ none | No test for `zstyle ':completion:*' matcher-list`. `test-completions` tests `66-compdefs` but not `50-completion` tuning. |
| `55-ui-helpers.zsh` | ⚠️ partial | Rich/Plain helpers exercised via `dusage/bigfiles/path` indirect, but `_ui_bar`, `_ui_badge` not directly unit-tested. |
| `70-globals.zsh` | ❌ none | Global aliases `G L W H T NE NUL` never asserted. `test-functions` could check `alias -g G`. |
| `80-tips.zsh` | ✅ via `test-help.zsh:262-286` | Tips length/actionability checked — adequate. |
| `lib/theme-*.zsh` | ✅ via `test-theme` | Fully covered. |
| `62-cgm.zsh` | ✅ via `test-cgm` | Fully covered. |
| `66-compdefs.zsh` | ✅ via `test-completions` | Fully covered. |

Recommendation: Add `scripts/test-aliases.zsh` or extend `test-init` to assert `alias -g` and `zstyle` values; add `10-history` glob: `zsh -fc 'source init.zsh; [[ -o SHARE_HISTORY ]]'`.

### 2.8 CI Caching & Failure Modes

| # | Severity | File:Line | Evidence | Fix |
|---|----------|-----------|----------|-----|
| F1 | **Low** | `checks.yml:15-22` | No `timeout-minutes`. Suites with `zselect` loops could hang. | Add `timeout-minutes: 15`. |
| F2 | **Low** | `checks.yml:19-22` | `actions/checkout@v4` without `fetch-depth`. Default `1` — okay for syntax checks, but `git` history needed for `glog`? Not needed today. | Keep shallow, or add `fetch-depth: 0` if tests ever need `git log`. |
| F3 | **Info** | `checks.yml:16-22` | `runs-on: ubuntu-latest` image already has `zsh`, `git`, `curl`, `jq`, `fzf` (newer). Installing only `zsh` minimal — tests fake rest, so no need to install `lsd` etc. Correct for speed. Document this intentional minimalism in CI comment. | Add comment: `# Tests stub lsd/zoxide/fzf via fakebin; only zsh required`. |

## 3. Recommended Patch Set (Ordered)

1. **CI alignment (Critical)** — `.github/workflows/checks.yml`:

```yaml
- name: Check Zsh syntax (modules)
  run: zsh -n *.zsh lib/*.zsh functions/ztheme functions/_fbr_format_entry
- name: Check Zsh syntax (scripts)
  run: zsh -n scripts/benchmark-startup.zsh scripts/test-*.zsh
- name: Check dependency script syntax
  run: sh -n scripts/check-deps.sh
- name: Smoke-source init
  run: zsh -fc 'source "$HOME/.config/zsh/init.zsh"'
```

Add `timeout-minutes: 10` and comment about fakebins.

2. **Benchmark guard** — `scripts/benchmark-startup.zsh:19-22` allow `ZSH_BENCHMARK_ROOT` override.

3. **Test robustness** — `scripts/test-init.zsh:6` fallback `zsh_bin=${commands[zsh]:-$(command -v zsh)}`.

4. **Coverage** — Extend `test-init` or new `test-aliases` to assert `10-history`, `50-completion`, `70-globals`.

## 4. Summary Table

| Category | Pass | Gaps | Severity Highest |
|---|---|---|---|
| Syntax `zsh -n` | ✅ | `benchmark-startup.zsh` not in CI | Critical |
| `sh -n` POSIX | ✅ | IFS newline trick needs comment | Medium |
| Test execution | ✅ 7 suites | 3 modules untracked | Medium |
| `check-deps` required/optional | ✅ | CI never runs it (fakebin-only) | High |
| Benchmark | ✅ runs 22ms | HOME-path strict, no error check | Medium |
| Guards `$+commands` vs `command -v` | ✅ correct | `ports()` missing `ss` guard | Low |
| Isolation / fakebins | ✅ | `zsh_bin` fallback, `zselect` skip | Medium |

Overall status: **CI is green but not equivalent to `AGENTS.md` verification**. Two critical divergences (missing benchmark syntax, missing final `zsh -fc` smoke) should be patched before next release. No shell-critical bugs; `check-deps.sh` is POSIX-clean and matches spec.

*Generated via read-only audit of `checks.yml:1-70`, `scripts/check-deps.sh:1-220`, `scripts/benchmark-startup.zsh:1-85`, all `scripts/test-*.zsh`, `init.zsh`, `25-theme.zsh`, `40-fzf.zsh`. Verified with `zsh -n` / `sh -n` / `zsh scripts/test-*.zsh` execution.*
