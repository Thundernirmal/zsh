# Trusted lazy system implementations; loaded by functions-catalogue.zsh.

# Keep network calls finite by default while allowing a deliberate per-shell
# override. Values are integer seconds; zero and malformed values are rejected
# so an accidental environment typo cannot restore an unbounded request.
_zsh_http_timeout_args() {
  emulate -L zsh

  local connect=${ZSH_HTTP_CONNECT_TIMEOUT:-5}
  local maximum=${ZSH_HTTP_MAX_TIME:-15}
  local value name variable normalized
  local -a names=(connect maximum) values=("$connect" "$maximum")
  integer index

  for (( index = 1; index <= ${#names[@]}; index++ )); do
    name=${names[$index]}
    value=${values[$index]}
    case $name in
      connect) variable=ZSH_HTTP_CONNECT_TIMEOUT ;;
      maximum) variable=ZSH_HTTP_MAX_TIME ;;
    esac
    case $value in
      ''|*[!0-9]*)
        print -u2 -r -- "zsh network: $variable: invalid timeout '$value' (use positive integer seconds)"
        return 1
        ;;
    esac
    normalized=$value
    while [[ ${#normalized} -gt 1 && $normalized == 0* ]]; do
      normalized=${normalized#0}
    done
    if [[ $normalized == 0 ]]; then
      print -u2 -r -- "zsh network: $variable: timeout must be positive"
      return 1
    fi
  done

  reply=( --connect-timeout "$connect" --max-time "$maximum" )
}

# Fuzzy kill process
_fkill_normalize_signal() {
  emulate -L zsh

  local signal=${1:-15}
  local signal_name signal_number

  signal=${(U)${signal#-}}
  signal=${signal#SIG}
  [[ -n $signal ]] || return 1

  if [[ $signal == <-> ]]; then
    signal_number=$signal
    signal_name=$(builtin kill -l "$signal_number" 2>/dev/null) || return 1
  else
    signal_number=$(builtin kill -l "$signal" 2>/dev/null) || return 1
    signal_name=$(builtin kill -l "$signal_number" 2>/dev/null) || return 1
  fi

  REPLY=$signal_name
  reply=( "$signal_number" )
}

_fkill_usage() {
  print 'Usage: fkill [--all] [signal]'
  print 'Pick a process and send SIGTERM by default; use --all to include other users.'
  print 'SIGKILL and multi-process selections require an explicit confirmation.'
}

fkill() {
  emulate -L zsh

  local signal='15' signal_name signal_number current_user scope_label
  local selected pid multi_footer preview_command confirm_reply arg
  local -a args pids fzf_args multi_args context_args preview_args
  local -i all_users=0 needs_review=0 pid_idx kill_rc=0 failed_count=0 signal_given=0
  args=( "$@" )

  for arg in "${args[@]}"; do
    case $arg in
      -h|--help)
        _fkill_usage
        return 0
        ;;
      --all|-a) all_users=1 ;;
      *)
        if (( signal_given )); then
          print -u2 -r -- "fkill: too many arguments: $arg"
          print -u2 -r -- 'Usage: fkill [--all] [signal]'
          return 1
        fi
        signal=$arg
        signal_given=1
        ;;
    esac
  done

  _fkill_normalize_signal "$signal" || {
    print -u2 -r -- "fkill: invalid signal: $signal"
    print -u2 -r -- 'Usage: fkill [--all] [signal]'
    return 1
  }
  signal_name=$REPLY
  signal_number=$reply[1]

  _zsh_require_fzf || return 1

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    print -u2 -r -- 'fkill requires an interactive terminal'
    return 1
  fi

  if (( all_users )); then
    scope_label='all users'
  else
    current_user=$(command id -un 2>/dev/null) || current_user=${USER:-}
    [[ -n $current_user ]] || {
      print -u2 -r -- 'fkill: cannot determine the current user; pass --all to list every process'
      return 1
    }
    scope_label="user: $current_user"
  fi

  _fzf_picker_multi_args kill
  multi_footer=$REPLY
  multi_args=( "${reply[@]}" )
  _fzf_picker_context_args Processes 'Type to filter processes' "$multi_footer"
  context_args=( "${reply[@]}" )
  _fzf_picker_preview_args Process
  preview_args=( "${reply[@]}" )
  preview_command='pid={1}; command ps -p "$pid" -o pid=,ppid=,user=,etime=,args= 2>/dev/null; command readlink -f "/proc/$pid/cwd" 2>/dev/null'
  fzf_args=(
    "${context_args[@]}"
    "${multi_args[@]}"
    "${preview_args[@]}"
    --delimiter=$'\t'
    --with-nth=1,2,3,4
    --accept-nth=1
    "--header=Signal: SIG${signal_name} (${scope_label})"
    --header-label=Signal
    "--preview=$preview_command"
  )
  if (( all_users )); then
    selected=$(
      command ps -eo pid,user,etime,args | command sed 1d | command awk '
        {
          pid = $1
          user = $2
          etime = $3
          $1 = $2 = $3 = ""
          sub(/^ +/, "")
          print pid "\t" user "\t" etime "\t" $0
        }
      ' | command fzf "${fzf_args[@]}"
    ) || return 0
  else
    selected=$(
      command ps -u "$current_user" -o pid=,user=,etime=,args= | command awk '
        {
          pid = $1
          user = $2
          etime = $3
          $1 = $2 = $3 = ""
          sub(/^ +/, "")
          print pid "\t" user "\t" etime "\t" $0
        }
      ' | command fzf "${fzf_args[@]}"
    ) || return 0
  fi

  while IFS= read -r pid; do
    [ -n "$pid" ] && pids+=("$pid")
  done <<< "$selected"

  (( ${#pids[@]} > 0 )) || return 0

  if (( signal_number == 9 || ${#pids[@]} > 1 )); then
    needs_review=1
  fi
  if (( needs_review )); then
    print -u2 -r -- "Send SIG${signal_name} to ${#pids[@]} process(es): ${(j:, :)pids}?"
    confirm_reply=''
    if ! read -q "confirm_reply?Press y to confirm, any other key to cancel: "; then
      print -u2 -r -- ''
      print -u2 -r -- 'fkill: cancelled; no signal sent'
      return 0
    fi
    print -u2 -r -- ''
    if [[ $confirm_reply != [Yy] ]]; then
      print -u2 -r -- 'fkill: cancelled; no signal sent'
      return 0
    fi
  fi

  for (( pid_idx = 1; pid_idx <= ${#pids[@]}; pid_idx++ )); do
    pid=${pids[$pid_idx]}
    if builtin kill "-$signal_number" -- "$pid" 2>/dev/null; then
      print -r -- "fkill: sent SIG${signal_name} to $pid"
    else
      kill_rc=$?
      (( failed_count++ ))
      print -u2 -r -- "fkill: failed to send SIG${signal_name} to $pid"
    fi
  done

  (( failed_count == 0 )) || return $kill_rc
}

# Quick HTTP header check
headers() {
  emulate -L zsh

  case ${1:-} in
    -h|--help)
      print 'Usage: headers <url>'
      print 'Fetch response headers through redirects with bounded timeouts.'
      print 'Override ZSH_HTTP_CONNECT_TIMEOUT and ZSH_HTTP_MAX_TIME with positive seconds.'
      return 0
      ;;
  esac

  if (( $# != 1 )); then
    print -u2 -r -- 'Usage: headers <url>'
    return 1
  fi

  local -a timeout_args
  _zsh_http_timeout_args || return 1
  timeout_args=( "${reply[@]}" )
  command curl -sSIL "${timeout_args[@]}" -- "$1" || {
    local rc=$?
    print -u2 -r -- "headers: request failed (curl exit $rc)"
    return $rc
  }
}

# Show current laptop thermal/performance profile
fanprofile() {
  emulate -L zsh

  case ${1:-} in
    -h|--help)
      print 'Usage: fanprofile'
      print 'Show the current Linux platform or ASUS fan profile without changing it.'
      return 0
      ;;
  esac
  if (( $# > 0 )); then
    print -u2 -r -- 'Usage: fanprofile'
    return 1
  fi

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
        print -u2 -r -- "Unknown ASUS fan profile value: $raw"
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
    print -u2 -r -- 'No supported laptop performance profile interface found'
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

# Show listening ports and owning processes
ports() {
  emulate -L zsh

  case ${1:-} in
    -h|--help)
      print 'Usage: ports'
      print 'Show listening TCP and UDP sockets with owning processes when permitted.'
      return 0
      ;;
  esac
  if (( $# > 0 )); then
    print -u2 -r -- 'Usage: ports'
    return 1
  fi

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

# Show the default forecast over HTTPS
weather() {
  emulate -L zsh

  case ${1:-} in
    -h|--help)
      print 'Usage: weather'
      print 'Fetch the default concise forecast from wttr.in with bounded timeouts.'
      print 'Override ZSH_HTTP_CONNECT_TIMEOUT and ZSH_HTTP_MAX_TIME with positive seconds.'
      return 0
      ;;
  esac
  if (( $# > 0 )); then
    print -u2 -r -- 'Usage: weather'
    return 1
  fi

  local -a timeout_args
  _zsh_http_timeout_args || return 1
  timeout_args=( "${reply[@]}" )
  command curl --http1.1 -fsSL "${timeout_args[@]}" -- https://wttr.in || {
    local rc=$?
    print -u2 -r -- "weather: request failed (curl exit $rc)"
    return $rc
  }
}

# Show public IP address over HTTPS
myip() {
  emulate -L zsh

  case ${1:-} in
    -h|--help)
      print 'Usage: myip'
      print 'Look up the public IP over HTTPS with bounded timeouts.'
      print 'Override ZSH_HTTP_CONNECT_TIMEOUT and ZSH_HTTP_MAX_TIME with positive seconds.'
      return 0
      ;;
  esac
  if (( $# > 0 )); then
    print -u2 -r -- 'Usage: myip'
    return 1
  fi

  local endpoint='https://ifconfig.me/ip'
  local ip
  local -a timeout_args
  _zsh_http_timeout_args || return 1
  timeout_args=( "${reply[@]}" )

  ip=$(command curl -fsSL "${timeout_args[@]}" -- "$endpoint") || {
    local rc=$?
    print -u2 -r -- "myip: request failed (curl exit $rc)"
    return $rc
  }
  if _ui_plain_mode; then
    print -r -- "$ip"
    return 0
  fi

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

# Print PATH entries with rich interactive output and plain pipe-friendly output
path() {
  emulate -L zsh

  case ${1:-} in
    -h|--help)
      print 'Usage: path'
      print 'List PATH entries while preserving empty components.'
      return 0
      ;;
  esac
  if (( $# > 0 )); then
    print -u2 -r -- 'Usage: path'
    return 1
  fi

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

_zdoctor_usage() {
  print 'Usage: zdoctor [--network] [--secrets]'
  print ''
  print 'Diagnose the shared Zsh setup without changing it:'
  print '  install location, module readability, completion readiness,'
  print '  required and optional tools, glyph configuration, and'
  print '  integration status (fzf, zoxide, cgm, npkg, global aliases).'
  print ''
  print 'Network endpoints and Secret Service are probed only with:'
  print '  --network   Check the myip and weather endpoints (curl, 8s timeout)'
  print '  --secrets   Check secret-tool without retrieving any value'
}

# On-demand setup and integration diagnosis. Reads local state only unless
# the explicit probe flags are given; never edits configuration.
zdoctor() {
  emulate -L zsh

  local arg repo_dir install_base module failures=0 warnings=0
  local fzf_version fzf_major fzf_minor fzf_patch current_user
  local -a modules missing_modules
  local -i check_network=0 check_secrets=0

  for arg in "$@"; do
    case $arg in
      --network) check_network=1 ;;
      --secrets) check_secrets=1 ;;
      -h|--help) _zdoctor_usage; return 0 ;;
      --) ;;
      -*)
        print -u2 -r -- "Unknown zdoctor option: $arg"
        _zdoctor_usage >&2
        return 1
        ;;
      *)
        print -u2 -r -- "Unknown zdoctor argument: $arg"
        _zdoctor_usage >&2
        return 1
        ;;
    esac
  done

  if ! _ui_plain_mode; then
    _ui_title_line 'Doctor' 'shared zsh config' accent '*' '*'
    _ui_section_break
  fi

  _zdoctor_report() {
    # Local reporting helper; removed before zdoctor returns.
    local level=$1 text=$2
    case $level in
      ok) print -r -- "ok: $text" ;;
      warn)
        print -r -- "warning: $text"
        (( warnings++ ))
        ;;
      fail)
        print -r -- "fail: $text"
        (( failures++ ))
        ;;
    esac
  }

  repo_dir=${_ZSH_FUNCTIONS_MODULE_DIR:-${HOME:-}/.config/zsh}
  install_base=${HOME:-}/.config/zsh
  if [[ ${repo_dir:A} == ${install_base:A} ]]; then
    _zdoctor_report ok "install location ($repo_dir)"
  else
    _zdoctor_report fail "install location ($repo_dir is not $install_base; move the clone or symlink it there)"
  fi

  modules=( 10-history 20-aliases 25-theme 30-zoxide 40-fzf 50-completion
    55-ui-helpers 60-functions 62-cgm 65-help 66-compdefs 70-globals 80-tips )
  missing_modules=()
  for module in "${modules[@]}"; do
    if [[ $module == 62-cgm ]] && ! command -v secret-tool >/dev/null 2>&1; then
      continue
    fi
    [[ -r $install_base/$module.zsh ]] || missing_modules+=("$module.zsh")
  done
  if (( ${#missing_modules[@]} == 0 )); then
    _zdoctor_report ok 'all expected modules are readable'
  else
    _zdoctor_report fail "unreadable modules (startup skips them): ${(j:, :)missing_modules}"
  fi

  if (( $+functions[compdef] )); then
    if (( ${+_comps[zhelp]} )); then
      _zdoctor_report ok 'completion is ready (compinit ran; custom completions registered)'
    else
      _zdoctor_report warn 'compinit ran but custom completions are not registered; restart the shell'
    fi
  else
    _zdoctor_report warn 'compinit has not run; add `autoload -Uz compinit && compinit -i` before sourcing init.zsh for Tab completion'
  fi

  for module in zsh git curl ss lsd zoxide; do
    if command -v $module >/dev/null 2>&1; then
      _zdoctor_report ok "required tool: $module"
    else
      _zdoctor_report fail "required tool missing: $module (see scripts/check-deps.sh for install hints)"
    fi
  done
  if command -v fzf >/dev/null 2>&1; then
    fzf_version=$(command fzf --version 2>/dev/null) || fzf_version=''
    fzf_version=${${fzf_version%% *}:-}
    if [[ $fzf_version == <->.<-> || $fzf_version == <->.<->.<-> ]]; then
      fzf_major=${fzf_version%%.*}
      fzf_minor=${${fzf_version#*.}%%.*}
      fzf_patch=0
      [[ $fzf_version == *.*.* ]] && fzf_patch=${fzf_version##*.}
      if (( fzf_major > 0 || fzf_minor > 68 || ( fzf_minor == 68 && fzf_patch >= 0 ) )); then
        _zdoctor_report ok "required tool: fzf $fzf_version (minimum 0.68.0)"
      else
        _zdoctor_report fail "fzf $fzf_version is older than the 0.68.0 minimum"
      fi
    else
      _zdoctor_report fail 'fzf version is unparseable (minimum 0.68.0)'
    fi
  else
    _zdoctor_report fail 'required tool missing: fzf (minimum 0.68.0)'
  fi

  for module in bat tree jq secret-tool nix; do
    if command -v $module >/dev/null 2>&1; then
      _zdoctor_report ok "optional tool: $module"
    else
      _zdoctor_report warn "optional tool missing: $module (only its workflows stay unavailable)"
    fi
  done
  if command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1; then
    _zdoctor_report ok 'optional tool: fd/fdfind'
  else
    _zdoctor_report warn 'optional tool missing: fd/fdfind (ff falls back to find)'
  fi

  if (( $+functions[_zsh_theme_resolve_glyph_tier] )); then
    if _zsh_theme_resolve_glyph_tier "${ZSH_UI_GLYPHS:-auto}"; then
      _zdoctor_report ok "glyphs resolve to $REPLY (ZSH_UI_GLYPHS=${ZSH_UI_GLYPHS:-auto}${NO_NERD_FONT:+, NO_NERD_FONT is set})"
    else
      _zdoctor_report fail "ZSH_UI_GLYPHS=${ZSH_UI_GLYPHS:-auto} is invalid (use auto, nerd, unicode, or ascii)"
    fi
  else
    _zdoctor_report warn 'glyph resolver is not loaded yet; run `ztheme list` to load it'
  fi

  _zdoctor_report ok "fzf integration state: ${_FZF_STATE:-unchecked} (found: ${_FZF_FOUND:-not checked})"
  if command -v zoxide >/dev/null 2>&1; then
    if (( $+functions[zi] )); then
      _zdoctor_report ok 'zoxide integration is ready'
    else
      _zdoctor_report warn 'zoxide is installed but zi is unavailable; restart the shell'
    fi
  else
    _zdoctor_report warn 'zoxide is not installed; z and zi stay unavailable'
  fi
  if (( $+functions[cgm] )); then
    _zdoctor_report ok 'cgm is defined (secret-tool was present at startup)'
  elif command -v secret-tool >/dev/null 2>&1; then
    _zdoctor_report warn 'secret-tool is installed but cgm is undefined; restart the shell'
  else
    _zdoctor_report warn 'cgm is unavailable (secret-tool is not installed)'
  fi
  if (( $+functions[npkg] )); then
    _zdoctor_report ok 'npkg is defined'
  elif command -v nix >/dev/null 2>&1; then
    _zdoctor_report warn 'nix is installed but npkg is undefined; restart the shell'
  else
    _zdoctor_report warn 'npkg is unavailable (nix is not installed)'
  fi
  if (( ${+galiases[G]} )); then
    _zdoctor_report ok 'global aliases are enabled (ZSH_GLOBAL_ALIASES=1)'
  else
    _zdoctor_report warn "global aliases are disabled; export ZSH_GLOBAL_ALIASES=1 before startup to enable them"
  fi

  if (( check_network )); then
    if command -v curl >/dev/null 2>&1; then
      if command curl -fsS --max-time 8 -o /dev/null https://ifconfig.me/ip 2>/dev/null; then
        _zdoctor_report ok 'myip endpoint is reachable (https://ifconfig.me/ip)'
      else
        _zdoctor_report fail 'myip endpoint is unreachable (https://ifconfig.me/ip)'
      fi
      if command curl -fsS --max-time 8 -o /dev/null 'https://wttr.in/?format=3' 2>/dev/null; then
        _zdoctor_report ok 'weather endpoint is reachable (https://wttr.in/)'
      else
        _zdoctor_report fail 'weather endpoint is unreachable (https://wttr.in/)'
      fi
    else
      _zdoctor_report fail 'curl is missing so network endpoints cannot be checked'
    fi
  else
    print -r -- 'note: network endpoints not probed (pass --network to check myip and weather)'
  fi

  if (( check_secrets )); then
    if command -v secret-tool >/dev/null 2>&1; then
      _zdoctor_report ok 'secret-tool is installed; zdoctor never retrieves credential values'
    else
      _zdoctor_report fail 'secret-tool is not installed'
    fi
  else
    print -r -- 'note: Secret Service not contacted (pass --secrets to check secret-tool)'
  fi

  if (( failures > 0 )); then
    print -r -- "zdoctor: $failures failure(s), $warnings warning(s)"
    unfunction _zdoctor_report
    return 1
  fi
  print -r -- "zdoctor: healthy ($warnings warning(s))"
  unfunction _zdoctor_report
  return 0
}
