# Lazily loaded searchable help catalogue and command palette.
# Catalogue setup is data-only: availability checks and fzf run only when
# zhelp is invoked, never while this module is sourced.

typeset -ga _ZSH_HELP_ORDER
typeset -gA _ZSH_HELP_CATEGORY
typeset -gA _ZSH_HELP_SUMMARY
typeset -gA _ZSH_HELP_USAGE
typeset -gA _ZSH_HELP_EXAMPLE
typeset -gA _ZSH_HELP_DEPS
typeset -gA _ZSH_HELP_KIND
typeset -gA _ZSH_HELP_CHECK

_ZSH_HELP_ORDER=()
_ZSH_HELP_CATEGORY=()
_ZSH_HELP_SUMMARY=()
_ZSH_HELP_USAGE=()
_ZSH_HELP_EXAMPLE=()
_ZSH_HELP_DEPS=()
_ZSH_HELP_KIND=()
_ZSH_HELP_CHECK=()

_zsh_help_register() {
  emulate -L zsh

  local id=${1-}
  local category=${2-}
  local summary=${3-}
  local usage=${4-}
  local example=${5-}
  local dependencies=${6-}
  local kind=${7-}
  local check=${8-}
  local value

  [[ -n $id && -n $category && -n $summary && -n $usage && -n $example ]] || return 1
  [[ $kind == function || $kind == alias ]] || return 1
  [[ -z ${_ZSH_HELP_CATEGORY[$id]-} ]] || return 1

  for value in "$id" "$category" "$summary" "$usage" "$example" "$dependencies"; do
    [[ $value != *$'\t'* && $value != *$'\n'* && $value != *$'\r'* ]] || return 1
  done

  _ZSH_HELP_ORDER+=("$id")
  _ZSH_HELP_CATEGORY[$id]=$category
  _ZSH_HELP_SUMMARY[$id]=$summary
  _ZSH_HELP_USAGE[$id]=$usage
  _ZSH_HELP_EXAMPLE[$id]=$example
  _ZSH_HELP_DEPS[$id]=${dependencies:-none}
  _ZSH_HELP_KIND[$id]=$kind
  _ZSH_HELP_CHECK[$id]=$check
}

# Navigation
_zsh_help_register '..' Navigation 'Move up one directory' '..' '..' none alias none
_zsh_help_register '...' Navigation 'Move up two directories' '...' '...' none alias none
_zsh_help_register '....' Navigation 'Move up three directories' '....' '....' none alias none
_zsh_help_register '-' Navigation 'Return to the previous directory' '-' '-' none alias none
_zsh_help_register z Navigation 'Jump with zoxide' 'z <query>' 'z projects' zoxide function zoxide
_zsh_help_register zi Navigation 'Pick a zoxide directory' 'zi [query]' 'zi projects' 'zoxide and fzf 0.68.0+' function zoxide-fzf
_zsh_help_register mkcd Navigation 'Create a directory and enter it' 'mkcd <directory>' 'mkcd new-project' none function none
_zsh_help_register croot Navigation 'Enter the Git repository root' 'croot' 'croot' git function git

# Files and search
_zsh_help_register ls Files 'List directory contents' 'ls [path]' 'ls' 'lsd or GNU ls' alias none
_zsh_help_register ll Files 'List all entries with details' 'll [path]' 'll' 'lsd or GNU ls' alias none
_zsh_help_register la Files 'List entries including hidden files' 'la [path]' 'la' 'lsd or GNU ls' alias none
_zsh_help_register lt Files 'Show a three-level directory tree' 'lt [path]' 'lt' 'lsd or tree' alias none
_zsh_help_register mkdir Files 'Create directories, including missing parents' 'mkdir <directory> ...' 'mkdir new-project/src' mkdir alias none
_zsh_help_register cp Files 'Copy verbosely; confirm overwrites' 'cp <source> <destination>' 'cp config.example config.local' cp alias none
_zsh_help_register mv Files 'Move verbosely; confirm overwrites' 'mv <source> <destination>' 'mv old-name new-name' mv alias none
_zsh_help_register rm Files 'Remove verbosely; confirm each path' 'rm <path> ...' 'rm unwanted-file' rm alias none
_zsh_help_register cat Files 'Print files with bat highlighting' 'cat <file>' 'cat README.md' bat alias none
_zsh_help_register extract Files 'Unpack a supported archive' 'extract <archive>' 'extract archive.tar.gz' 'tar; format-specific unpackers when needed' function none
_zsh_help_register peek Files 'Preview a file with bat or cat' 'peek <file>' 'peek README.md' 'bat or cat' function peek
_zsh_help_register dusage Files 'Rank immediate entries by disk usage' 'dusage [path] [count]' 'dusage . 10' 'GNU du and find' function disk
_zsh_help_register bigfiles Files 'Rank files recursively by size' 'bigfiles [path] [count]' 'bigfiles . 10' 'GNU find and du' function disk
_zsh_help_register grep Search 'Search text with automatic colour' 'grep <pattern> [file ...]' 'grep TODO README.md' 'grep with --color=auto support' alias none
_zsh_help_register diff Files 'Compare files with automatic colour' 'diff <file-a> <file-b>' 'diff before.txt after.txt' 'diff with --color=auto support' alias none
_zsh_help_register ff Search 'Find files by name' 'ff <pattern> [path]' 'ff config .' 'fd, fdfind, or find' function file-search
_zsh_help_register ft Search 'Search file contents' 'ft <pattern> [path]' 'ft TODO .' 'rg or grep' function text-search

# Git
_zsh_help_register glog Git 'Graph the latest 20 commits' 'glog' 'glog' git alias git
_zsh_help_register gpr Git 'Pull with rebase' 'gpr' 'gpr' git alias git
_zsh_help_register gun Git 'Undo the latest commit; keep changes staged' 'gun' 'gun' git alias git
_zsh_help_register gitcount Git 'Count non-merge commits by contributor' 'gitcount' 'gitcount' git function git
_zsh_help_register gcount Git 'Alias for gitcount' 'gcount' 'gcount' git alias git
_zsh_help_register fbr Git 'Pick a branch; enter its worktree or check it out' 'fbr' 'fbr' 'git and fzf 0.68.0+' function git-fzf

# System
_zsh_help_register weather System 'Show the default HTTPS forecast' 'weather' 'weather' curl alias curl
_zsh_help_register fkill System 'Pick processes and send a signal' 'fkill [signal]' 'fkill 15' 'ps and fzf 0.68.0+' function process-fzf
_zsh_help_register headers System 'Print response headers after redirects' 'headers <url>' 'headers https://example.com' curl function curl
_zsh_help_register fanprofile System 'Show the laptop performance profile' 'fanprofile' 'fanprofile' 'Linux ACPI or ASUS WMI profile interface' function fan-profile
_zsh_help_register ports System 'Show listening sockets and processes' 'ports' 'ports' ss function ss
_zsh_help_register myip System 'Show the public IP address' 'myip' 'myip' curl function curl
_zsh_help_register path System 'List PATH entries' 'path' 'path' none function none

# Credentials
_zsh_help_register cgm Security 'Store and load shell credentials securely' 'cgm <command> [credential ...]' 'cgm env OPENAI_KEY' 'secret-tool and a Secret Service provider' function secret-tool

# Packages and meta helpers
_zsh_help_register upkg Packages 'Check, search, upgrade, and clean detected managers' 'upkg [command] [args] [flags]' 'upkg search ripgrep --only=apt,nix' 'a supported package manager' function package-manager
_zsh_help_register npkg Packages 'Manage the current Nix profile' 'npkg <command> [args]' 'npkg search ripgrep' 'nix; jq and fzf 0.68.0+ for optional workflows' function nix
_zsh_help_register G Meta 'Pipe command output to grep' '<command> G <pattern>' 'git log --oneline G fix' grep alias grep
_zsh_help_register L Meta 'Pipe command output to less' '<command> L' 'git diff L' less alias less
_zsh_help_register W Meta 'Pipe command output to a line count' '<command> W' 'git log --oneline W' wc alias wc
_zsh_help_register H Meta 'Pipe command output to head' '<command> H' 'git log --oneline H' head alias head
_zsh_help_register T Meta 'Pipe command output to tail' '<command> T' 'git log --oneline T' tail alias tail
_zsh_help_register NE Meta 'Suppress stderr for one command' '<command> NE' 'optional-command NE' none alias none
_zsh_help_register NUL Meta 'Suppress stdout and stderr for one command' '<command> NUL' 'noisy-command NUL' none alias none
_zsh_help_register tips Meta 'Print one short usage tip' 'tips' 'tips' none function none
_zsh_help_register ztheme Meta 'Inspect or switch shared terminal themes' 'ztheme <list|current|show|use|reset|export> [theme]' 'ztheme use nord' none function none
_zsh_help_register zhelp Meta 'Find commands and queue an example' 'zhelp [--all] [--plain] [query]' 'zhelp package' 'fzf 0.68.0+ for the optional interactive palette' function none

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
      command -v bat >/dev/null 2>&1 || command -v cat >/dev/null 2>&1
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
    REPLY="unavailable (needs ${_ZSH_HELP_DEPS[$id]})"
  fi
}

_zsh_help_matches() {
  emulate -L zsh

  local query=${1-}
  local include_all=${2:-0}
  local id haystack pattern needle=${(L)query}
  typeset -ga reply
  reply=()

  for id in "${_ZSH_HELP_ORDER[@]}"; do
    (( include_all )) || _zsh_help_is_available "$id" || continue

    if [[ -n $needle ]]; then
      haystack="${id} ${_ZSH_HELP_CATEGORY[$id]} ${_ZSH_HELP_SUMMARY[$id]} ${_ZSH_HELP_USAGE[$id]} ${_ZSH_HELP_EXAMPLE[$id]}"
      pattern="*${(b)needle}*"
      [[ ${(L)haystack} == ${~pattern} ]] || continue
    fi

    reply+=("$id")
  done
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
      summary+=" [needs ${_ZSH_HELP_DEPS[$id]}]"
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

  _zsh_help_matches "$query" "$include_all"
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
    --nth=1,2,3,4,5
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

  print -z -- "$example"
}

_zsh_help_close_matches() {
  emulate -L zsh

  local query=${(L)1}
  local include_all=${2:-0}
  local prefix id
  typeset -ga reply
  reply=()

  prefix=${query[1,2]}
  [[ -n $prefix ]] || return 0

  for id in "${_ZSH_HELP_ORDER[@]}"; do
    (( include_all )) || _zsh_help_is_available "$id" || continue
    [[ ${(L)id} == ${(b)prefix}* ]] || continue
    reply+=("$id")
    (( ${#reply[@]} >= 5 )) && break
  done
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
      -*)
        print -u2 -- "Unknown zhelp option: $1"
        _zsh_help_usage >&2
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
      print -u2 -- "Command is unavailable: $query (needs ${_ZSH_HELP_DEPS[$query]})"
      print -u2 -- "Run 'zhelp --all $query' to view its help."
      return 1
    fi
    _zsh_help_render_detail "$query"
    return 0
  fi

  _zsh_help_matches "$query" "$include_all"
  matches=( "${reply[@]}" )
  if (( ${#matches[@]} == 0 )); then
    print -u2 -- "No commands matched: $query"
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
}
