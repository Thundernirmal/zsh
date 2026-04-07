# On-demand tips from across the shared shell config.

_zsh_tip_pool=(
  "Use z <pattern> to jump to directories zoxide remembers"
  "Press Ctrl+R to fuzzy search your command history"
  "Press Ctrl+T to fuzzy insert a file path at your cursor"
  "Press Alt+C to fuzzy cd into a directory"
  "Type a directory name and press Enter to cd into it (AUTO_CD)"
  "Use .. / ... / .... to go up 1/2/3 levels quickly"
  "Use - to go back to your previous directory"
  "Run glog for a visual git graph of the last 20 commits"
  "Run gpr to pull with rebase for a cleaner history"
  "Run gun to undo your last commit while keeping changes staged"
  "Run gcount to see who contributed the most commits"
  "Use ff <name> to find files by name recursively"
  "Use ft <text> to search for text inside files (uses ripgrep if available)"
  "Run extract <archive> to unpack a supported archive"
  "Run mkcd <dir> to create a directory and cd into it in one step"
  "Run croot to jump to the root of the current git repo"
  "Run path to print each PATH entry on its own line"
  "Run fbr to fuzzy-pick and checkout a git branch"
  "Run dusage to see the largest items in the current directory"
  "Run bigfiles to find the largest files recursively in the tree"
  "Run dusage [path] [count] to summarize any directory with a custom limit"
  "Run bigfiles [path] [count] to inspect any tree with a custom limit"
  "Run fkill to fuzzy select and kill a process"
  "Run fkill 15 to send SIGTERM and select multiple processes"
  "Run ports to see all listening ports and their processes"
  "Run myip to check your public IP address"
  "Run weather to get a quick forecast"
  "Run peek <file> to preview a file quickly"
  "Run http <url> to follow redirects and print response headers"
  "Use global alias G anywhere: git log G fix pipes to grep"
  "Use global alias L anywhere: cat file.txt L pipes to less"
  "Use global alias W anywhere: ps aux W counts lines"
  "Use global alias NE anywhere: command NE suppresses errors"
  "Use global alias NUL anywhere: noisy-command NUL silences stdout and stderr"
  "Use pushd/popd and dirs -v for directory stack navigation"
  "Use cd ~1 after dirs -v to jump back through your directory stack"
  "Run ll for a long listing with hidden files and readable sizes"
  "Run lt for a tree view up to 3 levels deep"
  "Use **/*.ext for recursive glob matching (EXTENDED_GLOB)"
  "* includes dotfiles because GLOB_DOTS is enabled"
  "Use *(.m-1) to glob files modified in the last day"
  "file2 sorts before file10 because NUMERIC_GLOB_SORT is enabled"
  "Mistyped commands may offer a correction because CORRECT is enabled"
  "Tab completion is case-insensitive for names and paths"
  "ff <pattern> [path] uses fd or fdfind when available for faster searches"
  "Use gs, gd, ga, gaa, gco, gb for quick git operations (OMZ)"
  "Grey suggestions as you type come from zsh-autosuggestions"
  "Green commands are valid, red means unknown (syntax highlighting)"
  "Use zi for an interactive fzf-powered directory picker"
  "History is shared across all open terminal sessions"
  "Ctrl+R history search skips duplicate commands"
  "Use ft TODO to quickly find TODO comments in your code"
  "Combine globals: git log G fix W counts commits mentioning fix"
)

tips() {
  local total=${#_zsh_tip_pool}

  if (( total == 0 )); then
    print 'No tips configured.'
    return 1
  fi

  print -P "%F{244}tip:%f ${_zsh_tip_pool[$(( RANDOM % total + 1 ))]}"
}
