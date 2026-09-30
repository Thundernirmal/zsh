# Trusted lazy common implementations; loaded by functions-catalogue.zsh.

_zsh_require_fzf() {
  if (( ! $+functions[_fzf_require_ready] )); then
    print -u2 -r -- 'zsh config: fzf 0.68.0 or newer is required (found: configuration guard unavailable). Upgrade fzf and restart the shell.'
    return 1
  fi
  _fzf_require_ready
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

_ui_safe_text_reply() {
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

  REPLY=$output
}

_ui_safe_text() {
  _ui_safe_text_reply "$@"
  print -r -- "$REPLY"
}

_ui_safe_truncate() {
  emulate -L zsh

  local width=$1
  shift

  local text="$*"
  local marker='…'
  local token pair quad prefix='' suffix=''
  local -a tokens
  integer index left right token_width prefix_width suffix_width text_width marker_width
  integer have_display_width=$(( $+functions[_ui_display_width] ))

  (( width > 0 )) || {
    print -r -- ''
    return 0
  }

  if _ui_ascii_mode; then
    marker='...'
  fi

  if (( have_display_width )); then
    _ui_display_width "$text"
    text_width=$REPLY
    _ui_display_width "$marker"
    marker_width=$REPLY
  else
    text_width=${#text}
    marker_width=${#marker}
  fi

  if (( text_width <= width )); then
    print -r -- "$text"
    return 0
  fi

  if (( width <= marker_width )); then
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

  left=$(( (width - marker_width) / 2 ))
  right=$(( width - marker_width - left ))

  prefix_width=0
  for token in "${tokens[@]}"; do
    if (( have_display_width )); then
      _ui_display_width "$token"
      token_width=$REPLY
    else
      token_width=${#token}
    fi
    (( prefix_width + token_width <= left )) || break
    prefix+=$token
    (( prefix_width += token_width ))
  done

  suffix_width=0
  for (( index = ${#tokens[@]}; index >= 1; index-- )); do
    token=${tokens[$index]}
    if (( have_display_width )); then
      _ui_display_width "$token"
      token_width=$REPLY
    else
      token_width=${#token}
    fi
    (( suffix_width + token_width <= right )) || break
    suffix="${token}${suffix}"
    (( suffix_width += token_width ))
  done

  if (( $+functions[_ui_strip_leading_marks_reply] )); then
    _ui_strip_leading_marks_reply "$suffix"
    suffix=$REPLY
  fi
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
if ! (( $+functions[_ui_pad_reply] )); then
  _ui_pad_reply() {
    emulate -L zsh
    local align=$1 width=$2
    shift 2
    if [ "$align" = 'right' ]; then
      printf -v REPLY '%*s' "$width" "$*"
    else
      printf -v REPLY '%-*s' "$width" "$*"
    fi
  }
fi
if ! (( $+functions[_ui_bar] )); then
  _ui_bar() { :; }
fi
if ! (( $+functions[_ui_visible_count] )); then
  _ui_visible_count() {
    emulate -L zsh
    integer requested=$1 total=$2 reserve=${3:-6} height available

    if (( $+functions[_ui_term_height] )); then
      height=$(_ui_term_height)
    else
      height=${LINES:-24}
      case $height in
        ''|*[!0-9]*) height=24 ;;
      esac
    fi
    available=$(( height - reserve ))

    (( available < 1 )) && available=1
    (( requested > total )) && requested=$total
    (( requested > available )) && requested=$available
    (( requested < 0 )) && requested=0
    print -r -- "$requested"
  }
fi

# Liveness means this shell's recorded worker, not merely an occupied PID.
_zsh_owned_job_is_running() {
  emulate -L zsh
  zmodload zsh/system || return 1
  local pid=$1 stat_text expected
  local -a fields
  [[ $pid == <-> && -r /proc/$pid/stat ]] || return 1
  stat_text=$(</proc/$pid/stat); fields=( ${=${stat_text##*\) }} )
  [[ ${fields[2]-} == "$sysparams[pid]" && ${fields[1]-} != Z ]] || return 1
  expected=${job_identities[$pid]-}
  [[ -z $expected || ${fields[20]-} == "$expected" ]]
}

# Workers own their native query sessions and perform their own shutdown.
_zsh_stop_owned_jobs() {
  emulate -L zsh
  local pid
  for pid in "$@"; do
    _zsh_owned_job_is_running "$pid" || continue
    builtin kill -TERM "$pid" 2>/dev/null
  done
  return 0
}

# A live supervisor pins the process-group identity through TERM and KILL.
_zsh_stop_owned_group() {
  emulate -L zsh
  local pid=$1 identity=$2 stat_text
  local -a fields
  [[ $pid == <-> && -r /proc/$pid/stat ]] || return 0
  stat_text=$(</proc/$pid/stat); fields=( ${=${stat_text##*\) }} )
  [[ ${fields[3]-} == "$pid" && ${fields[4]-} == "$pid" && ${fields[20]-} == "$identity" ]] || return 0
  builtin kill -TERM -- "-$pid" 2>/dev/null
  (( $3 )) && zselect -t 10
  builtin kill -KILL -- "-$pid" 2>/dev/null
  return 0
}

# Before the handshake, own the launch process and its direct setsid child.
_zsh_stop_unidentified_launcher() {
  emulate -L zsh
  local pid=$1 identity=$2 parent=$3 stat_text child_file child
  local -a fields children
  [[ -n $identity && -r /proc/$pid/stat ]] || return 0
  stat_text=$(</proc/$pid/stat); fields=( ${=${stat_text##*\) }} )
  [[ ${fields[2]-} == "$parent" && ${fields[20]-} == "$identity" ]] || return 0
  # Freeze the launcher so setsid cannot fork after its child list is read.
  builtin kill -STOP "$pid" 2>/dev/null || return 0
  for child_file in /proc/$pid/task/*/children(N); do
    children=( ${=$(<"$child_file")} )
    for child in "${children[@]}"; do
      [[ -r /proc/$child/stat ]] || continue
      stat_text=$(</proc/$child/stat); fields=( ${=${stat_text##*\) }} )
      [[ ${fields[2]-} == "$pid" && ${fields[1]-} != Z ]] || continue
      if [[ ${fields[3]-} == "$child" && ${fields[4]-} == "$child" ]]; then
        _zsh_stop_owned_group "$child" "${fields[20]}" 1
      else
        builtin kill -KILL "$child" 2>/dev/null
      fi
    done
  done
  stat_text=$(</proc/$pid/stat); fields=( ${=${stat_text##*\) }} )
  if [[ ${fields[3]-} == "$pid" && ${fields[4]-} == "$pid" ]]; then
    _zsh_stop_owned_group "$pid" "$identity" 1
  else
    builtin kill -KILL "$pid" 2>/dev/null
  fi
  return 0
}

# Captured queries have a private session, including children forked during TERM.
_zsh_run_owned_query() {
  emulate -L zsh
  setopt localtraps NO_MONITOR
  local control_dir='' launcher_pid='' owner_pid='' identity='' command_status=1 signal_status=0
  local shell_executable caller_pid caller_identity root_pid root_identity launcher_identity='' stat_text
  local -a record fields cleanup_dirs
  if (( ${funcstack[(Ie)_upkg_capture_query]} || ${funcstack[(Ie)_npkg_outdated]} )); then
    cleanup_dirs=( "${_ZSH_QUERY_ROOT_CLEANUP_DIRS[@]-}" )
  fi
  integer ticks=0
  if ! zmodload zsh/system || ! zmodload zsh/zselect || ! zmodload zsh/stat || [[ ! -r /proc/$sysparams[pid]/stat ]] || ! command -v setsid >/dev/null 2>&1; then
    print -u2 -r -- 'Captured package queries require Linux /proc, Zsh system/stat/zselect, and setsid (util-linux).'
    return 1
  fi
  caller_pid=$sysparams[pid]
  stat_text=$(</proc/$caller_pid/stat); fields=( ${=${stat_text##*\) }} )
  caller_identity=${fields[20]}
  root_pid=$caller_pid; root_identity=$caller_identity
  if (( ${funcstack[(Ie)_npkg_outdated]} )); then
    root_pid=${_ZSH_QUERY_ROOT_PID:-$caller_pid}
    root_identity=${_ZSH_QUERY_ROOT_IDENTITY:-$caller_identity}
  fi
  shell_executable="/proc/$caller_pid/exe"
  control_dir=$(command mktemp -d "${TMPDIR:-/tmp}/zsh-query-owner.XXXXXXXX") || return 1
  trap '(( signal_status )) || signal_status=130' INT
  trap '(( signal_status )) || signal_status=143' TERM
  trap '(( signal_status )) || signal_status=129' HUP
  {
    command setsid --wait "$shell_executable" -df "$_ZSH_FUNCTIONS_MODULE_DIR/lib/query-supervisor.zsh" "$control_dir" "$caller_pid" "$caller_identity" "$root_pid" "$root_identity" "${#cleanup_dirs}" "${cleanup_dirs[@]}" "$@" &
    launcher_pid=$!
    if [[ -r /proc/$launcher_pid/stat ]]; then
      stat_text=$(</proc/$launcher_pid/stat); fields=( ${=${stat_text##*\) }} )
      [[ ${fields[2]-} != "$caller_pid" ]] || launcher_identity=${fields[20]-}
    fi
    while [[ ! -f $control_dir/identity || ! -s $control_dir/identity ]] && (( ! signal_status && ticks++ < 300 )); do
      builtin kill -0 "$launcher_pid" 2>/dev/null || break
      zselect -t 1
    done
    if [[ ! -f $control_dir/identity || ! -s $control_dir/identity ]] && (( ! signal_status )); then
      print -u2 -r -- 'Captured package query supervisor did not establish its identity.'
    fi
    if [[ -f $control_dir/identity && -s $control_dir/identity ]]; then
      record=( ${=$(<"$control_dir/identity")} )
      owner_pid=${record[1]-}; identity=${record[2]-}
      while [[ ! -f $control_dir/status || ! -s $control_dir/status ]] && (( ! signal_status )); do
        builtin kill -0 "$launcher_pid" 2>/dev/null || break
        zselect -t 1
      done
      [[ ! -f $control_dir/status || ! -s $control_dir/status ]] || command_status=$(<"$control_dir/status")
      [[ $command_status == <-> && $command_status -le 255 ]] || command_status=1
    fi
  } always {
    if [[ -n $owner_pid ]]; then
      _zsh_stop_owned_group "$owner_pid" "$identity" "$signal_status"
    elif [[ -n $launcher_pid ]]; then
      _zsh_stop_unidentified_launcher "$launcher_pid" "$launcher_identity" "$caller_pid"
    fi
    [[ -z $launcher_pid ]] || wait "$launcher_pid" 2>/dev/null
    command rm -rf -- "$control_dir"
  }
  (( ! signal_status )) || command_status=$signal_status
  return "$command_status"
}
