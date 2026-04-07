# AGENTS.md

## Repo Shape

- This repo is a shared Zsh config, not an app/workspace: there is no package manager, lockfile, test runner, or CI config at the root.
- `init.zsh` is the executable source of truth. It sets shell options, then sources modules in this order: `10-history.zsh`, `20-aliases.zsh`, `30-zoxide.zsh`, `40-fzf.zsh`, `50-completion.zsh`, `60-functions.zsh`, `70-globals.zsh`, `80-tips.zsh`.
- Prefer `init.zsh` and the module files over `README.md` or `GUIDE.md` if they disagree; the docs currently lag the actual load order.

## Edit Rules

- Keep external tool integrations guarded with `command -v ... >/dev/null 2>&1` and preserve clean fallbacks. This repo is meant to stay portable across machines with different tool sets.
- IMPORTANT: whenever you change a user-facing alias, function, completion behavior, or workflow in this repo, update `80-tips.zsh` in the same change so the on-demand `tips` output stays accurate.
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
3. `zsh -fc 'source "$HOME/.config/zsh/init.zsh"'`

- Optional environment check: `"$HOME/.config/zsh/scripts/check-deps.sh"`
- `scripts/check-deps.sh` exits nonzero only when required tools are missing (`zsh`, `git`, `lsd`, `zoxide`, `fzf`). Missing optional tools (`bat`, `tree`) still exit `0` and only print hints.

## Automation Gotcha

- Aliases and functions in this repo are interactive shell features. Automation should call real binaries or explicitly source `init.zsh` inside `zsh -fc '...'`; do not assume aliases like `ll` or functions like `ft` exist in non-interactive shells.
- `~/.zshrc` is intentionally outside this repo. If a change depends on OMZ plugins, Starship, or local PATH/completion wiring, document the repo side here but do not assume those user-level files are versioned with this project.
