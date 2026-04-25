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
  local _fzf_pointer='>' _fzf_marker='+'
  (( $+functions[_ui_has_icons] )) && _ui_has_icons && { _fzf_pointer='󰘳'; _fzf_marker='󰄬'; }

  signal=${signal#-}
  selected=$(
    ps -ef | sed 1d | awk '
      {
        pid = $2
        $1 = $2 = $3 = $4 = $5 = $6 = $7 = ""
        sub(/^ +/, "")
        print pid "\t" $0
      }
    ' | fzf -m --delimiter=$'\t' --with-nth=2.. \
      --prompt='Kill> ' \
      --header="Select process(es) to kill with SIG${signal}" \
      --pointer="$_fzf_pointer" \
      --marker="$_fzf_marker"
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

_ui_usage_entry_icon() {
  local target=$1

  if [ -L "$target" ]; then
    _ui_icon '󰌷' '@'
  elif [ -d "$target" ]; then
    _ui_icon '󰉋' '/'
  else
    _ui_icon '󰈔' '-'
  fi
}

_ui_profile_role() {
  case $1 in
    silent|quiet|low-power) print -r -- 'success' ;;
    balanced|balanced-performance|cool|normal) print -r -- 'info' ;;
    performance|overboost|turbo) print -r -- 'danger' ;;
    *) print -r -- 'accent' ;;
  esac
}

# Show current laptop thermal/performance profile
fanprofile() {
  emulate -L zsh

  local platform_profile_file=/sys/firmware/acpi/platform_profile
  local platform_choices_file=/sys/firmware/acpi/platform_profile_choices
  local asus_profile_file=/sys/devices/platform/asus-nb-wmi/fan_boost_mode
  local raw profile role source choices meta

  if [ -r "$platform_profile_file" ]; then
    raw=$(<"$platform_profile_file")
    if _ui_plain_mode; then
      printf '%s (platform_profile)\n' "$raw"
      return 0
    fi

    role=$(_ui_profile_role "$raw")
    source='platform_profile'
    [ -r "$platform_choices_file" ] && choices=$(<"$platform_choices_file")

    _ui_panel_header 'Fan Profile' "$source" "$role"
    _ui_panel_prefix
    _ui_icon '󰈐' '*'
    print -nr -- ' '
    _ui_badge "$raw" "$role"
    print ''
    [ -n "$choices" ] && _ui_panel_kv 'Choices' "$choices" muted text
    _ui_panel_footer 'Kernel platform profile interface' "$role"
    return 0
  fi

  if [ -r "$asus_profile_file" ]; then
    raw=$(<"$asus_profile_file")
    case $raw in
      0) profile="normal" ;;
      1) profile="overboost" ;;
      2) profile="silent" ;;
      *)
        echo "Unknown ASUS fan profile value: $raw"
        return 1
        ;;
    esac

    if _ui_plain_mode; then
      printf '%s (fan_boost_mode=%s)\n' "$profile" "$raw"
      return 0
    fi

    role=$(_ui_profile_role "$profile")
    meta="fan_boost_mode=${raw}"
    _ui_panel_header 'Fan Profile' 'ASUS WMI fallback' "$role"
    _ui_panel_prefix
    _ui_icon '󰈐' '*'
    print -nr -- ' '
    _ui_badge "$profile" "$role"
    print ''
    _ui_panel_kv 'Source' 'fan_boost_mode' muted text
    _ui_panel_kv 'Raw' "$raw" muted text
    _ui_panel_footer "$meta" "$role"
    return 0
  fi

  if _ui_plain_mode; then
    echo "No supported laptop performance profile interface found"
  else
    _ui_panel_header 'Fan Profile' 'unsupported host' warning
    _ui_panel_kv 'Status' 'No supported laptop performance profile interface found' muted text
    _ui_panel_footer 'Checked platform_profile and ASUS fan_boost_mode' warning
  fi
  return 1
}

# Disk usage summary for current directory
dusage() {
  emulate -L zsh
  setopt pipefail

  local target=${1:-.}
  local limit=${2:-20}
  local output line kib entry_path label icon shown visible_count more total_kib bar_width name_width width size_width percent_width
  local size_text percent_text header_meta footer_text
  local -a entries
  local -a lines

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

  if _ui_plain_mode; then
    du -sh -- "${entries[@]}" 2>/dev/null | command sort -rh | command head -n "$limit"
    return ${pipestatus[1]:-0}
  fi

  output=$(du -sk -- "${entries[@]}" 2>/dev/null | command sort -rn) || return 1
  lines=( ${(f)output} )
  (( ${#lines[@]} > 0 )) || {
    echo "No entries found in '$target'"
    return 0
  }

  for line in "${lines[@]}"; do
    kib=${line%%$'\t'*}
    case $kib in
      ''|*[!0-9]*) continue ;;
    esac
    total_kib=$(( total_kib + kib ))
  done

  shown=$(_ui_visible_count "$limit" "${#lines[@]}" 6)
  more=$(( ${#lines[@]} - shown ))
  visible_count=$shown
  width=$(_ui_term_width)
  read -r name_width size_width bar_width percent_width <<< "$(_ui_list_widths "$width")"

  header_meta="$target"
  footer_text="showing ${visible_count}/${#lines[@]} entries"
  _ui_panel_header 'Disk Usage' "$header_meta" accent
  _ui_panel_kv 'Entries' "${#lines[@]}" muted text
  _ui_panel_kv 'Total' "$(_ui_human_kib "$total_kib")" muted text
  _ui_panel_divider

  integer idx
  for (( idx = 1; idx <= visible_count; idx++ )); do
    line=${lines[$idx]}
    kib=${line%%$'\t'*}
    entry_path=${line#*$'\t'}
    size_text=$(_ui_human_kib "$kib")
    percent_text=''

    if (( total_kib > 0 && percent_width > 0 )); then
      percent_text="$(( kib * 100 / total_kib ))%"
    fi

    label=${entry_path##*/}
    [ -n "$label" ] || label=$entry_path
    icon=$(_ui_usage_entry_icon "$entry_path")
    label=$(_ui_truncate "$name_width" "$label")

    _ui_panel_prefix
    print -nr -- "$icon "
    _ui_color text
    _ui_pad left "$name_width" "$label"
    _ui_reset
    print -nr -- ' '
    _ui_color muted
    _ui_pad right "$size_width" "$size_text"
    _ui_reset
    (( percent_width > 0 )) && printf ' %*s' "$percent_width" "$percent_text"
    print -nr -- ' '
    _ui_bar "$bar_width" "$kib" "$total_kib" info
    print ''
  done

  if (( more > 0 )); then
    _ui_panel_kv 'More' "+${more} not shown" muted muted
  fi

  _ui_panel_footer "$footer_text" accent
}

# Largest files in current directory tree
bigfiles() {
  emulate -L zsh
  setopt pipefail

  local target=${1:-.}
  local limit=${2:-20}
  local output line kib file_path label shown more total_kib bar_width path_width footer_text icon width size_width
  local -a lines

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

  if _ui_plain_mode; then
    command find "$target" -type f -exec du -h {} + 2>/dev/null | command sort -rh | command head -n "$limit"
    return ${pipestatus[1]:-0}
  fi

  output=$(command find "$target" -type f -exec du -k {} + 2>/dev/null | command sort -rn) || return 1
  lines=( ${(f)output} )

  if (( ${#lines[@]} == 0 )); then
    _ui_panel_header 'Big Files' "$target" accent
    _ui_panel_kv 'Status' 'No files found under target' muted text
    _ui_panel_footer 'Nothing to display' accent
    return 0
  fi

  for line in "${lines[@]}"; do
    kib=${line%%$'\t'*}
    case $kib in
      ''|*[!0-9]*) continue ;;
    esac
    total_kib=$(( total_kib + kib ))
  done

  shown=$(_ui_visible_count "$limit" "${#lines[@]}" 6)
  more=$(( ${#lines[@]} - shown ))
  width=$(_ui_term_width)
  read -r path_width size_width bar_width _ <<< "$(_ui_list_widths "$width")"
  (( width >= 120 )) && path_width=52
  (( width >= 80 && width < 120 )) && path_width=34
  (( width < 80 )) && path_width=22

  _ui_panel_header 'Big Files' "$target" accent
  _ui_panel_kv 'Files found' "${#lines[@]}" muted text
  _ui_panel_kv 'Total' "$(_ui_human_kib "$total_kib")" muted text
  _ui_panel_divider

  integer idx
  for (( idx = 1; idx <= shown; idx++ )); do
    line=${lines[$idx]}
    kib=${line%%$'\t'*}
    file_path=${line#*$'\t'}
    icon=$(_ui_usage_entry_icon "$file_path")

    if (( width < 80 )); then
      label=${file_path##*/}
    else
      label=$file_path
    fi

    label=$(_ui_truncate "$path_width" "$label")

    _ui_panel_prefix
    print -nr -- "$icon "
    _ui_color text
    _ui_pad left "$path_width" "$label"
    _ui_reset
    print -nr -- ' '
    _ui_color muted
    _ui_pad right "$size_width" "$(_ui_human_kib "$kib")"
    _ui_reset
    print -nr -- ' '
    _ui_bar "$bar_width" "$kib" "$total_kib" accent
    print ''
  done

  if (( more > 0 )); then
    _ui_panel_kv 'More' "+${more} not shown" muted muted
  fi

  footer_text="showing ${shown}/${#lines[@]} files"
  _ui_panel_footer "$footer_text" accent
}

# Show listening ports and owning processes
ports() {
  emulate -L zsh

  local output header parsed line netid state state_role localaddr port address process pid shown more
  local -a lines rows
  local row_delim=$'\t'
  integer width addr_width proc_width

  if _ui_plain_mode; then
    command ss -tulnp
    return $?
  fi

  output=$(command ss -tulnp 2>/dev/null) || {
    command ss -tulnp
    return $?
  }

  lines=( ${(f)output} )
  for line in "${lines[@]}"; do
    [ -n "${line//[[:space:]]/}" ] || continue
    header=$line
    break
  done

  if [[ $header != *Netid* || $header != *State* || $header != *Recv-Q* || $header != *Local\ Address:Port* || $header != *Process* ]]; then
    print -r -- "$output"
    return 0
  fi

  parsed=$(print -r -- "$output" | command awk '
    NR == 1 || NF == 0 { next }
    {
      netid = $1
      state = $2
      localaddr = $5
      port = localaddr
      address = localaddr
      proc = "-"
      pid = "-"

      sub(/^.*:/, "", port)
      sub(/:[^:]*$/, "", address)

      if (match($0, /users:\(\("[^"]+"/)) {
        proc = substr($0, RSTART, RLENGTH)
        sub(/^users:\(\("/, "", proc)
        sub(/"$/, "", proc)
      }

      if (match($0, /pid=[0-9]+/)) {
        pid = substr($0, RSTART + 4, RLENGTH - 4)
      }

      print netid "\t" state "\t" address "\t" port "\t" proc "\t" pid
    }
  ')

  rows=( ${(f)parsed} )
  (( ${#rows[@]} > 0 )) || {
    print -r -- "$output"
    return 0
  }

  shown=$(_ui_visible_count 999 "${#rows[@]}" 8)
  more=$(( ${#rows[@]} - shown ))
  width=$(_ui_term_width)

  if (( width >= 120 )); then
    addr_width=26
    proc_width=22
  elif (( width >= 80 )); then
    addr_width=20
    proc_width=16
  else
    addr_width=16
    proc_width=12
  fi

  _ui_panel_header 'Listening Ports' 'ss -tulnp' accent
  _ui_panel_kv 'Sockets' "${#rows[@]}" muted text
  _ui_panel_divider

  integer idx
  for (( idx = 1; idx <= shown; idx++ )); do
    line=${rows[$idx]}
    netid=${line%%${row_delim}*}
    line=${line#*${row_delim}}
    state=${line%%${row_delim}*}
    line=${line#*${row_delim}}
    address=${line%%${row_delim}*}
    line=${line#*${row_delim}}
    port=${line%%${row_delim}*}
    line=${line#*${row_delim}}
    process=${line%%${row_delim}*}
    pid=${line#*${row_delim}}
    state_role=warning
    [ "$state" = 'LISTEN' ] && state_role=success

    _ui_panel_prefix
    _ui_badge "$netid" info
    print -nr -- ' '
    _ui_badge "$state" "$state_role"
    print -nr -- ' '
    _ui_color text
    _ui_pad left "$addr_width" "$(_ui_truncate "$addr_width" "$address")"
    _ui_reset
    print -nr -- ':'
    _ui_color accent
    _ui_pad right 5 "$port"
    _ui_reset
    print -nr -- ' '
    _ui_color muted
    _ui_pad left "$proc_width" "$(_ui_truncate "$proc_width" "$process")"
    _ui_reset
    print -nr -- ' '
    _ui_color muted
    print -nr -- "pid=$pid"
    _ui_reset
    print ''
  done

  if (( more > 0 )); then
    _ui_panel_kv 'More' "+${more} not shown" muted muted
  fi

  _ui_panel_footer 'Raw fallback: ss -tulnp' accent
}

# Show public IP address over HTTPS
myip() {
  emulate -L zsh

  local endpoint='https://ifconfig.me/ip'
  local ip

  if _ui_plain_mode; then
    curl -fsSL "$endpoint" && printf '\n'
    return $?
  fi

  ip=$(curl -fsSL "$endpoint") || return $?

  _ui_panel_header 'Public IP' 'HTTPS lookup' accent
  _ui_panel_prefix
  _ui_icon '󰩟' '*'
  print -nr -- ' '
  _ui_color text
  print -nr -- "$ip"
  _ui_reset
  print ''
  _ui_panel_kv 'Source' 'ifconfig.me/ip' muted text
  _ui_panel_footer 'Use plain mode for scripting' accent
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
  local _fzf_pointer='>' _fzf_marker='+'
  (( $+functions[_ui_has_icons] )) && _ui_has_icons && { _fzf_pointer='󰘳'; _fzf_marker='󰄬'; }

  selection=$(
    git for-each-ref --sort=-committerdate \
      --format=$'%(refname:short)\t%(committerdate:relative)\t%(subject)' \
      refs/heads refs/remotes |
      command grep -v $'^[^[:space:]]+/HEAD\t' |
      fzf --ansi --height=50% --delimiter=$'\t' --with-nth=1,2,3 \
        --prompt='Branch> ' \
        --pointer="$_fzf_pointer" \
        --marker="$_fzf_marker" \
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

  if [ -n "${_UPKG_THEME_MODE:-}" ] && ! _ui_plain_mode; then
    print ''
    _ui_panel_prefix
    _ui_color accent
    print -r -- "── $title"
    _ui_reset
  else
    print ''
    print "==> $title"
  fi
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

  local manager detail state role

  if [ -n "${_UPKG_THEME_MODE:-}" ] && ! _ui_plain_mode; then
    _ui_panel_divider
    _ui_panel_prefix
    _ui_color muted
    print -r -- 'Summary'
    _ui_reset
    for manager in "${_UPKG_SUMMARY_ORDER[@]}"; do
      detail=${_UPKG_SUMMARY_DETAIL[$manager]}
      state=${_UPKG_SUMMARY_STATE[$manager]}
      case $state in
        'up to date'|upgraded)    role='success' ;;
        'updates available')      role='warning' ;;
        blocked)                  role='warning' ;;
        failed)                   role='danger'  ;;
        skipped)                  role='muted'   ;;
        *)                        role='accent'  ;;
      esac
      _ui_panel_prefix
      _ui_badge "$state" "$role"
      print -nr -- ' '
      _ui_color text
      print -nr -- "$(_upkg_manager_title "$manager")"
      _ui_reset
      if [ -n "$detail" ]; then
        print -nr -- ' '
        _ui_color muted
        print -nr -- "($detail)"
        _ui_reset
      fi
      print ''
    done
  else
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
  fi
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
    [[ $line == Package[[:space:]]*Current[[:space:]]*Wanted[[:space:]]*Latest* ]] && return 0
  done

  return 1
}

_upkg_run_outdated_apt() {
  emulate -L zsh

  local output line status
  local -a packages

  _upkg_print_section apt

  output=$(command apt list --upgradable 2>&1)
  status=$?
  output=$(print -r -- "$output" | sed '/^Listing\.\.\.$/d')
  if (( status != 0 )); then
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'apt list --upgradable failed'
    return 1
  fi

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

  local raw_cmd='' cmd='outdated' manager
  local only_raw='' skip_raw=''
  local allow_sudo=0 dry_run=0 filtered=0 exit_code=0
  local -a candidate_pool run_order display_order
  local -A selected_map skipped_map alternate_map display_seen

  typeset -g _UPKG_THEME_MODE=''

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
    if ! _ui_plain_mode; then
      _UPKG_THEME_MODE=1
    fi

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

    if _ui_plain_mode || [ -z "${_UPKG_THEME_MODE:-}" ]; then
      print 'Detected managers:'
    else
      _ui_panel_header 'Detected Managers' 'upkg managers' accent
      [ -n "$only_raw" ] && _ui_panel_kv 'Only' "$only_raw" muted text
      [ -n "$skip_raw" ] && _ui_panel_kv 'Skip' "$skip_raw" muted text
      _ui_panel_divider
    fi

    for manager in "${display_order[@]}"; do
      local manager_status='' role='muted' title
      title=$(_upkg_manager_title "$manager")

      if [ -n "${skipped_map[$manager]}" ]; then
        manager_status='skipped by filter'
        role='muted'
      elif [ -n "${selected_map[$manager]}" ]; then
        if [ -n "${alternate_map[$manager]}" ]; then
          manager_status='selected via --only'
        else
          manager_status='selected'
        fi
        role='accent'
      elif (( filtered )); then
        if [ -n "${alternate_map[$manager]}" ]; then
          manager_status="available via --only $manager"
        else
          manager_status='not selected'
        fi
        role='warning'
      elif [ -n "${alternate_map[$manager]}" ]; then
        manager_status="available via --only $manager"
        role='warning'
      else
        manager_status='active'
        role='success'
      fi

      if _ui_plain_mode || [ -z "${_UPKG_THEME_MODE:-}" ]; then
        print "  - $manager ($manager_status)"
      else
        _ui_panel_prefix
        _ui_badge "$manager_status" "$role"
        print -nr -- ' '
        _ui_color text
        print -nr -- "$title"
        _ui_reset
        print ''
      fi
    done

    if ! _ui_plain_mode && [ -n "${_UPKG_THEME_MODE:-}" ]; then
      _ui_panel_footer 'Selection order follows execution order' accent
    fi

    if (( filtered && ${#_UPKG_SELECTED_MANAGERS[@]} == 0 )); then
      return 1
    fi

    return 0
  fi

  _upkg_apply_filters "$only_raw" "$skip_raw" || return 1

  if [ "$cmd" = 'outdated' ] || [ "$cmd" = 'plan' ]; then
    if ! _ui_plain_mode; then
      _UPKG_THEME_MODE=1
      _ui_panel_header 'Package Dashboard' "$cmd" accent
      [ -n "$only_raw" ] && _ui_panel_kv 'Only' "$only_raw" muted text
      [ -n "$skip_raw" ] && _ui_panel_kv 'Skip' "$skip_raw" muted text
      _ui_panel_divider
    fi
  fi

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
  if [ -n "${_UPKG_THEME_MODE:-}" ] && ! _ui_plain_mode; then
    _ui_panel_footer 'Backend output remains mostly raw inside each section' accent
  fi
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
    local _c_attr='' _c_muted='' _c_success='' _c_info='' _c0=''

    _npkg_require_picker 'install' || return 1

    if ! _ui_plain_mode && [ -z "${NO_COLOR:-}" ]; then
      _c_attr='\033[38;2;245;224;220m'
      _c_muted='\033[38;2;166;173;200m'
      _c_success='\033[38;2;166;227;161m'
      _c_info='\033[38;2;137;180;250m'
      _c0='\033[0m'
    fi

    query="${(j: :)@}"
    cache_file=$(_npkg_attr_index) || return 1

    selection=$(
      _c_attr="$_c_attr" _c_muted="$_c_muted" _c_success="$_c_success" \
      _c_info="$_c_info" _c0="$_c0" \
      command fzf -m \
        --prompt='Nix install> ' \
        --query="$query" \
        --header='Type to filter attribute names, Tab marks packages, Enter adds' \
        --preview '
            attr={}
            printf "${_c_attr}Attr:${_c0} %s\n" "$attr"
            printf "${_c_attr}Install ref:${_c0} nixpkgs#%s\n\n" "$attr"
            meta_json=$(command nix --extra-experimental-features "nix-command flakes" \
              eval --json --apply "p: { v = p.version or \"\"; d = p.meta.description or \"\"; h = p.meta.homepage or \"\"; }" "nixpkgs#$attr" 2>/dev/null || echo "{}")

            desc=$(echo "$meta_json" | command jq -r ".d | select(. != \"\") // empty")
            ver=$(echo "$meta_json" | command jq -r ".v | select(. != \"\") // empty")
            hp=$(echo "$meta_json" | command jq -r ".h | select(. != \"\") // empty")

            if [ -n "$desc" ]; then
              printf "${_c_muted}Description:${_c0}\n%s\n\n" "$desc"
            else
              printf "${_c_muted}(no description available)${_c0}\n\n"
            fi

            if [ -n "$ver" ]; then
              printf "${_c_success}Version:${_c0} %s\n" "$ver"
            fi

            if [ -n "$hp" ]; then
              printf "${_c_info}Homepage:${_c0} %s\n" "$hp"
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
    local _c_attr='' _c_muted='' _c_info='' _c0=''

    _npkg_require_picker 'remove' || return 1

    if ! _ui_plain_mode && [ -z "${NO_COLOR:-}" ]; then
      _c_attr='\033[38;2;245;224;220m'
      _c_muted='\033[38;2;166;173;200m'
      _c_info='\033[38;2;137;180;250m'
      _c0='\033[0m'
    fi

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
        _c_attr="$_c_attr" _c_muted="$_c_muted" _c_info="$_c_info" _c0="$_c0" \
        command fzf -m --delimiter=$'\t' --with-nth=2,3,4 \
          --prompt='Nix remove> ' \
          --header='Tab marks packages, Enter removes' \
          --preview 'printf "${_c_attr}Name:${_c0} %s\n${_c_muted}Attr:${_c0} %s\n${_c_info}Source:${_c0} %s\n" {2} {3} {4}' \
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
    local name inst avail marker role shown more width name_width version_width visible_count

    if _ui_plain_mode; then
      if [ -n "${NO_COLOR:-}" ] || ! [ -t 1 ]; then
        printf '\n'
        printf '%-25s %-20s %-20s %s\n' 'Package' 'Installed' 'Available' 'Status'
        printf '%-25s %-20s %-20s %s\n' '-------' '---------' '---------' '------'

        for (( idx = 1; idx <= pkg_count; idx++ )); do
          name="${names[$idx]}"
          inst="${installed_versions[$idx]}"
          avail="${latest_versions[$idx]}"

          if [ "$inst" = "??" ] || [ "$avail" = "??" ]; then
            marker='?'
          elif [ "$inst" = "$avail" ]; then
            marker='ok'
          else
            marker='upgrade'
            (( upgrades++ ))
          fi

          printf '%-25s %-20s %-20s %s\n' "$name" "$inst" "$avail" "$marker"
        done

        printf '\n'
        if (( upgrades > 0 )); then
          printf '%d upgrade(s) available. Run: npkg upgrade\n' "$upgrades"
        else
          printf 'Everything is up to date.\n'
        fi
      else
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
      fi

      command rm -rf "$tmp_dir"
      trap - EXIT INT TERM
      return 0
    fi

    width=$(_ui_term_width)
    if (( width >= 120 )); then
      name_width=28
      version_width=18
    elif (( width >= 80 )); then
      name_width=22
      version_width=14
    else
      name_width=16
      version_width=10
    fi

    visible_count=$(_ui_visible_count "$pkg_count" "$pkg_count" 9)
    more=$(( pkg_count - visible_count ))

    _ui_panel_header 'Nix Package Drift' "$pkg_count package(s) checked" accent
    _ui_panel_kv 'Command' 'npkg outdated' muted text
    _ui_panel_divider

    for (( idx = 1; idx <= visible_count; idx++ )); do
      name="${names[$idx]}"
      inst="${installed_versions[$idx]}"
      avail="${latest_versions[$idx]}"

      if [ "$inst" = "??" ] || [ "$avail" = "??" ]; then
        marker='unknown'
        role='muted'
      elif [ "$inst" = "$avail" ]; then
        marker='up to date'
        role='success'
      else
        marker='upgrade'
        role='warning'
        (( upgrades++ ))
      fi

      _ui_panel_prefix
      _ui_badge "$marker" "$role"
      print -nr -- ' '
      _ui_color text
      _ui_pad left "$name_width" "$(_ui_truncate "$name_width" "$name")"
      _ui_reset
      print -nr -- ' '
      _ui_color muted
      _ui_pad left "$version_width" "$inst"
      _ui_reset
      print -nr -- ' '
      _ui_color info
      _ui_pad left "$version_width" "$avail"
      _ui_reset
      print ''
    done

    if (( more > 0 )); then
      _ui_panel_kv 'More' "+${more} not shown" muted muted
    fi

    if (( upgrades > 0 )); then
      _ui_panel_footer "$upgrades upgrade(s) available. Run npkg upgrade to apply." warning
    else
      _ui_panel_footer 'Everything is up to date.' success
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
