# AGENTS.md

## Repo Shape

- This repo is a shared Zsh config, not an app/workspace: there is no package manager, lockfile, or root-level test runner config. CI automation exists via GitHub Actions in `.github/workflows/checks.yml`.
- `init.zsh` is the executable source of truth. It sets shell options, then sources modules in this order: `10-history.zsh`, `20-aliases.zsh`, `30-zoxide.zsh`, `40-fzf.zsh`, `50-completion.zsh`, `55-ui-helpers.zsh`, `60-functions.zsh`, `66-compdefs.zsh`, `70-globals.zsh`, `80-tips.zsh`.
- The module files are the source of truth for behavior. `README.md` and `GUIDE.md` must be kept in sync with them at all times.

## Edit Rules

- Keep external tool integrations guarded and preserve clean fallbacks. This repo is meant to stay portable across machines with different tool sets.
- Which guard to use depends on when it runs:
  - Startup-time guards (top level of a module, evaluated on every shell start) use `(( $+commands[tool] ))`. A `command -v` miss walks the whole `PATH`, which dominates startup time on long `PATH`s such as WSL2 setups that inherit Windows entries.
  - Guards inside function bodies keep `command -v ... >/dev/null 2>&1`. `$commands` is a cached hash, so it can go stale mid-session and it defeats the `PATH`-stubbed fake binaries in `scripts/test-upkg.zsh`.
- `40-fzf.zsh` also embeds `command -v` inside the exported `FZF_*_OPTS` preview strings. Those run in a separate shell that fzf spawns, so they must stay `command -v`.
- IMPORTANT: whenever you change a user-facing alias, function, completion behavior, or workflow in this repo, update `80-tips.zsh`, `README.md`, and `GUIDE.md` in the same change so all documentation stays accurate and consistent.
- If you add or remove a shared external dependency, update `scripts/check-deps.sh` too.
- `scripts/check-deps.sh` is POSIX `sh`, not Zsh. Keep it portable.
- `40-fzf.zsh` should stay safe in non-prompt startup paths. Keep the `fzf --zsh` init guarded so `zsh -i -c ...` does not hit `can't change option: zle` warnings.
- `50-completion.zsh` only tunes `zstyle`s; it assumes the main `~/.zshrc` / Oh My Zsh layer already ran `compinit`.
- Keep `50-completion.zsh` lightweight. Heavy completion UI options were intentionally removed because they made completion lists noticeably slower.
- `80-tips.zsh` defines an on-demand `tips` shell function. Keep it hook-free; prompt hooks were removed because they added latency for every command cycle.
- Changes in `20-aliases.zsh` are high impact: it intentionally redefines common interactive commands such as `mkdir`, `cp`, `mv`, and `rm`.

## Verification

Run these in order after edits:

1. `zsh -n *.zsh`
2. `sh -n scripts/check-deps.sh`
3. `zsh scripts/test-init.zsh`
4. `zsh scripts/test-functions.zsh`
5. `zsh scripts/test-upkg.zsh`
6. `zsh scripts/test-completions.zsh`
7. `zsh -fc 'source "$HOME/.config/zsh/init.zsh"'`

- Optional environment check: `"$HOME/.config/zsh/scripts/check-deps.sh"`
- `scripts/check-deps.sh` exits nonzero only when required tools are missing (`zsh`, `git`, `curl`, `ss`, `lsd`, `zoxide`, `fzf`). Missing optional tools (`bat`, `tree`, `fd`/`fdfind`, `jq`, `nix`) still exit `0` and only print hints.

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
