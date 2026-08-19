# Shared Zsh Config

A portable, versioned Zsh layer for GNU/Linux. It adds safer interactive defaults, fast navigation and search, fuzzy pickers, package helpers, completion, and searchable command help while leaving machine-specific setup in `~/.zshrc`.

[`init.zsh`](./init.zsh) is the entrypoint and the executable source of truth. The complete command reference and every important caveat live in [`GUIDE.md`](./GUIDE.md).

## Quick start

This repository expects to live at `~/.config/zsh`. Source it near the end of `~/.zshrc`, after Oh My Zsh if the shared aliases should take precedence:

```zsh
if [ -r "$HOME/.config/zsh/init.zsh" ]; then
  source "$HOME/.config/zsh/init.zsh"
fi
```

Reload the shell, check the installation, and discover the commands:

```zsh
exec zsh
$HOME/.config/zsh/scripts/check-deps.sh
zhelp
tips
```

`zhelp` opens a searchable palette in a capable terminal and prints a plain command list elsewhere. Selecting an entry queues an example for editing; it never runs the example.

## What it provides

- Shared history, directory-stack navigation, explicit dotfile globbing, and lightweight completion tuning.
- Guarded `zoxide` and `fzf` integration with Ctrl+R, Ctrl+T, and Alt+C bindings.
- File, search, Git branch navigation with labeled alternate worktrees, network, disk-usage, and process helpers.
- `upkg` for detected package managers and optional `npkg` helpers for Nix profiles.
- Optional `cgm` credential storage through Linux Secret Service.
- Theme-aware rich terminal dashboards with deterministic plain-text fallbacks.

## Requirements

The dependency checker treats these as required for the intended setup:

- `zsh`, `git`, `curl`, and `ss`
- `lsd` and `zoxide`
- stable `fzf` 0.52.0 or newer

Optional integrations use `bat`, `tree`, `fd` or `fdfind`, `jq`, `secret-tool`, and Nix. When Nix is installed, `nix-collect-garbage` enables the cleanup path. Missing optional tools either disable a feature or select a documented fallback.

The configuration targets GNU/Linux. Some commands and flags are not portable to BSD or macOS userlands without adjustment.

## Configuration boundary

This repository does not manage Oh My Zsh, Starship, PATH setup, `compinit`, or host-specific configuration. Keep those in `~/.zshrc` and source this shared layer afterward. Unreadable modules are skipped so one missing optional file does not prevent shell startup.

## Documentation

- [`GUIDE.md`](./GUIDE.md) — setup, full command reference, dependencies, workflows, and gotchas
- [`AGENTS.md`](./AGENTS.md) — repository maintenance rules and required verification
- [`docs/specs/`](./docs/specs/) — historical design and remediation records

For changes, follow the documentation ownership rules and run the complete verification sequence in [`GUIDE.md`](./GUIDE.md#maintenance-and-verification).
