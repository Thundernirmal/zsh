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
  "Run dusage to see the largest items in the current directory"
  "Run bigfiles to find the largest files recursively in the tree"
  "Run fkill to fuzzy select and kill a process"
  "Run ports to see all listening ports and their processes"
  "Run myip to check your public IP address"
  "Run weather to get a quick forecast"
  "Run peek <file> to preview a file quickly"
  "Use global alias G anywhere: git log G fix pipes to grep"
  "Use global alias L anywhere: cat file.txt L pipes to less"
  "Use global alias W anywhere: ps aux W counts lines"
  "Use global alias NE anywhere: command NE suppresses errors"
  "Use pushd/popd and dirs -v for directory stack navigation"
  "Use **/*.ext for recursive glob matching (EXTENDED_GLOB)"
  "Use *(.m-1) to glob files modified in the last day"
  "Tab completion is case-insensitive for names and paths"
  "Use gs, gd, ga, gaa, gco, gb for quick git operations (OMZ)"
  "Press ESC twice to prefix the current command with sudo (OMZ)"
  "Grey suggestions as you type come from zsh-autosuggestions"
  "Green commands are valid, red means unknown (syntax highlighting)"
  "Use zi for an interactive fzf-powered directory picker"
  "Run http <url> to quickly check HTTP response headers"
  "History is shared across all open terminal sessions"
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
