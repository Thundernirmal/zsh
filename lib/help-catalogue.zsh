# Lazily loaded command palette and live availability checks.
source "${${(%):-%N}:A:h}/command-registry.zsh"

_zsh_help_entry_exists() {
  emulate -L zsh

  local id=$1

  case ${_ZSH_HELP_KIND[$id]-} in
    function)
      [[ -n ${functions[$id]-} ]]
      ;;
    alias)
      [[ -n ${aliases[$id]-} || -n ${galiases[$id]-} ]]
      ;;
    action)
      [[ -n ${functions[${_ZSH_HELP_EXAMPLE[$id]%% *}]-} ]]
      ;;
    *)
      return 1
      ;;
  esac
}

_zsh_help_fzf_is_ready_cached() {
  (( $+functions[_fzf_is_ready_cached] )) || return 1
  _fzf_is_ready_cached
}

_zsh_help_is_available() {
  emulate -L zsh

  local id=$1

  _zsh_help_entry_exists "$id" || return 1

  case ${_ZSH_HELP_CHECK[$id]-none} in
    none)
      return 0
      ;;
    zoxide)
      command -v zoxide >/dev/null 2>&1
      ;;
    zoxide-fzf)
      command -v zoxide >/dev/null 2>&1 && _zsh_help_fzf_is_ready_cached
      ;;
    peek)
      command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1 || command -v sed >/dev/null 2>&1
      ;;
    disk)
      command -v find >/dev/null 2>&1 && command -v du >/dev/null 2>&1
      ;;
    file-search)
      command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1 || command -v find >/dev/null 2>&1
      ;;
    text-search)
      command -v rg >/dev/null 2>&1 || command -v grep >/dev/null 2>&1
      ;;
    git)
      command -v git >/dev/null 2>&1
      ;;
    git-fzf)
      command -v git >/dev/null 2>&1 && _zsh_help_fzf_is_ready_cached
      ;;
    curl)
      command -v curl >/dev/null 2>&1
      ;;
    process-fzf)
      command -v ps >/dev/null 2>&1 && _zsh_help_fzf_is_ready_cached
      ;;
    fan-profile)
      [[ -r /sys/firmware/acpi/platform_profile || -r /sys/devices/platform/asus-nb-wmi/fan_boost_mode ]]
      ;;
    ss)
      command -v ss >/dev/null 2>&1
      ;;
    secret-health)
      command -v secret-tool >/dev/null 2>&1 && command -v gdbus >/dev/null 2>&1
      ;;
    secret-tool)
      command -v secret-tool >/dev/null 2>&1
      ;;
    package-manager)
      command -v paru >/dev/null 2>&1 ||
        command -v pacman >/dev/null 2>&1 ||
        command -v apt >/dev/null 2>&1 ||
        command -v dnf >/dev/null 2>&1 ||
        command -v brew >/dev/null 2>&1 ||
        command -v flatpak >/dev/null 2>&1 ||
        { command -v nix >/dev/null 2>&1 && [[ -n ${functions[npkg]-} ]]; } ||
        command -v npm >/dev/null 2>&1
      ;;
    nix)
      command -v nix >/dev/null 2>&1
      ;;
    grep|less|wc|head|tail)
      command -v "${_ZSH_HELP_CHECK[$id]}" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

# Why a command is unavailable, as REPLY. Global aliases are opt-in, so their
# reason is the setting rather than the (unrelated) tool they pipe into.
_zsh_help_unavailable_reason() {
  emulate -L zsh

  local id=$1

  if [[ ${_ZSH_HELP_KIND[$id]-} == alias && ${_ZSH_HELP_USAGE[$id]-} == '<command> '* ]] &&
    ! _zsh_help_entry_exists "$id"; then
    REPLY='opt-in; export ZSH_GLOBAL_ALIASES=1 before startup'
  else
    REPLY="needs ${_ZSH_HELP_DEPS[$id]}"
  fi
}

_zsh_help_availability_label() {
  emulate -L zsh

  local id=$1

  if _zsh_help_is_available "$id"; then
    if [[ ${_ZSH_HELP_DEPS[$id]} == none ]]; then
      REPLY=available
    else
      REPLY="available (uses ${_ZSH_HELP_DEPS[$id]})"
    fi
  else
    _zsh_help_unavailable_reason "$id"
    REPLY="unavailable ($REPLY)"
  fi
}

# True when $2 occurs in $1 at the start of a word: at the beginning of the text
# or right after a character that is not a letter or digit. Both are lower-case.
_zsh_help_word_start_match() {
  [[ $1 == "$2"* || $1 == *[^[:alnum:]]"$2"* ]]
}

# A query matches anywhere inside a command name, but only at the start of a
# word in the category, summary, and usage text (never the example), so "port"
# finds ports but not "supported" or "export". Results are ranked: exact name,
# name prefix, name substring, then the rest in registry order.
_zsh_help_matches() {
  emulate -L zsh

  local query=${1-}
  local include_all=${2:-0}
  local id lid needle=${(L)query}
  local -a exact prefix inname other
  typeset -ga reply
  reply=()

  for id in "${_ZSH_HELP_ORDER[@]}"; do
    (( include_all )) || _zsh_help_is_available "$id" || continue

    if [[ -z $needle ]]; then
      other+=("$id")
      continue
    fi

    lid=${(L)id}
    if [[ $lid == "$needle" ]]; then
      exact+=("$id")
    elif [[ $lid == "$needle"* ]]; then
      prefix+=("$id")
    elif [[ $lid == *"$needle"* ]]; then
      inname+=("$id")
    elif _zsh_help_word_start_match "${(L)_ZSH_HELP_CATEGORY[$id]}" "$needle" ||
      _zsh_help_word_start_match "${(L)_ZSH_HELP_SUMMARY[$id]}" "$needle" ||
      _zsh_help_word_start_match "${(L)_ZSH_HELP_USAGE[$id]}" "$needle"; then
      other+=("$id")
    fi
  done

  reply=( "${exact[@]}" "${prefix[@]}" "${inname[@]}" "${other[@]}" )
}

_zsh_help_render_detail() {
  emulate -L zsh

  local id=$1

  _zsh_help_availability_label "$id"
  print -r -- "$id: ${_ZSH_HELP_SUMMARY[$id]}"
  print -r -- "Usage:   ${_ZSH_HELP_USAGE[$id]}"
  print -r -- "Example: ${_ZSH_HELP_EXAMPLE[$id]}"
  print -r -- "Status:  $REPLY"
}

_zsh_help_render_list() {
  emulate -L zsh

  local id summary

  printf '%-14s %-12s %s\n' 'Command' 'Category' 'Description'
  printf '%-14s %-12s %s\n' '-------' '--------' '-----------'
  for id in "$@"; do
    summary=${_ZSH_HELP_SUMMARY[$id]}
    if ! _zsh_help_is_available "$id"; then
      _zsh_help_unavailable_reason "$id"
      summary+=" [$REPLY]"
    fi
    printf '%-14s %-12s %s\n' "$id" "${_ZSH_HELP_CATEGORY[$id]}" "$summary"
  done
}

_zsh_help_can_palette() {
  emulate -L zsh

  [[ -t 0 && -t 1 ]] || return 1
  [[ -n ${TERM:-} && ${TERM} != dumb ]] || return 1
  (( $+functions[_fzf_is_ready] )) || return 1
  _fzf_is_ready
}

_zsh_help_palette() {
  emulate -L zsh

  local query=${1-}
  local include_all=${2:-0}
  local id selection example
  local -a ids rows fzf_args context_args preview_args

  if (( ! $+functions[_fzf_require_ready] )); then
    print -u2 -r -- 'zsh config: fzf 0.68.0 or newer is required (found: configuration guard unavailable). Upgrade fzf and restart the shell.'
    return 1
  fi
  _fzf_require_ready || return 1

  # Seed the picker's query but keep the whole eligible catalogue browsable:
  # clearing the query must broaden results instead of trapping the user in
  # the CLI-filtered subset. Plain-text search stays deterministically filtered.
  _zsh_help_matches "" "$include_all"
  ids=( "${reply[@]}" )
  (( ${#ids[@]} > 0 )) || return 1

  for id in "${ids[@]}"; do
    _zsh_help_availability_label "$id"
    rows+=("${id}"$'\t'"${_ZSH_HELP_CATEGORY[$id]}"$'\t'"${_ZSH_HELP_SUMMARY[$id]}"$'\t'"${_ZSH_HELP_USAGE[$id]}"$'\t'"${_ZSH_HELP_EXAMPLE[$id]}"$'\t'"$REPLY")
  done

  _fzf_picker_context_args Commands 'Type to filter commands' 'Enter edit example  Ctrl-P preview  Ctrl-/ wrap  Esc close'
  context_args=( "${reply[@]}" )
  _fzf_picker_preview_args Usage
  preview_args=( "${reply[@]}" )
  fzf_args=(
    "${context_args[@]}"
    "${preview_args[@]}"
    --delimiter=$'\t'
    --with-nth=1,2,3
    --nth=1,2,3,4
    --accept-nth=5
    --freeze-left=1
    --wrap=word
    --preview='printf "Usage:   %s\nExample: %s\nStatus:  %s\n" {4} {5} {6}'
  )
  [[ -n $query ]] && fzf_args+=(--query="$query")

  selection=$(print -l -- "${rows[@]}" | command fzf "${fzf_args[@]}") || return 0
  [[ -n $selection ]] || return 0

  example=$selection
  [[ -n $example ]] || return 0

  print -rz -- "$example"
}

# Up to five suggestions: names within a small edit distance of the query,
# then names sharing its first two letters.
_zsh_help_close_matches() {
  emulate -L zsh

  local query=${(L)1}
  local include_all=${2:-0}
  local prefix id
  local -a pool
  typeset -ga reply
  reply=()

  [[ -n $query ]] || return 0

  for id in "${_ZSH_HELP_ORDER[@]}"; do
    (( include_all )) || _zsh_help_is_available "$id" || continue
    pool+=("$id")
  done

  _ui_close_matches "$query" "${pool[@]}"

  prefix=${query[1,2]}
  for id in "${pool[@]}"; do
    (( ${#reply[@]} >= 5 )) && break
    [[ ${(L)id} == "$prefix"* ]] || continue
    (( ${reply[(Ie)$id]} )) && continue
    reply+=("$id")
  done
  (( ${#reply[@]} > 5 )) && reply[6,-1]=()
}

_zsh_help_usage() {
  print 'Usage: zhelp [options] [query]'
  print ''
  print 'Options:'
  print '  --all       Include unavailable commands'
  print '  --plain     Force plain-text output'
  print '  -h, --help  Show help'
}

zhelp() {
  emulate -L zsh

  local include_all=0 force_plain=0 query=''
  local -a query_parts matches close
  local -i hidden_count=0

  while (( $# > 0 )); do
    case $1 in
      --all)
        include_all=1
        ;;
      --plain)
        force_plain=1
        ;;
      -h|--help)
        _zsh_help_usage
        return 0
        ;;
      --)
        shift
        query_parts+=("$@")
        break
        ;;
      -)
        # The alias for cd -, which completion offers as a command name.
        query_parts+=("$1")
        ;;
      -*)
        _ui_usage_error zhelp 'zhelp [--all] [--plain] [query]' "unknown option: $1" "$1" --all --plain --help
        return 1
        ;;
      *)
        query_parts+=("$1")
        ;;
    esac
    shift
  done

  query="${(j: :)query_parts}"

  if [[ -n $query && -n ${_ZSH_HELP_CATEGORY[$query]-} ]]; then
    if (( ! include_all )) && ! _zsh_help_is_available "$query"; then
      _zsh_help_unavailable_reason "$query"
      print -u2 -- "zhelp: command is unavailable: $query ($REPLY)"
      print -u2 -- "Run 'zhelp --all $query' to view its help."
      return 1
    fi
    _zsh_help_render_detail "$query"
    return 0
  fi

  _zsh_help_matches "$query" "$include_all"
  matches=( "${reply[@]}" )
  if (( ${#matches[@]} == 0 )); then
    if (( ! include_all )); then
      _zsh_help_matches "$query" 1
      if (( ${#reply[@]} > 0 )); then
        print -u2 -- "zhelp: no available commands matched: $query"
        print -u2 -- "${#reply[@]} unavailable command(s) match: ${(j:, :)${(@)reply[1,5]}}"
        print -u2 -- "Run 'zhelp --all $query' to view requirements."
        return 1
      fi
    fi
    print -u2 -- "zhelp: no commands matched: $query"
    _zsh_help_close_matches "$query" "$include_all"
    close=( "${reply[@]}" )
    (( ${#close[@]} > 0 )) && print -u2 -- "Close matches: ${(j:, :)close}"
    return 1
  fi

  if (( ! force_plain )) && _zsh_help_can_palette; then
    _zsh_help_palette "$query" "$include_all"
    return $?
  fi

  _zsh_help_render_list "${matches[@]}"
  if (( ! include_all )); then
    _zsh_help_matches "$query" 1
    hidden_count=$(( ${#reply[@]} - ${#matches[@]} ))
    if (( hidden_count > 0 )); then
      print -r -- "$hidden_count unavailable command(s) hidden; run 'zhelp --all${query:+ $query}' to view requirements."
    fi
  fi
}
