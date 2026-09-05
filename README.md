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

Without `compinit`, shells start normally but command-specific Tab completion stays disabled. Unreadable modules are skipped the same quiet way, so one bad file does not prevent startup.

Reload the shell, check the installation, and discover the commands:

```zsh
exec zsh
$HOME/.config/zsh/scripts/check-deps.sh
zdoctor
zhelp
tips
ztheme list
```

`zdoctor` diagnoses install location, missing modules, completion readiness, tool availability, glyph settings, and integration status without touching the network or Secret Service unless asked (`zdoctor --network`, `zdoctor --secrets`). `zhelp` opens a searchable palette in a capable terminal and prints a plain command list elsewhere. Selecting an entry queues an example for editing; it never runs the example. General helpers support `--help`; see the [guide](GUIDE.md#function-reference) for search controls, extraction destinations, bounded network requests, and credential status.

Fuzzy pickers share one rounded frame with unfilled input and footer rows, restrained section dividers, concise key hints, responsive previews, and theme-aware focus and selection cues. Tabular pickers align their display columns by terminal cells while returning undecorated values. Glyphs default to ordinary Unicode in UTF-8 locales; use `ztheme current` to preview them or explicitly select Nerd Font icons (see [theme settings](GUIDE.md#terminal-output-modes)). Preview pickers use Ctrl+P to show or hide the preview and Ctrl+/ to toggle word wrapping.

## What it provides

- Shared history, directory-stack navigation, explicit dotfile globbing, and lightweight completion tuning.
- Guarded `zoxide` and `fzf` integration with Ctrl+R, Ctrl+T, and Alt+C bindings.
- File, search, Git branch navigation with undecorated branch selection and labeled alternate worktrees, network, disk-usage, and process helpers with pipe-friendly output and normalized numeric or named signals. Native `mkdir`, `cp`, `mv`, and `rm` behavior is left unchanged.
- `upkg` for detected package managers and optional `npkg` helpers for Nix profiles.
- Optional `cgm` credential storage through Linux Secret Service.
- Shared themes for rich dashboards and every fzf entry point, with safe session switching through `ztheme` and deterministic plain-text fallbacks.

## Requirements

The dependency checker treats these as required for the intended setup:

- `zsh`, `git`, `curl`, and `ss`
- `lsd` and `zoxide`
- stable `fzf` 0.68.0 or newer

Optional integrations use `bat`, `tree`, `fd` or `fdfind`, `jq`, `secret-tool`, and Nix. When Nix is installed, `nix-collect-garbage` enables the cleanup path. Missing optional tools either disable a feature or select a documented fallback.

If the packaged fzf is older than 0.68.0, upgrade it through a current package source or follow the upstream installation link printed by `scripts/check-deps.sh`.

The configuration targets GNU/Linux. Some commands and flags are not portable to BSD or macOS userlands without adjustment.

## Configuration boundary

This repository does not manage Oh My Zsh, Starship, PATH setup, `compinit`, or host-specific configuration. Keep those in `~/.zshrc` and source this shared layer afterward. Unreadable modules are skipped so one missing optional file does not prevent shell startup; run `zdoctor` when a feature is silently missing.

## Documentation

- [`GUIDE.md`](./GUIDE.md) — setup, full command reference, dependencies, workflows, and gotchas
- [`AGENTS.md`](./AGENTS.md) — repository maintenance rules and required verification
- [`docs/specs/`](./docs/specs/) — historical design and remediation records

For changes, follow the documentation ownership rules and run `zsh scripts/run-tests.zsh`; the maintenance contract is in [`GUIDE.md`](./GUIDE.md#maintenance-and-verification).
