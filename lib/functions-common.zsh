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
  local IFS=$' \t\n'
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
  local IFS=$' \t\n'
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

# Parse kernel child lists with fixed whitespace, independent of caller IFS.
_zsh_query_task_children_files() {
  emulate -L zsh
  local IFS=$' \t\n'
  local child_file text child
  local -a children tokens
  reply=()
  (( $# )) || return 1
  for child_file in "$@"; do
    [[ -r $child_file ]] || return 1
    text=$(<"$child_file") 2>/dev/null || return 1
    tokens=( ${=text} )
    for child in "${tokens[@]}"; do
      [[ $child == <-> ]] || return 1
      children+=( "$child" )
    done
  done
  (( ${#children} )) || return 1
  reply=( "${children[@]}" )
}

# Optional per-task child lists are not present in every Linux kernel.
_zsh_query_task_children() {
  emulate -L zsh
  local pid=$1 child
  local -a files candidates children
  files=( /proc/$pid/task/*/children(N) )
  _zsh_query_task_children_files "${files[@]}" || return 1
  candidates=( "${reply[@]}" )
  for child in "${candidates[@]}"; do
    _zsh_query_process_record "$child" || return 1
    [[ ${reply[2]} == "$pid" && ${reply[1]} != Z ]] || return 1
    children+=( "$child" )
  done
  reply=( "${children[@]}" )
  (( ${#children} ))
}

_zsh_query_proc_children() {
  emulate -L zsh
  local pid=$1 stat_file
  local -a children
  for stat_file in /proc/<->/stat(N); do
    _zsh_query_process_record "${stat_file:h:t}" || continue
    [[ ${reply[2]} == "$pid" ]] || continue
    children+=( "${stat_file:h:t}" )
  done
  reply=( "${children[@]}" )
}

# A held proc descriptor keeps reads tied to the original task, even after reap.
_zsh_query_process_record() {
  emulate -L zsh
  local IFS=$' \t\n'
  local pid=$1 fd=${2:-} text opened=0
  reply=()
  [[ $pid == <-> ]] || return 1
  zmodload zsh/system || return 1
  if [[ -z $fd ]]; then
    sysopen -r -o cloexec -u fd "/proc/$pid/stat" 2>/dev/null || return 1
    opened=1
  fi
  {
    sysseek -u "$fd" 0 2>/dev/null || return 1
    sysread -i "$fd" text 2>/dev/null || return 1
    reply=( ${=${text##*\) }} )
    [[ ${reply[2]-} == <-> && ${reply[20]-} == <-> ]]
  } always {
    (( ! opened )) || exec {fd}<&-
  }
}

# Before the handshake, own the launch process and its direct setsid child.
_zsh_stop_unidentified_launcher() {
  emulate -L zsh
  local pid=$1 identity=$2 parent=$3 stat_file child child_identity launcher_fd
  local -a children reply
  [[ -n $identity && $pid == <-> ]] || return 0
  zmodload zsh/system || return 0
  # Open before STOP: later path permission/visibility changes cannot strand it.
  sysopen -r -o cloexec -u launcher_fd "/proc/$pid/stat" 2>/dev/null || return 0
  {
    _zsh_query_process_record "$pid" "$launcher_fd" || return 0
    [[ ${reply[2]} == "$parent" && ${reply[20]} == "$identity" && ${reply[1]} != Z ]] || return 0
    builtin kill -STOP "$pid" 2>/dev/null || return 0
    if _zsh_query_task_children "$pid"; then
      children=( "${reply[@]}" )
    else
      # Read-only discovery; PPID establishes candidates, never permission to kill.
      _zsh_query_proc_children "$pid"
      children=( "${reply[@]}" )
    fi
    for child in "${children[@]}"; do
      _zsh_query_process_record "$child" || continue
      [[ ${reply[2]} == "$pid" && ${reply[1]} != Z ]] || continue
      child_identity=${reply[20]}
      if [[ ${reply[3]} == "$child" && ${reply[4]} == "$child" ]]; then
        _zsh_stop_owned_group "$child" "$child_identity" 1
      else
        # Do not STOP children: failed revalidation must never strand a stopped task.
        builtin kill -TERM "$child" 2>/dev/null
        zselect -t 10
        # Previously established parent ownership survives reparenting; the start
        # identity must still match. Recheck in case setsid ran during the grace.
        _zsh_query_process_record "$child" || continue
        [[ ${reply[20]} == "$child_identity" && ${reply[1]} != Z ]] || continue
        if [[ ${reply[3]} == "$child" && ${reply[4]} == "$child" ]]; then
          _zsh_stop_owned_group "$child" "$child_identity" 1
        else
          builtin kill -KILL "$child" 2>/dev/null
        fi
      fi
    done
  } always {
    # Revalidate through the held descriptor, including parent and start time.
    # A dead original task returns ESRCH, rather than data for a recycled PID.
    if _zsh_query_process_record "$pid" "$launcher_fd" &&
       [[ ${reply[2]} == "$parent" && ${reply[20]} == "$identity" && ${reply[1]} != Z ]]; then
      if [[ ${reply[3]} == "$pid" && ${reply[4]} == "$pid" ]]; then
        builtin kill -KILL -- "-$pid" 2>/dev/null
      else
        builtin kill -KILL "$pid" 2>/dev/null
      fi
    fi
    exec {launcher_fd}<&-
  }
  return 0
}

# Captured queries have a private session, including children forked during TERM.
_zsh_run_owned_query() {
  emulate -L zsh
  local IFS=$' \t\n'
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
