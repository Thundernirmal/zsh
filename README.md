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
| `62-cgm.zsh` | Optional Credential Global Manager backed by Linux Secret Service |
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
- `fzf` 0.52.0 or newer

Optional extras:

- `bat`
- `tree`
- `fd` / `fdfind`
- `jq`
- `secret-tool` from the system's libsecret tools package (`libsecret-tools` on Debian/Ubuntu) for the optional `cgm` credential manager
- `nix`
- `nix-collect-garbage` for Nix cleanup (checked when `nix` is installed)

Missing optional tools keep the shell usable. The config uses runtime checks and either skips the integration or falls back to a simpler command where possible.

The dependency checker reads `fzf --version`, reports both the installed and minimum versions, and fails for a missing, malformed, prerelease, or pre-0.52 build. Its install hint points to a current supported package or the official upstream instructions instead of assuming an older distribution package is sufficient.

## Behavior Notes

- `init.zsh` skips unreadable module files instead of failing shell startup.
- Ordinary `*` and `**/*` globs exclude hidden entries, even if an earlier framework enabled `GLOB_DOTS`; opt in with `*(D)` or `**/*(D)` when hidden matches are intentional.
- External integrations are guarded before use. Startup-time guards use zsh's prehashed `$+commands` table so a missing tool costs no `PATH` walk; guards inside functions use `command -v` so they stay correct when `PATH` changes mid-session.
- `62-cgm.zsh` is not sourced at all when `secret-tool` is absent at startup. When present, sourcing defines functions only: it does not contact Secret Service, unlock a keyring, or read the credential catalogue.
- `40-fzf.zsh` requires stable `fzf` 0.52.0 or newer. The first normal prompt for a new fzf binary validates its version, non-empty generated Zsh code, and syntax before atomically storing a private integration cache under `${XDG_CACHE_HOME:-$HOME/.cache}/zsh/fzf/`. Later prompts match that cache to the executable identity and Zsh version with builtins, verify its ownership and permissions, and source it without launching `fzf` or a validation shell again. Missing, older, malformed, prerelease, and broken installations hard-block only fuzzy workflows and print one actionable diagnostic; non-interactive and `zsh -i -c ...` paths stay silent.
- Within a shell, the `fzf` result is cached by resolved executable path. Every repository picker—including Ctrl+R, Ctrl+T, Alt+C, `fkill`, `fbr`, `zi`, `zhelp`, and interactive `npkg` paths—consults that shared gate before launch, so a different binary selected after a `PATH` change is checked before use. Across shells, changing the fzf file identity, Zsh version, or cache schema automatically creates a newly validated integration cache.
- `50-completion.zsh` intentionally stays small and assumes the main `~/.zshrc` or framework already ran `compinit`.
- `65-help.zsh` registers catalogue data without launching subprocesses. `zhelp` checks the live shell only when invoked.
- `66-compdefs.zsh` registers custom completions only when `compdef` is available. Without `compinit`, it is a silent no-op.
- `upkg` completion covers subcommands, aliases, flags, and comma-separated manager IDs. `npkg` completion reads an existing attribute cache when available but never runs Nix or refreshes the cache from Tab.
- `zhelp` uses fzf only in a suitable interactive terminal with a supported, ready version. Enter queues the selected example for editing and never executes it; pipes, redirects, blocked fzf, `TERM=dumb`, and `--plain` use stable plain text without launching the blocked binary.
- Rich dashboards are used only in real UTF-8 terminals that are at least 60 columns wide and do not set `NO_COLOR`; pipes, redirects, `TERM=dumb`, and narrow terminals get plain output.
- Set `NO_NERD_FONT=1` to keep colors while forcing ASCII-safe icons and bars.
- `path` uses rich indexed output in capable terminals and stays one-entry-per-line in plain contexts.
- `path` preserves empty `PATH` components exactly; rich output labels them as `.`, while plain output keeps the corresponding empty lines.
- `dusage`, `bigfiles`, and `path` sanitize filesystem- and environment-controlled labels before measuring or rendering them. Control bytes become visible escapes such as `\e`, `\n`, or `\x7f`, while ordinary ASCII and printable Unicode remain unchanged.
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

## Credential Global Manager

`cgm` stores API keys and personal access tokens in Linux Secret Service through `secret-tool`, then loads selected values into the current Zsh session when requested. It is defined only when `secret-tool` is available during startup.

```zsh
cgm set OPENAI_KEY             # enter and save a value with hidden input
cgm list                       # list saved names; never retrieve values
cgm env OPENAI_KEY            # export one value into this shell
cgm env OPENAI_KEY GITHUB_PAT # export selected values together
cgm env --all                 # export every saved value
cgm unset OPENAI_KEY          # remove it from this shell only
cgm delete OPENAI_KEY         # delete it from storage and unset it here
```

Credential values never enter command arguments, the local catalogue, completion, `cgm list`, or CGM status output. Secret loading locally disables Zsh execution tracing so an inherited `set -x` cannot print retrieved assignments, then restores the caller's tracing state. The name-only catalogue lives under `${XDG_DATA_HOME:-$HOME/.local/share}/cgm/entries/` with private permissions. `cgm env --all` completes every keyring lookup before exporting anything, so a missing or inaccessible item leaves the environment unchanged.

Credential names follow the conventional uppercase environment format `[A-Z_][A-Z0-9_]*`; CGM also refuses to replace Zsh special, read-only, or non-scalar parameters.

Environment variables are inherited by processes started after loading. They do not alter other open shells or already-running processes, and deleting a credential cannot remove copies already inherited by those processes. Run the environment-changing `env`, `unset`, and `delete` commands directly in the current shell; pipelines, command substitutions, and subshells are rejected to avoid reporting a change that cannot reach the parent shell.

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

`npkg outdated` compares the complete installed store-path set with the outputs selected by the current nixpkgs installable. A difference is reported conservatively as `change available`—it may be an upgrade, downgrade, rebuild, input change, or packaging change. Display versions are informational and never determine status. Missing profile data or failed evaluation produces `unknown`, a partial summary, and a nonzero result; only a complete all-current report may say `Everything is up to date.` Pressing Ctrl+C cancels and reaps only the command's evaluation workers, removes its temporary files, leaves unrelated background jobs alone, and returns status `130`. The `upkg` Nix bridge consumes the stable `current`, `changed`, or `partial` state rather than matching display text.

See [`GUIDE.md`](./GUIDE.md#unified-package-updates-upkg) for the full command reference.

## Verification

After changing aliases, functions, completions, tips, or docs, run:

```sh
zsh -n *.zsh
sh -n scripts/check-deps.sh
zsh scripts/test-init.zsh
zsh scripts/test-functions.zsh
zsh scripts/test-cgm.zsh
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
