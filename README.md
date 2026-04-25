# Shared Zsh Config

This directory holds the portable part of the Zsh setup that can be tracked in git and reused across different GNU/Linux distributions or machines.

The goal is to keep stable, reusable shell behavior here, while leaving machine-specific choices in the main `~/.zshrc`.

## What lives here

This shared config currently manages:

- Zsh options (AUTO_CD, EXTENDED_GLOB, INTERACTIVE_COMMENTS, NO_BEEP, no CORRECT prompts)
- History settings
- Aliases (ls, git extras, safety, network helpers over HTTPS)
- `zoxide` integration
- `fzf` settings and shell bindings
- Tab completion tuning (case-insensitive matching, process completion)
- Shell functions (extract, mkcd, ff, ft, fkill, fbr, croot, path, headers, fanprofile, upkg, npkg, etc.)
- Global aliases (G, L, W, H, T, NE, NUL)
- On-demand `tips` function

These files are loaded by the main entrypoint:

- `init.zsh` - sets zsh options and sources the shared modules in order
- `10-history.zsh` - shared history behavior
- `20-aliases.zsh` - shared aliases and fallbacks
- `30-zoxide.zsh` - guarded `zoxide` initialization
- `40-fzf.zsh` - shared `fzf` configuration and shell bindings
- `50-completion.zsh` - completion zstyles (case-insensitive, process completion)
- `55-ui-helpers.zsh` - shared terminal UI helpers for rich dashboard output
- `60-functions.zsh` - useful shell functions
- `70-globals.zsh` - global aliases for command-line piping
- `80-tips.zsh` - on-demand `tips` shell function

`init.zsh` is the executable source of truth. It sources those modules in order and skips any file that is not readable, so missing or intentionally removed modules fail soft instead of breaking shell startup.

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

For command-by-command examples and a fuller walkthrough, see [`GUIDE.md`](./GUIDE.md).

## Dependency checker

This directory includes a one-time dependency checker:

```sh
$HOME/.config/zsh/scripts/check-deps.sh
```

It checks whether the shared tools used by this config are available:

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
- `nix` (for the `npkg` wrapper)

If something is missing, the script prints install hints for common package managers.

## Portability notes

- `init.zsh` only sources readable module files, so absent modules are skipped cleanly.
- If `lsd` is missing, aliases fall back to standard `ls` behavior.
- If `tree` is missing, the `lt` alias is not created unless `lsd` is available.
- If `zoxide` or `fzf` are missing, their init blocks are skipped cleanly.
- `40-fzf.zsh` only loads `fzf --zsh` in interactive shells when `ZSH_EXECUTION_STRING` is empty, which keeps `zsh -i -c ...` startup paths free of `zle` warnings.
- `55-ui-helpers.zsh` only affects commands at runtime; it does not add hooks, redraw loops, or startup-time terminal work.
- `fkill` and `fbr` are interactive helpers: they require both `fzf` and a real terminal.
- If `bat` is missing, `fzf` file previews fall back to `sed` and `peek` falls back to `cat`.
- If `rg` (ripgrep) is missing, `ft` falls back to `grep`.
- If `fd`/`fdfind` is missing, `ff` falls back to `find`.
- `extract` supports many archive extensions, but some formats still depend on external tools such as `unzip`, `unrar`, `7z`, `gunzip`, `bunzip2`, or `uncompress`.
- `50-completion.zsh` assumes your main `~/.zshrc` or framework already ran `compinit`; it only adds lightweight `zstyle` tuning.
- If `nix` is missing, the `npkg` wrapper is not defined.
- If `jq` is missing, `npkg refresh`, `npkg outdated`, and interactive `npkg add`/`find`/`remove` pickers are not available.
- Rich dashboard output is enabled only for real UTF-8 terminals that are at least 60 columns wide and do not set `NO_COLOR`.
- Set `NO_NERD_FONT=1` to keep the dashboards colorized while forcing ASCII-safe icons and bars.
- `fanprofile` uses `/sys/firmware/acpi/platform_profile` when available, and falls back to ASUS `fan_boost_mode` on older ASUS/TUF hardware.
- `headers` is a redirect-following header check built on `curl -sSIL` (silent, show errors, head, follow redirects).
- `dusage`, `bigfiles`, `ports`, `myip`, `upkg` read-only views, `npkg outdated`, and `tips` render Catppuccin Mocha dashboards in rich terminals and fall back to plain text for pipes, redirects, `TERM=dumb`, or narrow terminals.
- `dusage` and `bigfiles` skip unreadable paths when they can still produce readable results, instead of failing the whole listing because one subtree is inaccessible.
- `ports` and `myip` are now shell functions instead of aliases so they can render rich panels while keeping their original command names.
- `upkg` uses runtime `command -v` detection, so it reflects whichever supported package managers are currently installed.
- `upkg` prefers `paru` over `pacman` on Arch-family systems; `pacman` stays available via `upkg --only pacman`.
- `upkg` with no arguments is read-only and shows outdated packages; upgrades require `upkg upgrade`.
- `upkg plan`, `upkg --dry-run`, and `upkg upgrade --dry-run` preview upgrades using the same read-only outdated checks.
- `upkg managers --only ...` lists selected managers in the same order `upkg` would execute them.
- `upkg managers` keeps active managers as bare IDs in plain output so piping and simple scripts do not need to strip an `(active)` suffix.
- `upkg upgrade` never injects `sudo` automatically; pass `--sudo` explicitly for `apt`, `dnf`, `pacman`, or `paru`.
- When `--sudo` is requested from an unprivileged shell, `upkg` expects `sudo` to exist; otherwise it blocks the backend and tells you to rerun as root.
- On Arch-family backends, empty `pacman -Qu` or `paru -Qua` results with exit `1` are treated as "no updates available" rather than as failures.
- `upkg` keeps npm upgrades user-space only and blocks `npm` upgrades when the global prefix is not user-writable instead of suggesting `sudo npm`.
- The `tips` function only includes dependency-specific tips when their supporting commands are available.
- This shared config targets GNU/Linux environments; commands such as `ss`, GNU `ls`/`grep` color flags, and some `find`/`du` pipelines are intentionally Linux-oriented.

## Unified package updates

For complete command examples, quick-reference workflows, and function-level notes, use [`GUIDE.md`](./GUIDE.md). The summary below keeps the repo README aligned with the code's package-update behavior.

`upkg` is a portable package-update entrypoint defined in `60-functions.zsh`. It opportunistically uses the managers already present on the host:

- distro backend: `apt`, `dnf`, or `paru`/`pacman`
- extras: `flatpak`, `nix` via `npkg`, and global `npm`

Default behavior is read-only:

- `upkg`, `upkg outdated`, `upkg check`, and `upkg list` show outdated packages using each manager's native output
- `upkg plan`, `upkg --dry-run`, and `upkg upgrade --dry-run` preview the selected upgrade set without changing packages
- `upkg upgrade`, `upkg up`, and `upkg update` run upgrades only when you ask for them
- `upkg managers` shows detected backends, keeps filtered selections first in execution order, and labels alternates that are available only via `--only`
- In rich terminals, the read-only `upkg` views add themed section headers and a summary card, while backend package-manager output stays mostly raw.

Filters and privilege policy:

- `--only <list>` / `--only=<list>` and `--skip <list>` / `--skip=<list>` accept comma-separated manager IDs such as `flatpak,npm`
- `--only` runs managers in the order you name them; default runs use detection order
- `--dry-run` previews upgrades instead of running them
- `--sudo` is an explicit opt-in for privileged upgrade paths; `upkg` never adds it automatically
- `flatpak` runs in the user installation by default via `--user`
- Empty `pacman -Qu` / `paru -Qu` / `paru -Qua` runs with exit `1` are treated as the normal no-update case
- `paru` previews both repo updates and AUR updates when `pacman` is available; if the repo check fails, `upkg` still shows any AUR preview it can gather before returning nonzero
- `paru` still runs unprefixed even when `--sudo` is passed so it can handle its own escalation flow
- `npm` upgrades are supported only as a user-space workflow

`upkg` does not add any new required shared dependency. It only uses managers already installed on the current machine.

## Suggested git usage

Track this directory in your dotfiles repository and keep the main `~/.zshrc` as the local machine entrypoint.

Typical approach:

1. Put `.config/zsh` in your dotfiles repo.
2. Keep `~/.zshrc` on each machine for OMZ, Starship, and local differences.
3. Source `~/.config/zsh/init.zsh` from `~/.zshrc`.
4. Run the dependency checker after setting up a new system.
