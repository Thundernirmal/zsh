# Zsh Configuration Guide

Your zsh setup is built in two layers: **Oh My Zsh** in `~/.zshrc` handles the framework, plugins, and prompt integrations, while the shared config in `~/.config/zsh/` adds the portable behavior that is actually versioned in this repo.

```
~/.zshrc                    → OMZ, Starship, plugins, PATH
~/.config/zsh/init.zsh      → Entry point that loads everything below
├── 10-history.zsh          → History settings (100k entries, shared across sessions)
├── 20-aliases.zsh          → Aliases for ls, git, navigation, safety, network
├── 30-zoxide.zsh           → Smart directory jumping
├── 40-fzf.zsh              → Fuzzy finder with previews
├── 50-completion.zsh       → Tab completion tuning (case-insensitive, process completion)
├── 55-ui-helpers.zsh       → Shared Catppuccin Mocha dashboard helpers, title lines, and consistent section separators
├── 60-functions.zsh        → Shell functions (extract, search, kill, fanprofile, git helpers, upkg, npkg, etc.)
├── 65-help.zsh             → Searchable command catalogue and zhelp palette
├── 66-compdefs.zsh          → Command-aware completion for custom functions
├── 70-globals.zsh          → Global aliases (pipe shortcuts)
└── 80-tips.zsh             → On-demand tips function
```

---

## Table of Contents

1. [Zsh Options](#zsh-options)
2. [History](#history)
3. [Aliases](#aliases)
4. [Zoxide — Smart Navigation](#zoxide--smart-navigation)
5. [FZF — Fuzzy Finder](#fzf--fuzzy-finder)
6. [Tab Completion](#tab-completion)
7. [Searchable Help](#searchable-help)
8. [Shell Functions](#shell-functions)
9. [Global Aliases](#global-aliases)
10. [Unified Package Updates (upkg)](#unified-package-updates-upkg)
11. [Nix Package Manager (npkg)](#nix-package-manager-npkg)
12. [Tips Function](#tips-function)
13. [OMZ Plugins](#omz-plugins)
14. [Starship Prompt](#starship-prompt)
15. [Quick Reference Card](#quick-reference-card)

---

## Zsh Options

This shared layer intentionally targets GNU/Linux environments. A few commands and flags below assume GNU userland tools such as `ss`, GNU `ls`/`grep` color flags, and standard Linux networking utilities.

These options are set in `init.zsh` and change how zsh behaves day-to-day.

### AUTO_PUSHD + PUSHD_SILENT + PUSHD_IGNORE_DUPS
Every `cd` pushes the previous directory onto a stack. Navigate back with `popd` or jump to any entry with `cd ~2`.

```zsh
cd /etc          # silently pushes ~/ onto stack
cd /var/log      # pushes /etc onto stack
dirs -v          # show the stack:
#  0  /var/log
#  1  /etc
#  2  ~
cd ~1            # jump to /etc
popd             # remove top entry, cd to next
```

### EXTENDED_GLOB
Powerful glob patterns for file matching.

```zsh
ls **/*.js              # all .js files recursively
ls *.^(log|tmp)         # all files except .log and .tmp
ls *(.m-1)              # files modified in last day
ls *(Lk+100)            # files larger than 100KB
```

### GLOB_DOTS is disabled
Ordinary globs keep zsh's conventional safety boundary: `*` and `**/*` exclude leading-dot entries. `init.zsh` explicitly disables `GLOB_DOTS`, so this remains true even if a framework enabled it earlier. Opt in only where hidden matches are intentional with the `(D)` qualifier or a command whose contract includes hidden files.

```zsh
print -rl -- *        # visible entries only
print -rl -- *(D)     # visible and hidden entries
print -rl -- **/*(D)  # recursive, including hidden entries
ls -A                 # ls explicitly includes hidden entries
```

### NUMERIC_GLOB_SORT
Numbers in filenames sort numerically, not alphabetically.

```zsh
# Without: file1 file10 file2 file20 file3
# With:    file1 file2 file3 file10 file20
```

### CORRECT is disabled
This shared layer explicitly turns command spell-correction off, even if a higher-level config such as `~/.zshrc` enabled it earlier.

### NO_BEEP
The terminal bell is silenced. No audible or visible bell when hitting errors or the end of a completion list.

### INTERACTIVE_COMMENTS
Allows `#` comments on the command line.

```zsh
git commit -m "fix bug" # I'll explain this later
```

---

## History

Configured in `10-history.zsh`.

| Setting | Value | What it does |
|---|---|---|
| `HISTSIZE` | 100000 | Commands kept in memory |
| `SAVEHIST` | 100000 | Commands saved to disk |
| `APPEND_HISTORY` | on | New sessions append, don't overwrite |
| `SHARE_HISTORY` | on | History shared across all open terminals |
| `HIST_IGNORE_ALL_DUPS` | on | Remove older duplicates from the entire history |
| `HIST_FIND_NO_DUPS` | on | `Ctrl+R` shows each command only once |
| `HIST_IGNORE_SPACE` | on | Commands starting with a space are omitted (good for secrets) |
| `HIST_REDUCE_BLANKS` | on | Strip extraneous spaces from commands before saving |

**Practical benefit:** Open two terminals, run a command in one, immediately search for it with `Ctrl+R` in the other.

---

## Aliases

### Directory Navigation

| Alias | Expands to | Use |
|---|---|---|
| `..` | `cd ..` | Go up one level |
| `...` | `cd ../..` | Go up two levels |
| `....` | `cd ../../..` | Go up three levels |
| `-` | `cd -` | Go to previous directory |

```zsh
..       # one level up
...      # two levels up
-        # go back to where you were before
```

### Safety

| Alias | Expands to | What it does |
|---|---|---|
| `mkdir` | `mkdir -p` | Creates parent dirs automatically |
| `cp` | `cp -iv` | Verbose + ask before overwrite |
| `mv` | `mv -iv` | Verbose + ask before overwrite |
| `rm` | `rm -iv` | Verbose + ask before delete |

```zsh
mkdir a/b/c/d    # works even if a, b, c don't exist
cp file.txt /tmp # tells you what it copied, asks if /tmp/file.txt exists
```

### File Listing (lsd or fallback)

If `lsd` is installed (recommended), you get icons and colors. If not, falls back to standard `ls`.

| Alias | What it does |
|---|---|
| `ls` | Color/icon listing |
| `ll` | Long listing, all files, human-readable sizes |
| `la` | All files (including hidden) |
| `lt` | Tree view, 3 levels deep |

```zsh
ls    # quick listing
ll    # detailed view
la    # show hidden files too
lt    # tree structure
```

### File Viewing

| Alias | Expands to |
|---|---|
| `cat` | `bat` (if installed) — syntax-highlighted output |
| `grep` | `grep --color=auto` |
| `diff` | `diff --color=auto` |

### Network & System

| Command | What it does |
|---|---|
| `ports` | Show all listening ports and their processes |
| `myip` | Show your public IP address over HTTPS |
| `weather` | Show weather forecast over HTTPS |

```zsh
ports     # what's listening on your machine
myip      # your public IP
weather   # current weather + 3-day forecast
```

`ports` and `myip` render Catppuccin Mocha cards in rich terminals. They stay plain and pipe-friendly when stdout is not a TTY, when `TERM=dumb`, when `NO_COLOR=1`, or when the terminal is narrower than 60 columns. In the rich `ports` dashboard, normal UDP listeners keep their native `UNCONN` state without being treated as warnings.

Set `NO_NERD_FONT=1` to keep the dashboards colorized while forcing ASCII-safe icons and bar characters. This is useful on terminals that support color but do not have a Nerd Font installed.

### Git Extras

The OMZ `git` plugin already provides `gs`, `gc`, `gp`, `gd`, `gco`, `gb`, etc. These fill the gaps:

| Alias | Expands to | What it does |
|---|---|---|
| `glog` | `git log --oneline --graph --decorate -20` | Visual log, last 20 commits |
| `gpr` | `git pull --rebase` | Pull with rebase (cleaner history) |
| `gun` | `git reset HEAD~1 --soft` | Undo last commit, keep changes staged |
| `gitcount` | shell function | Contributor commit counts for the current repo, with a friendly message before the first commit |
| `gcount` | alias to `gitcount` | Compatibility shortcut that overrides the conflicting OMZ `gcount` alias |

```zsh
glog      # pretty commit graph
gpr       # pull without merge commits
gun       # oops, undo that last commit
gitcount  # who contributed what
gcount    # same helper, compatibility shortcut
```

---

## Zoxide — Smart Navigation

Zoxide learns where you go and lets you jump there instantly.

### Basic usage

```zsh
z projects          # jump to the most likely "projects" directory
z myapp src         # jump to a path containing both "myapp" and "src"
z -i                # interactive selection (uses fzf)
zi                  # same as above (shorter)
```

### How it works

Zoxide tracks every directory you visit. The more you use a path, the higher it ranks.

```zsh
cd ~/projects/myapp/src/components
# zoxide remembers this

# Later, from anywhere:
z components    # takes you right back
```

### Useful zoxide commands

```zsh
z foo           # jump to best match for "foo"
z -l            # list all known directories, ranked
z -r foo        # jump by frequency (most visited)
z -t foo        # jump by recency (most recent)
zi              # interactive picker with fzf
```

---

## FZF — Fuzzy Finder

The shared `fzf` layer is guarded carefully: the bindings only initialize when `fzf` exists, the shell is interactive, and `ZSH_EXECUTION_STRING` is empty. That keeps `zsh -i -c ...` startup paths from tripping `zle` warnings.

### Ctrl+T — Insert file/directory

Press `Ctrl+T` to fuzzy search files and insert the selected path at your cursor.

```zsh
cat <Ctrl+T>    # opens fuzzy finder, select a file, path is inserted
```

The preview pane (right side) shows:
- **Directories:** tree view of contents
- **Files:** first 200 lines with syntax highlighting via `bat`, or a `sed -n 1,200p` fallback in the preview pane when `bat` is unavailable (the `peek` function falls back to `cat` separately)

### Ctrl+R — Search history

Press `Ctrl+R` to fuzzy search your command history.

```zsh
<Ctrl+R>        # opens history search
# Type to filter: "docker run"
# ? to toggle preview of the full command
# Enter to select and run
# Esc to cancel
```

### Alt+C — Change directory

Press `Alt+C` to fuzzy search directories and cd into one.

```zsh
<Alt+C>         # opens directory picker
# Type to filter directories
# Enter to cd into selected directory
```

### fkill function

Fuzzy select one or more processes and send a signal. This helper requires both `fzf` and an interactive terminal.

```zsh
fkill           # opens process picker
fkill 9         # force termination with SIGKILL
```

By default `fkill` sends `SIGTERM` (`15`) so processes can shut down cleanly. Pass the signal number with or without a leading `-`; use `9` only when force is required.

The picker uses matching pointer and marker glyphs when Nerd Fonts are enabled.

---

## Tab Completion

Configured in two layers. `50-completion.zsh` keeps the global styles lightweight, while `66-compdefs.zsh` adds command-specific definitions after the custom functions load. OMZ / `compinit` still provides the completion system itself; if `compdef` is unavailable, the command-specific module silently does nothing.

### Case-insensitive matching

Tab completion ignores case for names and paths.

```zsh
cd ~/dow<Tab>    # completes to ~/Downloads
vim readme<Tab>  # completes to README.md
```

### Squeeze slashes

Extra slashes are cleaned up during path completion automatically.

### Process completion for `kill`

```zsh
kill <Tab>    # shows PID, user, command for each process
```

### Custom command completion

The shared command suite completes arguments according to what each function accepts:

```zsh
upkg <Tab>                 # commands and aliases
upkg --only=<Tab>          # apt, dnf, pacman, paru, brew, flatpak, nix, npm
upkg --only=apt,<Tab>      # remaining manager IDs in the same argument
npkg <Tab>                 # commands and aliases, when npkg is available
extract <Tab>              # supported archive types only
ff pattern <Tab>           # search root directories
fkill <Tab>                # signal names and numbers
```

`npkg add` and picker-oriented `npkg find` completion may read attribute names from files already under `${XDG_CACHE_HOME:-~/.cache}/npkg/`. A missing cache produces no package candidates. Tab never runs `nix search`, `nix eval`, `nix profile list`, a cache refresh, or a network lookup.

File, directory, numeric-count, URL, signal, and no-argument functions also suppress irrelevant fallback completion where appropriate. All completion work is deferred until Tab is pressed, and sourcing the module launches no subprocesses.

> **Note:** Heavy global completion UI features such as menu selection, colored listings, and grouped results remain intentionally disabled because they made completion lists noticeably slower. The concise descriptions attached to custom commands do not enable those global UI layers. Add any heavier presentation locally in `~/.zshrc` after sourcing `init.zsh`.

---

## Searchable Help

`65-help.zsh` provides a central catalogue for every custom command and the important aliases in this repository. Each record includes a category, description, usage, editable example, dependency label, and current availability.

```zsh
zhelp                  # open the palette, or list available commands in plain mode
zhelp package          # search names, categories, descriptions, usage, and examples
zhelp upkg             # show full help for an exact command
zhelp --all npkg       # include unavailable commands and explain requirements
zhelp --plain file     # force deterministic plain text
zhelp --help           # show zhelp usage
```

In a real terminal with fzf available, the palette shows command, category, and summary rows with a detail preview. Enter closes the picker and places the selected example in the editable command buffer; it never runs the example. Escape cancels successfully without changing the buffer. `NO_COLOR=1` keeps the picker interactive but removes colour, while `NO_NERD_FONT=1` uses ASCII markers.

When fzf is missing, stdin or stdout is redirected, `TERM=dumb`, or `--plain` is passed, `zhelp` prints a stable uncoloured table instead. Exact command records remain detailed in either mode. Commands unavailable in the live shell are hidden by default and included with `--all`.

Module sourcing registers data only. Availability checks and fzf launch only after `zhelp` is called, so the catalogue adds no startup subprocesses.

---

## Shell Functions

### extract — Unpack any archive

```zsh
extract archive.tar.gz
extract archive.zip
extract archive.7z
extract archive.tar.xz
```

Supports: `.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tar.zst`, `.zip`, `.rar`, `.7z`, `.gz`, `.tar`, `.tbz2`, `.tgz`, `.tzst`, `.bz2`, `.Z`

For single-format tools, `extract` checks the real binary at runtime and fails loudly if it is missing. For example, `.zip` needs `unzip`, `.rar` needs `unrar`, `.7z` needs `7z`, and bare `.gz` / `.bz2` / `.Z` files need `gunzip` / `bunzip2` / `uncompress`.

### mkcd — Create and enter directory

```zsh
mkcd new-project
# Creates "new-project" and cd's into it in one step
```

### ff — Find files by name

Uses `fd` first, then `fdfind`, and finally falls back to `find`. The second argument is an optional search root.

```zsh
ff config        # find all files with "config" in the name
ff ".js" src     # find .js files under src/
```

### ft — Find text in files

Uses `ripgrep` (rg) if installed, falls back to `grep`.

```zsh
ft "TODO"           # search for "TODO" in all files under .
ft "function" src   # search for "function" under src/
```

### peek — Preview a file

Uses `bat` for syntax highlighting if available, falls back to `cat`.

```zsh
peek config.json
peek script.sh
```

### fanprofile — Show current laptop performance profile

Uses the standard Linux `platform_profile` interface when it exists, and falls back to ASUS `fan_boost_mode` on older ASUS/TUF laptops.

In rich terminals it renders a status card with a profile badge, source details, and available choices when the kernel exposes them.

```zsh
fanprofile
# normal (fan_boost_mode=0)
```

On ASUS/TUF systems using `fan_boost_mode`, the values map as:

| Raw value | Profile |
|---|---|
| `0` | `normal` |
| `1` | `overboost` |
| `2` | `silent` |

### headers — Quick HTTP header check

```zsh
headers https://example.com  # follows redirects and prints response headers
```

### dusage — Disk usage of top-level directory entries

Shows the largest immediate children of a directory, including dotfiles, sorted by size.

In rich terminals it renders a responsive dashboard with icons, sizes, and proportional bars. In pipes or narrow terminals it prints a sorted size-and-path list. If one child is unreadable, `dusage` still shows the readable entries instead of failing the whole listing. Requested targets and entry paths are sanitized before measurement or styling: controls appear as visible escapes such as `\e`, `\n`, and `\x7f`, so a hostile filename cannot inject terminal behavior or create a second output row. Printable Unicode is preserved.

```zsh
dusage           # top 20 largest items, human-readable
dusage /var 10   # top 10 items in /var
```

### bigfiles — Largest files in tree

In rich terminals it renders a responsive dashboard with truncated paths and proportional bars. In pipes or narrow terminals it prints a recursive size-and-path list. If one subtree is unreadable, `bigfiles` still reports the readable files it can inspect. Its scan is NUL-delimited, and requested targets plus file paths use the same safe-text contract as `dusage`. Truncation is calculated after escaping and never splits a visible escape token.

```zsh
bigfiles         # top 20 largest files recursively
bigfiles /home 5 # top 5 largest files under /home
```

### croot — Jump to git repo root

```zsh
cd ~/projects/myapp/src/components
croot            # jumps to ~/projects/myapp
```

### path — Inspect PATH entries

```zsh
path    # shows each PATH entry
```

In rich terminals it renders a compact dashboard with indexed entries. In pipes, redirects, `TERM=dumb`, `NO_COLOR=1`, or narrow terminals, it prints one PATH entry per line. Empty components, which make the current directory part of command lookup, are preserved; rich output labels them as `.`, while plain output represents them as empty lines. Every environment-controlled entry is sanitized before rendering, so C0, DEL, and C1 controls are visible text rather than active terminal bytes.

### fbr — Fuzzy-pick and checkout a git branch

Requires `fzf` and an interactive terminal. Shows local and remote branches sorted by most recent commit, with a log preview.

```zsh
fbr              # opens branch picker and checks out the selected branch
```

If you pick a remote branch that is not checked out locally yet, `fbr` creates a tracking branch automatically.

The picker inherits your `FZF_DEFAULT_OPTS` theme (Catppuccin Mocha when configured globally) and adds matching pointer and marker glyphs when Nerd Fonts are enabled.

---

## Global Aliases

These work **anywhere** in a command line, not just at the start.

| Global Alias | Expands to | Example |
|---|---|---|
| `G` | `\| grep` | `git log G "fix"` |
| `L` | `\| less` | `cat file.txt L` |
| `W` | `\| wc -l` | `ps aux W` |
| `H` | `\| head` | `dmesg H` |
| `T` | `\| tail` | `cat log.txt T` |
| `NE` | `2>/dev/null` | `find / NE` |
| `NUL` | `>/dev/null 2>&1` | `make test NUL` |

### Real-world examples

```zsh
# Search git log for "fix" and page through results
git log G "fix" L

# Count how many processes are running
ps aux W

# Suppress errors from find
find / -name "secret" NE

# Run a command completely silently
noisy-command NUL

# Chain multiple globals
docker ps G "running" W
```

**Tip:** After typing a command with a global alias, press `Space` then `Ctrl+X G` (expand-global) to see what it will expand to before running.

---

## Unified Package Updates (upkg)

Defined in `60-functions.zsh`. `upkg` is a single entrypoint for checking, searching, upgrading, and conservatively cleaning the package managers available on the current machine. Runtime detection is the source of truth: there is no bootstrap variable to keep in sync, and `upkg` only uses managers that `command -v` can see right now.

Detection order is:

1. distro backend: `paru` when present, otherwise `pacman`, otherwise `apt`, otherwise `dnf`
2. `brew`
3. `flatpak`
4. `nix` via the existing `npkg` wrapper
5. global `npm`

If both `paru` and `pacman` are installed, `paru` is the default Arch-family backend and `pacman` remains available only through `--only pacman`.

### Commands

| Command | What it does |
|---|---|
| `upkg` | Show outdated packages across detected managers |
| `upkg outdated` | Same as the default read-only check |
| `upkg check` | Alias for `outdated` |
| `upkg list` | Alias for `outdated` |
| `upkg search <query>` | Search detected managers for package names and available versions |
| `upkg upgrade` | Run upgrades across selected managers |
| `upkg up` | Alias for `upgrade` |
| `upkg update` | Alias for `upgrade` |
| `upkg plan` | Preview available upgrades without changing packages |
| `upkg clean` | Remove packages and manager-owned cache data the selected backends classify as unused, stale, or unreachable |
| `upkg managers` | Show detected managers; filtered selections appear in execution order first |
| `upkg help` | Show usage help |

### Flags

| Flag | What it does |
|---|---|
| `--only <list>` / `--only=<list>` | Include only the comma-separated manager IDs you name |
| `--skip <list>` / `--skip=<list>` | Exclude the comma-separated manager IDs you name |
| `--sudo` | Explicitly authorize privileged distro upgrade and cleanup paths; native prompts are still authoritative |
| `--dry-run` | Preview upgrades or cleanup without changing packages or manager state |

Supported manager IDs: `apt`, `dnf`, `pacman`, `paru`, `brew`, `flatpak`, `nix`, `npm`.

### Backends

| Manager | Outdated command | Upgrade command | Notes |
|---|---|---|---|
| `apt` | `apt list --upgradable` | `apt update && apt full-upgrade` | Upgrade path is blocked unless already root or `--sudo` is passed |
| `dnf` | `dnf check-update` | `dnf upgrade --refresh` | `dnf check-update` exit `100` means updates are available |
| `pacman` | `pacman -Qu` | `pacman -Syu` | Default only when `paru` is absent |
| `paru` | `pacman -Qu` plus `paru -Qua` | `paru -Syu` | Preferred on Arch-family systems; preview includes repo and AUR updates, and still shows AUR results if the repo check fails; upgrade requires explicit `--sudo` opt-in but still runs unprefixed |
| `brew` | `brew outdated` | `brew upgrade` | Homebrew backend stays unprefixed; formulae and casks follow whatever Homebrew manages on that host |
| `flatpak` | `flatpak remote-ls --updates` | `flatpak update` | Checks both user and system installations |
| `nix` | `npkg outdated` | `npkg upgrade` | Reuses the existing `npkg` wrapper instead of duplicating Nix logic |
| `npm` | `npm outdated -g --depth=0` | `npm update -g` | Upgrade path is user-space only; `upkg` will not suggest `sudo npm` |

### Cleanup backends

`upkg clean` is mutating. Within each manager it removes unused packages before cleaning caches, so artifacts made stale by the first phase can become candidates in the second. Each manager owns the decision about what is safe to remove; `upkg` does not delete cache directories itself.

| Manager | Unused-package phase | Cache/store phase | Safety boundary |
|---|---|---|---|
| `apt` | `apt autoremove` | `apt autoclean` | Root or `--sudo` is required; `autoclean` preserves archives APT still considers downloadable |
| `dnf` | `dnf autoremove` | `dnf clean all` | Root or `--sudo` is required; DNF owns removal of cached packages, metadata, and temporary repository files |
| `pacman` | Query `pacman -Qtdq`, then pass a non-empty orphan array to `pacman -Rs --` | `pacman -Sc` | Root or `--sudo` is required; avoids `-Rn`, `-Scc`, and automatic confirmation |
| `paru` | `paru -c` | `paru -Sc` | Requires explicit `--sudo` authorization but runs unprefixed so Paru controls its privilege helper; the default Paru route does not also run Pacman |
| `brew` | `brew autoremove` | `brew cleanup` | Runs in Homebrew user space without `--prune=all` or `--scrub` |
| `flatpak` | `flatpak uninstall --unused --user`, then `flatpak uninstall --unused --system` | Included in Flatpak's uninstall pruning | Keeps application data and allows normal polkit authentication for the system installation |
| `nix` | None | `nix-collect-garbage` | Deletes only unreachable store objects; never deletes profile generations or the `npkg` attribute cache |
| `npm` | None | List with `npm cache npx ls`, remove the returned keys with `npm cache npx rm <key>...`, then run `npm cache verify` | Runs in user space, uses npm rather than raw directory deletion, and never passes `--force` |

Cleanup does not delete application data such as `~/.var/app`, project-local `node_modules`, lockfiles, virtual environments, build output, user-edited package configuration, or Nix rollback generations. It also does not inject `-y`, `--assumeyes`, `--noconfirm`, or an equivalent response to native prompts. Backend output can report its own reclaimed space, but `upkg` does not fabricate a cross-manager byte total.

Dry-run cleanup uses native read-only probes where available: APT simulation for unused packages, `dnf --cacheonly repoquery --unneeded`, `pacman -Qtdq`, both Homebrew `--dry-run` forms, `nix-collect-garbage --dry-run`, and `npm cache npx ls`. DNF's cache-only mode prevents a metadata refresh. Steps without a safe unprivileged simulation—including APT cache cleanup—are printed as `would run` and are not invoked. Privileged commands are displayed with `sudo` context when needed, but a preview never calls `sudo` or requires `--sudo`.

If `nix-collect-garbage` is unexpectedly unavailable, Nix cleanup fails with an installation/PATH hint rather than deleting store paths directly. npm releases that require `--force` for a keyless npx-cache removal are supported by listing and passing explicit cache keys instead. Older npm releases may reject the npx cache subcommands entirely; `upkg` still verifies and garbage-collects the normal npm cache, reports npm as `partial`, returns nonzero overall, and recommends upgrading npm.

### Behavior notes

- `upkg` with no arguments is read-only and does not refresh package metadata automatically.
- `upkg search <query>` is also read-only and searches the active/default managers unless you narrow it with `--only` or `--skip`; Homebrew formulae and casks are queried separately so the search path matches current `brew` flag handling. Results are aggregated into one compact table with a `Manager` column, no-match output is summarized once across the selected managers, backend failures are summarized with the failing manager IDs, multi-word searches are passed to backends as separate query arguments, and `upkg search --help` shows usage.
- In rich terminals, `upkg search` prints a transient progress line with a distinct progress icon and manager icon while each backend is running; simplified text equivalents would read `Searching npm...` or `Searching Homebrew (formulae)...`, and the real line is cleared before the compact table is rendered.
- `upkg plan`, `upkg --dry-run`, and `upkg upgrade --dry-run` use the read-only outdated checks to preview what would be considered for upgrade. `upkg clean --dry-run` instead previews the cleanup phases described above.
- In rich terminals, every valid `upkg` command path—including `upkg help`, `upkg upgrade`, and `upkg clean`—uses the same shared dashboard treatment as the rest of the repo, plus Nerd Font manager/status icons when available. Cleanup uses a `Package Cleanup` title. Operational commands include themed titles, manager sections, and summaries; help uses themed command and flag panels. Pipes, redirects, and other plain contexts keep script-friendly output.
- Distro outdated results depend on the package metadata already present on the machine.
- The authoritative full system update path for root-managed distros is `upkg upgrade --sudo`; the corresponding cleanup authorization is `upkg clean --sudo`.
- When `--sudo` is requested from a non-root shell, `upkg` expects `sudo` to be installed; otherwise it blocks the backend and tells you to rerun it as root.
- Multi-manager runs continue after a backend fails or is blocked, then print a final summary. Multi-phase cleanup also attempts later independent phases after an earlier phase fails.
- Cleanup summary states are `cleaned` when every phase succeeds, `planned` for a successful dry-run preview, `partial` when some cleanup work succeeds and some fails, `failed` when no required work succeeds or a preview probe fails, `blocked` for missing authorization/capability, and `skipped` for a filter omission. `partial`, `failed`, and `blocked` make the overall command return `1` after all selected managers have run.
- `blocked` means the backend needed explicit privilege or local setup that was not available.
- `skipped` means the backend was intentionally omitted by `--skip`.
- `--only` runs managers in the order you name them; default runs use detection order.
- `upkg managers --only ...` keeps the selected managers at the top in that same order.
- For normal `upkg` actions, empty filtered selections print a normalized `upkg managers --only/--skip ...` hint so manager lists with spaces stay copy-pasteable.
- Plain `upkg managers` output keeps active managers as bare IDs for pipe- and script-friendly output; annotations are reserved for alternates, filtered selections, and skipped managers.
- Empty Arch-family outdated checks that exit `1` without output are treated as the normal "up to date" case.
- `apt` upgrade summaries distinguish metadata refresh failures from full-upgrade failures.
- `paru` preview still returns nonzero if the repo-side check fails, even when it can show AUR results.
- `brew` runs with Homebrew's own user-space model; `upkg` does not wrap it in `sudo`.
- Search results are normalized into one table with manager ID, package name, available version, and descriptions when the native backend returns them cheaply.
- Search matching is backend-specific: `apt`, `pacman`, `paru`, `flatpak`, `nix`, and `npm` can use native search flows, while `dnf` and `brew` lean on name-oriented lookups to keep version data portable. On Homebrew, `upkg search` queries formulae and casks separately before collecting version info.
- Broad Homebrew searches cap follow-up `brew info` calls to the first 50 formulae and first 50 casks so short queries cannot stall on hundreds of metadata lookups; refine the query when the cap warning appears.

Flatpak note:

- `upkg` checks both user and system Flatpak installations by default.
- `flatpak update` without `--user` may prompt for authentication via polkit when upgrading system packages.
- `upkg clean` addresses user and system installations separately and never passes `--delete-data`, `--force-remove`, or `--assumeyes`.

Nix bridge details:

- `upkg` only exposes the `nix` backend when `nix` is installed and the `npkg` shell function is defined in the current shell.
- `upkg outdated --only nix` is blocked when `jq` is missing because `npkg outdated` depends on it.
- Nix outdated checks propagate a stable `current`, `changed`, or `partial` result into both `upkg outdated` and `upkg plan`. A partial result is reported as failed, keeps the Nix diagnostic rows, and makes the aggregate command return nonzero after other managers finish.
- `upkg upgrade --only nix` still works without `jq`.
- `upkg clean --only nix` calls `nix-collect-garbage` directly without generation-deletion flags, so it does not depend on `jq` and preserves rollback history.
- The dependency checker verifies `nix-collect-garbage` when Nix is installed and reports it as an optional missing capability.

npm note:

- `upkg upgrade --only npm` checks the configured global prefix before running.
- If that prefix is not writable by the current user, `upkg` blocks the npm backend and tells you to move the prefix under your home directory.
- `upkg` never recommends `sudo npm`.
- `upkg clean --only npm` does not inspect the global prefix: it lists npm-managed npx execution-cache entries, passes only those explicit keys to `npm cache npx rm`, and then verifies/garbage-collects the content-addressable cache in user space.
- `upkg` never uses the keyless, whole-npx-cache `npm cache npx rm --force` form.
- When an older npm does not support the npx cache subcommands, cache verification still runs and the manager is reported as `partial` with an npm upgrade recommendation.

### Examples

```zsh
upkg
upkg search ripgrep
upkg search ripgrep viewer
upkg search ripgrep --only=npm,flatpak
upkg managers
upkg --only brew
upkg --only flatpak,npm
upkg --only=npm,flatpak
upkg plan
upkg --dry-run --only flatpak
upkg upgrade --dry-run --only npm
upkg upgrade --sudo
upkg upgrade --sudo --only apt
upkg upgrade --only npm
upkg --only pacman
upkg clean --dry-run
upkg clean --only brew,npm
upkg clean --skip nix
upkg clean --sudo --only apt
```

Compact search output keeps every selected backend in one table:

```text
Manager   Package                              Available          Description
-------   -------                              ---------          -----------
paru      ripgrep-all                          0.9.1-2            search multiple ripgrep backends together
brew      ripgrep                              15.1.0             formula

Search summary: 2 result(s) across 2 manager(s).
```

`upkg managers` shows active backends in execution order and labels alternates that are only available via `--only`, which is especially useful on Arch or CachyOS systems that have both `paru` and `pacman`.

---

## Nix Package Manager (npkg)

Defined in `60-functions.zsh`. Only available when `nix` is installed. It is an `apt`-like wrapper around `nix profile` with optional `fzf` pickers. `npkg refresh` and `npkg outdated` require `jq`; interactive `add`/`find`/`remove` pickers require `jq`, `fzf`, and a real terminal.

### Commands

| Command | What it does |
|---|---|
| `npkg add <pkg>` / `npkg install <pkg>` / `npkg i <pkg>` | Install a package from nixpkgs |
| `npkg add` / `npkg install` | Open an fzf picker to choose packages |
| `npkg find <query>` / `npkg pick <query>` / `npkg fzf <query>` | Seed the fzf picker with an initial query |
| `npkg search <query>` / `npkg s <query>` | Plain text search with descriptions |
| `npkg list` / `npkg ls` | List installed packages in the current profile |
| `npkg remove <pkg>` / `npkg rm <pkg>` / `npkg uninstall <pkg>` / `npkg delete <pkg>` | Remove a package |
| `npkg remove` / `npkg rm` | Open an fzf picker to choose packages to remove |
| `npkg outdated` / `npkg check` / `npkg diff` | Compare installed and currently evaluated output-path sets |
| `npkg upgrade` / `npkg up` / `npkg update` | Upgrade all packages |
| `npkg upgrade <pkg>` | Upgrade a specific package |
| `npkg refresh` | Rebuild the cached nixpkgs attribute index |

```zsh
npkg add bat           # install bat
npkg find nvim         # fuzzy-pick a neovim variant
npkg search ripgrep    # search with descriptions
npkg remove            # interactive removal picker
npkg outdated          # report current, changed, and unknown outputs
npkg upgrade           # upgrade everything
```

The fzf picker preview shows the package description, version, and homepage from nixpkgs using the shared Catppuccin Mocha palette. The preview stays on the right in wide terminals and moves below the picker in narrower terminals so package names and metadata remain readable. The attribute name cache is stored under `${XDG_CACHE_HOME:-~/.cache}/npkg/` and is refreshed automatically once it is at least 24 hours old.

`npkg outdated` reads every active nixpkgs profile element from either the object- or array-shaped manifest schema, then evaluates the same source, resolved attribute, and selected outputs in parallel. Status comes only from output identity: an equal store-path set is `current`; a different set is `change available`; and incomplete profile data, failed evaluation, or missing usable outputs is `unknown`. The comparison honors explicit multi-output selection and `meta.outputsToInstall` defaults. Version strings come from evaluated package metadata only, are display information, and are never parsed from store-path basenames or used to infer ordering.

A complete report with changes still exits zero because the check itself succeeded. A report containing any `unknown` row is labeled partial and exits nonzero, with separate change and unknown counts; it never prints `Everything is up to date.` This deliberately does not claim that a changed output is newer—it can be an upgrade, downgrade, rebuild, changed input, or packaging change. A profile with no active nixpkgs elements is a complete zero-count result and prints `No nixpkgs packages found in the current profile.`

`npkg refresh` also needs `jq`, because the cache is built from JSON output.

Bare install names are expanded to `nixpkgs#<name>`, so `npkg add ripgrep` and `nix profile add nixpkgs#ripgrep` land in the same place.

---

## Tips Function

Defined in `80-tips.zsh`. Prints a random tip from the shared config on demand.

```zsh
tips    # prints one random tip, e.g.:
        # tip: Run mkcd <dir> to create a directory and cd into it in one step
```

Tips cover aliases, functions, glob patterns, history, and more. Dependency-specific tips only appear when the supporting commands are available. Extra `npkg` tips are added automatically when `nix`, `fzf`, and `jq` are available, and `upkg` tips are added automatically whenever at least one supported package manager is detected.

One tip points to `zhelp` for searchable command discovery. Command-tip catalogue consolidation remains separate from the palette itself, so the existing tip pool and hook-free behavior are otherwise unchanged.

In rich terminals, `tips` renders a compact Rosewater card. In plain contexts it stays a one-line `tip:` message.

---

## OMZ Plugins

These are **not** defined by this repo. They come from your own `~/.zshrc`, and the shared config here only assumes they may exist.

### git (built-in)
If you enable the OMZ `git` plugin, common aliases include:

| Alias | Expands to |
|---|---|
| `gs` | `git status -sb` |
| `gc` | `git commit -m` |
| `gca` | `git commit -am` |
| `gp` | `git push` |
| `gl` | `git pull` |
| `gd` | `git diff` |
| `gco` | `git checkout` |
| `gb` | `git branch -vv` |
| `gst` | `git status` |
| `ga` | `git add` |
| `gaa` | `git add --all` |
| `gcm` | `git commit -m` |
| `gcmsg` | `git commit -m` |
| `gsta` | `git stash` |
| `gstp` | `git stash pop` |
| `grh` | `git reset` |
| `grhh` | `git reset --hard` |

### zsh-autosuggestions
Shows greyed-out suggestions based on your history as you type.

```zsh
git sta   # shows "git stash" in grey
# Press → (right arrow) to accept
# Press Ctrl+F to accept
```

### zsh-syntax-highlighting
Colors commands as you type:
- **Green** = valid command
- **Red** = unknown command
- **Underline** = valid path
- **Blue** = built-in

---

## Starship Prompt

Starship is configured separately in `~/.config/starship.toml`; it is outside this repo's tracked shell modules. It typically shows:
- Current directory
- Git branch and status
- Command execution time
- And any other modules you've enabled

---

## Quick Reference Card

### Navigation
```
.. / ... / ....     → go up 1/2/3 levels
-                   → go to previous directory
z <pattern>         → smart jump to directory
zi                  → interactive directory picker
mkcd <name>         → create + cd in one step
croot               → jump to git repo root
fbr                 → fuzzy-pick and checkout a git branch
pushd / popd        → directory stack navigation
dirs -v             → show directory stack
```

### File Operations
```
ls / ll / la / lt   → list files (various views)
extract <archive>   → unpack any archive
peek <file>         → preview file with syntax highlighting
ff <pattern> [path] → find files by name
ft <pattern> [path] → find text in files
dusage [path] [n]   → largest top-level entries
bigfiles [path] [n] → largest files in tree
```

### FZF Keybindings
```
Ctrl+T              → fuzzy insert file path
Ctrl+R              → fuzzy search history
Alt+C               → fuzzy cd into directory
```

### Git
```
gs / gd / ga / gaa  → status, diff, add, add all
gc / gca            → commit, commit all
gp / gpr            → push, pull --rebase
gco / gb            → checkout, branch
glog                → visual log (last 20)
gun                 → undo last commit
gitcount            → contributor stats
gcount              → contributor stats (compatibility shortcut)
```

### Global Aliases (use anywhere in command)
```
<G>                 → pipe to grep
<L>                 → pipe to less
<W>                 → pipe to wc -l
<H>                 → pipe to head
<T>                 → pipe to tail
<NE>                → suppress errors
<NUL>               → suppress all output
```

### System
```
ports               → listening ports
myip                → public IP
weather             → weather forecast
fkill [signal]      → fuzzy kill one or more processes
headers <url>       → HTTP headers
path                → inspect PATH entries
fanprofile          → current laptop performance profile
tips                → print a random usage tip
zhelp [query]       → search commands or queue an editable example
```

### Package Updates
```
upkg                → show outdated packages across detected managers
upkg search <query> → search managers for package names and versions
upkg plan           → preview upgrades without changing packages
upkg managers       → show active managers and alternates
upkg --only brew    → limit checks to the Homebrew backend
upkg --only a,b     → limit checks to selected managers
upkg upgrade --sudo → explicitly allow privileged upgrades
```

### Nix (npkg — requires nix)
```
npkg add <pkg>      → install from nixpkgs
npkg add            → fuzzy-pick packages to install
npkg find <query>   → seeded fuzzy install picker
npkg search <query> → search nixpkgs with descriptions
npkg list           → list installed packages
npkg remove         → fuzzy-pick packages to remove
npkg outdated       → compare Nix output identities
npkg upgrade        → upgrade all packages
npkg refresh        → rebuild nixpkgs attribute cache
```

### Completion
```
<Tab>               → trigger completion (case-insensitive)
kill <Tab>          → shows process list with PID, user, command
upkg <Tab>          → commands, aliases, and flags
upkg --only=<Tab>   → comma-separated package-manager IDs
npkg <Tab>          → commands and aliases when Nix is available
extract <Tab>       → supported archive files only
```

### History
```
Ctrl+R              → fuzzy search (fzf-enhanced)
↑ / ↓               → browse history
```

---

## Tips & Tricks

### Use global aliases with git
```zsh
git log --oneline G "fix" W    # count commits mentioning "fix"
git diff G "TODO" L            # search diff for TODO and page it
```

### FZF history preview
```zsh
# Press Ctrl+R, type something
# Press ? to see the full command in preview
```

### Directory stack workflow
```zsh
cd /etc/nginx    # working on config
cd /var/log/nginx  # checking logs
dirs -v          # see where you've been
cd ~0            # back to /var/log/nginx
cd ~1            # back to /etc/nginx
popd             # remove current, go to next
```
