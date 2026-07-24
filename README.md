# Shared Zsh Config

This directory contains the portable, versioned part of the Zsh setup. It is meant to be sourced from the machine-local `~/.zshrc`, while framework, prompt, PATH, and host-specific choices stay outside this repo.

`init.zsh` is the executable source of truth. It sets shared Zsh options, then sources readable modules in this order:

| File | Purpose |
|---|---|
| `10-history.zsh` | 100k-entry shared history with duplicate and secret-friendly defaults |
| `20-aliases.zsh` | Portable aliases for listing, navigation, safer file operations, git extras, and weather |
| `30-zoxide.zsh` | Guarded `zoxide` initialization |
| `40-fzf.zsh` | `fzf` defaults, previews, and guarded shell keybindings |
| `50-completion.zsh` | Lightweight completion `zstyle`s; assumes `compinit` already ran |
| `55-ui-helpers.zsh` | Shared rich-terminal UI helpers with plain fallbacks |
| `60-functions.zsh` | Shell helpers such as `extract`, `ff`, `ft`, `path`, `fbr`, `dusage`, `upkg`, and `npkg` |
| `70-globals.zsh` | Global aliases for pipes and redirection (`G`, `L`, `W`, `H`, `T`, `NE`, `NUL`) |
| `80-tips.zsh` | On-demand `tips` function |

For command examples and detailed behavior, use [`GUIDE.md`](./GUIDE.md).

## Loading

Source the shared entrypoint from `~/.zshrc`:

```zsh
if [ -r "$HOME/.config/zsh/init.zsh" ]; then
  source "$HOME/.config/zsh/init.zsh"
fi
```

Place it after Oh My Zsh if you want these aliases and functions to take precedence over framework defaults. This repo does not manage Oh My Zsh, Starship, local PATH wiring, or other machine-specific shell setup.

## Dependencies

Run the dependency checker after setting up a machine:

```sh
$HOME/.config/zsh/scripts/check-deps.sh
```

Required for the intended shared setup:

- `zsh`
- `git`
- `curl`
- `ss`
- `lsd`
- `zoxide`
- `fzf`

Optional extras:

- `bat`
- `tree`
- `fd` / `fdfind`
- `jq`
- `nix`

Missing optional tools keep the shell usable. The config uses runtime checks and either skips the integration or falls back to a simpler command where possible.

## Behavior Notes

- `init.zsh` skips unreadable module files instead of failing shell startup.
- External integrations are guarded with `command -v`.
- `40-fzf.zsh` initializes `fzf --zsh` only for normal interactive startup, which avoids `zle` warnings in `zsh -i -c ...` paths.
- `50-completion.zsh` intentionally stays small and assumes the main `~/.zshrc` or framework already ran `compinit`.
- Rich dashboards are used only in real UTF-8 terminals that are at least 60 columns wide and do not set `NO_COLOR`; pipes, redirects, `TERM=dumb`, and narrow terminals get plain output.
- Set `NO_NERD_FONT=1` to keep colors while forcing ASCII-safe icons and bars.
- `path` uses rich indexed output in capable terminals and stays one-entry-per-line in plain contexts.
- `path` preserves empty `PATH` components exactly; rich output labels them as `.`, while plain output keeps the corresponding empty lines.
- `fkill` defaults to `SIGTERM` for graceful shutdown; pass `9` explicitly when a process must be force-killed.
- `tips` is hook-free and only prints when called manually.
- This shared config targets GNU/Linux environments. Commands such as `ss`, GNU color flags, and several `find`/`du` flows are Linux-oriented.

## Package Helpers

`upkg` is the shared package-update wrapper. It detects supported managers at runtime: one distro backend (`paru`, `pacman`, `apt`, or `dnf`), plus optional `brew`, `flatpak`, `nix` via `npkg`, and global `npm`.

Default `upkg`, `upkg outdated`, `upkg check`, `upkg list`, `upkg search`, `upkg plan`, and `--dry-run` flows are read-only. Upgrades only run through `upkg upgrade`, `upkg up`, or `upkg update`; privileged distro upgrades require explicit `--sudo`.

In rich terminals, every valid `upkg` command path—including help and upgrades—uses the shared dashboard theme. Operational commands include themed titles, manager sections, and summaries; help uses themed command and flag panels. Pipes, redirects, and other plain contexts keep script-friendly output.

`npkg` is defined only when `nix` is available. Interactive `npkg` pickers and `npkg refresh`/`outdated` need `jq`, and the pickers also need `fzf` plus a real terminal.

See [`GUIDE.md`](./GUIDE.md#unified-package-updates-upkg) for the full command reference.

## Verification

After changing aliases, functions, completions, tips, or docs, run:

```sh
zsh -n *.zsh
sh -n scripts/check-deps.sh
zsh scripts/test-init.zsh
zsh scripts/test-functions.zsh
zsh -fc 'source "$HOME/.config/zsh/init.zsh"'
```

Optional environment check:

```sh
$HOME/.config/zsh/scripts/check-deps.sh
```

## Maintenance

- Keep `README.md`, `GUIDE.md`, and `80-tips.zsh` aligned with module behavior.
- Update `scripts/check-deps.sh` when shared external dependencies are added or removed.
- Treat `20-aliases.zsh` changes carefully because it redefines common commands such as `mkdir`, `cp`, `mv`, and `rm`.
