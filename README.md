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

`zdoctor` reports installation, tool, and integration problems without touching the network or Secret Service unless asked (`--network`, `--secrets`). `zhelp` searches every command and queues an editable example; it never runs the example. General helpers support `--help`; the [function reference](./GUIDE.md#function-reference) covers their options and safety rules.

Fuzzy pickers share one themed, responsive frame, with file previews limited to the first 200 lines. Use Ctrl+P to toggle a preview and Ctrl+/ to toggle wrapping. Glyphs default to Nerd Font icons in UTF-8 locales; set `NO_NERD_FONT=1` or `ZSH_UI_GLYPHS=unicode` otherwise (see [terminal output modes](./GUIDE.md#terminal-output-modes) and [finder sizing](./GUIDE.md#finder-layout-and-option-precedence)).

## What it provides

- Shared history, directory-stack navigation, explicit dotfile globbing, and lightweight completion tuning, including offline cached Nix candidates.
- Guarded `zoxide` and `fzf` integration with validated caches and Ctrl+R, Ctrl+T, Alt+C, and `zi` pickers.
- File, content search, Git, network, disk-usage, and process helpers with pipe-friendly output. Native `mkdir`, `cp`, `mv`, and `rm` behavior is left unchanged.
- `upkg` for update inventories, upgrades, search, and cleanup across detected package managers, plus optional `npkg` for fresh, bounded-parallel Nix profile checks and package operations.
- Optional `cgm` credential storage through Linux Secret Service.
- Shared themes for dashboards and every fzf entry point through `ztheme`, with plain-text fallbacks.
- On-demand `tips` that only mention tools you have installed.

Upgrade and cleanup previews never install or remove packages, but they can contact the network and write caches. See [the package workflow reference](./GUIDE.md#package-manager-upkg) and [search behavior](./GUIDE.md#search-behavior).

## Requirements

The dependency checker treats these as required for the intended setup:

- `zsh`, `git`, `curl`, and `ss`
- `lsd` and `zoxide`
- stable `fzf` 0.68.0 or newer

Captured package queries require readable Linux `/proc` process identities and `setsid` from util-linux; optional per-task child lists are not required. Optional integrations use `bat`, `tree`, `fd` or `fdfind`, `rg`, `jq`, `secret-tool`, and Nix. Optional `checkupdates` (`pacman-contrib`, requiring `fakeroot`) enables fresh Pacman inventories using a separate database. When Nix is installed, `nix-collect-garbage` enables the cleanup path. Missing optional tools either disable a feature or select a documented fallback.

If the packaged fzf is older than 0.68.0, upgrade it through a current package source or follow the upstream installation link printed by `scripts/check-deps.sh`.

The configuration targets GNU/Linux. Some commands and flags are not portable to BSD or macOS userlands without adjustment.

## Configuration boundary

This repository does not manage Oh My Zsh, Starship, PATH setup, `compinit`, or host-specific configuration. Keep those in `~/.zshrc` and source this shared layer afterward. Unreadable modules are skipped so one missing optional file does not prevent shell startup; run `zdoctor` when a feature is silently missing.

## Documentation

- [`GUIDE.md`](./GUIDE.md) — setup, full command reference, dependencies, workflows, and gotchas
- [`docs/issues/README.md`](./docs/issues/README.md) — unresolved issue tracker and consistent report template
- [`docs/performance/README.md`](./docs/performance/README.md) — consolidated performance review, validation evidence, and open implementation plan
- [`AGENTS.md`](./AGENTS.md) — repository maintenance rules and required verification

For changes, follow the documentation ownership rules and run `zsh scripts/run-tests.zsh`; the maintenance contract and native picker test coverage are in [`GUIDE.md`](./GUIDE.md#maintenance-and-verification).
