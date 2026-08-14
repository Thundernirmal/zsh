# Shared Zsh Configuration Guide

This is the complete user and maintainer reference for the shared configuration in `~/.config/zsh`. For the shortest setup path, start with [`README.md`](./README.md). When documentation and code disagree, the module files are authoritative.

The configuration is a GNU/Linux-focused layer that is sourced by a machine-local `~/.zshrc`. Oh My Zsh, Starship, PATH setup, `compinit`, and host-specific choices remain outside this repository.

## Contents

- [Setup and scope](#setup-and-scope)
- [Module layout](#module-layout)
- [Dependencies](#dependencies)
- [Terminal output modes](#terminal-output-modes)
- [Shell options and history](#shell-options-and-history)
- [Completion](#completion)
- [Command discovery](#command-discovery)
- [Aliases](#aliases)
- [Zoxide and fzf](#zoxide-and-fzf)
- [Function reference](#function-reference)
- [Credential manager: cgm](#credential-manager-cgm)
- [Package manager: upkg](#package-manager-upkg)
- [Nix profile manager: npkg](#nix-profile-manager-npkg)
- [Gotchas and safety boundaries](#gotchas-and-safety-boundaries)
- [Maintenance and verification](#maintenance-and-verification)

## Setup and scope

The repository is expected at `~/.config/zsh` because `init.zsh` loads modules from that fixed location. Add this near the end of `~/.zshrc`:

```zsh
if [ -r "$HOME/.config/zsh/init.zsh" ]; then
  source "$HOME/.config/zsh/init.zsh"
fi
```

Source it after Oh My Zsh when these aliases and functions should override framework defaults. Reload with:

```zsh
exec zsh
```

The shared layer manages:

- Zsh options and history defaults
- aliases, global aliases, and shell functions
- guarded zoxide, fzf, Nix, and Secret Service integrations
- lightweight completion styles and command-specific completions
- terminal UI helpers, `zhelp`, and `tips`

It does not manage:

- framework or plugin installation
- prompt configuration
- machine-local PATH entries
- `compinit` startup
- non-Zsh shells

Unreadable module files are skipped. The optional credential module is skipped entirely when `secret-tool` is absent at startup.

## Module layout

`init.zsh` sets the shared options, then sources modules in this order:

| Module | Responsibility |
|---|---|
| `10-history.zsh` | Shared 100,000-entry history |
| `20-aliases.zsh` | Navigation, file, Git, and weather aliases |
| `30-zoxide.zsh` | Guarded zoxide initialization and `zi` fzf gate |
| `40-fzf.zsh` | fzf validation, cache, theme, previews, and bindings |
| `50-completion.zsh` | Lightweight global completion styles |
| `55-ui-helpers.zsh` | Rich terminal rendering and plain fallbacks |
| `60-functions.zsh` | General helpers, `upkg`, and optional `npkg` |
| `62-cgm.zsh` | Optional Secret Service credential manager |
| `65-help.zsh` | Command catalogue and `zhelp` |
| `66-compdefs.zsh` | Command-aware completion definitions |
| `70-globals.zsh` | Global pipe and redirection aliases |
| `80-tips.zsh` | Hook-free, on-demand tips |

The numbered filenames define load order. `50-completion.zsh` assumes an earlier layer already ran `compinit`; `66-compdefs.zsh` becomes a silent no-op when `compdef` is unavailable.

## Dependencies

Run the checker after installing or changing tools:

```sh
$HOME/.config/zsh/scripts/check-deps.sh
```

### Required for the intended setup

| Command | Used for |
|---|---|
| `zsh` | Shell and module syntax |
| `git` | Git helpers and `fbr` |
| `curl` | `weather`, `headers`, and `myip` |
| `ss` | `ports` |
| `lsd` | Preferred file listing |
| `zoxide` | `z` and `zi` navigation |
| `fzf` 0.52.0+ | Keybindings and every fuzzy picker |

`fzf` must report a stable numeric version. Missing, malformed, prerelease, and older builds fail the dependency check and hard-block fuzzy workflows.

### Optional integrations and fallbacks

| Command | Effect when present | Fallback or absence behavior |
|---|---|---|
| `bat` | Highlighted `cat` alias, `peek`, and file previews | `peek` uses `cat`; fzf previews use `sed` |
| `tree` | `lt` and directory previews when `lsd` is absent | Preview uses `ls`; `lt` is unavailable without `lsd` or `tree` |
| `fd` / `fdfind` | Faster `ff` search | GNU `find` |
| `rg` | Faster `ft` content search | Recursive `grep` |
| `jq` | `npkg refresh`, `npkg outdated`, and Nix pickers | Those workflows are unavailable; basic Nix commands still work |
| `secret-tool` | Defines `cgm` | The entire module is skipped |
| `nix` | Defines `npkg` and the `upkg` Nix backend | Nix commands are absent |
| `nix-collect-garbage` | `upkg clean --only nix` | Nix cleanup reports a failure |
| `unzip`, `unrar`, `7z`, and related tools | Format-specific extraction | `extract` reports the missing tool when used |

Package managers are detected at runtime; they are not setup dependencies. The checker reports the primary optional integrations, while format-specific unpackers and ordinary GNU userland tools are checked only by the workflows that need them.

On Debian and Ubuntu, the distribution may expose `bat` as `batcat`. This repository looks specifically for `bat`, so install a package that provides that command or add a deliberate local wrapper.

## Terminal output modes

Dashboards use the shared Catppuccin-themed renderer only when all of these are true:

- stdout is a terminal
- `TERM` is set and is not `dumb`
- the locale is UTF-8
- the terminal is at least 60 columns wide
- `NO_COLOR` is unset

Pipes, redirects, narrow terminals, non-UTF-8 locales, and dumb terminals receive deterministic plain text.

| Setting | Effect |
|---|---|
| `NO_COLOR=1` | Force shared dashboards to plain, uncoloured output |
| `NO_NERD_FONT=1` | Keep colour but use ASCII-safe icons and bars |
| `zhelp --plain` | Force the stable plain help view |

`NO_COLOR` does not disable fuzzy interaction: the `zhelp` palette stays interactive with colour disabled, while other fzf workflows retain fzf's own options.

`dusage`, `bigfiles`, and `path` sanitize filesystem- or environment-controlled labels before rendering. Named controls such as newline, tab, escape, and bell become visible escapes; other C0, DEL, and C1 bytes use forms such as `\x7f`. Sanitization happens before measuring or truncating, keeps each value on one logical line, and preserves printable Unicode.

Rich output is for people, not parsers. Pipe a command or use its explicit plain option when output will be consumed by another program.

## Shell options and history

### Options set by init.zsh

| Option | State | Behavior |
|---|---|---|
| `AUTO_PUSHD` | on | Every directory change pushes the previous directory |
| `PUSHD_IGNORE_DUPS` | on | The directory stack omits duplicates |
| `PUSHD_SILENT` | on | Stack changes do not print automatically |
| `EXTENDED_GLOB` | on | Enables Zsh glob qualifiers and exclusions |
| `GLOB_DOTS` | off | Ordinary globs exclude leading-dot entries |
| `NUMERIC_GLOB_SORT` | on | `file2` sorts before `file10` |
| `CORRECT` | off | Command spell-correction prompts are disabled |
| `NO_BEEP` | on | The terminal bell is suppressed |
| `INTERACTIVE_COMMENTS` | on | `#` starts a comment on an interactive command line |

Hidden files require an explicit opt-in:

```zsh
print -rl -- *        # visible entries
print -rl -- *(D)     # visible and hidden entries
print -rl -- **/*(D)  # recursive, including hidden entries
```

Useful extended-glob examples:

```zsh
print -rl -- **/*.js
print -rl -- *(.m-1)
print -rl -- *(Lk+100)
```

### Directory stack

```zsh
cd /etc
cd /var/log
dirs -v
cd ~1
popd
```

Because `AUTO_PUSHD` is active, ordinary `cd` participates in this stack.

### History

| Setting | Value or state |
|---|---|
| `HISTFILE` | `~/.zsh_history` |
| `HISTSIZE` / `SAVEHIST` | `100000` |
| `APPEND_HISTORY` | on |
| `SHARE_HISTORY` | on |
| `HIST_IGNORE_ALL_DUPS` | on |
| `HIST_FIND_NO_DUPS` | on |
| `HIST_IGNORE_SPACE` | on |
| `HIST_REDUCE_BLANKS` | on |

History is shared across open shells. Commands beginning with a space are omitted, duplicate search results are suppressed, and redundant spaces are reduced before saving.

## Completion

The global layer is intentionally small:

- case-insensitive filename and command matching
- repeated slash cleanup
- process details for `kill <Tab>`

Command-specific completion covers:

```zsh
upkg <Tab>
upkg --only=<Tab>
npkg <Tab>
cgm env <Tab>
extract <Tab>
ff pattern <Tab>
fkill <Tab>
zhelp <Tab>
```

The definitions understand subcommands, aliases, manager lists, archive suffixes, directories, counts, URLs, and signals. `npkg` completion may read an existing attribute cache, and `cgm` completion reads the name-only catalogue. Pressing Tab never runs Nix, refreshes a cache, contacts Secret Service, or retrieves a credential value.

If the parent `~/.zshrc` has not run `compinit`, command-specific completion is not registered. Heavy menu selection, grouped listings, and global coloured completion lists are intentionally omitted because they made completion noticeably slower.

## Command discovery

### zhelp

`zhelp` searches the repository's public functions and important aliases:

```zsh
zhelp                  # interactive palette, or a plain list
zhelp package          # search all catalogue fields
zhelp upkg             # exact command record
zhelp --all npkg       # include unavailable commands
zhelp --plain file     # stable text for a pipe or log
zhelp --help
```

The default result set hides commands that cannot run in the current shell. `--all` includes them and shows the missing requirement. Exact names show usage, an example, and live availability.

In the palette, Enter places the selected example in the editable command buffer. It does not evaluate or execute the text. Escape closes the palette without changing the buffer. When fzf or a suitable terminal is unavailable, `zhelp` uses plain output and does not invoke a blocked fzf binary.

Sourcing `65-help.zsh` only registers data. Availability checks and subprocesses are deferred until `zhelp` is called.

### tips

`tips` prints one short hint:

```text
tip: Run mkcd <dir> to create and enter a directory
```

It is on demand and installs no prompt or command-cycle hook. Run it again for another hint.

## Aliases

### Navigation

| Alias | Expansion |
|---|---|
| `..` | `cd ..` |
| `...` | `cd ../..` |
| `....` | `cd ../../..` |
| `-` | `cd -` |

### File operations and viewing

| Alias | Behavior |
|---|---|
| `ls` | `lsd`, otherwise a guarded `ls` colour form |
| `ll` | Long listing including hidden entries and readable sizes |
| `la` | Listing including hidden entries |
| `lt` | Tree to depth 3; defined only with `lsd` or `tree` |
| `mkdir` | `mkdir -p` |
| `cp` | `cp -iv` |
| `mv` | `mv -iv` |
| `rm` | `rm -iv` |
| `cat` | `bat --style=numbers --paging=never` when `bat` is present |
| `grep` | Adds `--color=auto` when supported |
| `diff` | Adds `--color=auto` when supported |

### Git extras

| Alias | Expansion |
|---|---|
| `glog` | `git log --oneline --graph --decorate -20` |
| `gpr` | `git pull --rebase` |
| `gun` | `git reset HEAD~1 --soft` |
| `gcount` | `gitcount` |

`gcount` deliberately replaces the conflicting Oh My Zsh alias when this layer is sourced afterward.

### Weather

`weather` runs a concise forecast request over HTTPS:

```zsh
weather
```

It is an alias for `curl --http1.1 -fsSL https://wttr.in` and does not implement a separate location argument.

### Global aliases

Global aliases expand as unquoted tokens anywhere in a command line:

| Alias | Expansion | Example |
|---|---|---|
| `G` | `| grep` | `git log G fix` |
| `L` | `| less` | `git diff L` |
| `W` | `| wc -l` | `ps aux W` |
| `H` | `| head` | `dmesg H` |
| `T` | `| tail` | `cat app.log T` |
| `NE` | `2>/dev/null` | `optional-command NE` |
| `NUL` | `>/dev/null 2>&1` | `noisy-command NUL` |

## Zoxide and fzf

### Zoxide

When `zoxide` is available at startup, its generated Zsh integration defines `z` and `zi`:

```zsh
z projects
z myapp src
z -l
zi projects
```

`z` performs ranked directory jumps. `zi` uses zoxide's interactive picker but is wrapped by the shared fzf version gate.

### fzf requirement and startup

Every fuzzy workflow requires stable `fzf` 0.52.0 or newer. At the first normal prompt for a new fzf executable, the configuration:

1. validates the version;
2. captures non-empty `fzf --zsh` output;
3. syntax-checks the generated Zsh;
4. writes a private integration cache when possible;
5. loads the validated integration and shared theme.

The cache is stored below `${XDG_CACHE_HOME:-$HOME/.cache}/zsh/fzf/` and is keyed by the fzf file identity, Zsh version, and cache schema. A matching cache is reused without launching fzf or a validation shell. Cache files and their directory must be regular, user-owned, non-symlink paths that are not group- or world-writable. A changed executable or PATH selection is validated before use. Removing the `zsh/fzf` directory below the active cache home forces a rebuild.

Missing, old, prerelease, malformed, or broken builds block only fuzzy workflows and print an actionable diagnostic. Non-interactive sourcing and `zsh -i -c ...` remain silent and do not initialize ZLE bindings.

### Keybindings

| Binding | Action |
|---|---|
| Ctrl+T | Select a file or directory and insert its path at the cursor |
| Ctrl+R | Select a history entry and insert it for editing |
| Alt+C | Select a directory and change to it |

Ctrl+T previews directories with `lsd`, `tree`, or `ls`, and files with `bat` or the first 200 lines from `sed`. Ctrl+R uses `?` to toggle its full-command preview.

The shared gate also covers `fkill`, `fbr`, `zi`, the `zhelp` palette, and interactive `npkg` install, find, and remove paths.

## Function reference

### General helpers

| Command | Purpose |
|---|---|
| `extract <archive>` | Unpack a supported archive |
| `mkcd <dir>` | Create a directory and enter it |
| `ff <pattern> [path]` | Find names case-insensitively |
| `ft <pattern> [path]` | Search file contents |
| `peek <file>` | Preview with `bat` or `cat` |
| `headers <url>` | Follow redirects and print HTTP headers |
| `fanprofile` | Show the current Linux platform or ASUS fan profile |
| `dusage [path] [count]` | Rank immediate entries by disk usage |
| `bigfiles [path] [count]` | Rank files recursively |
| `ports` | Show listening sockets and owning processes |
| `myip` | Show the public IP over HTTPS |
| `path` | Print PATH entries |
| `croot` | Change to the current Git repository root |
| `gitcount` | Show non-merge commit counts by contributor |
| `fkill [signal]` | Select processes and send a signal |
| `fbr` | Select a branch; enter its worktree or check it out |

#### extract

Supported suffixes are `.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tar.zst`, `.zip`, `.rar`, `.7z`, `.gz`, `.bz2`, `.Z`, `.tar`, `.tbz2`, `.tgz`, and `.tzst`. Format-specific commands are checked when invoked, so a missing unpacker produces a direct error. Bare `.gz`, `.bz2`, and `.Z` files use their decompressors' normal in-place semantics, which usually remove the compressed input after success.

#### ff and ft

`ff` prefers `fd`, then `fdfind`, then `find`. The fd paths include hidden entries, follow links, and apply a case-insensitive substring glob. The fallback still searches hidden names but follows `find`'s normal symlink behavior.

`ft` prefers `rg` and falls back to recursive, binary-skipping `grep`:

```zsh
ff config .
ft TODO src
```

The ripgrep branch requests coloured matches even when redirected. For machine parsing, call `rg` directly with the desired `--color` mode.

#### fanprofile

`fanprofile` reads the standard Linux `/sys/firmware/acpi/platform_profile` interface when available. On older ASUS/TUF systems it falls back to `fan_boost_mode`:

| Raw value | Profile |
|---|---|
| `0` | `normal` |
| `1` | `overboost` |
| `2` | `silent` |

The command reports state only; it does not change the profile.

#### dusage, bigfiles, and path

`dusage` includes hidden immediate children and defaults to 20 rows. `bigfiles` searches recursively and also defaults to 20. Both keep readable results when another entry or subtree cannot be measured.

`path` preserves empty PATH components. In command lookup, an empty component means the current directory; rich output labels it `.`, while plain output preserves an empty line.

All three commands apply the safe-text contract described in [Terminal output modes](#terminal-output-modes).

#### ports and myip

`ports` uses `ss -tulnp`. Process details can be limited by system permissions. `myip` queries `https://ifconfig.me/ip`. Both use rich dashboards only in capable terminals.

#### fkill and fbr

`fkill` requires a terminal and defaults to `SIGTERM` (`15`), allowing graceful shutdown. Pass `9` only when force is necessary:

```zsh
fkill
fkill 9
```

`fbr` lists local and remote branches by recent commit and previews the log. A local branch registered to another Git worktree has a prominent `[WT]` badge immediately before its branch name and includes the worktree path later in the row; the current checkout is intentionally unmarked. The badge is coloured in capable terminals and remains plain text otherwise. Selecting a marked branch changes the current shell to its worktree path. This also applies when selecting the corresponding remote branch. Other selections keep the checkout behavior: a remote branch creates a tracking branch when no local branch with the same short name exists.

## Credential manager: cgm

`cgm` is defined only when `secret-tool` is present during startup. It stores single-line credential values in the current user's Linux Secret Service collection and exports them only on request.

### Commands

| Command | Behavior |
|---|---|
| `cgm set <name>` | Prompt invisibly and store or replace one value |
| `cgm list` | List saved names without retrieving values |
| `cgm env <name ...>` | Load selected values into this shell |
| `cgm env --all` | Load every catalogued value into this shell |
| `cgm unset <name ...>` | Remove variables from this shell only |
| `cgm delete <name ...>` | Delete stored values and unset local copies |
| `cgm help` | Show concise command help |

Names must match `[A-Z_][A-Z0-9_]*`. CGM rejects Zsh special, read-only, and non-scalar parameters, so values such as `PATH` cannot be replaced accidentally.

### Storage and secrecy

- Values are sent to `secret-tool` through its hidden input path, never as command arguments.
- No plaintext fallback exists.
- Sourcing the module does not contact Secret Service, unlock a keyring, or read the catalogue.
- `cgm list`, completion, status output, and help never retrieve or display values.
- The name-only catalogue lives under `${XDG_DATA_HOME:-$HOME/.local/share}/cgm/entries/`; directories are mode `0700` and empty markers are `0600`.
- Secret loading disables inherited Zsh xtrace locally and restores the caller's state afterward.
- `cgm env --all` retrieves and validates every value before exporting any, so one failure leaves the environment unchanged.

### Shell scope

Loaded variables affect the current shell and processes started from it afterward. They cannot change another terminal, an already-running process, or a parent shell. For that reason, `cgm env`, `cgm unset`, and `cgm delete` reject pipelines, command substitutions, and subshells.

Deleting a credential cannot recall copies already inherited by child processes. If a stored item is deleted but its current-shell variable has become unsafe to unset, `cgm delete` reports the retained variable and returns nonzero.

## Package manager: upkg

`upkg` detects supported managers each time it runs and provides one interface for read-only checks, search, upgrades, and conservative cleanup.

### Detection

The active order is:

1. one distro backend: `paru`, otherwise `pacman`, otherwise `apt`, otherwise `dnf`;
2. `brew`;
3. `flatpak`;
4. Nix through `npkg`;
5. global `npm`.

When both `paru` and `pacman` exist, `paru` is active and `pacman` remains available through `--only pacman`.

### Commands

| Command | Behavior |
|---|---|
| `upkg` | Read-only outdated check |
| `upkg outdated` / `check` / `list` | Same read-only check |
| `upkg search <query>` | Search selected managers |
| `upkg plan` | Preview available upgrades |
| `upkg upgrade` / `up` / `update` | Run selected upgrades |
| `upkg clean` | Remove manager-classified unused or stale data |
| `upkg managers` | Show active managers and alternates |
| `upkg help` | Show command help |

### Flags

| Flag | Behavior |
|---|---|
| `--only <ids>` / `--only=<ids>` | Run only comma-separated manager IDs |
| `--skip <ids>` / `--skip=<ids>` | Exclude comma-separated manager IDs |
| `--sudo` | Authorize privileged distro upgrade or cleanup paths |
| `--dry-run` | Preview upgrades or cleanup |

Supported IDs are `apt`, `dnf`, `pacman`, `paru`, `brew`, `flatpak`, `nix`, and `npm`. `--only` preserves the order supplied by the user.

### Check and upgrade backends

| Manager | Outdated check | Upgrade |
|---|---|---|
| `apt` | `apt list --upgradable` | `apt update`, then `apt full-upgrade` |
| `dnf` | `dnf check-update` | `dnf upgrade --refresh` |
| `pacman` | `pacman -Qu` | `pacman -Syu` |
| `paru` | repo check plus `paru -Qua` | `paru -Syu` |
| `brew` | `brew outdated` | `brew upgrade` |
| `flatpak` | `flatpak remote-ls --updates` | `flatpak update` |
| `nix` | `npkg outdated` | `npkg upgrade` |
| `npm` | `npm outdated -g --depth=0` | `npm update -g` |

`apt`, `dnf`, and `pacman` upgrade paths require root or explicit `--sudo`. Paru also requires the explicit flag, but runs unprefixed so Paru controls privilege escalation. Homebrew and npm always remain unprefixed; an unwritable npm global prefix blocks the upgrade with a user-space setup hint.

The Nix outdated and plan paths require `jq`; Nix upgrade does not. Nix cleanup depends on `nix-collect-garbage`, not `jq`.

`upkg` never auto-confirms native prompts. It does not inject `-y`, `--assumeyes`, `--noconfirm`, or `sudo` without the explicit authorization flag.

### Search behavior

Search accepts multiple words and passes them as separate query arguments:

```zsh
upkg search ripgrep
upkg search ripgrep viewer --only=brew,npm
```

Results are normalized into one table with manager, package, available version, and a cheap native description when available. A no-match result is summarized once. Backend failures name the affected managers, and other managers continue.

Homebrew formulae and casks are queried separately. Broad searches cap follow-up metadata calls at 50 formulae and 50 casks; refine the query when the cap warning appears.

### Cleanup policy

`upkg clean` is mutating. Use `upkg clean --dry-run` first.

| Manager | Unused phase | Cache or store phase |
|---|---|---|
| `apt` | `apt autoremove` | `apt autoclean` |
| `dnf` | `dnf autoremove` | `dnf clean all` |
| `pacman` | remove the non-empty `pacman -Qtdq` orphan array with `pacman -Rs --` | `pacman -Sc` |
| `paru` | `paru -c` | `paru -Sc` |
| `brew` | `brew autoremove` | `brew cleanup` |
| `flatpak` | `flatpak uninstall --unused --user`, then `--system` | handled by the uninstall pruning |
| `nix` | none | `nix-collect-garbage` |
| `npm` | remove explicit keys from `npm cache npx ls` | `npm cache verify` |

Cleanup uses manager-owned commands. It does not directly delete cache directories, application data, project files, lockfiles, virtual environments, build output, user configuration, or Nix profile generations. It does not claim a portable reclaimed-byte total.

Dry-run uses native probes where safe. Steps without a safe unprivileged simulation are printed as `would run` and are not invoked. A preview never calls `sudo` or requires `--sudo`.

Nix cleanup removes unreachable store objects without generation-deletion flags, preserving rollback history. Flatpak cleanup does not pass `--delete-data`. npm cleanup never uses the keyless, forced whole-cache removal form; old npm releases without the npx cache subcommands still run `npm cache verify` and report a partial result.

Flatpak updates and system cleanup may request authorization through polkit. User and system cleanup are attempted as separate phases.

### Results and exit status

Multi-manager runs continue after a backend fails:

| State | Meaning |
|---|---|
| `up to date` | A complete outdated check found no changes |
| `updates available` | A complete check found changes |
| `cleaned` | Every requested cleanup phase succeeded |
| `planned` | A cleanup preview completed successfully |
| `partial` | Some phases succeeded and others failed |
| `failed` | Required work or a preview probe failed |
| `blocked` | Authorization or a required capability was missing |
| `skipped` | A filter intentionally omitted the manager |

A partial, failed, or blocked selected backend makes the aggregate command return nonzero.

Distribution outdated checks use existing local metadata; `upkg` does not refresh it automatically. On Arch-family systems, an empty status-1 repo or AUR check is treated as no updates. A failed Paru repo check can still show AUR results but leaves the backend failed.

### Examples

```zsh
upkg
upkg search ripgrep
upkg managers
upkg managers --only=npm,flatpak
upkg plan --only=brew,npm
upkg upgrade --sudo --only=apt
upkg clean --dry-run
upkg clean --only=brew,npm
upkg clean --sudo --only=apt
```

## Nix profile manager: npkg

`npkg` is defined only when `nix` is available. It wraps the current `nix profile` with shorter commands and optional pickers while enabling the required `nix-command flakes` features.

### Commands

| Command | Behavior |
|---|---|
| `npkg add <pkg ...>` / `install` / `i` | Add packages |
| `npkg add` | Open the install picker |
| `npkg find [query]` / `pick` / `fzf` | Open a seeded install picker |
| `npkg search <query>` / `s` | Plain nixpkgs search |
| `npkg list` / `ls` | List the current profile |
| `npkg remove <pkg ...>` / `rm` / `uninstall` / `delete` | Remove profile elements |
| `npkg remove` | Open the removal picker |
| `npkg outdated` / `check` / `diff` | Compare installed and evaluated outputs |
| `npkg refresh` | Rebuild the attribute-name cache |
| `npkg upgrade [pkg ...]` / `up` / `update` | Upgrade all or selected elements |
| `npkg help` | Show help |

Bare install names become `nixpkgs#<name>`. Flake references, paths, and arguments beginning with `-` pass through without that expansion. Use `nix` directly for advanced flags not represented by the wrapper.

### Picker cache and dependencies

`npkg refresh` and `npkg outdated` require `jq`. Interactive add, find, and remove also require a real terminal and supported fzf.

The attribute cache lives under `${XDG_CACHE_HOME:-$HOME/.cache}/npkg/` and refreshes on install or find picker use after 24 hours. Building it evaluates nixpkgs and can take time or require network access. Tab completion may read an existing cache but never creates or refreshes it. Picker previews evaluate package metadata to show description, version, and homepage; they move below the list when the terminal is narrower than 100 columns.

### Outdated semantics

`npkg outdated` compares the complete installed store-path set for each active nixpkgs profile element with the output set selected by the currently evaluated installable:

| State | Meaning |
|---|---|
| `current` | Installed and evaluated output sets match |
| `change available` | The sets differ |
| `unknown` | Profile data or evaluation is incomplete |

A change is not necessarily an upgrade. It can be a downgrade, rebuild, changed input, output-selection change, or packaging change. Display versions are informational and never determine state.

A complete report containing current or changed rows returns zero. Any unknown row produces a partial summary and nonzero status; only a complete all-current report may say `Everything is up to date.` A profile with no active nixpkgs elements is a complete zero-count result.

Ctrl+C stops and reaps only the command's recorded evaluation workers, removes its temporary files, preserves unrelated background jobs, and returns `130`. The `upkg` Nix bridge consumes the stable internal `current`, `changed`, or `partial` state rather than matching display text.

## Gotchas and safety boundaries

These are the cross-cutting rules most likely to surprise a new user:

1. **The install path is fixed.** `init.zsh` loads `$HOME/.config/zsh/*.zsh`. A clone elsewhere needs a symlink or a deliberate code change.
2. **Source order matters.** Source this layer after frameworks when its aliases should win. `~/.zshrc` itself is not versioned here.
3. **Common commands are redefined.** `mkdir`, `cp`, `mv`, and `rm` are aliases. Use `command <name>` to bypass an alias deliberately.
4. **Interactive aliases are not a backup.** Later flags such as `-f`, direct binary calls, scripts, and non-interactive shells can bypass prompts. Review destructive commands and keep real backups.
5. **Ordinary globs exclude dotfiles.** Use `*(D)` only when hidden entries are intentional. In contrast, `ff` and `dusage` explicitly include hidden entries by design.
6. **Leading-space history is convenience, not secret storage.** `HIST_IGNORE_SPACE` reduces accidental persistence but does not protect process arguments, logs, terminal capture, or already-shared history.
7. **Global aliases expand anywhere.** Unquoted tokens such as `G` or `NUL` can change a command far from its first word. Quote literal occurrences.
8. **An empty PATH component means the current directory.** `path` preserves and exposes it because silently normalizing PATH would change command lookup.
9. **Completion needs compinit.** Without `compdef`, command-specific completion quietly does nothing.
10. **fzf is all-or-nothing at 0.52.0+.** An unsupported build blocks fuzzy workflows instead of enabling a reduced theme or partial bindings. Plain `zhelp` remains available.
11. **Ctrl+R does not execute the selection.** It inserts history into the command buffer for review and editing.
12. **`fkill` defaults to SIGTERM.** `fkill 9` is a force-kill and should be the exception.
13. **CGM is startup-optional.** Installing `secret-tool` mid-session does not define `cgm` until the module is sourced again or the shell restarts.
14. **CGM changes only the current shell.** Run `env`, `unset`, and `delete` directly, not through a pipe, command substitution, or subshell. Deletion cannot revoke values inherited by existing processes.
15. **`upkg` is not entirely read-only.** The default, `outdated`, `search`, and `plan` are read-only; `upgrade` and `clean` mutate manager state. Preview cleanup with `clean --dry-run`.
16. **`--sudo` authorizes but does not auto-confirm.** Native package-manager and polkit prompts remain authoritative.
17. **Outdated data can be stale.** Distro checks use local metadata, and `npkg` reports output identity—not version ordering.
18. **Partial package results fail.** `upkg` continues other managers but returns nonzero for partial, failed, or blocked selected backends. `npkg` returns nonzero when any row is unknown.
19. **Rich output is presentation.** Use a pipe, redirect, `NO_COLOR`, or an explicit plain option for stable machine-readable text.
20. **The target platform is GNU/Linux.** `ss`, GNU flags, sysfs profile paths, and several `find`/`du` flows are Linux-oriented.
21. **Network helpers contact external services.** `weather` requests `wttr.in`, `myip` requests `ifconfig.me`, and `headers` contacts the URL supplied by the user.
22. **Automation must load the layer explicitly.** Aliases and functions are interactive shell features; scripts should call real binaries or source `init.zsh` inside Zsh.

## Maintenance and verification

### Documentation ownership

Keep each surface at one level:

| Surface | Owns |
|---|---|
| `README.md` | Purpose, five-minute setup, requirements summary, and links |
| `GUIDE.md` | Full behavior, examples, dependencies, safety boundaries, and gotchas |
| `zhelp` catalogue | One-line command discovery, usage, example, and availability |
| `80-tips.zsh` | Short, actionable reminders only |
| `docs/specs/` | Historical decisions and acceptance criteria |

When user-facing behavior changes, update every affected surface without copying long explanations between them.

### Editing rules

- Startup-time dependency guards use `(( $+commands[tool] ))`.
- Guards inside functions use `command -v ... >/dev/null 2>&1` so PATH changes and test stubs are visible.
- Keep external integrations guarded and preserve fallbacks.
- Keep `50-completion.zsh` lightweight and `80-tips.zsh` hook-free.
- Never add a plaintext CGM fallback, value-retrieving completion, or `eval`-based secret export.
- Treat aliases in `20-aliases.zsh` as high-impact changes.

### Required checks

Run these in order:

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

The environment check is optional because it reflects the current machine rather than repository correctness:

```sh
$HOME/.config/zsh/scripts/check-deps.sh
```

For a full stable-release manual pass, use the ignored `qa-features.csv` checklist described in [`AGENTS.md`](./AGENTS.md).
