# On-demand tips from across the shared shell config.

_zsh_tip_pool=(
  "Type a directory name and press Enter to cd into it (AUTO_CD)"
  "Use .. / ... / .... to go up 1/2/3 levels quickly"
  "Use - to go back to your previous directory"
  "Run glog for a visual git graph of the last 20 commits"
  "Run gpr to pull with rebase for a cleaner history"
  "Run gun to undo your last commit while keeping changes staged"
  "Run gitcount to see contributor counts for the current repo; gcount still works as a shortcut"
  "Use ff <name> to find files by name recursively"
  "Use ft <text> to search for text inside files (uses ripgrep if available)"
  "Run extract <archive> to unpack a supported archive"
  "Run mkcd <dir> to create a directory and cd into it in one step"
  "Run croot to jump to the root of the current git repo"
  "Run path to print each PATH entry on its own line"
  "Run fbr to fuzzy-pick and checkout a git branch from local or remote refs"
  "Run dusage to see the largest items in the current directory"
  "Run bigfiles to find the largest files recursively in the tree"
  "Run dusage [path] [count] to summarize any directory with a custom limit"
  "Run bigfiles [path] [count] to inspect any tree with a custom limit"
  "dusage and bigfiles still show readable results even when one subtree is inaccessible"
  "Run fkill to fuzzy select and kill a process"
  "Run fkill 15 to send SIGTERM and select multiple processes"
  "Run ports to see all listening ports and their processes"
  "Run myip to check your public IP address over HTTPS"
  "Run weather to get a quick forecast over HTTPS"
  "Run peek <file> to preview a file quickly"
  "Run fanprofile to see the current laptop performance/fan profile"
  "Run headers <url> to follow redirects and print response headers"
  "Use global alias G anywhere: git log G fix pipes to grep"
  "Use global alias L anywhere: cat file.txt L pipes to less"
  "Use global alias W anywhere: ps aux W counts lines"
  "Use global alias NE anywhere: command NE suppresses errors"
  "Use global alias NUL anywhere: noisy-command NUL silences stdout and stderr"
  "Use pushd/popd and dirs -v for directory stack navigation"
  "Use cd ~1 after dirs -v to jump back through your directory stack"
  "Run ll for a long listing with hidden files and readable sizes"
  "Use **/*.ext for recursive glob matching (EXTENDED_GLOB)"
  "* includes dotfiles because GLOB_DOTS is enabled"
  "Use *(.m-1) to glob files modified in the last day"
  "file2 sorts before file10 because NUMERIC_GLOB_SORT is enabled"
  "Command spell-correction prompts are intentionally disabled"
  "Tab completion is case-insensitive for names and paths"
  "ff <pattern> [path] uses fd or fdfind when available for faster searches"
  "History is shared across all open terminal sessions"
  "Ctrl+R history search skips duplicate commands"
  "Commands starting with a space are omitted from history (HIST_IGNORE_SPACE)"
  "Use ft TODO to quickly find TODO comments in your code"
  "Combine globals: git log G fix W counts commits mentioning fix"
)

if command -v zoxide >/dev/null 2>&1; then
  _zsh_tip_pool+=(
    "Use z <pattern> to jump to directories zoxide remembers"
    "Use zi for an interactive zoxide directory picker"
  )
fi

if command -v fzf >/dev/null 2>&1 && [[ -o interactive ]] && [[ -z "$ZSH_EXECUTION_STRING" ]]; then
  _zsh_tip_pool+=(
    "Press Ctrl+R to fuzzy search your command history"
    "Press Ctrl+T to fuzzy insert a file path at your cursor"
    "Press Alt+C to fuzzy cd into a directory"
  )
fi

if alias lt >/dev/null 2>&1; then
  _zsh_tip_pool+=(
    "Run lt for a tree view up to 3 levels deep"
  )
fi

if command -v nix >/dev/null 2>&1; then
  _zsh_tip_pool+=(
    "Run npkg add bat for a short nix profile add command"
    "Run npkg search ripgrep to search nixpkgs with package descriptions"
  )
fi

if command -v nix >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  _zsh_tip_pool+=(
    "Run npkg refresh to rebuild the cached nixpkgs picker index (requires jq)"
    "Run npkg outdated to preview available package upgrades before running npkg upgrade"
  )
fi

if command -v nix >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  _zsh_tip_pool+=(
    "Run npkg install with no args to fuzzy-pick nixpkgs attribute names"
    "Run npkg find nvim to seed the nix package picker with an initial query"
    "npkg find shows description, version, and homepage in the preview pane"
    "Run npkg remove with no args to fuzzy-select installed Nix packages to uninstall"
  )
fi

if command -v paru >/dev/null 2>&1 || command -v pacman >/dev/null 2>&1 || command -v apt >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1 || command -v flatpak >/dev/null 2>&1 || (command -v nix >/dev/null 2>&1 && (( $+functions[npkg] ))) || command -v npm >/dev/null 2>&1; then
  _zsh_tip_pool+=(
    "Run upkg to list outdated packages across detected package managers with the same shared dashboard styling used across the repo, plus Nerd Font icons when available"
    "Run upkg managers to see active backends and alternates like pacman via --only"
    "Pipe upkg managers when you want plain active-manager IDs without extra status tags"
    "Run upkg managers --only=npm,flatpak to confirm selected execution order before upgrading"
    "On Arch-family systems, upkg treats empty repo and AUR outdated checks as up to date instead of surfacing a false failure"
    "Run upkg plan or upkg --dry-run to preview upgrades without changing packages"
    "Use upkg --only flatpak,npm to limit checks to selected managers"
  )
fi

if command -v paru >/dev/null 2>&1 || command -v pacman >/dev/null 2>&1 || command -v apt >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
  _zsh_tip_pool+=(
    "Run upkg upgrade --sudo to opt into system package upgrades explicitly"
  )
fi

if alias gs >/dev/null 2>&1 && alias gco >/dev/null 2>&1; then
  _zsh_tip_pool+=(
    "Use gs, gd, ga, gaa, gco, gb for quick git operations when the OMZ git plugin is enabled"
  )
fi

tips() {
  local total=${#_zsh_tip_pool}
  local tip

  if (( total == 0 )); then
    print 'No tips configured.'
    return 1
  fi

  tip=${_zsh_tip_pool[$(( RANDOM % total + 1 ))]}

  if (( $+functions[_ui_plain_mode] )) && ! _ui_plain_mode; then
    _ui_title_line 'Tip' 'shared zsh config' accent '󰛨' '*'
    _ui_section_break
    print -nr -- '  '
    _ui_color text
    print -nr -- "$tip"
    _ui_reset
    print ''
    _ui_section_break
    print -nr -- '  '
    _ui_color muted
    print -r -- 'Run tips again for another hint'
    _ui_reset
    return 0
  fi

  print -- "tip: $tip"
}
