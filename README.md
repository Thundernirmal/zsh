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
| `65-help.zsh` | Command catalogue, availability checks, plain help, and the searchable `zhelp` palette |
| `66-compdefs.zsh` | Guarded command-aware completions for the custom function suite |
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
- `nix-collect-garbage` for Nix cleanup (checked when `nix` is installed)

Missing optional tools keep the shell usable. The config uses runtime checks and either skips the integration or falls back to a simpler command where possible.

## Behavior Notes

- `init.zsh` skips unreadable module files instead of failing shell startup.
- Ordinary `*` and `**/*` globs exclude hidden entries, even if an earlier framework enabled `GLOB_DOTS`; opt in with `*(D)` or `**/*(D)` when hidden matches are intentional.
- External integrations are guarded before use. Startup-time guards use zsh's prehashed `$+commands` table so a missing tool costs no `PATH` walk; guards inside functions use `command -v` so they stay correct when `PATH` changes mid-session.
- `40-fzf.zsh` initializes `fzf --zsh` only for normal interactive startup, which avoids `zle` warnings in `zsh -i -c ...` paths.
- `50-completion.zsh` intentionally stays small and assumes the main `~/.zshrc` or framework already ran `compinit`.
- `65-help.zsh` registers catalogue data without launching subprocesses. `zhelp` checks the live shell only when invoked.
- `66-compdefs.zsh` registers custom completions only when `compdef` is available. Without `compinit`, it is a silent no-op.
- `upkg` completion covers subcommands, aliases, flags, and comma-separated manager IDs. `npkg` completion reads an existing attribute cache when available but never runs Nix or refreshes the cache from Tab.
- `zhelp` uses fzf only in a suitable interactive terminal. Enter queues the selected example for editing and never executes it; pipes, redirects, missing fzf, `TERM=dumb`, and `--plain` use stable plain text.
- Rich dashboards are used only in real UTF-8 terminals that are at least 60 columns wide and do not set `NO_COLOR`; pipes, redirects, `TERM=dumb`, and narrow terminals get plain output.
- Set `NO_NERD_FONT=1` to keep colors while forcing ASCII-safe icons and bars.
- `path` uses rich indexed output in capable terminals and stays one-entry-per-line in plain contexts.
- `path` preserves empty `PATH` components exactly; rich output labels them as `.`, while plain output keeps the corresponding empty lines.
- `fkill` defaults to `SIGTERM` for graceful shutdown; pass `9` explicitly when a process must be force-killed.
- `tips` is hook-free and only prints when called manually.
- This shared config targets GNU/Linux environments. Commands such as `ss`, GNU color flags, and several `find`/`du` flows are Linux-oriented.

## Command Help

Run `zhelp` to browse the commands and important aliases defined by this repository. Search terms match command names, categories, descriptions, usage strings, and examples.

```zsh
zhelp                  # open fzf, or list available commands in plain mode
zhelp package          # filter the palette or plain list
zhelp upkg             # show the exact command record
zhelp --all npkg       # include an unavailable command and explain its requirements
zhelp --plain file     # force deterministic text suitable for pipes
```

The default view hides commands that are unusable in the current shell. `--all` includes them with dependency and availability details. Interactive selection inserts the catalogue example into the command buffer with `print -z`; it does not evaluate or execute the text.

## Package Helpers

`upkg` is the shared package-maintenance wrapper. It detects supported managers at runtime: one distro backend (`paru`, `pacman`, `apt`, or `dnf`), plus optional `brew`, `flatpak`, `nix` via `npkg`, and global `npm`.

Default `upkg`, `upkg outdated`, `upkg check`, `upkg list`, `upkg search`, and `upkg plan` flows are read-only. Upgrades only run through `upkg upgrade`, `upkg up`, or `upkg update`. `upkg clean` is also explicitly mutating: use `upkg clean --dry-run` to preview cleanup without changing packages, caches, profiles, or manager state. `--only` and `--skip` select comma-separated manager IDs for every operational command; `--sudo` authorizes privileged distro upgrade or cleanup backends without auto-confirming native prompts.

Cleanup stays inside each manager's conservative, documented operations. It never deletes cache directories directly, application data, project-local files, user configuration, or Nix profile generations, and it does not claim a portable reclaimed-byte total.

| Manager | `upkg clean` policy |
|---|---|
| `apt` | `apt autoremove`, then `apt autoclean` |
| `dnf` | `dnf autoremove`, then `dnf clean all` |
| `pacman` | Remove the array returned by `pacman -Qtdq` with `pacman -Rs --`, then run `pacman -Sc` |
| `paru` | `paru -c`, then `paru -Sc`; requires `--sudo` authorization but runs Paru unprefixed and does not duplicate Pacman |
| `brew` | `brew autoremove`, then standard `brew cleanup` without aggressive prune flags |
| `flatpak` | `flatpak uninstall --unused --user`, then `--system`, without deleting application data |
| `nix` | `nix-collect-garbage` without generation-deletion flags, preserving rollback history |
| `npm` | List npx cache keys with `npm cache npx ls`, remove those explicit keys with `npm cache npx rm <key>...`, then run `npm cache verify`, always in user space and without `--force` |

Cleanup never injects `-y`, `--assumeyes`, or equivalent confirmation flags. A failed phase does not suppress later independent phases or managers. npm versions that require `--force` for a keyless `npm cache npx rm` are handled by passing the keys returned by `npm cache npx ls`; `upkg` never requests whole-cache forced removal. An older npm that rejects the npx cache subcommands still gets `npm cache verify`; the result is reported as `partial`, the overall command returns nonzero, and the output recommends upgrading npm.

```zsh
upkg clean --dry-run
upkg clean --only brew,npm
upkg clean --skip nix
upkg clean --sudo --only apt
```

In rich terminals, every valid `upkg` command path—including help, upgrades, and cleanup—uses the shared dashboard theme. Operational commands include themed titles, manager sections, and summaries; help uses themed command and flag panels. Pipes, redirects, and other plain contexts keep script-friendly output.

`npkg` is defined only when `nix` is available. Interactive `npkg` pickers and `npkg refresh`/`outdated` need `jq`, and the pickers also need `fzf` plus a real terminal.

See [`GUIDE.md`](./GUIDE.md#unified-package-updates-upkg) for the full command reference.

## Verification

After changing aliases, functions, completions, tips, or docs, run:

```sh
zsh -n *.zsh
sh -n scripts/check-deps.sh
zsh scripts/test-init.zsh
zsh scripts/test-functions.zsh
zsh scripts/test-upkg.zsh
zsh scripts/test-completions.zsh
zsh scripts/test-help.zsh
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
