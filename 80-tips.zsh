# Short, on-demand tips for the shared shell config.
# Startup-time availability checks use Zsh's prehashed command table.

_zsh_tip_pool=(
  "Use .., ..., or .... to move up one, two, or three directories"
  "Use - to return to the previous directory"
  "Run dirs -v to inspect the directory stack"
  "Use *(D) when a glob should include hidden entries"
  "Start a command with a space to keep it out of saved history"
  "Run zhelp to find a command and queue an editable example"
  "Run ztheme use nord to switch dashboard and finder colors for this session"
  "Use ZSH_FZF_LAYOUT=roomy for a larger rounded finder with extra spacing"
  "Run ll for a detailed listing that includes hidden entries"
  "Run ff <pattern> [path] to find files by name"
  "Run ft <pattern> [path] to search file contents"
  "Run extract <archive> to unpack a supported archive"
  "Run mkcd <dir> to create and enter a directory"
  "Run croot to jump to the current Git repository root"
  "Run glog to see the latest 20 commits as a graph"
  "Run gpr to pull the current branch with rebase"
  "Run gun to undo the latest commit but keep changes staged"
  "Run gitcount to count non-merge commits by contributor"
  "Run path to inspect every PATH entry"
  "Run dusage [path] [count] to rank immediate entries by size"
  "Run bigfiles [path] [count] to rank files recursively"
  "Run ports to show listening sockets and their processes"
  "Run myip to show your public IP address"
  "Run weather for a concise HTTPS forecast"
  "Run peek <file> for a quick file preview"
  "Run headers <url> to follow redirects and print HTTP headers"
  "Use G, L, or W to pipe to grep, less, or wc -l"
  "Use NE to hide stderr or NUL to hide all output"
  "Press Tab after a custom command to see valid arguments"
)

if [[ -r /sys/firmware/acpi/platform_profile || -r /sys/devices/platform/asus-nb-wmi/fan_boost_mode ]]; then
  _zsh_tip_pool+=("Run fanprofile to show the current laptop performance profile")
fi

if (( $+commands[zoxide] )); then
  _zsh_tip_pool+=("Use z <query> to jump to a remembered directory")
fi

if [[ ${_FZF_STATE:-blocked} == ready ]] && [[ -o interactive ]] && [[ -z ${ZSH_EXECUTION_STRING:-} ]]; then
  _zsh_tip_pool+=(
    "Press Ctrl+R to insert a history entry for editing"
    "Press Ctrl+T to insert a selected file path"
    "Press Alt+C to select and enter a directory"
    "Type in the unfilled fzf input row to filter; use the footer for keys"
    "Press Ctrl+P in preview pickers to toggle the preview; use Ctrl+/ to wrap"
    "Run fkill to select processes and send SIGTERM; use 9 only to force"
    "Run fbr to scan aligned branch details and enter or check out the result"
    "Use [WT] in fbr to spot branches checked out in another worktree"
  )

  if (( $+commands[zoxide] )); then
    _zsh_tip_pool+=("Use zi to select a remembered directory interactively")
  fi
fi

if alias lt >/dev/null 2>&1; then
  _zsh_tip_pool+=("Run lt for a tree view up to three levels deep")
fi

if (( $+functions[cgm] )); then
  _zsh_tip_pool+=(
    "Run cgm set OPENAI_KEY to store a credential securely"
    "Run cgm env OPENAI_KEY to load a credential into this shell"
    "Run cgm list to show saved names without retrieving values"
  )
fi

if (( $+commands[nix] )); then
  _zsh_tip_pool+=(
    "Run npkg add bat to add a package to the current Nix profile"
    "Run npkg search ripgrep to search nixpkgs"
    "Run npkg list to show the current Nix profile"
  )
fi

if (( $+commands[nix] && $+commands[jq] )); then
  _zsh_tip_pool+=(
    "Run npkg refresh to rebuild the nixpkgs attribute cache"
    "Run npkg outdated to check for Nix output changes"
  )
fi

if (( $+commands[nix] && $+commands[jq] )) && [[ ${_FZF_STATE:-blocked} == ready ]]; then
  _zsh_tip_pool+=(
    "Run npkg find nvim to open a seeded package picker"
    "Run npkg remove with no arguments to select installed packages"
  )
fi

if (( $+commands[paru] || $+commands[pacman] || $+commands[apt] || $+commands[dnf] || $+commands[brew] || $+commands[flatpak] || ($+commands[nix] && $+functions[npkg]) || $+commands[npm] )); then
  _zsh_tip_pool+=(
    "Run upkg to check detected package managers for updates"
    "Run upkg search ripgrep to search detected package managers"
    "Run upkg managers to show active and alternate backends"
    "Use upkg --only=brew,npm to select specific backends"
    "Run upkg plan to preview package upgrades"
    "Run upkg clean --dry-run before package cleanup"
  )
fi

if (( $+commands[paru] || $+commands[pacman] || $+commands[apt] || $+commands[dnf] )); then
  _zsh_tip_pool+=(
    "Run upkg upgrade --sudo to authorize system package upgrades"
    "Run upkg clean --sudo to authorize system package cleanup"
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
    print -r -- 'Run tips again'
    _ui_reset
    return 0
  fi

  print -- "tip: $tip"
}
