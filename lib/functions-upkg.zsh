# Trusted lazy upkg implementations; loaded by functions-catalogue.zsh.

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

source "$_ZSH_FUNCTIONS_MODULE_DIR/lib/upkg-registry.zsh"

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

    if (( ${_ZSH_UPKG_MANAGERS[(Ie)$item]} )); then
      parsed+=("$item")
    else
      print -u2 -- "Unsupported manager id: $item"
      return 1
    fi
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
          _upkg_usage >&2
          return 1
        fi
        only_raw=$1
        ;;
      --only=*)
        only_raw=${1#--only=}
        if [ -z "$only_raw" ]; then
          print -u2 -- 'Missing value for --only'
          _upkg_usage >&2
          return 1
        fi
        ;;
      --skip)
        shift
        if (( $# == 0 )); then
          print -u2 -- 'Missing value for --skip'
          _upkg_usage >&2
          return 1
        fi
        skip_raw=$1
        ;;
      --skip=*)
        skip_raw=${1#--skip=}
        if [ -z "$skip_raw" ]; then
          print -u2 -- 'Missing value for --skip'
          _upkg_usage >&2
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
        _upkg_usage >&2
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
            _upkg_usage >&2
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
          _upkg_usage >&2
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
      _upkg_usage >&2
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

  run_order=( "${_UPKG_SELECTED_MANAGERS[@]}" )

  for manager in "${run_order[@]}"; do
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

