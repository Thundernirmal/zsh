# Useful shell functions.

# Extract any archive
extract() {
  if [ -z "$1" ]; then
    echo "Usage: extract <file>"
    return 1
  fi
  if [ ! -f "$1" ]; then
    echo "'$1' is not a valid file"
    return 1
  fi
  case $1 in
    *.tar.bz2)   tar xjf "$1" ;;
    *.tar.gz)    tar xzf "$1" ;;
    *.tar.xz)    tar xJf "$1" ;;
    *.tar.zst)   tar --zstd -xf "$1" ;;
    *.bz2)
      command -v bunzip2 >/dev/null 2>&1 || { echo "bunzip2 is required to extract '$1'"; return 1; }
      bunzip2 "$1"
      ;;
    *.rar)
      command -v unrar >/dev/null 2>&1 || { echo "unrar is required to extract '$1'"; return 1; }
      unrar x "$1"
      ;;
    *.gz)
      command -v gunzip >/dev/null 2>&1 || { echo "gunzip is required to extract '$1'"; return 1; }
      gunzip "$1"
      ;;
    *.tar)       tar xf "$1" ;;
    *.tbz2)      tar xjf "$1" ;;
    *.tgz)       tar xzf "$1" ;;
    *.tzst)      tar --zstd -xf "$1" ;;
    *.zip)
      command -v unzip >/dev/null 2>&1 || { echo "unzip is required to extract '$1'"; return 1; }
      unzip "$1"
      ;;
    *.Z)
      command -v uncompress >/dev/null 2>&1 || { echo "uncompress is required to extract '$1'"; return 1; }
      uncompress "$1"
      ;;
    *.7z)
      command -v 7z >/dev/null 2>&1 || { echo "7z is required to extract '$1'"; return 1; }
      7z x "$1"
      ;;
    *)           echo "'$1' cannot be extracted via extract()"; return 1 ;;
  esac
}

# Create directory and cd into it
mkcd() { command mkdir -p "$1" && cd "$1"; }

# Find files by name
ff() {
  if [ -z "$1" ]; then
    echo "Usage: ff <pattern> [path]"
    return 1
  fi

  local pattern=$1
  local search_root=${2:-.}

  if [ ! -d "$search_root" ]; then
    echo "'$search_root' is not a directory"
    return 1
  fi

  if command -v fd >/dev/null 2>&1; then
    fd --hidden --follow --glob --ignore-case -- "*$pattern*" "$search_root"
  elif command -v fdfind >/dev/null 2>&1; then
    fdfind --hidden --follow --glob --ignore-case -- "*$pattern*" "$search_root"
  else
    command find "$search_root" -iname "*$pattern*" 2>/dev/null
  fi
}

# Find text in files (uses ripgrep if available, falls back to grep)
ft() {
  if [ -z "$1" ]; then
    echo "Usage: ft <pattern> [path]"
    return 1
  fi

  if command -v rg >/dev/null 2>&1; then
    rg --color=always -- "$1" "${2:-.}"
  else
    command grep -rnI --color=auto -- "$1" "${2:-.}" 2>/dev/null
  fi
}

# Fuzzy kill process
fkill() {
  if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf is required for fkill"
    return 1
  fi

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "fkill requires an interactive terminal"
    return 1
  fi

  local signal=${1:-9}
  local selected pid
  local -a pids

  signal=${signal#-}
  selected=$(
    ps -ef | sed 1d | awk '
      {
        pid = $2
        $1 = $2 = $3 = $4 = $5 = $6 = $7 = ""
        sub(/^ +/, "")
        print pid "\t" $0
      }
    ' | fzf -m --delimiter=$'\t' --with-nth=2.. --header="Select process(es) to kill with SIG${signal}"
  ) || return 0

  while IFS=$'\t' read -r pid _; do
    [ -n "$pid" ] && pids+=("$pid")
  done <<< "$selected"

  (( ${#pids[@]} > 0 )) || return 0
  kill "-$signal" "${pids[@]}"
}

# Quick HTTP header check
headers() {
  if [ -z "$1" ]; then
    echo "Usage: headers <url>"
    return 1
  fi

  curl -sSIL -- "$1"
}

# Preview file (uses bat if available)
peek() {
  if [ -z "$1" ]; then
    echo "Usage: peek <file>"
    return 1
  fi

  if command -v bat >/dev/null 2>&1; then
    bat --style=numbers --paging=never -- "$1"
  else
    command cat -- "$1"
  fi
}

# Disk usage summary for current directory
dusage() {
  local target=${1:-.}
  local limit=${2:-20}
  local -a entries

  if [ ! -d "$target" ]; then
    echo "'$target' is not a directory"
    return 1
  fi

  case $limit in
    ''|*[!0-9]*)
      echo "Usage: dusage [path] [count]"
      return 1
      ;;
  esac

  entries=( "$target"/*(DN) )
  if (( ${#entries[@]} == 0 )); then
    echo "No entries found in '$target'"
    return 0
  fi

  du -sh -- "${entries[@]}" 2>/dev/null | sort -rh | head -n "$limit"
}

# Largest files in current directory tree
bigfiles() {
  local target=${1:-.}
  local limit=${2:-20}

  if [ ! -e "$target" ]; then
    echo "'$target' does not exist"
    return 1
  fi

  case $limit in
    ''|*[!0-9]*)
      echo "Usage: bigfiles [path] [count]"
      return 1
      ;;
  esac

  command find "$target" -type f -exec du -h {} + 2>/dev/null | sort -rh | head -n "$limit"
}

# Jump to the root of the current git repository
croot() {
  local root

  root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Not in a git repo"
    return 1
  }

  cd "$root" || return
}

# Print PATH one entry per line
path() {
  print -l -- ${(s/:/)PATH}
}

# Fuzzy-pick and checkout a git branch
fbr() {
  if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf is required for fbr"
    return 1
  fi

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "fbr requires an interactive terminal"
    return 1
  fi

  git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "Not in a git repo"
    return 1
  }

  local selection branch local_branch
  selection=$(
    git for-each-ref --sort=-committerdate \
      --format=$'%(refname:short)\t%(committerdate:relative)\t%(subject)' \
      refs/heads refs/remotes |
      command grep -v $'^[^[:space:]]+/HEAD\t' |
      fzf --ansi --height=50% --delimiter=$'\t' --with-nth=1,2,3 \
        --prompt='Branch> ' \
        --preview 'git log --oneline --decorate --color=always -20 {1}' \
        --preview-window=right,60%,border-left,wrap
  ) || return 0

  branch=${selection%%$'\t'*}

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout "$branch"
    return
  fi

  if git show-ref --verify --quiet "refs/remotes/$branch"; then
    local_branch=${branch#*/}
    if git show-ref --verify --quiet "refs/heads/$local_branch"; then
      git checkout "$local_branch"
    else
      git checkout --track "$branch"
    fi
    return
  fi

  echo "Branch '$branch' was not found"
  return 1
}

# Unified package update/check wrapper across supported managers.
_upkg_usage() {
  print 'Usage: upkg [command] [--only <list>] [--skip <list>] [--sudo] [--dry-run]'
  print ''
  print 'Commands:'
  print '  outdated            Show outdated packages across detected managers'
  print '  check               Alias for outdated'
  print '  list                Alias for outdated'
  print '  upgrade             Run upgrades across selected managers'
  print '  up                  Alias for upgrade'
  print '  update              Alias for upgrade'
  print '  plan                Preview available upgrades without changing packages'
  print '  managers            Show detected managers and alternates'
  print '  help                Show this help text'
  print ''
  print 'Flags:'
  print '  --only <list>       Comma-separated manager IDs to include'
  print '  --skip <list>       Comma-separated manager IDs to exclude'
  print '  --sudo              Allow privileged upgrade backends to run'
  print '  --dry-run           Preview upgrades instead of running them'
  print ''
  print 'Supported manager IDs:'
  print '  apt, dnf, pacman, paru, flatpak, nix, npm'
  print ''
  print 'Examples:'
  print '  upkg'
  print '  upkg managers'
  print '  upkg --only flatpak,npm'
  print '  upkg upgrade --sudo'
  print '  upkg upgrade --dry-run --only npm,flatpak'
  print '  upkg upgrade --sudo --only apt'
  print ''
  print 'Notes:'
  print '  - upkg with no command defaults to outdated'
  print '  - plan and --dry-run use the read-only outdated checks'
  print '  - upgrades never inject sudo automatically'
  print '  - paru upgrades require explicit --sudo opt-in but still run unprefixed'
  print '  - npm upgrades stay user-space only; upkg will not recommend sudo npm'
}

_upkg_parse_manager_list() {
  emulate -L zsh

  local raw=$1
  local item
  local -a parsed

  [ -n "$raw" ] || return 0

  for item in ${(s:,:)raw}; do
    item=${item//[[:space:]]/}

    if [ -z "$item" ]; then
      print -u2 -- "Empty manager id in list: $raw"
      return 1
    fi

    case $item in
      apt|dnf|pacman|paru|flatpak|nix|npm)
        parsed+=("$item")
        ;;
      *)
        print -u2 -- "Unsupported manager id: $item"
        return 1
        ;;
    esac
  done

  print -l -- "${parsed[@]}"
}

_upkg_detect_managers() {
  emulate -L zsh

  typeset -g -a _UPKG_ACTIVE_MANAGERS _UPKG_ALTERNATE_MANAGERS
  _UPKG_ACTIVE_MANAGERS=()
  _UPKG_ALTERNATE_MANAGERS=()

  if command -v paru >/dev/null 2>&1; then
    _UPKG_ACTIVE_MANAGERS+=(paru)
    if command -v pacman >/dev/null 2>&1; then
      _UPKG_ALTERNATE_MANAGERS+=(pacman)
    fi
  elif command -v pacman >/dev/null 2>&1; then
    _UPKG_ACTIVE_MANAGERS+=(pacman)
  elif command -v apt >/dev/null 2>&1; then
    _UPKG_ACTIVE_MANAGERS+=(apt)
  elif command -v dnf >/dev/null 2>&1; then
    _UPKG_ACTIVE_MANAGERS+=(dnf)
  fi

  if command -v flatpak >/dev/null 2>&1; then
    _UPKG_ACTIVE_MANAGERS+=(flatpak)
  fi

  if command -v nix >/dev/null 2>&1 && (( $+functions[npkg] )); then
    _UPKG_ACTIVE_MANAGERS+=(nix)
  fi

  if command -v npm >/dev/null 2>&1; then
    _UPKG_ACTIVE_MANAGERS+=(npm)
  fi
}

_upkg_apply_filters() {
  emulate -L zsh

  local only_raw=$1
  local skip_raw=$2
  local parsed manager
  local -a only_list skip_list candidate_pool selected filtered unavailable skipped
  local -A available seen skipped_map

  typeset -g -a _UPKG_SELECTED_MANAGERS _UPKG_SKIPPED_MANAGERS
  _UPKG_SELECTED_MANAGERS=()
  _UPKG_SKIPPED_MANAGERS=()

  candidate_pool=( "${_UPKG_ACTIVE_MANAGERS[@]}" "${_UPKG_ALTERNATE_MANAGERS[@]}" )
  for manager in "${candidate_pool[@]}"; do
    available[$manager]=1
  done

  if [ -n "$only_raw" ]; then
    parsed=$(_upkg_parse_manager_list "$only_raw") || return 1
    only_list=( ${(f)parsed} )

    for manager in "${only_list[@]}"; do
      if [ -z "${available[$manager]}" ]; then
        unavailable+=("$manager")
        continue
      fi

      if [ -z "${seen[$manager]}" ]; then
        selected+=("$manager")
        seen[$manager]=1
      fi
    done

    if (( ${#unavailable[@]} > 0 )); then
      print -u2 -- "Selected managers are not available: ${(j:, :)unavailable}"
      return 1
    fi
  else
    selected=( "${_UPKG_ACTIVE_MANAGERS[@]}" )
  fi

  if [ -n "$skip_raw" ]; then
    parsed=$(_upkg_parse_manager_list "$skip_raw") || return 1
    skip_list=( ${(f)parsed} )

    for manager in "${skip_list[@]}"; do
      skipped_map[$manager]=1
    done

    filtered=()
    for manager in "${selected[@]}"; do
      if [ -n "${skipped_map[$manager]}" ]; then
        skipped+=("$manager")
      else
        filtered+=("$manager")
      fi
    done
    selected=( "${filtered[@]}" )
  fi

  _UPKG_SELECTED_MANAGERS=( "${selected[@]}" )
  _UPKG_SKIPPED_MANAGERS=( "${skipped[@]}" )
}

_upkg_manager_title() {
  case $1 in
    apt) print 'APT' ;;
    dnf) print 'DNF' ;;
    pacman) print 'Pacman' ;;
    paru) print 'Paru' ;;
    flatpak) print 'Flatpak' ;;
    nix) print 'Nix (npkg)' ;;
    npm) print 'npm' ;;
    *) print -r -- "$1" ;;
  esac
}

_upkg_print_section() {
  emulate -L zsh

  local title

  title=$(_upkg_manager_title "$1")
  print ''
  print "==> $title"
}

_upkg_set_last_result() {
  typeset -g _UPKG_LAST_STATE=$1
  typeset -g _UPKG_LAST_DETAIL=$2
}

_upkg_record_summary() {
  emulate -L zsh

  local manager=$1
  local state=$2
  local detail=$3

  _UPKG_SUMMARY_ORDER+=("$manager")
  _UPKG_SUMMARY_STATE[$manager]=$state
  _UPKG_SUMMARY_DETAIL[$manager]=$detail
}

_upkg_print_summary() {
  emulate -L zsh

  local manager detail

  print ''
  print 'Summary:'

  for manager in "${_UPKG_SUMMARY_ORDER[@]}"; do
    detail=${_UPKG_SUMMARY_DETAIL[$manager]}
    if [ -n "$detail" ]; then
      print "  ${manager}: ${_UPKG_SUMMARY_STATE[$manager]} - $detail"
    else
      print "  ${manager}: ${_UPKG_SUMMARY_STATE[$manager]}"
    fi
  done
}

_upkg_finish_upgrade_result() {
  emulate -L zsh

  local rc=$1
  local detail=$2

  if (( rc == 0 )); then
    _upkg_set_last_result 'upgraded' ''
    return 0
  fi

  _upkg_set_last_result 'failed' "$detail"
  return 1
}

_upkg_arch_outdated_has_no_updates() {
  emulate -L zsh

  local rc=$1
  local output=$2

  (( rc == 1 )) && [ -z "$output" ]
}

_upkg_npm_prefix() {
  emulate -L zsh

  local prefix

  prefix=$(command npm config get prefix 2>/dev/null) || return 1
  prefix=${prefix//$'\r'/}

  if [ -z "$prefix" ] || [ "$prefix" = 'undefined' ] || [ "$prefix" = 'null' ]; then
    return 1
  fi

  print -r -- "$prefix"
}

_upkg_print_npm_prefix_hint() {
  emulate -L zsh

  print 'Configure a user-space npm prefix under your home directory, for example:'
  print '  mkdir -p "$HOME/.local/npm"'
  print '  npm config set prefix "$HOME/.local/npm"'
  print '  export PATH="$HOME/.local/npm/bin:$PATH"'
}

_upkg_require_sudo_command() {
  emulate -L zsh

  if (( EUID == 0 )); then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    return 0
  fi

  print 'sudo is not installed; rerun this backend as root or install sudo first.'
  _upkg_set_last_result 'blocked' 'sudo is not installed; rerun as root'
  return 1
}

_upkg_npm_outdated_looks_valid() {
  emulate -L zsh

  local output=$1
  local line

  for line in ${(f)output}; do
    [ -n "$line" ] || continue
    [[ $line == Package[[:space:]]*Current[[:space:]]*Wanted[[:space:]]*Latest* ]]
    return $?
  done

  return 1
}

_upkg_run_outdated_apt() {
  emulate -L zsh

  local output line
  local -a packages

  _upkg_print_section apt

  output=$(command apt list --upgradable 2>/dev/null) || {
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'apt list --upgradable failed'
    return 1
  }

  for line in ${(f)output}; do
    [[ $line == */* ]] || continue
    packages+=("$line")
  done

  if (( ${#packages[@]} == 0 )); then
    print 'No updates available.'
    _upkg_set_last_result 'up to date' ''
    return 0
  fi

  print -l -- "${packages[@]}"
  _upkg_set_last_result 'updates available' ''
}

_upkg_run_outdated_dnf() {
  emulate -L zsh

  local output rc

  _upkg_print_section dnf

  output=$(command dnf check-update 2>&1)
  rc=$?

  case $rc in
    0)
      print 'No updates available.'
      _upkg_set_last_result 'up to date' ''
      ;;
    100)
      [ -n "$output" ] && print -r -- "$output"
      _upkg_set_last_result 'updates available' ''
      ;;
    *)
      [ -n "$output" ] && print -r -- "$output"
      _upkg_set_last_result 'failed' 'dnf check-update failed'
      return 1
      ;;
  esac
}

_upkg_run_outdated_pacman() {
  emulate -L zsh

  local output rc

  _upkg_print_section pacman

  output=$(command pacman -Qu 2>&1)
  rc=$?

  if _upkg_arch_outdated_has_no_updates "$rc" "$output"; then
    print 'No updates available.'
    _upkg_set_last_result 'up to date' ''
    return 0
  fi

  if (( rc != 0 )); then
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'pacman -Qu failed'
    return 1
  fi

  if [ -n "$output" ]; then
    print -r -- "$output"
    _upkg_set_last_result 'updates available' ''
  else
    print 'No updates available.'
    _upkg_set_last_result 'up to date' ''
  fi
}

_upkg_run_outdated_paru() {
  emulate -L zsh

  local pacman_output='' paru_output='' repo_error=''
  local pacman_rc=0 paru_rc=0
  local had_updates=0 repo_failed=0

  _upkg_print_section paru

  if command -v pacman >/dev/null 2>&1; then
    pacman_output=$(command pacman -Qu 2>&1)
    pacman_rc=$?

    if _upkg_arch_outdated_has_no_updates "$pacman_rc" "$pacman_output"; then
      pacman_output=''
    elif (( pacman_rc != 0 )); then
      repo_failed=1
      repo_error='pacman -Qu failed while checking paru repo updates'
    fi
  else
    pacman_output=$(command paru -Qu 2>&1)
    pacman_rc=$?

    if _upkg_arch_outdated_has_no_updates "$pacman_rc" "$pacman_output"; then
      pacman_output=''
    elif (( pacman_rc != 0 )); then
      repo_failed=1
      repo_error='paru -Qu failed'
    fi
  fi

  paru_output=$(command paru -Qua 2>&1)
  paru_rc=$?

  if _upkg_arch_outdated_has_no_updates "$paru_rc" "$paru_output"; then
    paru_output=''
    paru_rc=0
  fi

  if (( repo_failed )); then
    print 'Repo updates:'
    if [ -n "$pacman_output" ]; then
      print -r -- "$pacman_output"
    else
      print 'Repo update check failed.'
    fi
    print 'Repo update check failed; continuing with AUR preview.'
  elif [ -n "$pacman_output" ]; then
    print 'Repo updates:'
    print -r -- "$pacman_output"
    had_updates=1
  fi

  if (( paru_rc != 0 )); then
    (( repo_failed || had_updates )) && print ''
    print 'AUR updates:'
    [ -n "$paru_output" ] && print -r -- "$paru_output"
    if (( repo_failed )); then
      _upkg_set_last_result 'failed' "$repo_error; paru -Qua failed"
    else
      _upkg_set_last_result 'failed' 'paru -Qua failed'
    fi
    return 1
  fi

  if [ -n "$paru_output" ]; then
    (( repo_failed || had_updates )) && print ''
    print 'AUR updates:'
    print -r -- "$paru_output"
    had_updates=1
  elif (( repo_failed )); then
    print ''
    print 'AUR updates:'
    print 'No updates available.'
  fi

  if (( repo_failed )); then
    _upkg_set_last_result 'failed' "$repo_error; AUR preview still shown"
    return 1
  fi

  if (( had_updates )); then
    _upkg_set_last_result 'updates available' ''
  else
    print 'No updates available.'
    _upkg_set_last_result 'up to date' ''
  fi
}

_upkg_run_outdated_flatpak() {
  emulate -L zsh

  local output rc

  _upkg_print_section flatpak

  output=$(command flatpak remote-ls --user --updates 2>&1)
  rc=$?

  if (( rc != 0 )); then
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'flatpak remote-ls --user --updates failed'
    return 1
  fi

  if [ -n "$output" ]; then
    print -r -- "$output"
    _upkg_set_last_result 'updates available' ''
  else
    print 'No updates available.'
    _upkg_set_last_result 'up to date' ''
  fi
}

_upkg_run_outdated_nix() {
  emulate -L zsh

  local output rc

  _upkg_print_section nix

  if ! command -v jq >/dev/null 2>&1; then
    print 'jq is required for npkg outdated; install jq or run upkg upgrade --only nix.'
    _upkg_set_last_result 'blocked' 'jq is required for nix outdated'
    return 0
  fi

  output=$(npkg outdated 2>&1)
  rc=$?

  [ -n "$output" ] && print -r -- "$output"

  if (( rc != 0 )); then
    _upkg_set_last_result 'failed' 'npkg outdated failed'
    return 1
  fi

  if [[ $output == *'upgrade(s) available.'* ]]; then
    _upkg_set_last_result 'updates available' ''
  else
    _upkg_set_last_result 'up to date' ''
  fi
}

_upkg_run_outdated_npm() {
  emulate -L zsh

  local stdout_file stderr_file stdout_output stderr_output rc

  _upkg_print_section npm

  stdout_file=$(command mktemp) || {
    _upkg_set_last_result 'failed' 'could not create a temp file for npm outdated'
    return 1
  }
  stderr_file=$(command mktemp) || {
    command rm -f -- "$stdout_file"
    _upkg_set_last_result 'failed' 'could not create a temp file for npm outdated'
    return 1
  }

  command npm outdated -g --depth=0 >"$stdout_file" 2>"$stderr_file"
  rc=$?

  stdout_output=$(<"$stdout_file")
  stderr_output=$(<"$stderr_file")
  command rm -f -- "$stdout_file" "$stderr_file"

  case $rc in
    0)
      if [ -n "$stdout_output" ]; then
        print -r -- "$stdout_output"
        _upkg_set_last_result 'updates available' ''
      else
        print 'No updates available.'
        _upkg_set_last_result 'up to date' ''
      fi
      ;;
    1)
      if [ -z "$stderr_output" ] && _upkg_npm_outdated_looks_valid "$stdout_output"; then
        print -r -- "$stdout_output"
        _upkg_set_last_result 'updates available' ''
      else
        [ -n "$stdout_output" ] && print -r -- "$stdout_output"
        [ -n "$stderr_output" ] && print -u2 -- "$stderr_output"
        _upkg_set_last_result 'failed' 'npm outdated -g failed'
        return 1
      fi
      ;;
    *)
      [ -n "$stdout_output" ] && print -r -- "$stdout_output"
      [ -n "$stderr_output" ] && print -u2 -- "$stderr_output"
      _upkg_set_last_result 'failed' 'npm outdated -g failed'
      return 1
      ;;
  esac
}

_upkg_run_upgrade_apt() {
  emulate -L zsh

  local rc

  _upkg_print_section apt

  if (( EUID != 0 && ! _UPKG_ALLOW_SUDO )); then
    print 'apt upgrade requires root; rerun with: upkg upgrade --sudo --only apt'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only apt'
    return 0
  fi

  _upkg_require_sudo_command || return 0

  if (( EUID == 0 )); then
    command apt update
    rc=$?
    if (( rc != 0 )); then
      _upkg_set_last_result 'failed' 'apt update failed'
      return 1
    fi
    command apt full-upgrade
  else
    command sudo apt update
    rc=$?
    if (( rc != 0 )); then
      _upkg_set_last_result 'failed' 'sudo apt update failed'
      return 1
    fi
    command sudo apt full-upgrade
  fi
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'apt full-upgrade failed'
}

_upkg_run_upgrade_dnf() {
  emulate -L zsh

  local rc

  _upkg_print_section dnf

  if (( EUID != 0 && ! _UPKG_ALLOW_SUDO )); then
    print 'dnf upgrade requires root; rerun with: upkg upgrade --sudo --only dnf'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only dnf'
    return 0
  fi

  _upkg_require_sudo_command || return 0

  if (( EUID == 0 )); then
    command dnf upgrade --refresh
  else
    command sudo dnf upgrade --refresh
  fi
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'dnf upgrade --refresh failed'
}

_upkg_run_upgrade_pacman() {
  emulate -L zsh

  local rc

  _upkg_print_section pacman

  if (( EUID != 0 && ! _UPKG_ALLOW_SUDO )); then
    print 'pacman upgrade requires root; rerun with: upkg upgrade --sudo --only pacman'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only pacman'
    return 0
  fi

  _upkg_require_sudo_command || return 0

  if (( EUID == 0 )); then
    command pacman -Syu
  else
    command sudo pacman -Syu
  fi
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'pacman -Syu failed'
}

_upkg_run_upgrade_paru() {
  emulate -L zsh

  local rc

  _upkg_print_section paru

  if (( ! _UPKG_ALLOW_SUDO )); then
    print 'paru upgrade requires explicit --sudo opt-in; rerun with: upkg upgrade --sudo --only paru'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only paru'
    return 0
  fi

  command paru -Syu
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'paru -Syu failed'
}

_upkg_run_upgrade_flatpak() {
  emulate -L zsh

  local rc

  _upkg_print_section flatpak

  command flatpak update --user
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'flatpak update --user failed'
}

_upkg_run_upgrade_nix() {
  emulate -L zsh

  local rc

  _upkg_print_section nix

  npkg upgrade
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'npkg upgrade failed'
}

_upkg_run_upgrade_npm() {
  emulate -L zsh

  local prefix rc

  _upkg_print_section npm

  prefix=$(_upkg_npm_prefix) || {
    print 'Failed to determine the npm global prefix.'
    _upkg_set_last_result 'failed' 'could not determine npm global prefix'
    return 1
  }

  if [ ! -d "$prefix" ] || [ ! -w "$prefix" ]; then
    print "npm global prefix '$prefix' is not writable by the current user."
    _upkg_print_npm_prefix_hint
    _upkg_set_last_result 'blocked' 'configure a user-writable npm prefix'
    return 0
  fi

  command npm update -g
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'npm update -g failed'
}

upkg() {
  emulate -L zsh

  local raw_cmd='' cmd='outdated' manager parsed
  local only_raw='' skip_raw=''
  local allow_sudo=0 dry_run=0 filtered=0 exit_code=0
  local -a candidate_pool run_order display_order
  local -A selected_map skipped_map alternate_map display_seen

  while (( $# > 0 )); do
    case $1 in
      --only)
        shift
        if (( $# == 0 )); then
          print -u2 -- 'Missing value for --only'
          _upkg_usage
          return 1
        fi
        only_raw=$1
        ;;
      --only=*)
        only_raw=${1#--only=}
        if [ -z "$only_raw" ]; then
          print -u2 -- 'Missing value for --only'
          _upkg_usage
          return 1
        fi
        ;;
      --skip)
        shift
        if (( $# == 0 )); then
          print -u2 -- 'Missing value for --skip'
          _upkg_usage
          return 1
        fi
        skip_raw=$1
        ;;
      --skip=*)
        skip_raw=${1#--skip=}
        if [ -z "$skip_raw" ]; then
          print -u2 -- 'Missing value for --skip'
          _upkg_usage
          return 1
        fi
        ;;
      --sudo)
        allow_sudo=1
        ;;
      --dry-run)
        dry_run=1
        ;;
      help|-h|--help)
        raw_cmd='help'
        ;;
      outdated|check|list|upgrade|up|update|plan|managers)
        if [ -n "$raw_cmd" ] && [ "$raw_cmd" != "$1" ]; then
          print -u2 -- "Unexpected extra command: $1"
          _upkg_usage
          return 1
        fi
        raw_cmd=$1
        ;;
      *)
        print -u2 -- "Unknown argument: $1"
        _upkg_usage
        return 1
        ;;
    esac
    shift
  done

  case ${raw_cmd:-outdated} in
    outdated|check|list) cmd='outdated' ;;
    upgrade|up|update) cmd='upgrade' ;;
    plan) cmd='plan' ;;
    managers) cmd='managers' ;;
    help) cmd='help' ;;
  esac

  if (( dry_run )); then
    if [ "$cmd" = 'upgrade' ]; then
      cmd='plan'
    elif [ "$cmd" = 'outdated' ] || [ "$cmd" = 'plan' ]; then
      cmd='plan'
    else
      print -u2 -- '--dry-run is only valid with upgrade or plan'
      _upkg_usage
      return 1
    fi
  fi

  if [ "$cmd" = 'help' ]; then
    _upkg_usage
    return 0
  fi

  _upkg_detect_managers

  if (( ${#_UPKG_ACTIVE_MANAGERS[@]} == 0 && ${#_UPKG_ALTERNATE_MANAGERS[@]} == 0 )); then
    print -u2 -- 'No supported package managers detected.'
    return 1
  fi

  candidate_pool=( "${_UPKG_ACTIVE_MANAGERS[@]}" "${_UPKG_ALTERNATE_MANAGERS[@]}" )
  for manager in "${_UPKG_ALTERNATE_MANAGERS[@]}"; do
    alternate_map[$manager]=1
  done

  if [ "$cmd" = 'managers' ]; then
    if [ -n "$only_raw" ] || [ -n "$skip_raw" ]; then
      _upkg_apply_filters "$only_raw" "$skip_raw" || return 1
      filtered=1
      for manager in "${_UPKG_SELECTED_MANAGERS[@]}"; do
        selected_map[$manager]=1
      done
      for manager in "${_UPKG_SKIPPED_MANAGERS[@]}"; do
        skipped_map[$manager]=1
      done
    fi

    display_order=( "${candidate_pool[@]}" )
    if (( filtered )); then
      display_order=()
      for manager in "${_UPKG_SELECTED_MANAGERS[@]}" "${_UPKG_SKIPPED_MANAGERS[@]}" "${candidate_pool[@]}"; do
        if [ -n "$manager" ] && [ -z "${display_seen[$manager]}" ]; then
          display_order+=("$manager")
          display_seen[$manager]=1
        fi
      done
    fi

    print 'Detected managers:'
    for manager in "${display_order[@]}"; do
      if [ -n "${skipped_map[$manager]}" ]; then
        print "  - $manager (skipped by filter)"
      elif [ -n "${selected_map[$manager]}" ]; then
        if [ -n "${alternate_map[$manager]}" ]; then
          print "  - $manager (selected via --only)"
        else
          print "  - $manager (selected)"
        fi
      elif (( filtered )); then
        if [ -n "${alternate_map[$manager]}" ]; then
          print "  - $manager (available via --only $manager)"
        else
          print "  - $manager (not selected)"
        fi
      elif [ -n "${alternate_map[$manager]}" ]; then
        print "  - $manager (available via --only $manager)"
      else
        print "  - $manager"
      fi
    done

    if (( filtered && ${#_UPKG_SELECTED_MANAGERS[@]} == 0 )); then
      return 1
    fi

    return 0
  fi

  _upkg_apply_filters "$only_raw" "$skip_raw" || return 1

  if (( ${#_UPKG_SELECTED_MANAGERS[@]} == 0 )); then
    print -u2 -- 'No package managers selected after applying filters.'
    return 1
  fi

  typeset -g _UPKG_ALLOW_SUDO=$allow_sudo
  typeset -g -a _UPKG_SUMMARY_ORDER
  typeset -g -A _UPKG_SUMMARY_STATE _UPKG_SUMMARY_DETAIL
  _UPKG_SUMMARY_ORDER=()
  _UPKG_SUMMARY_STATE=()
  _UPKG_SUMMARY_DETAIL=()

  for manager in "${_UPKG_SELECTED_MANAGERS[@]}"; do
    selected_map[$manager]=1
  done
  for manager in "${_UPKG_SKIPPED_MANAGERS[@]}"; do
    skipped_map[$manager]=1
  done

  run_order=( "${_UPKG_SELECTED_MANAGERS[@]}" )

  for manager in "${run_order[@]}"; do
    if [ -n "${skipped_map[$manager]}" ]; then
      _upkg_record_summary "$manager" 'skipped' ''
      continue
    fi

    case "${cmd}:${manager}" in
      outdated:apt) _upkg_run_outdated_apt ;;
      outdated:dnf) _upkg_run_outdated_dnf ;;
      outdated:pacman) _upkg_run_outdated_pacman ;;
      outdated:paru) _upkg_run_outdated_paru ;;
      outdated:flatpak) _upkg_run_outdated_flatpak ;;
      outdated:nix) _upkg_run_outdated_nix ;;
      outdated:npm) _upkg_run_outdated_npm ;;
      plan:apt) _upkg_run_outdated_apt ;;
      plan:dnf) _upkg_run_outdated_dnf ;;
      plan:pacman) _upkg_run_outdated_pacman ;;
      plan:paru) _upkg_run_outdated_paru ;;
      plan:flatpak) _upkg_run_outdated_flatpak ;;
      plan:nix) _upkg_run_outdated_nix ;;
      plan:npm) _upkg_run_outdated_npm ;;
      upgrade:apt) _upkg_run_upgrade_apt ;;
      upgrade:dnf) _upkg_run_upgrade_dnf ;;
      upgrade:pacman) _upkg_run_upgrade_pacman ;;
      upgrade:paru) _upkg_run_upgrade_paru ;;
      upgrade:flatpak) _upkg_run_upgrade_flatpak ;;
      upgrade:nix) _upkg_run_upgrade_nix ;;
      upgrade:npm) _upkg_run_upgrade_npm ;;
      *)
        _upkg_print_section "$manager"
        print "No handler defined for $manager"
        _upkg_set_last_result 'failed' 'missing handler'
        ;;
    esac

    _upkg_record_summary "$manager" "$_UPKG_LAST_STATE" "$_UPKG_LAST_DETAIL"

    case $_UPKG_LAST_STATE in
      blocked|failed)
        exit_code=1
        ;;
    esac
  done

  for manager in "${_UPKG_SKIPPED_MANAGERS[@]}"; do
    _upkg_record_summary "$manager" 'skipped' ''
  done

  _upkg_print_summary
  return $exit_code
}

# Thin apt-like wrapper around nix profile with optional fzf pickers.
if command -v nix >/dev/null 2>&1; then
  _npkg_nix() {
    command nix --extra-experimental-features "nix-command flakes" "$@"
  }

  _npkg_usage() {
    print 'Usage: npkg <command> [args]'
    print ''
    print 'Commands:'
    print '  add [pkg ...]        Add package(s); with no args opens an fzf picker'
    print '  install [pkg ...]    Alias for add'
    print '  find [query]         Fuzzy-pick nixpkgs attribute names and add selections'
    print '  search <query>       Run a plain nixpkgs search with descriptions'
    print '  list                 List packages in the current profile'
    print '  remove [pkg ...]     Remove package(s); with no args opens an fzf picker'
    print '  outdated             Show available package upgrades before running upgrade'
    print '  refresh              Rebuild the cached nixpkgs attribute index'
    print '  upgrade [pkg ...]    Upgrade all packages or only the named ones'
    print '  help                 Show this help text'
    print ''
    print 'Examples:'
    print '  npkg add bat'
    print '  npkg find nvim'
    print '  npkg remove'
    print '  npkg outdated'
    print '  npkg refresh'
    print '  npkg upgrade'
    print ''
    print 'Notes:'
    print '  - Bare install names are expanded to nixpkgs#<name>'
    print '  - npkg find searches a cached list of nixpkgs attribute names'
    print '  - npkg refresh and outdated need jq'
    print '  - Interactive add/find/remove needs jq and fzf'
    print '  - Advanced nix flags can be passed through by calling nix directly'
  }

  _npkg_current_system() {
    _npkg_nix eval --impure --raw --expr 'builtins.currentSystem'
  }

  _npkg_attr_cache_file() {
    emulate -L zsh

    local system cache_dir

    system=$(_npkg_current_system) || return 1
    cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/npkg

    print -r -- "${cache_dir}/nixpkgs-attrs-${system}.txt"
  }

  _npkg_cache_is_stale() {
    emulate -L zsh

    local cache_file=$1
    local -A cache_stat

    if [ ! -s "$cache_file" ]; then
      return 0
    fi

    zmodload zsh/datetime 2>/dev/null || return 0
    zmodload zsh/stat 2>/dev/null || return 0
    zstat -H cache_stat -- "$cache_file" 2>/dev/null || return 0

    (( EPOCHSECONDS - cache_stat[mtime] >= 86400 ))
  }

  _npkg_refresh_index() {
    emulate -L zsh
    setopt pipefail

    local system cache_dir cache_file error_file

    if ! command -v jq >/dev/null 2>&1; then
      echo "jq is required for npkg refresh"
      return 1
    fi

    system=$(_npkg_current_system) || return 1
    cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/npkg
    cache_file="${cache_dir}/nixpkgs-attrs-${system}.txt"
    error_file="${cache_file}.err"

    command mkdir -p "$cache_dir" || return 1

    _npkg_nix eval --json "nixpkgs#legacyPackages.${system}" --apply builtins.attrNames 2>"$error_file" |
      command jq -r '.[]' > "${cache_file}.tmp" || {
        [ -f "${cache_file}.tmp" ] && command rm -f "${cache_file}.tmp"
        if [ -s "$error_file" ]; then
          command cat "$error_file"
          command rm -f "$error_file"
        fi
        return 1
      }

    command mv "${cache_file}.tmp" "$cache_file" || return 1
    command rm -f "$error_file"
    print -r -- "$cache_file"
  }

  _npkg_attr_index() {
    emulate -L zsh

    local cache_file

    cache_file=$(_npkg_attr_cache_file) || return 1

    if _npkg_cache_is_stale "$cache_file"; then
      if [ -f "$cache_file" ]; then
        print -u2 -- 'Refreshing nixpkgs attribute cache...'
      else
        print -u2 -- 'Building nixpkgs attribute cache...'
      fi

      _npkg_refresh_index >/dev/null || return 1
    fi

    print -r -- "$cache_file"
  }

  _npkg_require_picker() {
    local action=$1

    if ! command -v jq >/dev/null 2>&1; then
      echo "jq is required for interactive npkg ${action}"
      echo "Install jq or use non-interactive commands like 'npkg search <query>'"
      return 1
    fi

    if ! command -v fzf >/dev/null 2>&1; then
      echo "fzf is required for interactive npkg ${action}"
      return 1
    fi

    if [ ! -t 0 ] || [ ! -t 1 ]; then
      echo "Interactive npkg ${action} requires a terminal"
      return 1
    fi
  }

  _npkg_pick_installables() {
    emulate -L zsh

    local cache_file selection attr query
    local -a installables

    _npkg_require_picker 'install' || return 1

    query="${(j: :)@}"
    cache_file=$(_npkg_attr_index) || return 1

    selection=$(
      command fzf -m \
        --prompt='Nix install> ' \
        --query="$query" \
        --header='Type to filter attribute names, Tab marks packages, Enter adds' \
        --preview '
            attr={}
            printf "\033[1;36mAttr:\033[0m %s\n" "$attr"
            printf "\033[1;36mInstall ref:\033[0m nixpkgs#%s\n\n" "$attr"
            meta_json=$(command nix --extra-experimental-features "nix-command flakes" \
              eval --json --apply "p: { v = p.version or \"\"; d = p.meta.description or \"\"; h = p.meta.homepage or \"\"; }" "nixpkgs#$attr" 2>/dev/null || echo "{}")

            desc=$(echo "$meta_json" | command jq -r ".d | select(. != \"\") // empty")
            ver=$(echo "$meta_json" | command jq -r ".v | select(. != \"\") // empty")
            hp=$(echo "$meta_json" | command jq -r ".h | select(. != \"\") // empty")

            if [ -n "$desc" ]; then
              printf "\033[1;33mDescription:\033[0m\n%s\n\n" "$desc"
            else
              printf "\033[2m(no description available)\033[0m\n\n"
            fi

            if [ -n "$ver" ]; then
              printf "\033[1;33mVersion:\033[0m %s\n" "$ver"
            fi

            if [ -n "$hp" ]; then
              printf "\033[1;33mHomepage:\033[0m %s\n" "$hp"
            fi
          ' \
        --preview-window=right,45%,border-left,wrap \
        < "$cache_file"
    ) || return 0

    while IFS= read -r attr; do
      [ -n "$attr" ] && installables+=("nixpkgs#$attr")
    done <<< "$selection"

    (( ${#installables[@]} > 0 )) || return 0
    _npkg_nix profile add "${installables[@]}"
  }

  _npkg_remove_picker() {
    emulate -L zsh
    setopt pipefail

    local candidates selection
    local -a targets

    _npkg_require_picker 'remove' || return 1

    candidates=$(
      _npkg_nix profile list --json |
        command jq -r '
          def clean_text:
            tostring
            | gsub("[\r\n\t]+"; " ")
            | gsub("  +"; " ");

          def manifest_entries:
            if (.elements | type) == "object" then
              .elements
              | to_entries
              | sort_by(.key)
              | map(select(.value.active // true))
              | .[]
              | {
                  target: .key,
                  name: .key,
                  attr: (.value.attrPath // ""),
                  source: (.value.originalUrl // .value.originalUri // .value.url // .value.uri // "")
                }
            elif (.elements | type) == "array" then
              .elements[]
              | select(.active // true)
              | {
                  target: (.storePaths[0] // .attrPath // ""),
                  name: ((.attrPath // (.storePaths[0] // "")) | split(".")[-1]),
                  attr: (.attrPath // ""),
                  source: (.originalUrl // .originalUri // .url // .uri // "")
                }
            else
              empty
            end;

          manifest_entries
          | select(.target != "")
          | [
              .target,
              .name,
              .attr,
              (.source | clean_text)
            ]
          | @tsv
        '
    ) || return 1

    if [ -z "$candidates" ]; then
      echo "No packages are installed in the current Nix profile"
      return 0
    fi

    selection=$(
      print -r -- "$candidates" |
        command fzf -m --delimiter=$'\t' --with-nth=2,3,4 \
          --prompt='Nix remove> ' \
          --header='Tab marks packages, Enter removes' \
          --preview 'printf "Name: %s\nAttr: %s\nSource: %s\n" {2} {3} {4}' \
          --preview-window=right,60%,border-left,wrap
    ) || return 0

    while IFS=$'\t' read -r target _; do
      [ -n "$target" ] && targets+=("$target")
    done <<< "$selection"

    (( ${#targets[@]} > 0 )) || return 0
    _npkg_nix profile remove "${targets[@]}"
  }

  _npkg_outdated() {
    emulate -L zsh
    setopt pipefail NO_MONITOR NO_NOTIFY

    if ! command -v jq >/dev/null 2>&1; then
      echo "jq is required for npkg outdated"
      return 1
    fi

    local profile_json pkg_count tmp_dir
    local -a names attrs installed_versions

    profile_json=$(_npkg_nix profile list --json 2>/dev/null) || {
      echo "Failed to read profile"
      return 1
    }

    # Extract the profile name, full flake attrPath, and store-path-derived
    # version for each nixpkgs-sourced element.
    # version_from_path strips known Nix multi-output suffixes (man, lib,
    # dev, doc, info, bin, out, debug, static) so that e.g.
    # "tree-2.3.1-man" yields "2.3.1" instead of "2.3.1-man".
    local entry_data
    entry_data=$(
      print -r -- "$profile_json" | command jq -r '
        def version_from_path:
          split("/")[-1]            # basename
          | split("-")              # split on hyphens
          # strip known Nix multi-output suffixes from the end
          | if .[-1] | test("^(out|lib|dev|man|doc|info|bin|static|debug|py)$")
            then .[:-1] else . end
          | . as $parts
          | (length - 1) as $last
          | reduce range($last; 0; -1) as $i (
              null;
              if . == null and ($parts[$i] | test("^[0-9]")) then $i else . end
            )
          | if . then [$parts[.:][] ] | join("-") else "??" end;

        if (.elements | type) == "object" then
          .elements | to_entries[]
          | select((.value.originalUrl // .value.originalUri // .value.url // .value.uri // "") | test("nixpkgs"; "i"))
          | select(.value.active // true)
          | .key as $name
          | (.value.attrPath // "") as $attr
          | (.value.storePaths[0] // "") as $sp
          | ($sp | version_from_path) as $ver
          | [$name, $attr, $ver] | @tsv
        elif (.elements | type) == "array" then
          .elements[]
          | select(.active // true)
          | select((.originalUrl // .originalUri // .url // .uri // "") | test("nixpkgs"; "i"))
          | (.attrPath // "") as $attr
          | ($attr | split(".")[-1]) as $name
          | (.storePaths[0] // "") as $sp
          | ($sp | version_from_path) as $ver
          | [$name, $attr, $ver] | @tsv
        else
          empty
        end
      '
    ) || return 1

    if [ -z "$entry_data" ]; then
      echo "No nixpkgs packages found in the current profile"
      return 0
    fi

    # Read entries into arrays
    while IFS=$'\t' read -r name attr ver; do
      [ -z "$name" ] && continue
      names+=("$name")
      attrs+=("$attr")
      installed_versions+=("$ver")
    done <<< "$entry_data"

    pkg_count=${#names[@]}
    if (( pkg_count == 0 )); then
      echo "No nixpkgs packages found in the current profile"
      return 0
    fi

    echo "Checking $pkg_count package(s) for updates..."

    # Evaluate latest versions in parallel via temp files
    tmp_dir=$(command mktemp -d) || return 1
    trap "command rm -rf '$tmp_dir'; trap - EXIT INT TERM; return 1" INT TERM
    trap "command rm -rf '$tmp_dir'" EXIT

    local max_jobs=8 running=0 idx attr_name
    for (( idx = 1; idx <= pkg_count; idx++ )); do
      attr_name="${attrs[$idx]}"
      (
        local latest
        latest=$(_npkg_nix eval --raw "nixpkgs#${attr_name}.version" 2>/dev/null) || latest="??"
        print -r -- "$latest" > "${tmp_dir}/${idx}"
      ) &
      (( running++ ))
      if (( running >= max_jobs )); then
        wait
        running=0
      fi
    done
    wait

    # Collect results and build output
    local -a latest_versions
    local upgrades=0
    for (( idx = 1; idx <= pkg_count; idx++ )); do
      if [ -f "${tmp_dir}/${idx}" ]; then
        latest_versions+=("$(< "${tmp_dir}/${idx}")")
      else
        latest_versions+=("??")
      fi
    done

    # Print table
    local name inst avail marker
    printf '\n'
    printf '\033[1m%-25s %-20s %-20s %s\033[0m\n' 'Package' 'Installed' 'Available' ''
    printf '%-25s %-20s %-20s %s\n' '───────' '─────────' '─────────' ''

    for (( idx = 1; idx <= pkg_count; idx++ )); do
      name="${names[$idx]}"
      inst="${installed_versions[$idx]}"
      avail="${latest_versions[$idx]}"

      if [ "$inst" = "??" ] || [ "$avail" = "??" ]; then
        marker='—'
      elif [ "$inst" = "$avail" ]; then
        marker='\033[32m✓\033[0m'
      else
        marker='\033[33m⬆\033[0m'
        (( upgrades++ ))
      fi

      printf '%-25s %-20s %-20s %b\n' "$name" "$inst" "$avail" "$marker"
    done

    printf '\n'
    if (( upgrades > 0 )); then
      printf '\033[33m%d upgrade(s) available.\033[0m Run \033[1mnpkg upgrade\033[0m to apply.\n' "$upgrades"
    else
      printf '\033[32mEverything is up to date.\033[0m\n'
    fi

    command rm -rf "$tmp_dir"
    trap - EXIT INT TERM
  }

  npkg() {
    emulate -L zsh

    local cmd=${1:-help}
    local installable
    local -a expanded

    if (( $# > 0 )); then
      shift
    fi

    case $cmd in
      install|add|i)
        if (( $# == 0 )); then
          _npkg_pick_installables
          return
        fi

        if [[ $1 == -* ]]; then
          _npkg_nix profile add "$@"
          return
        fi

        for installable in "$@"; do
          case $installable in
            *'#'*|*':'*|/*|./*|../*) expanded+=("$installable") ;;
            *) expanded+=("nixpkgs#$installable") ;;
          esac
        done

        _npkg_nix profile add "${expanded[@]}"
        ;;
      find|pick|fzf)
        _npkg_pick_installables "$@"
        ;;
      search|s)
        if (( $# == 0 )); then
          echo "Usage: npkg search <query>"
          return 1
        fi

        if [[ $1 == -* ]]; then
          _npkg_nix search "$@"
        else
          _npkg_nix search nixpkgs "$@"
        fi
        ;;
      list|ls)
        _npkg_nix profile list "$@"
        ;;
      refresh)
        _npkg_refresh_index >/dev/null || return 1
        echo 'Refreshed nixpkgs attribute cache'
        ;;
      remove|rm|uninstall|delete)
        if (( $# == 0 )); then
          _npkg_remove_picker
        else
          _npkg_nix profile remove "$@"
        fi
        ;;
      outdated|check|diff)
        _npkg_outdated
        ;;
      upgrade|up|update)
        if (( $# == 0 )); then
          _npkg_nix profile upgrade --all
        else
          _npkg_nix profile upgrade "$@"
        fi
        ;;
      help|-h|--help)
        _npkg_usage
        ;;
      *)
        echo "Unknown npkg command: $cmd"
        _npkg_usage
        return 1
        ;;
    esac
  }
fi
