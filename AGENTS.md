# AGENTS.md

## Repo Shape

- This repo is a shared Zsh config, not an app/workspace: there is no package manager, lockfile, or root-level test runner config. CI automation exists via GitHub Actions in `.github/workflows/checks.yml`.
- `init.zsh` is the executable source of truth. It sets shell options, then sources modules in this order: `10-history.zsh`, `20-aliases.zsh`, `25-theme.zsh`, `30-zoxide.zsh`, `40-fzf.zsh`, `50-completion.zsh`, `55-ui-helpers.zsh`, `60-functions.zsh`, optional `62-cgm.zsh`, `65-help.zsh`, `66-compdefs.zsh`, `70-globals.zsh`, `80-tips.zsh`.
- `functions/ztheme`, `functions/_fbr_format_entry`, `lib/functions-*.zsh`, `lib/command-registry.zsh`, `lib/ui-width-data.zsh`, `lib/theme-*.zsh`, `lib/help-catalogue.zsh`, and `lib/tips-catalogue.zsh` are trusted repo-local lazy helpers. Normal startup registers fixed loaders and lightweight color stubs; general commands, package workflows, command-only rendering, catalogues, fbr formatting, palette, validation, and conversion code are parsed on first use. `lib/upkg-registry.zsh` is a trusted lightweight registry sourced during startup by `60-functions.zsh` and reused by `66-compdefs.zsh` when `compdef` is available.
- The module files are the source of truth for behavior. `README.md` and `GUIDE.md` must be kept in sync with them at all times.

## Documentation Ownership

- `README.md` is the short entrypoint: purpose, five-minute setup, requirements summary, and links. Do not turn it into a second command reference.
- `GUIDE.md` is the complete user reference. Keep detailed behavior, examples, dependency notes, safety boundaries, and gotchas there.
- `65-help.zsh` registers the fixed `zhelp` loader; `lib/command-registry.zsh` keeps shared help/completion records terse: one clear summary, usage, editable example, dependency label, and live availability.
- `80-tips.zsh` registers the fixed `tips` loader; `lib/tips-catalogue.zsh` contains short, actionable reminders. Add tips only for user-facing actions that users can perform. Do not use tips for implementation notes, release history, or long edge-case explanations.
- Keep current behavior in `GUIDE.md`. Completed specs and audits are retained in Git history; remove stale documents and their links instead of maintaining duplicate historical status notes.
- Link between surfaces instead of copying long explanations. When behavior changes, update each affected surface at its intended level of detail.

## Edit Rules

- Keep external tool integrations guarded and preserve clean fallbacks. This repo is meant to stay portable across machines with different tool sets.
- Which guard to use depends on when it runs:
  - Startup-time guards (top level of a module, evaluated on every shell start) use `(( $+commands[tool] ))`. A `command -v` miss walks the whole `PATH`, which dominates startup time on long `PATH`s such as WSL2 setups that inherit Windows entries.
  - Guards inside function bodies keep `command -v ... >/dev/null 2>&1`. `$commands` is a cached hash, so it can go stale mid-session and it defeats the `PATH`-stubbed fake binaries in `scripts/test-upkg.zsh`.
- `40-fzf.zsh` also embeds `command -v` inside the exported `FZF_*_OPTS` preview strings. Those run in a separate shell that fzf spawns, so they must stay `command -v`.
- `25-theme.zsh` is the single palette and glyph source of truth. Keep its startup path pure Zsh: no executable probes, terminal queries, filesystem theme discovery, downloaded palettes, arbitrary theme sourcing, or `eval`. Renderer and picker code consume semantic roles instead of palette-specific names or raw colors.
- `60-functions.zsh` owns fixed lazy registration for the general command catalogue and the session-only `ztheme` command. `lib/functions-catalogue.zsh` owns the fixed domain loader; `lib/functions-common.zsh`, `lib/functions-files.zsh`, `lib/functions-system.zsh`, `lib/functions-git.zsh`, `lib/functions-upkg.zsh`, `lib/functions-upkg-backends.zsh`, and `lib/functions-nix.zsh` own the implementations, and `functions/ztheme` owns its implementation. Theme export may print safe assignments but must not edit `.zshrc`; invalid settings and failed finder refreshes must remain atomic.
- `30-zoxide.zsh` may source generated integration only after `zsh -fn` validation. Its persistent cache must remain executable-fingerprint-keyed, owner-only, non-symlinked, atomically published, and fixed beneath an absolute `XDG_CACHE_HOME` or `HOME`; a cache miss may fall back to a private temporary file but never to unchecked `eval`.
- Keep the private `functions/` path idempotent and keep lazy helper sources fixed to the repository directory. Do not replace them with user-controlled discovery or runtime downloads.
- IMPORTANT: whenever you change a user-facing alias, function, completion behavior, or workflow in this repo, update `80-tips.zsh`, `README.md`, and `GUIDE.md` in the same change so all documentation stays accurate and consistent. Keep each update within the ownership boundaries above; synchronization does not mean duplicating the same prose.
- If you add or remove a shared external dependency, update `scripts/check-deps.sh` too.
- `scripts/check-deps.sh` is POSIX `sh`, not Zsh. Keep it portable.
- `40-fzf.zsh` should stay safe in non-prompt startup paths. Keep the `fzf --zsh` init guarded so `zsh -i -c ...` does not hit `can't change option: zle` warnings.
- `50-completion.zsh` only tunes `zstyle`s; it assumes the main `~/.zshrc` / Oh My Zsh layer already ran `compinit`.
- Keep `50-completion.zsh` lightweight. Heavy completion UI options were intentionally removed because they made completion lists noticeably slower.
- `80-tips.zsh` registers the on-demand `tips` shell function, and `lib/tips-catalogue.zsh` defines its first-use implementation and reminders. Keep both hook-free; prompt hooks were removed because they added latency for every command cycle.
- `62-cgm.zsh` must remain entirely optional. `init.zsh` skips the whole module when `secret-tool` is absent; when available, sourcing must not contact Secret Service or read the catalogue. Never add a plaintext secret fallback, reveal command, `eval`-based export, completion path that retrieves values, or secret-loading path that leaves Zsh `xtrace` enabled.
- Changes in `20-aliases.zsh` are high impact. Keep destructive file commands on their native semantics; do not imply safety through aliases whose flags later arguments can override.

## Verification

Run `zsh scripts/run-tests.zsh` after edits. The runner is the executable source of truth for the ordered syntax checks, regression suites, and fixed-install-path smoke test used by CI.

- Optional environment check: `"$HOME/.config/zsh/scripts/check-deps.sh"`
- `scripts/check-deps.sh` exits nonzero only when required tools are missing (`zsh`, `git`, `curl`, `ss`, `lsd`, `zoxide`, `fzf`). Missing optional tools (`bat`, `tree`, `fd`/`fdfind`, `jq`, `secret-tool`, `gdbus`, `nix`, and `nix-collect-garbage` when Nix is installed) still exit `0` and only print hints.
- `skills-lock.json` records maintainer skill provenance only; it is not a runtime dependency or package-manager lockfile.

## Manual QA Checklist

- When asked to prepare a full manual QA pass before a stable release, create `qa-features.csv` at the repo root.
- Keep the CSV local-only by listing `qa-features.csv` in `.gitignore`; it is a working checklist and should not be pushed to GitHub.
- Use these columns exactly: `cmd`, `expected behavior`, `Status`.
- Include only user-facing behavior that needs manual interactive QA, such as prompt startup, aliases, keybindings, completion, fzf pickers, guarded integrations, package-manager flows that should not be run automatically, rich/plain UI rendering, and other terminal ergonomics.
- Leave syntax checks, smoke tests, and scripted regression tests to the automated verification commands above instead of putting them in the manual CSV.
- Default `Status` to `Not Run` so the checklist can be filled during manual QA.

## Automation Gotcha

- Aliases and functions in this repo are interactive shell features. Automation should call real binaries or explicitly source `init.zsh` inside `zsh -fc '...'`; do not assume aliases like `ll` or functions like `ft` exist in non-interactive shells.
- `~/.zshrc` is intentionally outside this repo. If a change depends on OMZ plugins, Starship, or local PATH/completion wiring, document the repo side here but do not assume those user-level files are versioned with this project.
