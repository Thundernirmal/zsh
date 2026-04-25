# Zsh Configuration Guide

Your zsh setup is built in two layers: **Oh My Zsh** in `~/.zshrc` handles the framework, plugins, and Starship prompt. The shared config in `~/.config/zsh/` adds portable features that work across your GNU/Linux machines.

```
~/.zshrc                    → OMZ, Starship, plugins, PATH
~/.config/zsh/init.zsh      → Entry point that loads everything below
├── 10-history.zsh          → History settings (100k entries, shared across sessions)
├── 20-aliases.zsh          → Aliases for ls, git, navigation, safety, network
├── 30-zoxide.zsh           → Smart directory jumping
├── 40-fzf.zsh              → Fuzzy finder with previews
├── 50-completion.zsh       → Tab completion tuning (case-insensitive, process completion)
├── 60-functions.zsh        → Shell functions (extract, search, kill, git helpers, upkg, npkg, etc.)
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
7. [Shell Functions](#shell-functions)
8. [Global Aliases](#global-aliases)
9. [Unified Package Updates (upkg)](#unified-package-updates-upkg)
10. [Nix Package Manager (npkg)](#nix-package-manager-npkg)
11. [Tips Function](#tips-function)
12. [OMZ Plugins](#omz-plugins)
13. [Starship Prompt](#starship-prompt)
14. [Quick Reference Card](#quick-reference-card)

---

## Zsh Options

This shared layer intentionally targets GNU/Linux environments. A few commands and flags below assume GNU userland tools such as `ss`, GNU `ls`/`grep` color flags, and standard Linux networking utilities.

These options are set in `init.zsh` and change how zsh behaves day-to-day.

### AUTO_CD
Type a directory name and press Enter to cd into it — no `cd` needed.

```zsh
~/projects
# You just typed the directory name and hit Enter
~/projects  # now you're inside
```

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

### GLOB_DOTS
Include hidden files (dotfiles) in glob patterns.

```zsh
ls *     # now includes .gitignore, .env, etc.
```

### NUMERIC_GLOB_SORT
Numbers in filenames sort numerically, not alphabetically.

```zsh
# Without: file1 file10 file2 file20 file3
# With:    file1 file2 file3 file10 file20
```

### CORRECT is disabled
This shared layer explicitly turns command spell-correction off, even if a higher-level config such as `~/.zshrc` enabled it earlier.

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

| Alias | What it does |
|---|---|
| `ports` | Show all listening ports and their processes |
| `myip` | Show your public IP address over HTTPS |
| `weather` | Show weather forecast over HTTPS |

```zsh
ports     # what's listening on your machine
myip      # your public IP
weather   # current weather + 3-day forecast
```

### Git Extras

The OMZ `git` plugin already provides `gs`, `gc`, `gp`, `gd`, `gco`, `gb`, etc. These fill the gaps:

| Alias | Expands to | What it does |
|---|---|---|
| `glog` | `git log --oneline --graph --decorate -20` | Visual log, last 20 commits |
| `gpr` | `git pull --rebase` | Pull with rebase (cleaner history) |
| `gun` | `git reset HEAD~1 --soft` | Undo last commit, keep changes staged |
| `gcount` | `git shortlog -sn --no-merges` | Contributor commit counts |

```zsh
glog      # pretty commit graph
gpr       # pull without merge commits
gun       # oops, undo that last commit
gcount    # who contributed what
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

### Ctrl+T — Insert file/directory

Press `Ctrl+T` to fuzzy search files and insert the selected path at your cursor.

```zsh
cat <Ctrl+T>    # opens fuzzy finder, select a file, path is inserted
```

The preview pane (right side) shows:
- **Directories:** tree view of contents
- **Files:** first 200 lines with syntax highlighting (via `bat`)

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

Fuzzy select and kill processes.

```zsh
fkill           # opens process picker
fkill 15        # send SIGTERM instead of SIGKILL
```

---

## Tab Completion

Configured in `50-completion.zsh`. OMZ / `compinit` provides the base; this file adds lightweight tuning only.

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

> **Note:** Heavy completion UI features (menu selection, colored listings, grouped results, per-option descriptions) were intentionally removed because they made completion lists noticeably slower. If you want them, add them locally in `~/.zshrc` after sourcing `init.zsh`.

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

### mkcd — Create and enter directory

```zsh
mkcd new-project
# Creates "new-project" and cd's into it in one step
```

### ff — Find files by name

```zsh
ff config        # find all files with "config" in the name
ff ".js"         # find all .js files
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

### headers — Quick HTTP header check

```zsh
headers google.com  # shows response headers
```

### dusage — Disk usage of current directory

```zsh
dusage           # top 20 largest items, human-readable
dusage /var 10   # top 10 items in /var
```

### bigfiles — Largest files in tree

```zsh
bigfiles         # top 20 largest files recursively
bigfiles /home 5 # top 5 largest files under /home
```

### croot — Jump to git repo root

```zsh
cd ~/projects/myapp/src/components
croot            # jumps to ~/projects/myapp
```

### path — Print PATH entries

```zsh
path    # prints each PATH entry on its own line, one per line
```

### fbr — Fuzzy-pick and checkout a git branch

Requires `fzf`. Shows local and remote branches sorted by most recent commit, with a log preview.

```zsh
fbr              # opens branch picker — Tab to select, Enter to checkout
```

Remote branches are tracked locally automatically.

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

Defined in `60-functions.zsh`. `upkg` is a single entrypoint for checking outdated packages or running upgrades across the package managers available on the current machine. Runtime detection is the source of truth: there is no bootstrap variable to keep in sync, and `upkg` only uses managers that `command -v` can see right now.

Detection order is:

1. distro backend: `paru` when present, otherwise `pacman`, otherwise `apt`, otherwise `dnf`
2. `flatpak`
3. `nix` via the existing `npkg` wrapper
4. global `npm`

If both `paru` and `pacman` are installed, `paru` is the default Arch-family backend and `pacman` remains available only through `--only pacman`.

### Commands

| Command | What it does |
|---|---|
| `upkg` | Show outdated packages across detected managers |
| `upkg outdated` | Same as the default read-only check |
| `upkg check` | Alias for `outdated` |
| `upkg list` | Alias for `outdated` |
| `upkg upgrade` | Run upgrades across selected managers |
| `upkg up` | Alias for `upgrade` |
| `upkg update` | Alias for `upgrade` |
| `upkg plan` | Preview available upgrades without changing packages |
| `upkg managers` | Show detected managers; filtered selections appear in execution order first |
| `upkg help` | Show usage help |

### Flags

| Flag | What it does |
|---|---|
| `--only <list>` / `--only=<list>` | Include only the comma-separated manager IDs you name |
| `--skip <list>` / `--skip=<list>` | Exclude the comma-separated manager IDs you name |
| `--sudo` | Explicitly allow privileged upgrade paths to run |
| `--dry-run` | Preview upgrades instead of running them |

Supported manager IDs: `apt`, `dnf`, `pacman`, `paru`, `flatpak`, `nix`, `npm`.

### Backends

| Manager | Outdated command | Upgrade command | Notes |
|---|---|---|---|
| `apt` | `apt list --upgradable` | `apt update && apt full-upgrade` | Upgrade path is blocked unless already root or `--sudo` is passed |
| `dnf` | `dnf check-update` | `dnf upgrade --refresh` | `dnf check-update` exit `100` means updates are available |
| `pacman` | `pacman -Qu` | `pacman -Syu` | Default only when `paru` is absent |
| `paru` | `pacman -Qu` plus `paru -Qua` | `paru -Syu` | Preferred on Arch-family systems; preview includes repo and AUR updates, and still shows AUR results if the repo check fails; upgrade requires explicit `--sudo` opt-in but still runs unprefixed |
| `flatpak` | `flatpak remote-ls --user --updates` | `flatpak update --user` | User installation only by default |
| `nix` | `npkg outdated` | `npkg upgrade` | Reuses the existing `npkg` wrapper instead of duplicating Nix logic |
| `npm` | `npm outdated -g --depth=0` | `npm update -g` | Upgrade path is user-space only; `upkg` will not suggest `sudo npm` |

### Behavior notes

- `upkg` with no arguments is read-only and does not refresh package metadata automatically.
- `upkg plan`, `upkg --dry-run`, and `upkg upgrade --dry-run` use the read-only outdated checks to preview what would be considered for upgrade.
- Distro outdated results depend on the package metadata already present on the machine.
- The authoritative full system update path for root-managed distros is `upkg upgrade --sudo`.
- When `--sudo` is requested from a non-root shell, `upkg` expects `sudo` to be installed; otherwise it blocks the backend and tells you to rerun it as root.
- Multi-manager runs continue after a backend fails or is blocked, then print a final summary.
- `blocked` means the backend needed explicit privilege or local setup that was not available.
- `skipped` means the backend was intentionally omitted by `--skip`.
- `--only` runs managers in the order you name them; default runs use detection order.
- `upkg managers --only ...` keeps the selected managers at the top in that same order.
- Empty Arch-family outdated checks that exit `1` without output are treated as the normal "up to date" case.
- `apt` upgrade summaries distinguish metadata refresh failures from full-upgrade failures.
- `paru` preview still returns nonzero if the repo-side check fails, even when it can show AUR results.

Flatpak note:

- `upkg` uses the user Flatpak installation via `--user`, so it stays in the unprivileged workflow by default.
- System Flatpak installations are intentionally out of scope for the default `upkg` path in v1.

Nix bridge details:

- `upkg` only exposes the `nix` backend when `nix` is installed and the `npkg` shell function is defined in the current shell.
- `upkg outdated --only nix` is blocked when `jq` is missing because `npkg outdated` depends on it.
- `upkg upgrade --only nix` still works without `jq`.

npm note:

- `upkg upgrade --only npm` checks the configured global prefix before running.
- If that prefix is not writable by the current user, `upkg` blocks the npm backend and tells you to move the prefix under your home directory.
- `upkg` never recommends `sudo npm`.

### Examples

```zsh
upkg
upkg managers
upkg --only flatpak,npm
upkg --only=npm,flatpak
upkg plan
upkg --dry-run --only flatpak
upkg upgrade --dry-run --only npm
upkg upgrade --sudo
upkg upgrade --sudo --only apt
upkg upgrade --only npm
upkg --only pacman
```

`upkg managers` shows active backends in execution order and labels alternates that are only available via `--only`, which is especially useful on Arch or CachyOS systems that have both `paru` and `pacman`.

---

## Nix Package Manager (npkg)

Defined in `60-functions.zsh`. Only available when `nix` is installed. An `apt`-like wrapper around `nix profile` with optional `fzf` pickers. `npkg refresh` and `npkg outdated` require `jq`; interactive `add`/`find`/`remove` pickers require both `fzf` and `jq`.

### Commands

| Command | What it does |
|---|---|
| `npkg add <pkg>` | Install a package from nixpkgs |
| `npkg add` | Open an fzf picker to choose packages |
| `npkg find <query>` | Seed the fzf picker with an initial query |
| `npkg search <query>` | Plain text search with descriptions |
| `npkg list` | List installed packages in the current profile |
| `npkg remove <pkg>` | Remove a package |
| `npkg remove` | Open an fzf picker to choose packages to remove |
| `npkg outdated` | Show available upgrades before running upgrade |
| `npkg upgrade` | Upgrade all packages |
| `npkg upgrade <pkg>` | Upgrade a specific package |
| `npkg refresh` | Rebuild the cached nixpkgs attribute index |

```zsh
npkg add bat           # install bat
npkg find nvim         # fuzzy-pick a neovim variant
npkg search ripgrep    # search with descriptions
npkg remove            # interactive removal picker
npkg outdated          # see what would be upgraded
npkg upgrade           # upgrade everything
```

The fzf picker preview shows the package description, version, and homepage from nixpkgs. The attribute name cache is stored under `${XDG_CACHE_HOME:-~/.cache}/npkg/` and is refreshed automatically once it is at least 24 hours old.

`npkg outdated` compares installed store-path versions against the latest in nixpkgs (evaluated in parallel) and prints a table — run it before `npkg upgrade` to see what will change.

`npkg refresh` also needs `jq`, because the cache is built from JSON output.

---

## Tips Function

Defined in `80-tips.zsh`. Prints a random tip from the shared config on demand.

```zsh
tips    # prints one random tip, e.g.:
        # tip: Run mkcd <dir> to create a directory and cd into it in one step
```

Tips cover aliases, functions, glob patterns, history, and more. Dependency-specific tips only appear when the supporting commands are available. Extra `npkg` tips are added automatically when `nix`, `fzf`, and `jq` are available, and `upkg` tips are added automatically whenever at least one supported package manager is detected.

---

## OMZ Plugins

These are loaded from `~/.zshrc`:

### git (built-in)
Provides dozens of git aliases. Key ones:

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

Starship is configured separately in `~/.config/starship.toml`. It shows:
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
<directory_name>    → cd into it (AUTO_CD)
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
ff <pattern>        → find files by name
ft <pattern>        → find text in files
dusage              → disk usage of current dir
bigfiles            → largest files in tree
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
gcount              → contributor stats
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
fkill               → fuzzy kill process
headers <url>       → HTTP headers
path                → print PATH entries one per line
tips                → print a random usage tip
```

### Package Updates
```
upkg                → show outdated packages across detected managers
upkg managers       → show active managers and alternates
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
npkg outdated       → show available upgrades
npkg upgrade        → upgrade all packages
npkg refresh        → rebuild nixpkgs attribute cache
```

### Completion
```
<Tab>               → trigger completion (case-insensitive)
kill <Tab>          → shows process list with PID, user, command
```

### History
```
Ctrl+R              → fuzzy search (fzf-enhanced)
↑ / ↓               → browse history
```

---

## Tips & Tricks

### Combine AUTO_CD with zoxide
```zsh
z proj    # jump to ~/projects
ls        # look around
src       # AUTO_CD takes you into src/
```

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
