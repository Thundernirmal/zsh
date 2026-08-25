# dsV4flash_Performance_Report

Full performance review of the Zsh config repo (`~/.config/zsh`), run by a dedicated subagent on 2026-08-25.

## Methodology

Three independent timing methods, all on zsh 5.9 / Ubuntu:

1. Repo's own `scripts/benchmark-startup.zsh` (30 iters, median/p95, `-df` command and `-dfi` interactive modes, warmups).
2. Fresh-shell harness (Python `perf_counter`, 25–60 iters, median) for `zsh -df <script>`, `zsh -dfi <script>`, and `zsh -fc 'source init.zsh'`.
3. Cumulative per-module harness (fresh `zsh -f` sourcing progressively longer prefixes; per-module cost = delta) plus targeted microbenchmarks (probe subprocesses, `command -v` vs `$+commands`, preview-shell spawns).

### Environment caveats

- Short 10-entry PATH; `fzf` **not** installed; `zoxide`, `lsd`, `jq`, `secret-tool` present; `nix`, `bat`, `tree`, `fd` absent.
- Real fzf-init path measured with a **simulated `fzf 0.69.0` binary** (fake `--version`/`--zsh`, real cache behavior) in an isolated PATH/XDG_CACHE_HOME.
- `command -v` cost scales with PATH length (the AGENTS.md WSL2 concern); this machine under-represents that risk.
- One earlier batch had a string-interpolation harness bug; those numbers were discarded and re-measured.

## Measured numbers

### Full startup (this machine)

| Path | Median |
|---|---|
| `zsh -df <script>` (benchmark `command` mode) | **28.8 ms** |
| `zsh -dfi <script>` (benchmark `interactive` mode) | **27.9 ms** |
| `zsh -fc 'source init.zsh'` | **26.8 ms** (in-shell loop: 25–31 ms) |
| `zsh -i -c exit` (real user shell) | **~126 ms** — repo ≈ 26 ms; OMZ+compinit+brew+bun ≈ 100 ms outside repo |
| `zsh -dfi` with fzf, warm cache | **+0.37 ms** over no-fzf (simulated) |
| `zsh -dfi` with fzf, cold cache (first run) | **+3.2 ms** one-time (simulated) |

### Per-module net cost (fresh `zsh -f`, baseline 1.19 ms subtracted, median of 60)

| Module | ms | Module | ms |
|---|---|---|---|
| 10-history | +0.1 | 60-functions | **+5.7** |
| 20-aliases | **+7.1** | 62-cgm | +0.9 |
| 25-theme | +0.9 | 65-help | **+2.8** |
| 30-zoxide | **+7.0** | 66-compdefs | +0.4 |
| 40-fzf | +0.5 (non-interactive) | 70-globals | +0.1 |
| 50-completion | +0.3 | 80-tips | **+3.8** |
| 55-ui-helpers | +0.3 | | |

Decompositions: 20-aliases ≈ grep pipeline probe 2.6 ms + diff probe 1.7 ms + parse. 30-zoxide ≈ `zoxide init zsh` eval 1.9–3.4 ms + `_zsh_zoxide_refresh_fzf_opts` chrome computation ~2.2 ms + wrapper/parse. 60-functions ≈ parse of 4,639 lines + top-level `command -v nix` PATH walk. `command -v` vs `$+commands` miss delta: 0.3 ms on 300-entry synthetic PATH (9 µs vs 2 µs warm per access).

## Findings by severity

### High

**H1 — Two feature-probe subprocesses at every startup (≈4.3 ms, ~16% of repo startup).**
`20-aliases.zsh:42-44` runs `print -r -- x | command grep --color=auto -e x` (3-process pipeline) and `20-aliases.zsh:46-48` runs `command diff --color=auto /dev/null /dev/null` on **every shell start** to detect `--color=auto` support. Largest single module cost in the repo; runs even when the answer never changes.
*Fix:* single-process grep probe: `command grep --color=auto -e x </dev/null >/dev/null 2>&1` (exit 1 = supported, only exit 2 = unsupported); gate both probes behind `$commands[grep]`/`$commands[diff]` presence checks. **−2.6 ms** plus eliminated probes when binaries are absent.

**H2 — Top-level `command -v nix` violates the documented `$+commands` standard.**
`60-functions.zsh:3782` runs `command -v nix >/dev/null 2>&1` at module top level on every startup. AGENTS.md mandates `(( $+commands[tool] ))` for startup-time guards (a miss walks the whole PATH; commit `d90ed98` converted the other modules but missed this one — it predates that commit). ~0.3 ms here, dominates on long PATHs (WSL2).
*Fix:* one-line change to `(( $+commands[nix] ))`. Note: test-upkg stubs `nix` via PATH (test-upkg.zsh:416-458), so either rehash in tests or document the deliberate exception (see Project Report §8.1). All other `command -v` sites in 60-functions.zsh are correctly inside function bodies.

### Medium

**M1 — `_zsh_zoxide_refresh_fzf_opts` runs at startup unconditionally (~2.2 ms).**
`30-zoxide.zsh:31` calls the refresh outside the `$+commands[zoxide]` guard at :33. Computes full fzf chrome (45 semantic-role color lookups + arg joins + signature) and exports `_ZO_FZF_OPTS` — wasted on machines without zoxide. Result is reused by `_fzf_export_config`'s signature cache on fzf+zoxide machines.
*Fix:* move the call inside the `commands[zoxide]` guard; optionally defer to first `zi` via the `__zoxide_zi` wrapper (30-zoxide.zsh:40-47). **−2.2 ms** on zoxide-less machines.

**M2 — Eager data for on-demand commands: 65-help (+2.8 ms) + 80-tips (+3.8 ms) ≈ 6.6 ms (~24% of startup).**
`65-help.zsh:55-115` executes 60 `_zsh_help_register` calls (7-value validation loops each) building the zhelp catalog, read only when `zhelp` runs. `80-tips.zsh:4-111` builds the tip pool, read only by on-demand `tips`. Pure data, no side effects.
*Fix:* apply the existing lazy-lib pattern (`lib/theme-*.zsh`) — move data into `lib/` files sourced by a loader invoked from `tips`/`zhelp`/the zhelp compdef. `66-compdefs.zsh:267-270` already falls back gracefully when `_ZSH_HELP_ORDER` is absent, so the compdef can trigger the loader. **−6.6 ms** on shells that never invoke either command.

### Low

**L1 — Per-keystroke `command -v` probes in fzf preview strings.**
`40-fzf.zsh:79,81` embed a 3-way `command -v` cascade (lsd→tree→ls / bat→sed) run by a freshly spawned shell on every preview render. Placement is correct per AGENTS.md (preview shell is a new process). ~0.2–0.5 ms per render; short-circuiting limits it to one probe. `_fzf_export_config` already knows which tools exist and could pre-resolve the command at export time. Tradeoff: mid-session binary removal would break previews. Optional.

**L2 — fzf-missing diagnostic prints on every interactive shell.**
`40-fzf.zsh:551-555` → `_fzf_startup_diagnostic` (:39-43) prints a stderr warning per shell on fzf-less machines. A session-scoped suppression (marker in `XDG_STATE_HOME`/`$TMPDIR`) would keep it once per session. No perf impact.

**L3 — zoxide's generated `chpwd` hook spawns a subprocess on every `cd` (~2–4 ms).**
Inherent to the standard `zoxide init zsh` integration; zoxide offers no `--no-hook`. Correctly left intact; document as a known tradeoff.

### Info

- Cold fzf init is one-time and well-bounded (+3.2 ms); warm cache only **+0.37 ms**.
- 60-functions parse (+5.7 ms) is inherent — 4,639 lines of definitions; only autoload splitting would change it (large refactor, not recommended).
- 10-history: `HISTSIZE/SAVEHIST=100000`, file currently 529 lines (load +0.1 ms); latent risk if the file grows toward the cap (100k-line load = tens of ms).
- `zsh -i -c exit` under-reports by ~1 ms (ZSH_EXECUTION_STRING skips fzf init); benchmark `-dfi` mode is the representative measurement.
- 25-theme.zsh startup (+0.9 ms) verified pure Zsh; `_zsh_theme_resolve_settings` with defaults does no custom-palette work.

## Recommendations (priority order)

1. **H2** — `60-functions.zsh:3782`: `command -v nix` → `(( $+commands[nix] ))`. One line, zero risk, restores documented standard.
2. **H1** — `20-aliases.zsh:42-48`: single-process grep probe (`</dev/null`, accept exit 1); gate both probes on `$commands[grep]`/`$commands[diff]`. **−2.6 ms** (~10%), low risk.
3. **M2** — Lazy-load 65-help catalog and 80-tips pool on first use. **−6.6 ms** (~24%), medium effort.
4. **M1** — `30-zoxide.zsh:31`: move refresh inside the zoxide guard, defer to first `zi`. **−2.2 ms** on zoxide-less machines.
5. **L1 (optional)** — Pre-resolve preview commands at export time. −0.2–0.5 ms per keystroke render.

Combined addressable: **~9–12 ms of the ~27 ms (30–40%)** without touching the irreducible 60-functions parse or zoxide's required eval.

## What already follows best practice (verified)

- **fzf cache architecture** (`40-fzf.zsh:341-545`): schema-versioned header, inode/dev/size/mtime/ctime keying, ownership+mode+symlink safety checks, atomic `mktemp`+`mv`, `zsh -fn` validation before activation, per-path state machine. Warm-cache +0.37 ms proves it pays off.
- **Signature-based caching** of theme chrome (25-theme.zsh:295-307) and FZF config export (40-fzf.zsh:69); picker-open revalidation is a few hundred µs.
- **Guard discipline**: `$+commands` used consistently except H2; function-body guards correctly keep `command -v`; fzf init correctly gated on `interactive && !ZSH_EXECUTION_STRING` (40-fzf.zsh:549) — no zle warnings in `zsh -i -c`.
- **25-theme.zsh startup path pure Zsh** — zero executable probes, terminal queries, or eval.
- **Lazy lib loading** for `lib/theme-{registry,color,palettes}.zsh` — sourced only on first use; stubs keep startup light.
- **Hook-free modules**: no precmd/chpwd/zle -N/bindkey anywhere (grep-verified); only zoxide's generated chpwd hook exists.
- **62-cgm genuinely inert at startup** — sourcing never contacts Secret Service or reads the catalogue.
- **The benchmark script itself** is well-built: warmups, median+p95, temp-file cleanup, env normalization.
