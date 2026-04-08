# Shared Zsh Config

This directory holds the portable part of the Zsh setup that can be tracked in git and reused across different Linux distributions or machines.

The goal is to keep stable, reusable shell behavior here, while leaving machine-specific choices in the main `~/.zshrc`.

## What lives here

This shared config currently manages:

- Zsh options (AUTO_CD, EXTENDED_GLOB, CORRECT, etc.)
- History settings
- Aliases (ls, git extras, safety, network)
- `zoxide` integration
- `fzf` settings and shell bindings
- Tab completion tuning (case-insensitive matching, process completion)
- Shell functions (extract, mkcd, ff, ft, fkill, fbr, croot, path, npkg, etc.)
- Global aliases (G, L, W, H, T, NE, NUL)
- On-demand `tips` function

These files are loaded by the main entrypoint:

- `init.zsh` - sets zsh options and sources the shared modules in order
- `10-history.zsh` - shared history behavior
- `20-aliases.zsh` - shared aliases and fallbacks
- `30-zoxide.zsh` - guarded `zoxide` initialization
- `40-fzf.zsh` - shared `fzf` configuration and shell bindings
- `50-completion.zsh` - completion zstyles (case-insensitive, process completion)
- `60-functions.zsh` - useful shell functions
- `70-globals.zsh` - global aliases for command-line piping
- `80-tips.zsh` - on-demand `tips` shell function

## What does not live here

The following stay in the main `~/.zshrc` because they may differ by distro or machine:

- Oh My Zsh
- Starship prompt setup
- Any other machine-specific shell settings

## How it is loaded

The main `~/.zshrc` sources this directory through:

```zsh
source "$HOME/.config/zsh/init.zsh"
```

That means this folder can be version-controlled and reused, while the main `~/.zshrc` remains the place for local system differences.

If you want to wire it into your `~/.zshrc`, use this block:

```zsh
# Shared config: portable settings that live in git across machines.
if [ -r "$HOME/.config/zsh/init.zsh" ]; then
	source "$HOME/.config/zsh/init.zsh"
fi
```

Place that block in `~/.zshrc` wherever you want the shared config to load.
If you want shared aliases and shared shell behavior to apply after your framework setup, place it after Oh My Zsh is sourced.

## Dependency checker

This directory includes a one-time dependency checker:

```sh
$HOME/.config/zsh/scripts/check-deps.sh
```

It checks whether the shared tools used by this config are available:

- `zsh`
- `git`
- `lsd`
- `zoxide`
- `fzf`
- optional: `bat`
- optional: `tree`
- optional: `fd` / `fdfind`
- optional: `jq`
- optional: `nix` (for the `npkg` wrapper)

If something is missing, the script prints install hints for common package managers.

## Portability notes

- If `lsd` is missing, aliases fall back to standard `ls` behavior.
- If `tree` is missing, the `lt` alias is not created unless `lsd` is available.
- If `zoxide` or `fzf` are missing, their init blocks are skipped cleanly.
- If `bat` is missing, `fzf` file previews fall back to `sed` and `peek` falls back to `cat`.
- If `rg` (ripgrep) is missing, `ft` falls back to `grep`.
- If `fd`/`fdfind` is missing, `ff` falls back to `find`.
- If `nix` is missing, the `npkg` wrapper is not defined.
- If `jq` is missing, interactive `npkg add`/`remove` pickers are not available.

## Suggested git usage

Track this directory in your dotfiles repository and keep the main `~/.zshrc` as the local machine entrypoint.

Typical approach:

1. Put `.config/zsh` in your dotfiles repo.
2. Keep `~/.zshrc` on each machine for OMZ, Starship, and local differences.
3. Source `~/.config/zsh/init.zsh` from `~/.zshrc`.
4. Run the dependency checker after setting up a new system.
