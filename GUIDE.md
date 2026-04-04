# Zsh Configuration Guide

Your zsh setup is built in two layers: **Oh My Zsh** in `~/.zshrc` handles the framework, plugins, and Starship prompt. The shared config in `~/.config/zsh/` adds portable features that work across any machine.

```
~/.zshrc                    → OMZ, Starship, plugins, PATH
~/.config/zsh/init.zsh      → Entry point that loads everything below
├── 10-history.zsh          → History settings (100k entries, shared across sessions)
├── 20-aliases.zsh          → Aliases for ls, git, navigation, safety, network
├── 30-zoxide.zsh           → Smart directory jumping
├── 40-fzf.zsh              → Fuzzy finder with previews
├── 50-completion.zsh       → Enhanced tab completion
├── 60-functions.zsh        → Shell functions (extract, search, kill, etc.)
└── 70-globals.zsh          → Global aliases (pipe shortcuts)
```

---

## Table of Contents

1. [Zsh Options](#zsh-options)
2. [History](#history)
3. [Aliases](#aliases)
4. [Zoxide — Smart Navigation](#zoxide--smart-navigation)
5. [FZF — Fuzzy Finder](#fzf--fuzzy-finder)
6. [Enhanced Completion](#enhanced-completion)
7. [Shell Functions](#shell-functions)
8. [Global Aliases](#global-aliases)
9. [OMZ Plugins](#omz-plugins)
10. [Starship Prompt](#starship-prompt)
11. [Quick Reference Card](#quick-reference-card)

---

## Zsh Options

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

### CORRECT
Spell-checks commands before executing. If you mistype, zsh asks:

```zsh
sl
zsh: correct 'sl' to 'ls' [nyae]? y
```

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
| `HIST_IGNORE_DUPS` | on | Don't store consecutive duplicates |
| `HIST_FIND_NO_DUPS` | on | `Ctrl+R` shows each command only once |

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
| `myip` | Show your public IP address |
| `weather` | Show weather forecast |

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

## Enhanced Completion

Tab completion is upgraded with:

### Fuzzy matching
```zsh
cd /u/l/b<Tab>  # completes to /usr/local/bin
```

### Menu selection
When multiple options exist, press `Tab` to cycle through them with a visual menu. Use arrow keys or `Tab`/`Shift+Tab` to navigate.

### Colored listings
Files are colored by type (directories blue, executables green, etc.) matching your terminal theme.

### Grouped results
Completions are grouped by type:
```
-- command --
git  ls  cat
-- alias --
ll  la  lt
-- file --
README.md  guide.md
```

### Descriptions
Options show descriptions:
```
-- git options --
--oneline    show one line per commit
--graph      draw ASCII graph
```

### Process completion for `kill`
```zsh
kill <Tab>    # shows PID, user, command for each process
```

---

## Shell Functions

### extract — Unpack any archive

```zsh
extract archive.tar.gz
extract archive.zip
extract archive.7z
extract archive.tar.xz
```

Supports: `.tar.gz`, `.tar.bz2`, `.tar.xz`, `.zip`, `.rar`, `.7z`, `.gz`, `.tar`, `.bz2`, `.Z`

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
ft "TODO"        # search for "TODO" in all files
ft "function"    # search for "function"
```

### peek — Preview a file

Uses `bat` for syntax highlighting if available, falls back to `cat`.

```zsh
peek config.json
peek script.sh
```

### http — Quick HTTP header check

```zsh
http google.com  # shows response headers
```

### dusage — Disk usage of current directory

```zsh
dusage           # top 20 largest items, human-readable
```

### bigfiles — Largest files in tree

```zsh
bigfiles         # top 20 largest files recursively
```

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
docker ps W G "running"
```

**Tip:** After typing a command with a global alias, press `Space` then `Ctrl+X G` (expand-global) to see what it will expand to before running.

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
http <url>          → HTTP headers
```

### Completion
```
<Tab>               → trigger completion, cycle through menu
<Shift+Tab>         → cycle backwards
```

### History
```
Ctrl+R              → fuzzy search (fzf-enhanced)
↑ / ↓               → browse history
```

---

## Tips & Tricks

### Spell correction in action
```zsh
sl
# zsh: correct 'sl' to 'ls' [nyae]?
# y = yes, n = no, a = abort, e = edit
```

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
# Press Ctrl+Y to copy the command to clipboard
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
