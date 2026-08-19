# Useful shell functions.

# Extract any archive
extract() {
  if [ -z "${1:-}" ]; then
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
mkcd() {
  if [ -z "${1:-}" ]; then
    echo "Usage: mkcd <directory>"
    return 1
  fi

  command mkdir -p "$1" && cd "$1"
}

# Find files by name
ff() {
  if [ -z "${1:-}" ]; then
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
  if [ -z "${1:-}" ]; then
    echo "Usage: ft <pattern> [path]"
    return 1
  fi

  if command -v rg >/dev/null 2>&1; then
    rg --color=always -- "$1" "${2:-.}"
  else
    command grep -rnI --color=auto -- "$1" "${2:-.}" 2>/dev/null
  fi
}

_zsh_require_fzf() {
  if (( ! $+functions[_fzf_require_ready] )); then
    print -u2 -r -- 'zsh config: fzf 0.68.0 or newer is required (found: configuration guard unavailable). Upgrade fzf and restart the shell.'
    return 1
  fi
  _fzf_require_ready
}

typeset -g _ZSH_CONFIG_FUNCTIONS_DIR=${${(%):-%N}:A:h}/functions
if (( ! ${fpath[(Ie)$_ZSH_CONFIG_FUNCTIONS_DIR]} )); then
  fpath=( "$_ZSH_CONFIG_FUNCTIONS_DIR" "${fpath[@]}" )
fi
(( $+functions[ztheme] )) || autoload -Uz ztheme

# Fuzzy kill process
fkill() {
  _zsh_require_fzf || return 1

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "fkill requires an interactive terminal"
    return 1
  fi

  local signal=${1:-15}
  local selected pid multi_footer
  local -a pids fzf_args multi_args context_args

  signal=${signal#-}
  _fzf_picker_multi_args kill
  multi_footer=$REPLY
  multi_args=( "${reply[@]}" )
  _fzf_picker_context_args Processes 'Type to filter processes' "$multi_footer"
  context_args=( "${reply[@]}" )
  fzf_args=(
    "${context_args[@]}"
    "${multi_args[@]}"
    --delimiter=$'\t'
    --with-nth=2..
    --accept-nth=1
    "--header=Signal: SIG${signal}"
    --header-label=Signal
  )
  selected=$(
    ps -ef | sed 1d | awk '
      {
        pid = $2
        $1 = $2 = $3 = $4 = $5 = $6 = $7 = ""
        sub(/^ +/, "")
        print pid "\t" $0
      }
    ' | command fzf "${fzf_args[@]}"
  ) || return 0

  while IFS= read -r pid; do
    [ -n "$pid" ] && pids+=("$pid")
  done <<< "$selected"

  (( ${#pids[@]} > 0 )) || return 0
  kill "-$signal" "${pids[@]}"
}

# Quick HTTP header check
headers() {
  if [ -z "${1:-}" ]; then
    echo "Usage: headers <url>"
    return 1
  fi

  curl -sSIL -- "$1"
}

# Preview file (uses bat if available)
peek() {
  if [ -z "${1:-}" ]; then
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

_ui_safe_text() {
  emulate -L zsh
  setopt MULTIBYTE

  local value=$1
  local char escaped output=''
  integer index code

  for (( index = 1; index <= ${#value}; index++ )); do
    char=${value[$index]}

    case $char in
      $'\n') output+='\n' ;;
      $'\r') output+='\r' ;;
      $'\t') output+='\t' ;;
      $'\e') output+='\e' ;;
      $'\a') output+='\a' ;;
      $'\b') output+='\b' ;;
      $'\f') output+='\f' ;;
      $'\v') output+='\v' ;;
      *)
        printf -v code '%d' "'$char"
        if (( code < 32 || code == 127 || (code >= 128 && code <= 159) )); then
          printf -v escaped '\\x%02x' "$code"
          output+=$escaped
        else
          output+=$char
        fi
        ;;
    esac
  done

  print -r -- "$output"
}

_ui_safe_truncate() {
  emulate -L zsh

  local width=$1
  shift

  local text="$*"
  local marker='…'
  local token pair quad prefix='' suffix=''
  local -a tokens
  integer index left right token_length

  (( width > 0 )) || {
    print -r -- ''
    return 0
  }

  if _ui_ascii_mode; then
    marker='...'
  fi

  if (( ${#text} <= width )); then
    print -r -- "$text"
    return 0
  fi

  if (( width <= ${#marker} )); then
    print -r -- "${marker[1,width]}"
    return 0
  fi

  for (( index = 1; index <= ${#text}; index++ )); do
    token=${text[$index]}

    if [[ $token == $'\\' ]]; then
      pair=${text[$index,$(( index + 1 ))]}
      quad=${text[$index,$(( index + 3 ))]}

      if [[ $quad == \\x[0-9a-fA-F][0-9a-fA-F] ]]; then
        token=$quad
        (( index += 3 ))
      else
        case $pair in
          '\n'|'\r'|'\t'|'\e'|'\a'|'\b'|'\f'|'\v')
            token=$pair
            (( index++ ))
            ;;
        esac
      fi
    fi

    tokens+=("$token")
  done

  left=$(( (width - ${#marker}) / 2 ))
  right=$(( width - ${#marker} - left ))

  for token in "${tokens[@]}"; do
    token_length=${#token}
    (( ${#prefix} + token_length <= left )) || break
    prefix+=$token
  done

  for (( index = ${#tokens[@]}; index >= 1; index-- )); do
    token=${tokens[$index]}
    token_length=${#token}
    (( ${#suffix} + token_length <= right )) || break
    suffix="${token}${suffix}"
  done

  print -r -- "${prefix}${marker}${suffix}"
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

    _ui_title_line 'Fan Profile' "$source" "$role" '󰈐' '*'
    _ui_panel_prefix
    _ui_icon '󰈐' '*'
    print -nr -- ' '
    _ui_badge "$raw" "$role"
    print ''
    [ -n "$choices" ] && _ui_panel_kv 'Choices' "$choices" muted text
    _ui_section_break
    print -nr -- '  '
    _ui_color muted
    print -r -- 'Kernel platform profile interface'
    _ui_reset
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
    _ui_title_line 'Fan Profile' 'ASUS WMI fallback' "$role" '󰈐' '*'
    _ui_panel_prefix
    _ui_icon '󰈐' '*'
    print -nr -- ' '
    _ui_badge "$profile" "$role"
    print ''
    _ui_panel_kv 'Source' 'fan_boost_mode' muted text
    _ui_panel_kv 'Raw' "$raw" muted text
    _ui_section_break
    print -nr -- '  '
    _ui_color muted
    print -r -- "$meta"
    _ui_reset
    return 0
  fi

  if _ui_plain_mode; then
    echo "No supported laptop performance profile interface found"
  else
    _ui_title_line 'Fan Profile' 'unsupported host' warning '󰈐' '*'
    _ui_panel_kv 'Status' 'No supported laptop performance profile interface found' muted text
    _ui_section_break
    print -nr -- '  '
    _ui_color muted
    print -r -- 'Checked platform_profile and ASUS fan_boost_mode'
    _ui_reset
  fi
  return 1
}

# Minimal fallbacks when UI helpers are unavailable so functions degrade to plain output.
if ! (( $+functions[_ui_plain_mode] )); then
  _ui_plain_mode() { return 0; }
fi
if ! (( $+functions[_ui_ascii_mode] )); then
  _ui_ascii_mode() { return 0; }
fi
if ! (( $+functions[_ui_term_width] )); then
  _ui_term_width() { print -r -- 80; }
fi
if ! (( $+functions[_ui_repeat] )); then
  _ui_repeat() {
    emulate -L zsh
    local count=${1:-0} chunk=${2:- }
    local out=''
    integer i

    (( count > 0 )) || return 0

    for (( i = 0; i < count; i++ )); do
      out+="$chunk"
    done

    print -nr -- "$out"
  }
fi
if ! (( $+functions[_ui_color] )); then
  _ui_color() { :; }
fi
if ! (( $+functions[_ui_reset] )); then
  _ui_reset() { :; }
fi
if ! (( $+functions[_ui_bold] )); then
  _ui_bold() { :; }
fi
if ! (( $+functions[_ui_has_icons] )); then
  _ui_has_icons() { return 1; }
fi
if ! (( $+functions[_ui_icon] )); then
  _ui_icon() {
    emulate -L zsh
    print -nr -- "${2:-*}"
  }
fi
if ! (( $+functions[_ui_title_line] )); then
  _ui_title_line() {
    emulate -L zsh
    local title=$1 meta=${2:-}
    if [ -n "$meta" ]; then
      print -r -- "$title - $meta"
    else
      print -r -- "$title"
    fi
  }
fi
if ! (( $+functions[_ui_section_break] )); then
  _ui_section_break() { :; }
fi
if ! (( $+functions[_ui_panel_prefix] )); then
  _ui_panel_prefix() { :; }
fi
if ! (( $+functions[_ui_panel_kv] )); then
  _ui_panel_kv() {
    emulate -L zsh
    print -r -- "$1: $2"
  }
fi
if ! (( $+functions[_ui_badge] )); then
  _ui_badge() {
    emulate -L zsh
    print -nr -- "[$1]"
  }
fi
if ! (( $+functions[_ui_human_kib] )); then
  _ui_human_kib() {
    emulate -L zsh
    print -r -- "$1 KiB"
  }
fi
if ! (( $+functions[_ui_usage_entry_icon] )); then
  _ui_usage_entry_icon() {
    emulate -L zsh
    print -nr -- '*'
  }
fi
if ! (( $+functions[_ui_truncate] )); then
  _ui_truncate() {
    emulate -L zsh
    shift
    print -r -- "$*"
  }
fi
if ! (( $+functions[_ui_pad] )); then
  _ui_pad() {
    emulate -L zsh
    local align=$1 width=$2
    shift 2
    if [ "$align" = 'right' ]; then
      printf '%*s' "$width" "$*"
    else
      printf '%-*s' "$width" "$*"
    fi
  }
fi
if ! (( $+functions[_ui_bar] )); then
  _ui_bar() { :; }
fi
if ! (( $+functions[_ui_visible_count] )); then
  _ui_visible_count() {
    emulate -L zsh
    integer requested=$1 available=$2 max_rows=$3
    (( requested < available )) && available=$requested
    (( available > max_rows )) && available=$max_rows
    print -r -- "$available"
  }
fi

# Disk usage summary for current directory
dusage() {
  emulate -L zsh

  local target=${1:-.}
  local limit=${2:-20}
  local line kib entry_path label icon shown visible_count more total_kib=0 bar_width name_width width size_width percent_width
  local size_text percent_text header_meta footer_text display_target
  local scan_status=0 raw_output_file=''
  local -a entries records lines

  display_target=$(_ui_safe_text "$target")

  if [ ! -d "$target" ]; then
    echo "'$display_target' is not a directory"
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
    echo "No entries found in '$display_target'"
    return 0
  fi

  raw_output_file=$(command mktemp "${TMPDIR:-/tmp}/dusage.raw.XXXXXX") || return 1
  command du -sk --null -- "${entries[@]}" 2>/dev/null >"$raw_output_file"
  scan_status=$?

  while IFS=$'\t' read -r -d '' kib entry_path; do
    [[ $kib == <-> ]] || continue
    records+=("${kib}"$'\t'"${entry_path}")
  done <"$raw_output_file"

  command rm -f -- "$raw_output_file"

  if (( ${#records[@]} == 0 )); then
    (( scan_status != 0 )) && return $scan_status
    echo "No entries found in '$display_target'"
    return 0
  fi

  lines=( "${(@On)records}" )

  if _ui_plain_mode; then
    shown=$limit
    (( shown > ${#lines[@]} )) && shown=${#lines[@]}

    integer plain_idx
    for (( plain_idx = 1; plain_idx <= shown; plain_idx++ )); do
      line=${lines[$plain_idx]}
      kib=${line%%$'\t'*}
      entry_path=${line#*$'\t'}
      printf '%-8s %s\n' "$(_ui_human_kib "$kib")" "$(_ui_safe_text "$entry_path")"
    done
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
  visible_count=$shown
  width=$(_ui_term_width)
  size_width=9
  bar_width=16
  percent_width=5
  (( width < 80 )) && bar_width=10

  name_width=$(( width - size_width - percent_width - bar_width - 8 ))
  (( name_width < 10 )) && name_width=10

  header_meta=$display_target
  footer_text="showing ${visible_count}/${#lines[@]} entries"
  _ui_title_line 'Disk Usage' "$header_meta" accent '󰋊' '*'
  _ui_panel_kv 'Entries' "${#lines[@]}" muted text
  _ui_panel_kv 'Total' "$(_ui_human_kib "$total_kib")" muted text
  _ui_section_break

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
    label=$(_ui_safe_text "$label")
    icon=$(_ui_usage_entry_icon "$entry_path")
    label=$(_ui_safe_truncate "$name_width" "$label")

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

  _ui_section_break
  print -nr -- '  '
  _ui_color muted
  print -r -- "$footer_text"
  _ui_reset
}

# Largest files in current directory tree
bigfiles() {
  emulate -L zsh

  local target=${1:-.}
  local limit=${2:-20}
  local line kib file_path label shown more total_kib=0 bar_width path_width footer_text icon width size_width
  local find_status=0 scan_status=0 display_target
  local path_list_file='' raw_output_file='' line_count=0
  local -a records lines

  display_target=$(_ui_safe_text "$target")

  if [ ! -e "$target" ]; then
    echo "'$display_target' does not exist"
    return 1
  fi

  case $limit in
    ''|*[!0-9]*)
      echo "Usage: bigfiles [path] [count]"
      return 1
      ;;
  esac

  path_list_file=$(command mktemp "${TMPDIR:-/tmp}/bigfiles.paths.XXXXXX") || return 1
  raw_output_file=$(command mktemp "${TMPDIR:-/tmp}/bigfiles.raw.XXXXXX") || {
    command rm -f -- "$path_list_file"
    return 1
  }

  command find "$target" -type f -print0 2>/dev/null >"$path_list_file"
  find_status=$?

  if [ -s "$path_list_file" ]; then
    command du -k --null --files0-from="$path_list_file" 2>/dev/null >"$raw_output_file"
    scan_status=$?
  elif (( find_status != 0 )); then
    command rm -f -- "$path_list_file" "$raw_output_file"
    return $find_status
  fi

  while IFS=$'\t' read -r -d '' kib file_path; do
    [[ $kib == <-> ]] || continue
    records+=("${kib}"$'\t'"${file_path}")
  done <"$raw_output_file"

  command rm -f -- "$path_list_file" "$raw_output_file"

  if (( ${#records[@]} == 0 )); then
    (( scan_status != 0 )) && return $scan_status

    if _ui_plain_mode; then
      return 0
    fi

    _ui_title_line 'Big Files' "$display_target" accent '󰉋' '*'
    _ui_panel_kv 'Status' 'No files found under target' muted text
    _ui_section_break
    print -nr -- '  '
    _ui_color muted
    print -r -- 'Nothing to display'
    _ui_reset
    return 0
  fi

  lines=( "${(@On)records}" )
  line_count=${#lines[@]}

  if _ui_plain_mode; then
    shown=$limit
    (( shown > line_count )) && shown=$line_count

    integer plain_idx
    for (( plain_idx = 1; plain_idx <= shown; plain_idx++ )); do
      line=${lines[$plain_idx]}
      kib=${line%%$'\t'*}
      file_path=${line#*$'\t'}
      printf '%-8s %s\n' "$(_ui_human_kib "$kib")" "$(_ui_safe_text "$file_path")"
    done
    return 0
  fi

  for line in "${lines[@]}"; do
    kib=${line%%$'\t'*}
    total_kib=$(( total_kib + kib ))
  done

  shown=$(_ui_visible_count "$limit" "$line_count" 6)
  more=$(( line_count - shown ))

  width=$(_ui_term_width)
  size_width=9
  bar_width=16
  (( width < 80 )) && bar_width=10

  path_width=$(( width - size_width - bar_width - 7 ))
  (( path_width < 10 )) && path_width=10

  _ui_title_line 'Big Files' "$display_target" accent '󰉋' '*'
  _ui_panel_kv 'Files found' "$line_count" muted text
  _ui_panel_kv 'Total' "$(_ui_human_kib "$total_kib")" muted text
  _ui_section_break

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

    label=$(_ui_safe_text "$label")
    label=$(_ui_safe_truncate "$path_width" "$label")

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

  footer_text="showing ${shown}/${line_count} files"
  _ui_section_break
  print -nr -- '  '
  _ui_color muted
  print -r -- "$footer_text"
  _ui_reset
}

# Show listening ports and owning processes
ports() {
  emulate -L zsh

  local output header parsed line netid state state_role port address process pid shown more pid_text
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
    NR == 1 || NF == 0 || NF < 5 { next }
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

      rest = $0
      owners = ""
      pids = ""
      while (match(rest, /\("[^"]+",pid=[^,()]+[^)]*\)/)) {
        entry = substr(rest, RSTART, RLENGTH)
        owner = entry
        sub(/^\("/, "", owner)
        sub(/",pid=.*$/, "", owner)
        entry_pid = entry
        sub(/^.*pid=/, "", entry_pid)
        sub(/[,)].*$/, "", entry_pid)

        if (owners != "") owners = owners ", "
        owners = owners owner
        if (pids != "") pids = pids ","
        pids = pids entry_pid

        rest = substr(rest, RSTART + RLENGTH)
      }

      if (owners != "") {
        proc = owners
        pid = pids
      } else if (match($0, /users:\(\(.*\)\)/)) {
        proc = substr($0, RSTART, RLENGTH)
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

  local available=$(( width - 42 ))
  (( available < 20 )) && available=20
  addr_width=$(( available * 3 / 5 ))
  proc_width=$(( available - addr_width ))

  _ui_title_line 'Listening Ports' 'ss -tulnp' accent '󰒋' '*'
  _ui_panel_kv 'Sockets' "${#rows[@]}" muted text
  _ui_section_break

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
    case $state in
      LISTEN|UNCONN) state_role=success ;;
      *) state_role=warning ;;
    esac

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
    pid_text=$(_ui_truncate 18 "pid=$pid")
    _ui_color muted
    print -nr -- "$pid_text"
    _ui_reset
    print ''
  done

  if (( more > 0 )); then
    _ui_panel_kv 'More' "+${more} not shown" muted muted
  fi

  _ui_section_break
  print -nr -- '  '
  _ui_color muted
  print -r -- 'Raw fallback: ss -tulnp'
  _ui_reset
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

  _ui_title_line 'Public IP' 'HTTPS lookup' accent '󰩟' '*'
  print -nr -- '  '
  _ui_color text
  print -nr -- "$ip"
  _ui_reset
  print ''
  _ui_panel_kv 'Source' 'ifconfig.me/ip' muted text
  _ui_section_break
  print -nr -- '  '
  _ui_color muted
  print -r -- 'Use plain mode for scripting'
  _ui_reset
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

# Show contributor counts for the current repo history
function gitcount {
  git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "Not in a git repo"
    return 1
  }

  git rev-parse --verify HEAD >/dev/null 2>&1 || {
    echo "No commits yet"
    return 0
  }

  git shortlog -sn --no-merges HEAD
}

# Print PATH entries with rich interactive output and plain pipe-friendly output
path() {
  emulate -L zsh

  local -a entries
  local entry display_entry shown width index_width path_width

  entries=( "${(@s/:/)PATH}" )

  if _ui_plain_mode; then
    for entry in "${entries[@]}"; do
      _ui_safe_text "$entry"
    done
    return 0
  fi

  shown=${#entries[@]}
  width=$(_ui_term_width)
  index_width=4
  path_width=$(( width - index_width - 8 ))
  (( path_width < 20 )) && path_width=20

  _ui_title_line 'PATH Entries' "${#entries[@]} entries" accent '󰉋' '*'
  _ui_section_break

  integer idx
  for (( idx = 1; idx <= shown; idx++ )); do
    entry=${entries[$idx]}
    [ -n "$entry" ] || entry='.'
    display_entry=$(_ui_safe_text "$entry")

    _ui_panel_prefix
    _ui_color muted
    _ui_pad right "$index_width" "$idx"
    _ui_reset
    print -nr -- ' '
    _ui_color text
    print -nr -- "$(_ui_safe_truncate "$path_width" "$display_entry")"
    _ui_reset
    print ''
  done

}

# Emit NUL-delimited branch/path pairs for registered Git worktrees.
_fbr_worktree_entries() {
  emulate -L zsh

  local excluded_path=${1-} field worktree_path

  [[ -n $excluded_path ]] && excluded_path=${excluded_path:A}

  while IFS= read -r -d '' field; do
    case $field in
      'worktree '*)
        worktree_path=${field#worktree }
        ;;
      'branch refs/heads/'*)
        if [[ -n $excluded_path && ${worktree_path:A} == $excluded_path ]]; then
          continue
        fi
        print -rn -- "${field#branch refs/heads/}"$'\0'"$worktree_path"$'\0'
        ;;
    esac
  done < <(command git worktree list --porcelain -z)
}

# Enter a branch's worktree, or check out the branch when it has none.
_fbr_activate() {
  emulate -L zsh

  local branch=$1 worktree_path=${2-} local_branch

  if [[ -n $worktree_path ]]; then
    builtin cd -- "$worktree_path"
    return
  fi

  if command git show-ref --verify --quiet "refs/heads/$branch"; then
    command git checkout "$branch"
    return
  fi

  if command git show-ref --verify --quiet "refs/remotes/$branch"; then
    local_branch=${branch#*/}
    if command git show-ref --verify --quiet "refs/heads/$local_branch"; then
      command git checkout "$local_branch"
    else
      command git checkout --track "$branch"
    fi
    return
  fi

  echo "Branch '$branch' was not found"
  return 1
}

# Fuzzy-pick a Git branch, entering its worktree or checking it out.
fbr() {
  _zsh_require_fzf || return 1

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "fbr requires an interactive terminal"
    return 1
  fi

  command git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "Not in a git repo"
    return 1
  }

  local selection branch branch_label current_worktree ref_details ref_line worktree_branch worktree_display worktree_path
  local worktree_badge_color='' worktree_badge_reset='' preview_command
  local -A worktree_paths
  local -a fzf_args context_args preview_args
  if ! _ui_plain_mode; then
    if _zsh_theme_sgr success fg ui; then
      worktree_badge_color=$REPLY
      worktree_badge_reset=$'\e[0m'
    fi
  fi

  if [[ -n ${NO_COLOR:-} ]]; then
    preview_command='git log --oneline --decorate --color=never -20 {1}'
  else
    preview_command='git log --oneline --decorate --color=always -20 {1}'
  fi
  _fzf_picker_context_args Branches 'Type to filter branches' 'Enter checkout  Ctrl-P preview  Ctrl-/ wrap  Esc close'
  context_args=( "${reply[@]}" )
  _fzf_picker_preview_args Log
  preview_args=( "${reply[@]}" )
  fzf_args=(
    "${context_args[@]}"
    "${preview_args[@]}"
    --ansi
    --delimiter=$'\t'
    --with-nth=1,2,3
    --nth=1,2,3
    --accept-nth=4
    --freeze-left=1
    --no-multi
    "--preview=$preview_command"
  )

  current_worktree=$(command git rev-parse --show-toplevel 2>/dev/null) || current_worktree=''
  while IFS= read -r -d '' worktree_branch && IFS= read -r -d '' worktree_path; do
    worktree_paths[$worktree_branch]=$worktree_path
  done < <(_fbr_worktree_entries "$current_worktree")

  selection=$(
    while IFS= read -r ref_line; do
      branch=${ref_line%%$'\t'*}
      [[ $branch == */HEAD ]] && continue

      branch_label=$branch
      worktree_display=''
      if [[ -n ${worktree_paths[$branch]-} ]]; then
        branch_label="${worktree_badge_color}[WT]${worktree_badge_reset} $branch"
        worktree_display=$(_ui_safe_text "${worktree_paths[$branch]}")
      fi

      ref_details=${ref_line#*$'\t'}
      print -r -- "$branch_label"$'\t'"$ref_details"$'\t'"$worktree_display"$'\t'"$branch"
    done < <(
      command git for-each-ref --sort=-committerdate \
        --format=$'%(refname:short)\t%(committerdate:relative)\t%(subject)' \
        refs/heads refs/remotes
    ) |
      command fzf "${fzf_args[@]}"
  ) || return 0

  branch=$selection

  worktree_path=${worktree_paths[$branch]-}
  if [[ -z $worktree_path ]] && command git show-ref --verify --quiet "refs/remotes/$branch"; then
    worktree_path=${worktree_paths[${branch#*/}]-}
  fi

  _fbr_activate "$branch" "$worktree_path"
}

# Unified package check, update, and cleanup wrapper across supported managers.
_upkg_usage() {
  if ! _ui_plain_mode; then
    _ui_title_line 'Unified Package Updates' 'upkg help' accent '󰏖' '*'
    _ui_section_break
    _ui_panel_kv 'Usage' 'upkg [command] [args] [--only <list>] [--skip <list>] [--sudo] [--dry-run]' muted text
    _ui_section_break
    _ui_panel_kv 'outdated / check / list' 'Show outdated packages across detected managers' accent text
    _ui_panel_kv 'search <query>' 'Search package names across detected managers' accent text
    _ui_panel_kv 'upgrade / up / update' 'Run upgrades across selected managers' accent text
    _ui_panel_kv 'plan' 'Preview available upgrades without changing packages' accent text
    _ui_panel_kv 'clean' 'Remove unused packages and stale manager-owned caches' accent text
    _ui_panel_kv 'managers' 'Show detected managers and alternates' accent text
    _ui_panel_kv 'help' 'Show this help text' accent text
    _ui_section_break
    _ui_panel_kv '--only <list>' 'Include comma-separated manager IDs' muted text
    _ui_panel_kv '--skip <list>' 'Exclude comma-separated manager IDs' muted text
    _ui_panel_kv '--sudo' 'Authorize privileged upgrade and cleanup backends' muted text
    _ui_panel_kv '--dry-run' 'Preview upgrades or cleanup without changing packages' muted text
    _ui_section_break
    _ui_panel_kv 'Managers' 'apt, dnf, pacman, paru, brew, flatpak, nix, npm' muted text
    _ui_panel_kv 'Preview' 'upkg plan --only brew,npm' muted text
    _ui_panel_kv 'Upgrade' 'upkg upgrade --sudo --only apt' muted text
    _ui_panel_kv 'Cleanup preview' 'upkg clean --dry-run --only brew,npm' muted text
    return 0
  fi

  print 'Usage: upkg [command] [args] [--only <list>] [--skip <list>] [--sudo] [--dry-run]'
  print ''
  print 'Commands:'
  print '  outdated            Show outdated packages across detected managers'
  print '  check               Alias for outdated'
  print '  list                Alias for outdated'
  print '  search <query>      Search package names across detected managers'
  print '  upgrade             Run upgrades across selected managers'
  print '  up                  Alias for upgrade'
  print '  update              Alias for upgrade'
  print '  plan                Preview available upgrades without changing packages'
  print '  clean               Remove unused packages and stale manager-owned caches'
  print '  managers            Show detected managers and alternates'
  print '  help                Show this help text'
  print ''
  print 'Flags:'
  print '  --only <list>       Comma-separated manager IDs to include'
  print '  --skip <list>       Comma-separated manager IDs to exclude'
  print '  --sudo              Authorize privileged upgrade and cleanup backends'
  print '  --dry-run           Preview upgrades or cleanup without changing packages'
  print ''
  print 'Supported manager IDs:'
  print '  apt, dnf, pacman, paru, brew, flatpak, nix, npm'
  print ''
  print 'Examples:'
  print '  upkg                                  # check for outdated packages'
  print '  upkg search ripgrep                  # compare package search matches'
  print '  upkg --only brew,npm                 # check selected managers'
  print '  upkg plan                            # preview upgrades'
  print '  upkg upgrade --dry-run --only npm    # preview selected upgrades'
  print '  upkg upgrade --sudo --only apt       # run a privileged backend'
  print '  upkg clean --dry-run --only brew,npm # preview manager-owned cleanup'
  print '  upkg clean --sudo --only apt         # remove unused APT data'
  print '  upkg managers --only npm,flatpak     # inspect selected order'
  print ''
  print 'Notes:'
  print '  - upkg with no command defaults to outdated'
  print '  - search prints one compact table with a manager column'
  print '  - plan and upgrade --dry-run use the read-only outdated checks'
  print '  - clean is mutating; use clean --dry-run for a read-only preview'
  print '  - cleanup uses conservative manager commands and never deletes app data or user config directly'
  print '  - upgrades never inject sudo automatically'
  print '  - paru upgrades require explicit --sudo opt-in but still run unprefixed'
  print '  - brew upgrades run unprefixed and stay in Homebrew user space'
  print '  - npm upgrades stay user-space only; upkg will not recommend sudo npm'
}

_upkg_search_usage() {
  if ! _ui_plain_mode; then
    _ui_title_line 'Package Search' 'usage' accent '󰍉' '*'
    _ui_section_break
    _ui_panel_kv 'Usage' 'upkg search <query> [--only <list>] [--skip <list>]' muted text
    _ui_panel_kv 'Example' 'upkg search ripgrep --only npm,flatpak' muted text
    return 0
  fi

  print 'Usage: upkg search <query> [--only <list>] [--skip <list>]'
  print 'Example: upkg search ripgrep --only npm,flatpak'
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
      apt|dnf|pacman|paru|brew|flatpak|nix|npm)
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

  if command -v brew >/dev/null 2>&1; then
    _UPKG_ACTIVE_MANAGERS+=(brew)
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
  typeset -g _UPKG_ONLY_FILTER_HINT _UPKG_SKIP_FILTER_HINT
  _UPKG_SELECTED_MANAGERS=()
  _UPKG_SKIPPED_MANAGERS=()
  _UPKG_ONLY_FILTER_HINT=''
  _UPKG_SKIP_FILTER_HINT=''

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
      if (( ${#candidate_pool[@]} > 0 )); then
        print -u2 -- "Detected managers: ${(j:, :)candidate_pool}"
      fi
      print -u2 -- 'Run: upkg managers'
      return 1
    fi

    _UPKG_ONLY_FILTER_HINT="${(j:,:)selected}"
  else
    selected=( "${_UPKG_ACTIVE_MANAGERS[@]}" )
  fi

  if [ -n "$skip_raw" ]; then
    parsed=$(_upkg_parse_manager_list "$skip_raw") || return 1
    skip_list=( ${(f)parsed} )
    _UPKG_SKIP_FILTER_HINT="${(j:,:)skip_list}"

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
    brew) print 'Homebrew' ;;
    flatpak) print 'Flatpak' ;;
    nix) print 'Nix (npkg)' ;;
    npm) print 'npm' ;;
    *) print -r -- "$1" ;;
  esac
}

_upkg_print_section() {
  emulate -L zsh

  local manager=$1
  local title=$(_upkg_manager_title "$manager")
  local width fill='─' lead='─ '

  print ''
  if [ -n "${_UPKG_THEME_MODE:-}" ] && ! _ui_plain_mode; then
    width=$(( $(_ui_term_width) - 2 ))
    (( width < 32 )) && width=32
    if _ui_ascii_mode; then
      fill='-'
      lead='- '
    fi

    _ui_color border
    print -nr -- "$lead"
    _ui_repeat "$width" "$fill"
    _ui_reset
    print ''

    print -nr -- '  '
    _ui_color accent
    _ui_manager_icon "$manager"
    _ui_reset
    print -nr -- ' '
    _ui_color text
    print -r -- "$title"
    _ui_reset
  else
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

_upkg_summary_managers_by_state() {
  emulate -L zsh

  local wanted_state=$1
  local manager
  local -a matching=()

  for manager in "${_UPKG_SUMMARY_ORDER[@]}"; do
    [ "${_UPKG_SUMMARY_STATE[$manager]}" = "$wanted_state" ] && matching+=("$manager")
  done

  print -r -- "${(j:, :)matching}"
}

_upkg_print_summary() {
  emulate -L zsh

  local manager detail state role title metadata bucket family glyph fallback
  local cleanup_summary=0
  local -A status_counts=(
    ok 0
    updates 0
    matches 0
    empty 0
    cleaned 0
    planned 0
    partial 0
    blocked 0
    failed 0
    skipped 0
    other 0
  )

  [ "${_UPKG_OPERATION:-}" = 'clean' ] && cleanup_summary=1

  if [ -n "${_UPKG_THEME_MODE:-}" ] && ! _ui_plain_mode; then
    for manager in "${_UPKG_SUMMARY_ORDER[@]}"; do
      state=${_UPKG_SUMMARY_STATE[$manager]}
      metadata=$(_ui_status_metadata "$state")
      IFS=$'\t' read -r role bucket family glyph fallback <<< "$metadata"
      (( status_counts[$bucket]++ ))
      [ "$family" = 'cleanup' ] && cleanup_summary=1
    done

    _ui_section_break
    _ui_color muted
    _ui_icon '󰍹' '>'
    _ui_reset
    print -nr -- ' '
    _ui_color text
    print -nr -- 'Summary'
    _ui_reset
    print -nr -- ' '
    if (( cleanup_summary )); then
      _ui_badge "${status_counts[cleaned]} cleaned" success
      if (( status_counts[planned] > 0 )); then
        print -nr -- ' '
        _ui_badge "${status_counts[planned]} planned" info
      fi
      if (( status_counts[partial] > 0 )); then
        print -nr -- ' '
        _ui_badge "${status_counts[partial]} partial" danger
      fi
    else
      _ui_badge "${status_counts[ok]} ok" success
      print -nr -- ' '
      _ui_badge "${status_counts[updates]} updates" warning
      if (( status_counts[matches] > 0 )); then
        print -nr -- ' '
        _ui_badge "${status_counts[matches]} matches" info
      fi
      if (( status_counts[empty] > 0 )); then
        print -nr -- ' '
        _ui_badge "${status_counts[empty]} empty" muted
      fi
    fi
    if (( status_counts[blocked] > 0 )); then
      print -nr -- ' '
      _ui_badge "${status_counts[blocked]} blocked" warning
    fi
    if (( status_counts[failed] > 0 )); then
      print -nr -- ' '
      _ui_badge "${status_counts[failed]} failed" danger
    fi
    if (( status_counts[skipped] > 0 )); then
      print -nr -- ' '
      _ui_badge "${status_counts[skipped]} skipped" muted
    fi
    print ''

    for manager in "${_UPKG_SUMMARY_ORDER[@]}"; do
      detail=${_UPKG_SUMMARY_DETAIL[$manager]}
      state=${_UPKG_SUMMARY_STATE[$manager]}
      title=$(_upkg_manager_title "$manager")
      metadata=$(_ui_status_metadata "$state")
      IFS=$'\t' read -r role bucket family glyph fallback <<< "$metadata"

      print -nr -- '  '
      _ui_color "$role"
      _ui_status_icon "$state"
      _ui_reset
      print -nr -- ' '
      _ui_manager_icon "$manager"
      print -nr -- ' '
      _ui_color text
      print -nr -- "$title"
      _ui_reset
      print -nr -- ' '
      _ui_badge "$state" "$role"
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

_upkg_print_cleanup_phase() {
  print ''
  print "$1:"
}

_upkg_record_cleanup_result() {
  emulate -L zsh

  local rc=$1
  local failure_detail=$2

  # Cleanup handlers provide these caller-local counters and failure details.
  if (( rc == 0 )); then
    (( succeeded++ ))
  else
    (( failed++ ))
    failures+=("$failure_detail")
  fi

  return 0
}

_upkg_run_cleanup_step() {
  emulate -L zsh

  local failure_detail=$1
  local rc
  shift

  command "$@"
  rc=$?
  _upkg_record_cleanup_result "$rc" "$failure_detail"
}

_upkg_is_root() {
  (( EUID == 0 ))
}

_upkg_cleanup_privilege_prefix() {
  if _upkg_is_root; then
    print -r -- ''
  else
    print -r -- 'sudo '
  fi
}

_upkg_finish_cleanup_result() {
  emulate -L zsh

  local succeeded=$1
  local failed=$2
  local detail=$3

  if (( failed == 0 )); then
    if (( _UPKG_DRY_RUN )); then
      _upkg_set_last_result 'planned' ''
    else
      _upkg_set_last_result 'cleaned' ''
    fi
    return 0
  fi

  if (( _UPKG_DRY_RUN || succeeded == 0 )); then
    _upkg_set_last_result 'failed' "$detail"
  else
    _upkg_set_last_result 'partial' "$detail"
  fi
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

  if _upkg_is_root; then
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

_upkg_search_trim() {
  emulate -L zsh

  local value=$1

  value=${value//$'\r'/}
  value=${value//$'\n'/ }
  value=${value//$'\t'/ }

  while [ "${value# }" != "$value" ]; do
    value=${value# }
  done
  while [ "${value% }" != "$value" ]; do
    value=${value% }
  done
  while [[ $value == *'  '* ]]; do
    value=${value//'  '/' '}
  done

  print -r -- "$value"
}

_upkg_brew_version_from_header() {
  emulate -L zsh

  local header=$1 token
  local -a fields

  fields=( ${(z)header} )
  for token in "${fields[@]}"; do
    token=${token#,}
    token=${token%,}
    token=${token#\(}
    token=${token%\)}

    case $token in
      stable|keg-only|HEAD|formula|cask|from|versioned)
        continue
        ;;
    esac

    if [[ $token == [0-9]* || $token == latest ]]; then
      print -r -- "$token"
      return 0
    fi
  done

  print -r -- '?'
}

_upkg_brew_name_from_header() {
  emulate -L zsh

  local header=$1

  header=${header#'==> '}
  header=${header%%:*}
  header=${header%% \(*}

  print -r -- "$header"
}

_upkg_search_add_rows() {
  emulate -L zsh

  local manager=$1 row
  local name version description
  shift
  local -a rows=( "$@" )

  typeset -g -a _UPKG_SEARCH_ROWS

  (( ${#rows[@]} > 0 )) || return 0

  for row in "${rows[@]}"; do
    IFS=$'\t' read -r name version description <<< "$row"
    _UPKG_SEARCH_ROWS+=("${manager}"$'\t'"${name}"$'\t'"${version}"$'\t'"${description}")
  done
}

_upkg_finish_search_results() {
  emulate -L zsh

  local manager=$1
  shift
  local -a rows=( "$@" )

  if (( ${#rows[@]} == 0 )); then
    _upkg_set_last_result 'no matches' ''
    return 0
  fi

  _upkg_search_add_rows "$manager" "${rows[@]}"
  _upkg_set_last_result 'matches found' "${#rows[@]} result(s)"
}

_upkg_format_search_rows() {
  emulate -L zsh

  local row manager name version description
  local width manager_width name_width version_width desc_width
  local failed_count=0
  local failed_managers=''
  local -a rows=( "$@" )

  if (( ${#rows[@]} == 0 )); then
    for manager in "${_UPKG_SUMMARY_ORDER[@]}"; do
      [ "${_UPKG_SUMMARY_STATE[$manager]}" = 'failed' ] && (( failed_count++ ))
    done

    if (( failed_count > 0 )); then
      failed_managers=$(_upkg_summary_managers_by_state failed)
      if [ -n "$failed_managers" ]; then
        print "Search results unavailable; failed manager(s): $failed_managers."
      else
        print 'Search results unavailable; one or more selected managers failed.'
      fi
    else
      print 'No matches found across selected managers.'
    fi
    return 0
  fi

  if _ui_plain_mode || [ -z "${_UPKG_THEME_MODE:-}" ]; then
    printf '%-8s %-36s %-18s %s\n' 'Manager' 'Package' 'Available' 'Description'
    printf '%-8s %-36s %-18s %s\n' '-------' '-------' '---------' '-----------'

    for row in "${rows[@]}"; do
      IFS=$'\t' read -r manager name version description <<< "$row"
      [ -n "$version" ] || version='?'
      printf '%-8s %-36s %-18s %s\n' "$manager" "$name" "$version" "$description"
    done
  else
    width=$(_ui_term_width)
    if (( width >= 130 )); then
      manager_width=10
      name_width=36
      version_width=18
    elif (( width >= 100 )); then
      manager_width=9
      name_width=30
      version_width=16
    elif (( width >= 80 )); then
      manager_width=8
      name_width=24
      version_width=14
    else
      manager_width=7
      name_width=18
      version_width=12
    fi
    desc_width=$(( width - manager_width - name_width - version_width - 13 ))
    (( desc_width < 18 )) && desc_width=18

    _ui_panel_kv 'Results' "${#rows[@]} match(es)" muted text
    _ui_section_break

    for row in "${rows[@]}"; do
      IFS=$'\t' read -r manager name version description <<< "$row"
      [ -n "$version" ] || version='?'
      description=$(_upkg_search_trim "$description")

      _ui_panel_prefix
      _ui_color accent
      _ui_pad left "$manager_width" "$(_ui_truncate "$manager_width" "$manager")"
      _ui_reset
      print -nr -- ' '
      _ui_color text
      _ui_pad left "$name_width" "$(_ui_truncate "$name_width" "$name")"
      _ui_reset
      print -nr -- ' '
      _ui_color info
      _ui_pad left "$version_width" "$(_ui_truncate "$version_width" "$version")"
      _ui_reset
      if [ -n "$description" ]; then
        print -nr -- ' '
        _ui_color muted
        print -nr -- "$(_ui_truncate "$desc_width" "$description")"
        _ui_reset
      fi
      print ''
    done
  fi
}

_upkg_print_search_summary() {
  emulate -L zsh

  local manager state suffix failed_managers
  local result_count=${#_UPKG_SEARCH_ROWS[@]}
  local manager_count=0
  local failed_count=0

  for manager in "${_UPKG_SUMMARY_ORDER[@]}"; do
    state=${_UPKG_SUMMARY_STATE[$manager]}
    case $state in
      'matches found'|'no matches') (( manager_count++ )) ;;
      failed) (( failed_count++ )) ;;
    esac
  done

  failed_managers=$(_upkg_summary_managers_by_state failed)

  if (( failed_count > 0 )); then
    if [ -n "$failed_managers" ]; then
      suffix=", $failed_count failed ($failed_managers)."
    else
      suffix=", $failed_count failed."
    fi
  else
    suffix='.'
  fi

  if [ -n "${_UPKG_THEME_MODE:-}" ] && ! _ui_plain_mode; then
    _ui_section_break
    _ui_color muted
    _ui_icon '󰍹' '>'
    _ui_reset
    print -nr -- ' '
    _ui_color text
    print -nr -- 'Search summary'
    _ui_reset
    print -nr -- ' '
    _ui_badge "$result_count result(s)" info
    print -nr -- ' '
    _ui_badge "$manager_count manager(s)" muted
    if (( failed_count > 0 )); then
      print -nr -- ' '
      _ui_badge "$failed_count failed" danger
    fi
    print ''
    if (( failed_count > 0 )) && [ -n "$failed_managers" ]; then
      print -nr -- '  '
      _ui_color danger
      print -nr -- 'Failed managers:'
      _ui_reset
      print -nr -- ' '
      _ui_color muted
      print -nr -- "$failed_managers"
      _ui_reset
      print ''
    fi
  else
    print ''
    print "Search summary: $result_count result(s) across $manager_count manager(s)$suffix"
  fi
}

_upkg_search_progress() {
  emulate -L zsh

  local manager=$1
  local detail=$2

  [ -n "${_UPKG_THEME_MODE:-}" ] || return 0
  _ui_plain_mode && return 0

  print -nr -- $'\r'
  print -nr -- '  '
  _ui_color info
  _ui_icon '󰔟' '~'
  _ui_reset
  print -nr -- ' '
  _ui_color muted
  print -nr -- 'Searching'
  _ui_reset
  print -nr -- ' '
  _ui_color accent
  _ui_manager_icon "$manager"
  _ui_reset
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
  _ui_color muted
  print -nr -- '...'
  _ui_reset
}

_upkg_search_progress_clear() {
  emulate -L zsh

  local width

  [ -n "${_UPKG_THEME_MODE:-}" ] || return 0
  _ui_plain_mode && return 0

  width=$(_ui_term_width)
  case $width in
    ''|*[!0-9]*) width=80 ;;
  esac

  print -nr -- $'\r'
  _ui_repeat "$width" ' '
  print -nr -- $'\r'
}

_upkg_append_search_description() {
  emulate -L zsh

  local row=$1
  local description=$2

  [ -n "$description" ] || {
    print -r -- "$row"
    return 0
  }

  if [[ $row == *$'\t' ]]; then
    print -r -- "${row}${description}"
  else
    print -r -- "${row} ${description}"
  fi
}

_upkg_run_search_apt() {
  emulate -L zsh

  local output rc line header rest
  local current_name='' current_version='' current_desc=''
  local -a rows

  _upkg_search_progress apt ''
  output=$(command apt search --names-only "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear
  output=$(print -r -- "$output" | sed '/^WARNING: apt does not have a stable CLI interface\./d;/^Sorting\.\.\.$/d;/^Full Text Search\.\.\.$/d')
  if (( rc != 0 )); then
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'apt search failed'
    return 1
  fi

  for line in ${(f)output}; do
    [ -n "$line" ] || continue

    if [[ $line == [[:space:]]* ]]; then
      if [ -n "$current_name" ] && [ -z "$current_desc" ]; then
        current_desc=$(_upkg_search_trim "$line")
      fi
      continue
    fi

    if [ -n "$current_name" ]; then
      rows+=("${current_name}"$'\t'"${current_version}"$'\t'"${current_desc}")
    fi

    header=${line%% *}
    rest=${line#"$header"}
    rest=${rest# }
    current_name=${header%%/*}
    current_version=${rest%% *}
    current_desc=''
  done

  if [ -n "$current_name" ]; then
    rows+=("${current_name}"$'\t'"${current_version}"$'\t'"${current_desc}")
  fi

  _upkg_finish_search_results apt "${rows[@]}"
}

_upkg_run_search_dnf() {
  emulate -L zsh

  local output rc line name version query
  local -a rows fields query_patterns

  for query in "$@"; do
    query_patterns+=("*${query}*")
  done

  _upkg_search_progress dnf ''
  output=$(command dnf list --available "${query_patterns[@]}" 2>&1)
  rc=$?
  _upkg_search_progress_clear

  if (( rc != 0 )); then
    if [[ $output == *'No matching Packages to list'* ]]; then
      _upkg_finish_search_results dnf
      return 0
    fi
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'dnf list --available failed'
    return 1
  fi

  for line in ${(f)output}; do
    [ -n "$line" ] || continue
    [[ $line == 'Available Packages'* ]] && continue
    [[ $line == 'Last metadata expiration check:'* ]] && continue

    fields=( ${(z)line} )
    (( ${#fields[@]} >= 2 )) || continue
    name=${fields[1]}
    version=${fields[2]}
    rows+=("${name}"$'\t'"${version}"$'\t')
  done

  _upkg_finish_search_results dnf "${rows[@]}"
}

_upkg_run_search_pacman() {
  emulate -L zsh

  local output rc line header rest name version desc=''
  local -a rows

  _upkg_search_progress pacman ''
  output=$(command pacman -Ss -- "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear

  if (( rc != 0 )); then
    if (( rc == 1 )) && [ -z "$output" ]; then
      _upkg_finish_search_results pacman
      return 0
    fi
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'pacman -Ss failed'
    return 1
  fi

  for line in ${(f)output}; do
    [ -n "$line" ] || continue

    if [[ $line == [[:space:]]* ]]; then
      if (( ${#rows[@]} > 0 )); then
        desc=$(_upkg_search_trim "$line")
        rows[-1]=$(_upkg_append_search_description "${rows[-1]}" "$desc")
      fi
      continue
    fi

    header=${line%% *}
    rest=${line#"$header"}
    rest=${rest# }
    name=${header#*/}
    version=${rest%% *}
    rows+=("${name}"$'\t'"${version}"$'\t')
  done

  _upkg_finish_search_results pacman "${rows[@]}"
}

_upkg_run_search_paru() {
  emulate -L zsh

  local output rc line header rest name version desc=''
  local -a rows

  _upkg_search_progress paru ''
  output=$(command paru -Ss -- "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear

  if (( rc != 0 )); then
    if (( rc == 1 )) && [ -z "$output" ]; then
      _upkg_finish_search_results paru
      return 0
    fi
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'paru -Ss failed'
    return 1
  fi

  for line in ${(f)output}; do
    [ -n "$line" ] || continue

    if [[ $line == [[:space:]]* ]]; then
      if (( ${#rows[@]} > 0 )); then
        desc=$(_upkg_search_trim "$line")
        rows[-1]=$(_upkg_append_search_description "${rows[-1]}" "$desc")
      fi
      continue
    fi

    header=${line%% *}
    rest=${line#"$header"}
    rest=${rest# }
    name=${header#*/}
    version=${rest%% *}
    rows+=("${name}"$'\t'"${version}"$'\t')
  done

  _upkg_finish_search_results paru "${rows[@]}"
}

_upkg_run_search_brew() {
  emulate -L zsh

  local output rc line candidate meta version
  local info_limit=50 formula_total=0 cask_total=0
  local -a formulae casks formulae_for_info casks_for_info rows tokens
  local -A formula_wanted cask_wanted

  _upkg_search_progress brew 'formulae'
  output=$(HOMEBREW_NO_AUTO_UPDATE=1 command brew search --formula "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear
  if (( rc != 0 )); then
    if [[ $output != *'No formulae found'* && $output != *'No formulae or casks found'* ]]; then
      [ -n "$output" ] && print -r -- "$output"
      _upkg_set_last_result 'failed' 'brew search --formula failed'
      return 1
    fi
  else
    for line in ${(f)output}; do
      [ -n "$line" ] || continue
      [[ $line == '==>'* ]] && continue
      tokens=( ${(z)line} )
      formulae+=( "${tokens[@]}" )
    done
  fi

  _upkg_search_progress brew 'casks'
  output=$(HOMEBREW_NO_AUTO_UPDATE=1 command brew search --cask "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear
  if (( rc != 0 )); then
    if [[ $output != *'No casks found'* && $output != *'No formulae or casks found'* ]]; then
      [ -n "$output" ] && print -r -- "$output"
      _upkg_set_last_result 'failed' 'brew search --cask failed'
      return 1
    fi
  else
    for line in ${(f)output}; do
      [ -n "$line" ] || continue
      [[ $line == '==>'* ]] && continue
      tokens=( ${(z)line} )
      casks+=( "${tokens[@]}" )
    done
  fi

  if (( ${#formulae[@]} == 0 && ${#casks[@]} == 0 )); then
    _upkg_finish_search_results brew
    return 0
  fi

  formula_total=${#formulae[@]}
  cask_total=${#casks[@]}

  for candidate in "${formulae[@]}"; do
    (( ${#formulae_for_info[@]} >= info_limit )) && break
    formulae_for_info+=("$candidate")
    formula_wanted[$candidate]=1
  done
  for candidate in "${casks[@]}"; do
    (( ${#casks_for_info[@]} >= info_limit )) && break
    casks_for_info+=("$candidate")
    cask_wanted[$candidate]=1
  done

  if (( formula_total > info_limit )); then
    print -u2 -- "Homebrew formula search returned $formula_total matches; showing first $info_limit. Refine the query for more specific results."
  fi
  if (( cask_total > info_limit )); then
    print -u2 -- "Homebrew cask search returned $cask_total matches; showing first $info_limit. Refine the query for more specific results."
  fi

  if (( ${#formulae_for_info[@]} > 0 )); then
    _upkg_search_progress brew 'formula info'
    output=$(HOMEBREW_NO_AUTO_UPDATE=1 command brew info --formula "${formulae_for_info[@]}" 2>&1)
    rc=$?
    _upkg_search_progress_clear
    if (( rc != 0 )); then
      [ -n "$output" ] && print -r -- "$output"
      _upkg_set_last_result 'failed' 'brew info failed'
      return 1
    fi

    for line in ${(f)output}; do
      [ -n "$line" ] || continue
      candidate=$(_upkg_brew_name_from_header "$line")
      if [ -z "${formula_wanted[$candidate]}" ]; then
        continue
      fi

      meta=${line#*: }
      version=$(_upkg_brew_version_from_header "$meta")
      rows+=("${candidate}"$'\t'"${version}"$'\t'"formula")
    done
  fi

  if (( ${#casks_for_info[@]} > 0 )); then
    _upkg_search_progress brew 'cask info'
    output=$(HOMEBREW_NO_AUTO_UPDATE=1 command brew info --cask "${casks_for_info[@]}" 2>&1)
    rc=$?
    _upkg_search_progress_clear
    if (( rc != 0 )); then
      [ -n "$output" ] && print -r -- "$output"
      _upkg_set_last_result 'failed' 'brew info failed'
      return 1
    fi

    for line in ${(f)output}; do
      [ -n "$line" ] || continue
      candidate=$(_upkg_brew_name_from_header "$line")
      if [ -z "${cask_wanted[$candidate]}" ]; then
        continue
      fi

      meta=${line#*: }
      version=$(_upkg_brew_version_from_header "$meta")
      rows+=("${candidate}"$'\t'"${version}"$'\t'"cask")
    done
  fi

  _upkg_finish_search_results brew "${rows[@]}"
}

_upkg_run_search_flatpak() {
  emulate -L zsh

  local output rc app version name description display_name
  local -a rows

  _upkg_search_progress flatpak ''
  output=$(command flatpak search --columns=application,version,name,description "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear

  if (( rc != 0 )); then
    if [[ $output == *'No matches found'* ]]; then
      _upkg_finish_search_results flatpak
      return 0
    fi
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'flatpak search failed'
    return 1
  fi

  while IFS=$'\t' read -r app version name description _; do
    [ -n "$app" ] || continue
    [ "$app" = 'Application' ] && continue
    display_name=$(_upkg_search_trim "$name")
    description=$(_upkg_search_trim "$description")
    if [ -n "$display_name" ] && [ "$display_name" != "$app" ]; then
      if [ -n "$description" ]; then
        description="${display_name} - ${description}"
      else
        description=$display_name
      fi
    fi
    rows+=("${app}"$'\t'"${version}"$'\t'"${description}")
  done <<< "$output"

  _upkg_finish_search_results flatpak "${rows[@]}"
}

_upkg_run_search_nix() {
  emulate -L zsh

  local output output_lower rc line trimmed name version description=''
  local -a rows

  _upkg_search_progress nix ''
  output=$(_npkg_nix search nixpkgs "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear

  if (( rc != 0 )); then
    output_lower=${(L)output}
    if [[ $output_lower == *'no packages matched'* || $output_lower == *'no results for'* ]]; then
      _upkg_finish_search_results nix
      return 0
    fi
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'nix search failed'
    return 1
  fi

  for line in ${(f)output}; do
    [ -n "$line" ] || continue

    if [[ $line == [[:space:]]* ]]; then
      if (( ${#rows[@]} > 0 )); then
        description=$(_upkg_search_trim "$line")
        rows[-1]=$(_upkg_append_search_description "${rows[-1]}" "$description")
      fi
      continue
    fi

    trimmed=$line
    trimmed=${trimmed#\* }
    name=${trimmed%% \(*}
    version=${trimmed##*\(}
    version=${version%\)}
    if [ "$name" = "$trimmed" ] || [ "$version" = "$trimmed" ]; then
      continue
    fi
    rows+=("${name}"$'\t'"${version}"$'\t')
  done

  _upkg_finish_search_results nix "${rows[@]}"
}

_upkg_run_search_npm() {
  emulate -L zsh

  local output rc name description author date version
  local -a rows

  _upkg_search_progress npm ''
  output=$(command npm search --parseable "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear

  if (( rc != 0 )); then
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'npm search failed'
    return 1
  fi

  while IFS=$'\t' read -r name description author date version _; do
    [ -n "$name" ] || continue
    rows+=("${name}"$'\t'"${version}"$'\t'"$(_upkg_search_trim "$description")")
  done <<< "$output"

  _upkg_finish_search_results npm "${rows[@]}"
}

_upkg_run_outdated_apt() {
  emulate -L zsh

  local output line rc
  local -a packages

  _upkg_print_section apt

  output=$(command apt list --upgradable 2>&1)
  rc=$?
  output=$(print -r -- "$output" | sed '/^Listing\.\.\.$/d')
  if (( rc != 0 )); then
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

_upkg_run_outdated_brew() {
  emulate -L zsh

  local output rc

  _upkg_print_section brew

  output=$(command brew outdated 2>&1)
  rc=$?

  if (( rc != 0 )); then
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'brew outdated failed'
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

_upkg_run_outdated_flatpak() {
  emulate -L zsh

  local output rc

  _upkg_print_section flatpak

  output=$(command flatpak remote-ls --updates 2>&1)
  rc=$?

  if (( rc != 0 )); then
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'flatpak remote-ls --updates failed'
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

  local output output_file rc state changed unknown

  _upkg_print_section nix

  if ! command -v jq >/dev/null 2>&1; then
    print 'jq is required for npkg outdated; install jq or run upkg upgrade --only nix.'
    _upkg_set_last_result 'blocked' 'jq is required for nix outdated'
    return 0
  fi

  output_file=$(command mktemp "${TMPDIR:-/tmp}/upkg-nix-outdated.XXXXXX") || {
    _upkg_set_last_result 'failed' 'could not create a temp file for npkg outdated'
    return 1
  }

  npkg outdated >"$output_file" 2>&1
  rc=$?
  output=$(<"$output_file")
  command rm -f -- "$output_file"

  [ -n "$output" ] && print -r -- "$output"

  state=${_NPKG_OUTDATED_STATE:-partial}
  changed=${_NPKG_OUTDATED_CHANGED:-0}
  unknown=${_NPKG_OUTDATED_UNKNOWN:-0}

  case $state in
    current)
      if (( rc == 0 )); then
        _upkg_set_last_result 'up to date' ''
        return 0
      fi
      ;;
    changed)
      if (( rc == 0 )); then
        _upkg_set_last_result 'updates available' "${changed} change(s) available"
        return 0
      fi
      ;;
    partial)
      _upkg_set_last_result 'failed' "${changed} change(s), ${unknown} unknown"
      return 1
      ;;
  esac

  _upkg_set_last_result 'failed' 'npkg outdated returned inconsistent state'
  return 1
}

_upkg_run_outdated_npm() {
  emulate -L zsh

  local stdout_file stderr_file stdout_output stderr_output rc

  _upkg_print_section npm

  stdout_file=$(command mktemp "${TMPDIR:-/tmp}/upkg-npm.stdout.XXXXXX") || {
    _upkg_set_last_result 'failed' 'could not create a temp file for npm outdated'
    return 1
  }
  stderr_file=$(command mktemp "${TMPDIR:-/tmp}/upkg-npm.stderr.XXXXXX") || {
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

  if (( ! _UPKG_ALLOW_SUDO )) && ! _upkg_is_root; then
    print 'apt upgrade requires root; rerun with: upkg upgrade --sudo --only apt'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only apt'
    return 0
  fi

  _upkg_require_sudo_command || return 0

  if _upkg_is_root; then
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

  if (( ! _UPKG_ALLOW_SUDO )) && ! _upkg_is_root; then
    print 'dnf upgrade requires root; rerun with: upkg upgrade --sudo --only dnf'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only dnf'
    return 0
  fi

  _upkg_require_sudo_command || return 0

  if _upkg_is_root; then
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

  if (( ! _UPKG_ALLOW_SUDO )) && ! _upkg_is_root; then
    print 'pacman upgrade requires root; rerun with: upkg upgrade --sudo --only pacman'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only pacman'
    return 0
  fi

  _upkg_require_sudo_command || return 0

  if _upkg_is_root; then
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

_upkg_run_upgrade_brew() {
  emulate -L zsh

  local rc

  _upkg_print_section brew

  command brew upgrade
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'brew upgrade failed'
}

_upkg_run_upgrade_flatpak() {
  emulate -L zsh

  local rc

  _upkg_print_section flatpak

  command flatpak update
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'flatpak update failed'
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

_upkg_run_clean_apt() {
  emulate -L zsh

  local prefix
  local succeeded=0 failed=0
  local -a failures

  _upkg_print_section apt

  if (( _UPKG_DRY_RUN )); then
    prefix=$(_upkg_cleanup_privilege_prefix)
    _upkg_print_cleanup_phase 'Unused packages'
    print -r -- "preview: ${prefix}apt --simulate autoremove"
    _upkg_run_cleanup_step 'apt autoremove preview failed' apt --simulate autoremove

    _upkg_print_cleanup_phase 'Package cache'
    print -r -- "would run: ${prefix}apt autoclean"
    (( succeeded++ ))

    _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
    return $?
  fi

  if (( ! _UPKG_ALLOW_SUDO )) && ! _upkg_is_root; then
    print 'apt cleanup requires root; rerun with: upkg clean --sudo --only apt'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only apt'
    return 0
  fi

  _upkg_require_sudo_command || return 0

  _upkg_print_cleanup_phase 'Unused packages'
  if _upkg_is_root; then
    _upkg_run_cleanup_step 'apt autoremove failed' apt autoremove
  else
    _upkg_run_cleanup_step 'apt autoremove failed' sudo apt autoremove
  fi

  _upkg_print_cleanup_phase 'Package cache'
  if _upkg_is_root; then
    _upkg_run_cleanup_step 'apt autoclean failed' apt autoclean
  else
    _upkg_run_cleanup_step 'apt autoclean failed' sudo apt autoclean
  fi

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_clean_dnf() {
  emulate -L zsh

  local prefix
  local succeeded=0 failed=0
  local -a failures

  _upkg_print_section dnf

  if (( _UPKG_DRY_RUN )); then
    prefix=$(_upkg_cleanup_privilege_prefix)
    _upkg_print_cleanup_phase 'Unused packages'
    print 'preview: dnf --cacheonly repoquery --unneeded'
    _upkg_run_cleanup_step 'dnf cache-only unneeded-package preview failed' dnf --cacheonly repoquery --unneeded

    _upkg_print_cleanup_phase 'Package cache'
    print -r -- "would run: ${prefix}dnf clean all"
    (( succeeded++ ))

    _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
    return $?
  fi

  if (( ! _UPKG_ALLOW_SUDO )) && ! _upkg_is_root; then
    print 'dnf cleanup requires root; rerun with: upkg clean --sudo --only dnf'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only dnf'
    return 0
  fi

  _upkg_require_sudo_command || return 0

  _upkg_print_cleanup_phase 'Unused packages'
  if _upkg_is_root; then
    _upkg_run_cleanup_step 'dnf autoremove failed' dnf autoremove
  else
    _upkg_run_cleanup_step 'dnf autoremove failed' sudo dnf autoremove
  fi

  _upkg_print_cleanup_phase 'Package cache'
  if _upkg_is_root; then
    _upkg_run_cleanup_step 'dnf clean all failed' dnf clean all
  else
    _upkg_run_cleanup_step 'dnf clean all failed' sudo dnf clean all
  fi

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_clean_pacman() {
  emulate -L zsh

  local orphan_output rc prefix
  local succeeded=0 failed=0
  local -a failures orphans

  _upkg_print_section pacman

  if (( ! _UPKG_DRY_RUN && ! _UPKG_ALLOW_SUDO )) && ! _upkg_is_root; then
    print 'pacman cleanup requires root; rerun with: upkg clean --sudo --only pacman'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only pacman'
    return 0
  fi

  if (( ! _UPKG_DRY_RUN )); then
    _upkg_require_sudo_command || return 0
  fi

  prefix=$(_upkg_cleanup_privilege_prefix)
  _upkg_print_cleanup_phase 'Unused packages'
  orphan_output=$(command pacman -Qtdq)
  rc=$?
  if (( rc == 0 )); then
    orphans=( ${(f)orphan_output} )
    if (( ${#orphans[@]} == 0 )); then
      print 'No orphaned packages found.'
      (( succeeded++ ))
    elif (( _UPKG_DRY_RUN )); then
      print -r -- "$orphan_output"
      print -r -- "would run: ${prefix}pacman -Rs -- ${(j: :)orphans}"
      (( succeeded++ ))
    else
      if _upkg_is_root; then
        _upkg_run_cleanup_step 'pacman orphan removal failed' pacman -Rs -- "${orphans[@]}"
      else
        _upkg_run_cleanup_step 'pacman orphan removal failed' sudo pacman -Rs -- "${orphans[@]}"
      fi
    fi
  elif (( rc == 1 )) && [ -z "$orphan_output" ]; then
    print 'No orphaned packages found.'
    (( succeeded++ ))
  else
    [ -n "$orphan_output" ] && print -r -- "$orphan_output"
    (( failed++ ))
    failures+=('pacman orphan query failed')
  fi

  _upkg_print_cleanup_phase 'Package cache'
  if (( _UPKG_DRY_RUN )); then
    print -r -- "would run: ${prefix}pacman -Sc"
    (( succeeded++ ))
  else
    if _upkg_is_root; then
      _upkg_run_cleanup_step 'pacman -Sc failed' pacman -Sc
    else
      _upkg_run_cleanup_step 'pacman -Sc failed' sudo pacman -Sc
    fi
  fi

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_clean_paru() {
  emulate -L zsh

  local succeeded=0 failed=0
  local -a failures

  _upkg_print_section paru

  if (( _UPKG_DRY_RUN )); then
    _upkg_print_cleanup_phase 'Unused packages'
    print 'would run: paru -c'
    (( succeeded++ ))
    _upkg_print_cleanup_phase 'Package cache'
    print 'would run: paru -Sc'
    (( succeeded++ ))
    _upkg_finish_cleanup_result "$succeeded" "$failed" ''
    return $?
  fi

  if (( ! _UPKG_ALLOW_SUDO )); then
    print 'paru cleanup requires explicit --sudo opt-in; rerun with: upkg clean --sudo --only paru'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only paru'
    return 0
  fi

  _upkg_print_cleanup_phase 'Unused packages'
  _upkg_run_cleanup_step 'paru -c failed' paru -c

  _upkg_print_cleanup_phase 'Package cache'
  _upkg_run_cleanup_step 'paru -Sc failed' paru -Sc

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_clean_brew() {
  emulate -L zsh

  local succeeded=0 failed=0
  local -a failures

  _upkg_print_section brew

  _upkg_print_cleanup_phase 'Unused packages'
  if (( _UPKG_DRY_RUN )); then
    _upkg_run_cleanup_step 'brew autoremove preview failed' brew autoremove --dry-run
  else
    _upkg_run_cleanup_step 'brew autoremove failed' brew autoremove
  fi

  _upkg_print_cleanup_phase 'Package cache'
  if (( _UPKG_DRY_RUN )); then
    _upkg_run_cleanup_step 'brew cleanup preview failed' brew cleanup --dry-run
  else
    _upkg_run_cleanup_step 'brew cleanup failed' brew cleanup
  fi

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_clean_flatpak() {
  emulate -L zsh

  local succeeded=0 failed=0
  local -a failures

  _upkg_print_section flatpak

  if (( _UPKG_DRY_RUN )); then
    _upkg_print_cleanup_phase 'Unused user refs'
    print 'would run: flatpak uninstall --unused --user'
    (( succeeded++ ))
    _upkg_print_cleanup_phase 'Unused system refs'
    print 'would run: flatpak uninstall --unused --system'
    (( succeeded++ ))
    _upkg_finish_cleanup_result "$succeeded" "$failed" ''
    return $?
  fi

  _upkg_print_cleanup_phase 'Unused user refs'
  _upkg_run_cleanup_step 'flatpak user cleanup failed' flatpak uninstall --unused --user

  _upkg_print_cleanup_phase 'Unused system refs'
  _upkg_run_cleanup_step 'flatpak system cleanup failed' flatpak uninstall --unused --system

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_clean_nix() {
  emulate -L zsh

  local succeeded=0 failed=0
  local -a failures

  _upkg_print_section nix

  if ! command -v nix-collect-garbage >/dev/null 2>&1; then
    print 'nix-collect-garbage is required for Nix cleanup; ensure it is installed and available on PATH.'
    _upkg_set_last_result 'failed' 'nix-collect-garbage is not available'
    return 1
  fi

  _upkg_print_cleanup_phase 'Unreachable store objects'
  if (( _UPKG_DRY_RUN )); then
    _upkg_run_cleanup_step 'nix-collect-garbage failed' nix-collect-garbage --dry-run
  else
    _upkg_run_cleanup_step 'nix-collect-garbage failed' nix-collect-garbage
  fi

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_npm_npx_cache_command() {
  emulate -L zsh
  setopt multios

  local action=$1
  local stdout_file='' stderr_file='' stdout_output='' stderr_output=''
  local rc
  integer stdout_fd stderr_fd

  typeset -g _UPKG_NPM_NPX_STDOUT=''
  typeset -g _UPKG_NPM_NPX_STDERR=''
  typeset -g _UPKG_NPM_NPX_DIAGNOSTIC=''

  stdout_file=$(command mktemp "${TMPDIR:-/tmp}/upkg-npm-npx.stdout.XXXXXX") || {
    print -u2 -- 'Could not create temporary output capture for npm npx cache cleanup.'
    return 1
  }
  stderr_file=$(command mktemp "${TMPDIR:-/tmp}/upkg-npm-npx.stderr.XXXXXX") || {
    command rm -f -- "$stdout_file"
    print -u2 -- 'Could not create temporary error capture for npm npx cache cleanup.'
    return 1
  }

  exec {stdout_fd}>&1 || {
    command rm -f -- "$stdout_file" "$stderr_file"
    return 1
  }
  exec {stderr_fd}>&2 || {
    exec {stdout_fd}>&-
    command rm -f -- "$stdout_file" "$stderr_file"
    return 1
  }

  # Zsh multios duplicate each native stream to its original descriptor and a
  # private diagnostic file, preserving output while allowing capability checks.
  command npm cache npx "$action" >&$stdout_fd >"$stdout_file" 2>&$stderr_fd 2>"$stderr_file"
  rc=$?

  exec {stdout_fd}>&-
  exec {stderr_fd}>&-

  stdout_output=$(<"$stdout_file")
  stderr_output=$(<"$stderr_file")
  _UPKG_NPM_NPX_STDOUT=$stdout_output
  _UPKG_NPM_NPX_STDERR=$stderr_output
  _UPKG_NPM_NPX_DIAGNOSTIC="${stdout_output}"$'\n'"${stderr_output}"
  command rm -f -- "$stdout_file" "$stderr_file"

  return $rc
}

_upkg_npm_npx_cache_unsupported() {
  emulate -L zsh

  local output=${(L)1}

  if [[ $output == *'unknown command'* ||
    $output == *'invalid subcommand'* ||
    $output == *'not a valid npm command'* ]]; then
    return 0
  fi

  if [[ $output == *'usage:'* || $output == *'npm cache usage:'* ]]; then
    [[ $output != *'npm cache npx ls'* && $output != *'npm cache npx rm'* ]]
    return $?
  fi

  return 1
}

_upkg_run_clean_npm() {
  emulate -L zsh

  local output listing line key rc npx_failure_detail
  local npx_unsupported=0 parse_failed=0 verify_failures_before=0
  local succeeded=0 failed=0
  local -a failures npx_keys

  _upkg_print_section npm

  _upkg_print_cleanup_phase 'npx cache'
  if (( _UPKG_DRY_RUN )); then
    _upkg_run_npm_npx_cache_command ls
    rc=$?
    output=${_UPKG_NPM_NPX_DIAGNOSTIC:-}
    unset _UPKG_NPM_NPX_STDOUT _UPKG_NPM_NPX_STDERR _UPKG_NPM_NPX_DIAGNOSTIC
    _upkg_record_cleanup_result "$rc" 'npx cache preview failed'
    if (( rc != 0 )) && _upkg_npm_npx_cache_unsupported "$output"; then
      print 'This npm release does not support the npx cache subcommand; upgrade npm to enable npx cache cleanup.'
    fi

    _upkg_print_cleanup_phase 'npm cache'
    print 'would run: npm cache verify'
    (( succeeded++ ))
    _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
    return $?
  fi

  _upkg_run_npm_npx_cache_command ls
  rc=$?
  output=${_UPKG_NPM_NPX_DIAGNOSTIC:-}
  listing=${_UPKG_NPM_NPX_STDOUT:-}
  unset _UPKG_NPM_NPX_STDOUT _UPKG_NPM_NPX_STDERR _UPKG_NPM_NPX_DIAGNOSTIC

  if (( rc != 0 )); then
    npx_failure_detail='npx cache listing failed'
    if _upkg_npm_npx_cache_unsupported "$output"; then
      npx_unsupported=1
      npx_failure_detail='npx cache cleanup is unsupported'
      print 'This npm release does not support the npx cache subcommand; upgrade npm to enable npx cache cleanup.'
    fi
    _upkg_record_cleanup_result "$rc" "$npx_failure_detail"
  elif [ -z "$listing" ]; then
    print 'No npx cache entries found.'
    _upkg_record_cleanup_result 0 ''
  else
    for line in ${(f)listing}; do
      [ -n "$line" ] || continue
      if [[ $line != *:* ]]; then
        parse_failed=1
        break
      fi

      key=${line%%:*}
      case $key in
        ''|-*|*[![:alnum:]_-]*)
          parse_failed=1
          break
          ;;
      esac
      npx_keys+=("$key")
    done

    if (( parse_failed || ${#npx_keys[@]} == 0 )); then
      print -u2 -- 'Could not safely parse npm npx cache keys; no npx entries were removed.'
      _upkg_record_cleanup_result 1 'npx cache listing could not be parsed'
    else
      _upkg_run_cleanup_step 'npx cache cleanup failed' npm cache npx rm "${npx_keys[@]}"
    fi
  fi

  _upkg_print_cleanup_phase 'npm cache'
  verify_failures_before=$failed
  _upkg_run_cleanup_step 'npm cache verify failed' npm cache verify
  if (( npx_unsupported && failed == verify_failures_before )); then
    failures[-1]='npx cache cleanup is unsupported; npm cache verified'
  fi

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

upkg() {
  emulate -L zsh

  local raw_cmd='' cmd='outdated' manager
  local only_raw='' skip_raw=''
  local query=''
  local allow_sudo=0 dry_run=0 filtered=0 exit_code=0
  local -a candidate_pool run_order display_order query_parts
  local -A selected_map skipped_map alternate_map display_seen

  local _UPKG_THEME_MODE=''

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
      --)
        shift
        if [ "$raw_cmd" = 'search' ]; then
          while (( $# > 0 )); do
            query_parts+=("$1")
            shift
          done
          break
        fi
        print -u2 -- "Unknown argument: --"
        _upkg_usage
        return 1
        ;;
      help)
        if [ "$raw_cmd" = 'search' ]; then
          query_parts+=("$1")
        else
          raw_cmd='help'
        fi
        ;;
      -h|--help)
        raw_cmd='help'
        ;;
      outdated|check|list|search|upgrade|up|update|plan|clean|managers)
        if [ "$raw_cmd" = 'search' ]; then
          query_parts+=("$1")
        else
          if [ -n "$raw_cmd" ] && [ "$raw_cmd" != "$1" ]; then
            print -u2 -- "Unexpected extra command: $1"
            _upkg_usage
            return 1
          fi
          raw_cmd=$1
        fi
        ;;
      *)
        if [ "$raw_cmd" = 'search' ]; then
          query_parts+=("$1")
        else
          print -u2 -- "Unknown argument: $1"
          _upkg_usage
          return 1
        fi
        ;;
    esac
    shift
  done

  case ${raw_cmd:-outdated} in
    outdated|check|list) cmd='outdated' ;;
    search) cmd='search' ;;
    upgrade|up|update) cmd='upgrade' ;;
    plan) cmd='plan' ;;
    clean) cmd='clean' ;;
    managers) cmd='managers' ;;
    help) cmd='help' ;;
  esac

  if [ "$cmd" = 'search' ]; then
    if (( ${#query_parts[@]} == 0 )); then
      _upkg_search_usage >&2
      return 1
    fi
    query="${(j: :)query_parts}"
  fi

  if (( dry_run )); then
    if [ "$cmd" = 'upgrade' ]; then
      cmd='plan'
    elif [ "$cmd" = 'outdated' ] || [ "$cmd" = 'plan' ]; then
      cmd='plan'
    elif [ "$cmd" = 'clean' ]; then
      :
    else
      print -u2 -- '--dry-run is only valid with the default outdated check, plan, upgrade, or clean'
      _upkg_usage
      return 1
    fi
  fi

  if [ "$cmd" = 'help' ]; then
    _upkg_usage
    return 0
  fi

  if ! _ui_plain_mode; then
    _UPKG_THEME_MODE=1
    case $cmd in
      search)
        _ui_title_line 'Package Search' "$query" accent '󰍉' '*'
        ;;
      managers)
        _ui_title_line 'Detected Managers' 'upkg managers' accent '󰒓' '*'
        ;;
      clean)
        if (( dry_run )); then
          _ui_title_line 'Package Cleanup' 'dry-run' accent '󰃢' '*'
        else
          _ui_title_line 'Package Cleanup' 'upkg clean' accent '󰃢' '*'
        fi
        ;;
      *)
        _ui_title_line 'Package Dashboard' "$cmd" accent '󰏖' '*'
        ;;
    esac
    [ -n "$only_raw" ] && _ui_panel_kv 'Only' "$only_raw" muted text
    [ -n "$skip_raw" ] && _ui_panel_kv 'Skip' "$skip_raw" muted text
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

    if _ui_plain_mode || [ -z "${_UPKG_THEME_MODE:-}" ]; then
      print 'Detected managers:'
    else
      _ui_section_break
    fi

    for manager in "${display_order[@]}"; do
      local manager_status='' role='muted'

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
        if [ "$manager_status" = 'active' ]; then
          print "  - $manager"
        else
          print "  - $manager ($manager_status)"
        fi
      else
        _ui_panel_prefix
        _ui_badge "$manager_status" "$role"
        print -nr -- ' '
        _ui_color text
        print -nr -- "$(_upkg_manager_title "$manager")"
        _ui_reset
        print ''
      fi
    done

    if ! _ui_plain_mode && [ -n "${_UPKG_THEME_MODE:-}" ]; then
      _ui_section_break
      print -nr -- '  '
      _ui_color muted
      print -r -- 'Selection order follows execution order'
      _ui_reset
    fi

    if (( filtered && ${#_UPKG_SELECTED_MANAGERS[@]} == 0 )); then
      return 1
    fi

    return 0
  fi

  _upkg_apply_filters "$only_raw" "$skip_raw" || return 1

  if (( ${#_UPKG_SELECTED_MANAGERS[@]} == 0 )); then
    print -u2 -- 'No package managers selected after applying filters.'
    [ -n "$only_raw" ] && print -u2 -- "Only filter: $only_raw"
    [ -n "$skip_raw" ] && print -u2 -- "Skip filter: $skip_raw"
    print -u2 -- "Run: upkg managers${_UPKG_ONLY_FILTER_HINT:+ --only ${_UPKG_ONLY_FILTER_HINT}}${_UPKG_SKIP_FILTER_HINT:+ --skip ${_UPKG_SKIP_FILTER_HINT}}"
    return 1
  fi

  typeset -g _UPKG_ALLOW_SUDO=$allow_sudo
  typeset -g _UPKG_DRY_RUN=$dry_run
  typeset -g _UPKG_OPERATION=$cmd
  typeset -g -a _UPKG_SUMMARY_ORDER
  typeset -g -A _UPKG_SUMMARY_STATE _UPKG_SUMMARY_DETAIL
  _UPKG_SUMMARY_ORDER=()
  _UPKG_SUMMARY_STATE=()
  _UPKG_SUMMARY_DETAIL=()

  if [ "$cmd" = 'search' ]; then
    typeset -g -a _UPKG_SEARCH_ROWS
    _UPKG_SEARCH_ROWS=()
  fi

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
      outdated:brew) _upkg_run_outdated_brew ;;
      outdated:flatpak) _upkg_run_outdated_flatpak ;;
      outdated:nix) _upkg_run_outdated_nix ;;
      outdated:npm) _upkg_run_outdated_npm ;;
      search:apt) _upkg_run_search_apt "${query_parts[@]}" ;;
      search:dnf) _upkg_run_search_dnf "${query_parts[@]}" ;;
      search:pacman) _upkg_run_search_pacman "${query_parts[@]}" ;;
      search:paru) _upkg_run_search_paru "${query_parts[@]}" ;;
      search:brew) _upkg_run_search_brew "${query_parts[@]}" ;;
      search:flatpak) _upkg_run_search_flatpak "${query_parts[@]}" ;;
      search:nix) _upkg_run_search_nix "${query_parts[@]}" ;;
      search:npm) _upkg_run_search_npm "${query_parts[@]}" ;;
      plan:apt) _upkg_run_outdated_apt ;;
      plan:dnf) _upkg_run_outdated_dnf ;;
      plan:pacman) _upkg_run_outdated_pacman ;;
      plan:paru) _upkg_run_outdated_paru ;;
      plan:brew) _upkg_run_outdated_brew ;;
      plan:flatpak) _upkg_run_outdated_flatpak ;;
      plan:nix) _upkg_run_outdated_nix ;;
      plan:npm) _upkg_run_outdated_npm ;;
      upgrade:apt) _upkg_run_upgrade_apt ;;
      upgrade:dnf) _upkg_run_upgrade_dnf ;;
      upgrade:pacman) _upkg_run_upgrade_pacman ;;
      upgrade:paru) _upkg_run_upgrade_paru ;;
      upgrade:brew) _upkg_run_upgrade_brew ;;
      upgrade:flatpak) _upkg_run_upgrade_flatpak ;;
      upgrade:nix) _upkg_run_upgrade_nix ;;
      upgrade:npm) _upkg_run_upgrade_npm ;;
      clean:apt) _upkg_run_clean_apt ;;
      clean:dnf) _upkg_run_clean_dnf ;;
      clean:pacman) _upkg_run_clean_pacman ;;
      clean:paru) _upkg_run_clean_paru ;;
      clean:brew) _upkg_run_clean_brew ;;
      clean:flatpak) _upkg_run_clean_flatpak ;;
      clean:nix) _upkg_run_clean_nix ;;
      clean:npm) _upkg_run_clean_npm ;;
      *)
        _upkg_print_section "$manager"
        print "No handler defined for $manager"
        _upkg_set_last_result 'failed' 'missing handler'
        ;;
    esac

    _upkg_record_summary "$manager" "$_UPKG_LAST_STATE" "$_UPKG_LAST_DETAIL"

    case $_UPKG_LAST_STATE in
      partial|blocked|failed)
        exit_code=1
        ;;
    esac
  done

  for manager in "${_UPKG_SKIPPED_MANAGERS[@]}"; do
    _upkg_record_summary "$manager" 'skipped' ''
  done

  if [ "$cmd" = 'search' ]; then
    _upkg_format_search_rows "${_UPKG_SEARCH_ROWS[@]}"
    _upkg_print_search_summary
    return $exit_code
  fi

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
    print '  outdated             Compare installed and evaluated Nix output identities'
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
    print '  - Interactive add/find/remove needs jq and fzf 0.68.0+'
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

    _zsh_require_fzf || return 1

    if [ ! -t 0 ] || [ ! -t 1 ]; then
      echo "Interactive npkg ${action} requires a terminal"
      return 1
    fi
  }

  _npkg_fzf_preview_window() {
    emulate -L zsh

    if (( $+functions[_zsh_theme_fzf_preview_window] )); then
      _zsh_theme_fzf_preview_window || return 1
      print -r -- "$REPLY"
      return
    fi

    print -r -- 'down,40%,border-top,wrap-word'
  }

  _npkg_pick_installables() {
    emulate -L zsh

    local cache_file selection attr query multi_footer
    local -a installables fzf_args context_args preview_args multi_args
    local _c_attr='' _c_muted='' _c_success='' _c_info='' _c0=''

    _npkg_require_picker 'install' || return 1

    if (( $+functions[_ui_is_rich_terminal] )) && _ui_is_rich_terminal; then
      _zsh_theme_sgr accent fg ui && _c_attr=$REPLY
      _zsh_theme_sgr muted fg ui && _c_muted=$REPLY
      _zsh_theme_sgr success fg ui && _c_success=$REPLY
      _zsh_theme_sgr info fg ui && _c_info=$REPLY
      _c0=$'\e[0m'
    fi

    query="${(j: :)@}"
    cache_file=$(_npkg_attr_index) || return 1
    _fzf_picker_multi_args add
    multi_footer=$REPLY
    multi_args=( "${reply[@]}" )
    _fzf_picker_context_args Packages 'Type to filter packages' "$multi_footer"
    context_args=( "${reply[@]}" )
    _fzf_picker_preview_args Package
    preview_args=( "${reply[@]}" )
    fzf_args=(
      "${context_args[@]}"
      "${preview_args[@]}"
      "${multi_args[@]}"
      "--query=$query"
    )

    selection=$(
      _c_attr="$_c_attr" _c_muted="$_c_muted" _c_success="$_c_success" \
      _c_info="$_c_info" _c0="$_c0" \
      command fzf "${fzf_args[@]}" \
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

    local candidates selection multi_footer target
    local -a targets fzf_args context_args preview_args multi_args
    local _c_attr='' _c_muted='' _c_info='' _c0=''

    _npkg_require_picker 'remove' || return 1

    if (( $+functions[_ui_is_rich_terminal] )) && _ui_is_rich_terminal; then
      _zsh_theme_sgr accent fg ui && _c_attr=$REPLY
      _zsh_theme_sgr muted fg ui && _c_muted=$REPLY
      _zsh_theme_sgr info fg ui && _c_info=$REPLY
      _c0=$'\e[0m'
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
              .name,
              .attr,
              (.source | clean_text),
              .target
            ]
          | @tsv
        '
    ) || return 1

    if [ -z "$candidates" ]; then
      echo "No packages are installed in the current Nix profile"
      return 0
    fi

    _fzf_picker_multi_args remove
    multi_footer=$REPLY
    multi_args=( "${reply[@]}" )
    _fzf_picker_context_args 'Installed packages' 'Type to filter installed packages' "$multi_footer"
    context_args=( "${reply[@]}" )
    _fzf_picker_preview_args Package
    preview_args=( "${reply[@]}" )
    fzf_args=(
      "${context_args[@]}"
      "${preview_args[@]}"
      "${multi_args[@]}"
      --delimiter=$'\t'
      --with-nth=1,2,3
      --nth=1,2,3
      --accept-nth=4
      --freeze-left=1
      --wrap=word
    )

    selection=$(
      print -r -- "$candidates" |
        _c_attr="$_c_attr" _c_muted="$_c_muted" _c_info="$_c_info" _c0="$_c0" \
        command fzf "${fzf_args[@]}" \
          --preview 'printf "${_c_attr}Name:${_c0} %s\n${_c_muted}Attr:${_c0} %s\n${_c_info}Source:${_c0} %s\n" {1} {2} {3}'
    ) || return 0

    while IFS= read -r target; do
      [ -n "$target" ] && targets+=("$target")
    done <<< "$selection"

    (( ${#targets[@]} > 0 )) || return 0
    _npkg_nix profile remove "${targets[@]}"
  }

  _npkg_set_outdated_state() {
    typeset -g _NPKG_OUTDATED_STATE=$1
    typeset -gi _NPKG_OUTDATED_TOTAL=${2:-0}
    typeset -gi _NPKG_OUTDATED_CHANGED=${3:-0}
    typeset -gi _NPKG_OUTDATED_UNKNOWN=${4:-0}
  }

  _npkg_eval_installable_record() {
    emulate -L zsh

    local source=$1
    local attr_path=$2
    local outputs_json=$3
    local selection apply_expr output_name
    local -a output_names

    if [[ $outputs_json == null ]]; then
      selection='if (package.outputSpecified or false) then [ package.outputName ] else if (package ? meta) && (package.meta ? outputsToInstall) then package.meta.outputsToInstall else [ "out" ]'
    else
      print -r -- "$outputs_json" | command jq -e '
        type == "array"
        and length > 0
        and all(.[]; type == "string" and (. == "*" or test("^[A-Za-z0-9+._?=-]+$")))
        and ((map(select(. == "*")) | length) == 0 or (length == 1 and .[0] == "*"))
      ' >/dev/null 2>&1 || return 1

      output_names=( "${(@f)$(print -r -- "$outputs_json" | command jq -r '.[]')}" )
      if (( ${#output_names[@]} == 1 )) && [[ ${output_names[1]} == '*' ]]; then
        selection='package.outputs or [ "out" ]'
      else
        selection='[ '
        for output_name in "${output_names[@]}"; do
          selection+='"'"$output_name"'" '
        done
        selection+=']'
      fi
    fi

    apply_expr="package:
      let
        selectedOutputs = ${selection};
        outputPath = output:
          if builtins.hasAttr output package
          then builtins.toString (builtins.getAttr output package)
          else throw \"selected output is missing from the evaluated package\";
      in {
        paths = builtins.sort builtins.lessThan (builtins.map outputPath selectedOutputs);
        version = if package ? version then builtins.toString package.version else null;
      }"

    _npkg_nix eval --json "${source}#${attr_path}" --apply "$apply_expr"
  }

  _npkg_outdated() {
    emulate -L zsh
    setopt pipefail localtraps NO_MONITOR NO_NOTIFY

    _npkg_set_outdated_state partial 0 0 0

    if ! command -v jq >/dev/null 2>&1; then
      echo "jq is required for npkg outdated"
      return 1
    fi

    local profile_json profile_error_file profile_error entry_data entry_json name attr_path source locked_uri
    local store_paths_json outputs_json structural_value
    local tmp_dir current_record locked_record installed_paths available_paths
    local installed_version available_version package_state display_state marker role detail error_output
    local width name_width version_width visible_count more
    local current_file locked_file pid
    integer pkg_count=0 changed=0 unknown=0 idx interrupted=0
    integer max_jobs=8
    local -a names attrs sources locked_uris installed_path_sets output_specs structurally_valid
    local -a installed_versions available_versions statuses unknown_details job_pids

    profile_error_file=$(command mktemp "${TMPDIR:-/tmp}/npkg-profile-error.XXXXXX") || {
      echo "Failed to create temporary storage for npkg outdated."
      return 1
    }
    trap 'command rm -f -- "$profile_error_file"; trap - INT TERM; return 130' INT TERM

    profile_json=$(_npkg_nix profile list --json 2>"$profile_error_file") || {
      profile_error=$(<"$profile_error_file")
      command rm -f -- "$profile_error_file"
      trap - INT TERM
      echo "Failed to read Nix profile."
      [[ -n $profile_error ]] && print -r -- "Diagnostic: $(_ui_safe_text "$profile_error")"
      return 1
    }
    command rm -f -- "$profile_error_file"
    trap - INT TERM

    print -r -- "$profile_json" | command jq -e '
      type == "object"
      and (((.elements | type) == "object") or ((.elements | type) == "array"))
    ' >/dev/null 2>&1 || {
      echo "Failed to parse Nix profile JSON."
      return 1
    }

    entry_data=$(
      print -r -- "$profile_json" | command jq -c '
        def text: if type == "string" then . else "" end;
        def manifest_entries:
          if (.elements | type) == "object" then
            .elements
            | to_entries
            | sort_by(.key)
            | .[]
            | {
                fallbackName: .key,
                value: (.value | if type == "object" then . else {} end)
              }
          else
            .elements
            | to_entries[]
            | {
                fallbackName: "element-\(.key + 1)",
                value: (.value | if type == "object" then . else {} end)
              }
          end;

        manifest_entries
        | .fallbackName as $fallback
        | .value as $value
        | select(($value.active // true) == true)
        | (($value.attrPath // "") | text) as $attr
        | (($value.originalUrl // $value.originalUri // "") | text) as $original
        | (($value.uri // $value.url // "") | text) as $locked
        | ($value.storePaths // null) as $stores
        | select((($original + " " + $locked) | ascii_downcase | contains("nixpkgs")))
        | {
            displayName: (
              if (($value.name // "") | text) != "" then (($value.name // "") | text)
              elif $attr != "" then ($attr | split(".") | last)
              elif (($stores | type) == "array" and ($stores | length) > 0 and (($stores[0] | type) == "string")) then ($stores[0] | split("/") | last)
              else $fallback
              end
            ),
            attrPath: $attr,
            originalUrl: $original,
            lockedUri: $locked,
            storePaths: $stores,
            outputs: ($value.outputs // null)
          }
      '
    ) || {
      echo "Failed to parse Nix profile elements."
      return 1
    }

    while IFS= read -r entry_json; do
      [[ -n $entry_json ]] || continue

      name=$(print -r -- "$entry_json" | command jq -r '.displayName') || return 1
      attr_path=$(print -r -- "$entry_json" | command jq -r '.attrPath') || return 1
      source=$(print -r -- "$entry_json" | command jq -r '.originalUrl') || return 1
      locked_uri=$(print -r -- "$entry_json" | command jq -r '.lockedUri') || return 1
      store_paths_json=$(print -r -- "$entry_json" | command jq -c '.storePaths') || return 1
      outputs_json=$(print -r -- "$entry_json" | command jq -c '.outputs') || return 1

      if print -r -- "$entry_json" | command jq -e '
        (.displayName | type == "string" and length > 0)
        and (.attrPath | type == "string" and length > 0)
        and (.originalUrl | type == "string" and length > 0)
        and (.lockedUri | type == "string")
        and (.storePaths | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
        and (
          .outputs == null
          or (
            (.outputs | type) == "array"
            and (.outputs | length) > 0
            and all(.outputs[]; type == "string" and (. == "*" or test("^[A-Za-z0-9+._?=-]+$")))
            and (([.outputs[] | select(. == "*")] | length) == 0 or ((.outputs | length) == 1 and .outputs[0] == "*"))
          )
        )
      ' >/dev/null 2>&1; then
        structural_value=1
      else
        structural_value=0
      fi

      names+=("$(_ui_safe_text "$name")")
      attrs+=("$attr_path")
      sources+=("$source")
      locked_uris+=("$locked_uri")
      installed_path_sets+=("$store_paths_json")
      output_specs+=("$outputs_json")
      structurally_valid+=("$structural_value")
    done <<< "$entry_data"

    pkg_count=${#names[@]}
    if (( pkg_count == 0 )); then
      _npkg_set_outdated_state current 0 0 0
      echo "No nixpkgs packages found in the current profile."
      return 0
    fi

    echo "Checking $pkg_count package(s) for changes..."

    tmp_dir=$(command mktemp -d "${TMPDIR:-/tmp}/npkg-outdated.XXXXXX") || {
      echo "Failed to create temporary storage for npkg outdated."
      return 1
    }
    [[ -n $tmp_dir && -d $tmp_dir ]] || {
      echo "Failed to create temporary storage for npkg outdated."
      return 1
    }

    trap 'command rm -rf -- "$tmp_dir"' EXIT
    trap 'interrupted=1; for pid in "${job_pids[@]}"; do command kill "$pid" 2>/dev/null; done' INT TERM

    for (( idx = 1; idx <= pkg_count; idx++ )); do
      (( interrupted )) && break
      (( structurally_valid[$idx] )) || continue

      (
        _npkg_eval_installable_record \
          "${sources[$idx]}" \
          "${attrs[$idx]}" \
          "${output_specs[$idx]}" \
          >"${tmp_dir}/${idx}.current" \
          2>"${tmp_dir}/${idx}.current.error"

        if [[ -n ${locked_uris[$idx]} ]]; then
          _npkg_eval_installable_record \
            "${locked_uris[$idx]}" \
            "${attrs[$idx]}" \
            "${output_specs[$idx]}" \
            >"${tmp_dir}/${idx}.locked" \
            2>"${tmp_dir}/${idx}.locked.error"
        fi
        :
      ) &
      job_pids+=("$!")

      if (( interrupted )); then
        command kill "${job_pids[-1]}" 2>/dev/null
        break
      fi

      if (( ${#job_pids[@]} >= max_jobs )); then
        for pid in "${job_pids[@]}"; do
          wait "$pid" 2>/dev/null
        done
        job_pids=()
        (( interrupted )) && break
      fi
    done

    for pid in "${job_pids[@]}"; do
      wait "$pid" 2>/dev/null
    done
    job_pids=()

    if (( interrupted )); then
      trap - INT TERM
      command rm -rf -- "$tmp_dir"
      trap - EXIT
      return 130
    fi

    for (( idx = 1; idx <= pkg_count; idx++ )); do
      (( interrupted )) && break
      installed_version='?'
      available_version='?'
      package_state=unknown
      detail=''
      current_file="${tmp_dir}/${idx}.current"
      locked_file="${tmp_dir}/${idx}.locked"

      if (( ! structurally_valid[$idx] )); then
        detail='incomplete profile data'
      fi

      if [[ -s $locked_file ]]; then
        locked_record=$(<"$locked_file")
        if print -r -- "$locked_record" | command jq -e '
          type == "object" and (.version == null or (.version | type) == "string")
        ' >/dev/null 2>&1; then
          installed_version=$(print -r -- "$locked_record" | command jq -r 'if .version == null or .version == "" then "?" else .version end')
          installed_version=$(_ui_safe_text "$installed_version")
        fi
      fi

      if (( structurally_valid[$idx] )) && [[ -s $current_file ]]; then
        current_record=$(<"$current_file")
        if print -r -- "$current_record" | command jq -e '
          type == "object"
          and (.paths | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
          and (.version == null or (.version | type) == "string")
        ' >/dev/null 2>&1; then
          installed_paths=$(print -r -- "${installed_path_sets[$idx]}" | command jq -c 'sort | unique')
          available_paths=$(print -r -- "$current_record" | command jq -c '.paths | sort | unique')
          available_version=$(print -r -- "$current_record" | command jq -r 'if .version == null or .version == "" then "?" else .version end')
          available_version=$(_ui_safe_text "$available_version")

          if [[ $installed_paths == $available_paths ]]; then
            package_state=current
          else
            package_state=changed
            (( changed++ ))
          fi
        else
          detail='evaluation returned unusable output-path data'
        fi
      elif (( structurally_valid[$idx] )); then
        if [[ -s "${tmp_dir}/${idx}.current.error" ]]; then
          error_output=$(<"${tmp_dir}/${idx}.current.error")
          detail="evaluation failed: $(_ui_safe_text "$error_output")"
        else
          detail='evaluation failed without a diagnostic'
        fi
      fi

      if [[ $package_state == unknown ]]; then
        (( unknown++ ))
      fi

      installed_versions+=("$installed_version")
      available_versions+=("$available_version")
      statuses+=("$package_state")
      unknown_details+=("$detail")
    done

    trap - INT TERM
    if (( interrupted )); then
      command rm -rf -- "$tmp_dir"
      trap - EXIT
      return 130
    fi

    command rm -rf -- "$tmp_dir"
    trap - EXIT

    if (( unknown > 0 )); then
      _npkg_set_outdated_state partial "$pkg_count" "$changed" "$unknown"
    elif (( changed > 0 )); then
      _npkg_set_outdated_state changed "$pkg_count" "$changed" 0
    else
      _npkg_set_outdated_state current "$pkg_count" 0 0
    fi

    if _ui_plain_mode; then
      printf '\n'
      printf '%-25s %-20s %-20s %s\n' 'Package' 'Installed' 'Available' 'Status'
      printf '%-25s %-20s %-20s %s\n' '-------' '---------' '---------' '------'

      for (( idx = 1; idx <= pkg_count; idx++ )); do
        case ${statuses[$idx]} in
          changed) display_state='change available' ;;
          *) display_state=${statuses[$idx]} ;;
        esac
        printf '%-25s %-20s %-20s %s\n' \
          "${names[$idx]}" \
          "${installed_versions[$idx]}" \
          "${available_versions[$idx]}" \
          "$display_state"
      done

      if (( unknown > 0 )); then
        for (( idx = 1; idx <= pkg_count; idx++ )); do
          [[ ${statuses[$idx]} == unknown ]] || continue
          printf 'Unknown: %s - %s\n' "${names[$idx]}" "${unknown_details[$idx]}"
        done
      fi

      printf '\n'
      if (( unknown > 0 )); then
        printf 'Partial result: %d change(s) available; %d unknown.\n' "$changed" "$unknown"
        return 1
      elif (( changed > 0 )); then
        printf '%d change(s) available. Run: npkg upgrade\n' "$changed"
      else
        printf 'Everything is up to date.\n'
      fi
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

    _ui_title_line 'Nix Package Drift' "$pkg_count package(s) checked" accent '󱄅' '*'
    _ui_panel_kv 'Command' 'npkg outdated' muted text
    _ui_section_break

    for (( idx = 1; idx <= visible_count; idx++ )); do
      package_state=${statuses[$idx]}
      case $package_state in
        current) marker=current; role=success ;;
        changed) marker='change available'; role=warning ;;
        *) marker=unknown; role=danger ;;
      esac

      _ui_panel_prefix
      _ui_badge "$marker" "$role"
      print -nr -- ' '
      _ui_color text
      _ui_pad left "$name_width" "$(_ui_safe_truncate "$name_width" "${names[$idx]}")"
      _ui_reset
      print -nr -- ' '
      _ui_color muted
      _ui_pad left "$version_width" "$(_ui_safe_truncate "$version_width" "${installed_versions[$idx]}")"
      _ui_reset
      print -nr -- ' '
      _ui_color info
      _ui_pad left "$version_width" "$(_ui_safe_truncate "$version_width" "${available_versions[$idx]}")"
      _ui_reset
      print ''
    done

    if (( more > 0 )); then
      _ui_panel_kv 'More' "+${more} not shown" muted muted
    fi

    if (( unknown > 0 )); then
      for (( idx = 1; idx <= pkg_count; idx++ )); do
        [[ ${statuses[$idx]} == unknown ]] || continue
        _ui_panel_kv 'Unknown' "${names[$idx]} - ${unknown_details[$idx]}" danger text
      done
    fi

    _ui_section_break
    print -nr -- '  '
    if (( unknown > 0 )); then
      _ui_color danger
      print -r -- "Partial result: $changed change(s) available; $unknown unknown."
      _ui_reset
      return 1
    elif (( changed > 0 )); then
      _ui_color warning
      print -r -- "$changed change(s) available. Run npkg upgrade to apply."
    else
      _ui_color success
      print -r -- 'Everything is up to date.'
    fi
    _ui_reset
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
