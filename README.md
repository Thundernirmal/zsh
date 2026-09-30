# Shared Zsh Config

A portable, versioned Zsh layer for GNU/Linux. It adds predictable interactive defaults, fast navigation and search, fuzzy pickers, package helpers, completion, and searchable command help while leaving machine-specific setup in `~/.zshrc`.

[`init.zsh`](./init.zsh) is the entrypoint and the executable source of truth. The complete command reference and every important caveat live in [`GUIDE.md`](./GUIDE.md).

## Quick start

This repository must live at `~/.config/zsh` because `init.zsh` loads its modules from that fixed location. Clone it into an empty target directory:

```sh
git clone https://github.com/Thundernirmal/zsh.git "$HOME/.config/zsh"
```

Source it near the end of `~/.zshrc`. With Oh My Zsh, source it after `oh-my-zsh.sh` so the shared aliases take precedence (Oh My Zsh already runs `compinit`). Without a framework, run `compinit` first:

```zsh
# Optional: choose a built-in palette before loading the shared layer.
typeset -g ZSH_UI_THEME=nord

# Standalone setup without Oh My Zsh (skip when the framework runs compinit).
autoload -Uz compinit && compinit -i

if [ -r "$HOME/.config/zsh/init.zsh" ]; then
  source "$HOME/.config/zsh/init.zsh"
fi
```

Without `compinit`, shells start normally but command-specific Tab completion stays disabled. Zoxide startup also supports `NO_UNSET` when shell hook arrays have not been created. Unreadable modules are skipped the same quiet way, so one bad file does not prevent startup.

Reload the shell, check the installation, and discover the commands:

```zsh
exec zsh
$HOME/.config/zsh/scripts/check-deps.sh
zdoctor
zhelp
tips
ztheme list
```

`zdoctor` diagnoses install location, missing modules, completion readiness, tool availability, glyph settings, and integration status without touching the network or Secret Service unless asked (`zdoctor --network`, `zdoctor --secrets`). `zhelp` opens a searchable palette in a capable terminal and prints a plain command list elsewhere. Selecting an entry queues an example for editing; it never runs the example. Helpers load by domain so small commands leave package code unloaded. Package searches work on first use, including native DNF4 and DNF5 no-match handling, and Nix searches suppress evaluation progress, and update checks keep warnings separate from package results; see [package search](GUIDE.md#search-behavior). General helpers support `--help`; see the [guide](GUIDE.md#function-reference) for search controls, validated extraction destinations, native input-link handling, bounded network requests, and credential status.

Fuzzy pickers share one rounded frame with unfilled input and footer rows, restrained section dividers, concise key hints, responsive previews, and theme-aware focus and selection cues. Tabular pickers align their display columns by terminal cells while returning undecorated values. Glyphs default to Nerd Font icons in UTF-8 locales; use `NO_NERD_FONT=1` or `ZSH_UI_GLYPHS=unicode` for ordinary Unicode instead (see [theme settings](GUIDE.md#terminal-output-modes)). Preview pickers use Ctrl+P to show or hide the preview and Ctrl+/ to toggle word wrapping.

## What it provides

- Shared history, directory-stack navigation, explicit dotfile globbing, and lightweight completion tuning.
- Guarded `zoxide` and `fzf` integration with private validated cache fallbacks, failed-load rollback and stale-widget tolerance, and Ctrl+R, Ctrl+T, and Alt+C bindings.
- File, search, Git branch navigation with validated canonical selection identities and labeled alternate worktrees, network, disk-usage, and process helpers with pipe-friendly output and normalized numeric or named signals. Search fallbacks preserve diagnostics and exit status; native `mkdir`, `cp`, `mv`, and `rm` behavior is left unchanged.
- `upkg` update inventories, native upgrades, package search and stable npm inventories and search versions with visible diagnostics, complete Flatpak update refs, and cleanup that retains completed and failed phase counts on cancellation, with explicit backend selection and support for Paru configuration. Optional modern-CLI `npkg` helpers cover active Nix profile entries with separate diagnostic streams, with help before work and explicit argument validation.
- Optional `cgm` credential storage through Linux Secret Service with exact-value scalar exports and safe attributed-scalar removal.
- On-demand tips include manager-specific reminders only when their tools are available.
- Shared themes for rich dashboards and every fzf entry point, with atomic session switching and read-only inspection through `ztheme` and deterministic plain-text fallbacks.

Upgrade previews inventory available updates; cleanup previews describe cleanup work. Both avoid installing or removing packages but can contact the network and write caches. See [the package workflow reference](GUIDE.md#package-manager-upkg) for metadata freshness, transaction limits, cleared search progress and distinct cancellation summaries and owned query-process cleanup, and cleanup effects.

## Requirements

The dependency checker treats these as required for the intended setup:

- `zsh`, `git`, `curl`, and `ss`
- `lsd` and `zoxide`
- stable `fzf` 0.68.0 or newer

Captured package queries require Linux `/proc` and `setsid` from util-linux. Optional integrations use `bat`, `tree`, `fd` or `fdfind`, `jq`, `secret-tool`, and Nix. Optional `checkupdates` (`pacman-contrib`, requiring `fakeroot`) enables fresh Pacman inventories using a separate database. When Nix is installed, `nix-collect-garbage` enables the cleanup path. Missing optional tools either disable a feature or select a documented fallback.

If the packaged fzf is older than 0.68.0, upgrade it through a current package source or follow the upstream installation link printed by `scripts/check-deps.sh`.

The configuration targets GNU/Linux. Some commands and flags are not portable to BSD or macOS userlands without adjustment.

## Configuration boundary

This repository does not manage Oh My Zsh, Starship, PATH setup, `compinit`, or host-specific configuration. Keep those in `~/.zshrc` and source this shared layer afterward. Unreadable modules are skipped so one missing optional file does not prevent shell startup; run `zdoctor` when a feature is silently missing.

## Documentation

- [`GUIDE.md`](./GUIDE.md) — setup, full command reference, dependencies, workflows, and gotchas
- [`docs/issues/README.md`](./docs/issues/README.md) — open audit findings, reproduction details, and fix acceptance criteria
- [`AGENTS.md`](./AGENTS.md) — repository maintenance rules and required verification

For changes, follow the documentation ownership rules and run `zsh scripts/run-tests.zsh`; the maintenance contract is in [`GUIDE.md`](./GUIDE.md#maintenance-and-verification).
