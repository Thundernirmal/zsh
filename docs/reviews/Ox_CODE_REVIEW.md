# Ox Code Review — `~/.config/zsh`

**Date:** 2026-08-25 · **Scope:** correctness across all modules and lazy helpers, security-boundary compliance for `62-cgm.zsh`, code quality. Every finding below was verified by reading surrounding context; headline findings were additionally re-verified directly against source.

## 1. Correctness / robustness findings

| # | Sev | Location | Issue |
|---|---|---|---|
| F1 | **Med** | `25-theme.zsh:21` | `typeset -g _ZSH_THEME_MODULE_DIR=${_ZSH_THEME_MODULE_DIR:-${${(%):-%N}:A:h}}` — an exported `_ZSH_THEME_MODULE_DIR` redirects every lazy `source` of the theme libs (25-theme.zsh:27,52,63,121–160) to an arbitrary directory. AGENTS.md requires lazy helper sources "fixed to the repository directory… not user-controlled discovery." Contrast `60-functions.zsh:106`, which sets its dir **unconditionally**. Fix: drop the `${_ZSH_THEME_MODULE_DIR:-}` wrapper. |
| F2 | **Med** (spec/quality) | `66-compdefs.zsh:26–42` | Hand-maintained duplicates of data owned elsewhere: theme-name list vs theme registry (`25-theme.zsh`), upkg manager list vs `60-functions.zsh` whitelist (:1282), extract extensions vs `extract()` table (:13–47). Adding a sixth theme or manager silently desyncs completion from behavior — violates "single source of truth." Fix: derive at load time or add a drift-detection sync test. |
| F3 | Low | `30-zoxide.zsh:34` | `eval "$(zoxide init zsh)"` with no empty-output/syntax gate, unlike `40-fzf.zsh:470–525`'s rigor. Not practically exploitable (a hijacked `zoxide` binary executes attacker code when invoked anyway); consistency hardening only. |
| F4 | Low | `62-cgm.zsh:93–95,131–138` | Relative `XDG_DATA_HOME` puts the catalogue under `$PWD/cgm` (fzf validates `== /*` at `40-fzf.zsh:353`; cgm doesn't). Also `mkdir -p` then `chmod 700` leaves a brief umask-derived window; names-only content so impact is small. Fix: require absolute path + `( umask 077; mkdir -p … )`. |
| F5 | Low | `60-functions.zsh:2081,2255,2376,2462` | apt/brew/npm/flatpak search backends pass `"$@"` without `--`; queries starting with `-` parse as options. pacman/paru already protected (:2167,:2210). |
| F6 | Low | `60-functions.zsh:3704–3708` | Unreachable skip-recording branch: `run_order` is built from filtered managers (:3702) which by construction exclude skipped ones, and skipped entries are recorded anyway at :3767–3769. Dead code. |
| F7 | Low | `60-functions.zsh:3868–3879` | `_npkg_refresh_index` leaks `${cache_file}.err` when nix fails with empty stderr, and both `.tmp`/`.err` if the final `mv` fails. Elsewhere traps are used consistently (`_npkg_outdated:4186,4316`, upkg npm cache :3269–3302); `dusage` (:545–554), `bigfiles` (:674–696), `_upkg_run_outdated_nix` (:2722–2730), `_upkg_run_outdated_npm` (:2768–2783) lack INT/TERM traps. Inconsistent cleanup discipline. |
| F8 | Low | `60-functions.zsh:13–47` | `extract()` unpackers take `"$1"` without a preceding `--`; archive names starting with `-` parse as options. |
| F9 | Low | `50-completion.zsh:11` | `zstyle … command "ps -u $USER …"` expands `$USER` once at load; if unset, kill-completion's process list breaks silently. |

## 2. Security verdict — `62-cgm.zsh`: **PASS**

Every AGENTS.md constraint verified:

| Constraint | Verdict | Evidence |
|---|---|---|
| Entirely optional; no Secret Service contact on source | ✅ | `init.zsh:29–31` skips without `secret-tool`; top level defines functions only; test-cgm asserts zero startup invocations |
| No plaintext secret fallback | ✅ | Values live only in Secret Service (:467,:539); catalogue markers are empty `chmod 600` files under `umask 077`+noclobber (:168); symlink/non-regular refusals (:122–129,:162–165) |
| No reveal command | ✅ | `list` renders names only (:353–364); help states values never shown (:312) |
| No eval-based export | ✅ | `_cgm_export_one:269` = literal `typeset -gx -- "$1=$2"`; zero `eval` in file |
| Completion never retrieves values | ✅ | `66-compdefs.zsh:180–193` uses filesystem name markers only |
| No secret-loading with xtrace enabled | ✅ | `_cgm_env:496` disables xtrace around lookup+export; restored via `emulate -L` |
| Sentinel capture correctness | ✅ | `secret-tool(1)` adds its extra newline only on tty; inside `$( )` output is byte-exact so `value=${value[1,-2]}` strips exactly the sentinel (:551); trailing/multi-line secrets rejected (:557) |

Residual hardening items = F4 above (both low).

## 3. Explicitly checked — not bugs

- The four `eval` hits in `60-functions.zsh:3819/3868/3974/4157` are the **nix CLI subcommand** (`_npkg_nix eval …`), not shell eval. No backticks anywhere.
- All `rm/mv/mktemp/sudo` uses are `command`-prefixed, quoted, `--`-guarded; sudo only behind explicit `--sudo`/root gates (:2822,:3009,:3091,:3164).
- `40-fzf.zsh:79–81` bare `{}` previews are safe — fzf shell-quotes placeholder expansion by design.
- `25-theme.zsh` trampolines can't infinitely recurse on re-source (flags :162–167 force immediate re-source of real libs); palette re-append idempotent via `typeset -gA`.
- `functions/ztheme:33–54` rollback is genuinely atomic (validate → mutate → refresh → restore on failure); `:144–156` prints only `(q)`-quoted assignments, never touches `.zshrc`.
- `functions/_fbr_format_entry:17` `[WT] ` prefix surgery holds for any width ≥ 5.

## 4. Quality observations

**Duplication**
- `dusage`/`bigfiles` share ~85% scaffolding (:515–647 vs :650–793)
- `_upkg_run_search_pacman`/`_paru` identical except command (:2160–2244)
- fzf "0.68.0 or newer" string hand-copied in 5 places (`30-zoxide.zsh:42`, `60-functions.zsh:100`, `65-help.zsh:296`, plus `_FZF_MIN_VERSION` and `check-deps.sh`) — a version bump touches all

**Coupling:** `upkg`/`npkg` communicate via globals (`_UPKG_LAST_STATE`, `_NPKG_OUTDATED_STATE`…); `_upkg_record_cleanup_result:1632–1636` mutates caller-local counters (commented intentional, still fragile).

**Good discipline worth keeping:** correct startup/in-function guard split repo-wide; `(b)`-escaped user queries before glob interpolation (`65-help.zsh:242`); fbr selects raw branch names via `--accept-nth=5`, never parsed display rows.

## 5. Prioritized fixes

1. Pin `_ZSH_THEME_MODULE_DIR` unconditionally (`25-theme.zsh:21`) — closes the fixed-lazy-sources violation
2. Single-source or sync-test the `66-compdefs.zsh` duplicate registries
3. Harden cgm catalogue setup: require absolute `XDG_DATA_HOME`, mkdir-under-umask instead of chmod-after
4. Trap-based temp cleanup parity: fix `.tmp`/`.err` leak paths; add INT/TERM traps to dusage/bigfiles/outdated temp sections
5. Delete unreachable skip branch (`:3704–3708`); add `--` to apt/brew/npm/flatpak search backends and `extract()`
