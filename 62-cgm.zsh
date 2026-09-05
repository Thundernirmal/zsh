# Credential Global Manager (cgm).
#
# This module is sourced only when secret-tool is present. Secret values stay
# in Linux Secret Service; the local catalogue contains names only so listing
# and completion never retrieve credentials.

_cgm_error() {
  print -u2 -r -- "cgm: $*"
}

_cgm_require_backend() {
  if command -v secret-tool >/dev/null 2>&1; then
    return 0
  fi

  _cgm_error 'secret-tool is unavailable; install libsecret-tools and restart the shell.'
  return 1
}

_cgm_backend_check() {
  emulate -L zsh

  local backend_status

  _cgm_require_backend || return 1

  if ! command -v gdbus >/dev/null 2>&1; then
    _cgm_error 'gdbus is unavailable; install glib2 and retry the backend check.'
    return 1
  fi

  # Peer.Ping checks that the Secret Service D-Bus name is reachable without
  # invoking any Secret Service item method.  In particular, it cannot unlock,
  # search, or retrieve a credential value.  Keep the probe bounded and hide
  # implementation-specific diagnostics from the status output.
  command gdbus call --session \
    --dest org.freedesktop.secrets \
    --object-path /org/freedesktop/secrets \
    --method org.freedesktop.DBus.Peer.Ping \
    --timeout 5 >/dev/null 2>&1
  backend_status=$?
  if (( backend_status != 0 )); then
    _cgm_error 'Secret Service backend check failed; no credential values were requested.'
    return "$backend_status"
  fi

  return 0
}

_cgm_input_is_terminal() {
  [[ -t 0 ]]
}

_cgm_require_terminal() {
  if _cgm_input_is_terminal; then
    return 0
  fi

  _cgm_error 'this command needs an interactive terminal.'
  return 1
}

_cgm_require_current_shell() {
  local invocation=${1:-cgm}

  if (( ${ZSH_SUBSHELL:-0} == 0 )); then
    return 0
  fi

  _cgm_error "run '$invocation' directly, not in a pipeline, command substitution, or subshell."
  return 1
}

_cgm_validate_name() {
  emulate -L zsh

  local candidate=${1-}

  [[ -n $candidate ]] || return 1
  [[ $candidate == [A-Z_]* ]] || return 1
  [[ $candidate != *[^A-Z0-9_]* ]]
}

_cgm_validate_export_name() {
  emulate -L zsh

  local candidate=${1-}
  local parameter_kind

  _cgm_validate_name "$candidate" || return 1
  parameter_kind=${parameters[$candidate]-}
  [[ $parameter_kind != *readonly* && $parameter_kind != *special* ]] || return 1
  [[ -z $parameter_kind || $parameter_kind == scalar* ]]
}

_cgm_require_name() {
  local candidate=${1-}

  if _cgm_validate_name "$candidate"; then
    return 0
  fi

  _cgm_error "invalid environment variable name: ${candidate:-<empty>}"
  _cgm_error 'names must match [A-Z_][A-Z0-9_]*.'
  return 1
}

_cgm_require_export_name() {
  local candidate=${1-}

  _cgm_require_name "$candidate" || return 1
  if _cgm_validate_export_name "$candidate"; then
    return 0
  fi

  _cgm_error "refusing to replace a non-scalar, special, or read-only Zsh parameter: $candidate"
  return 1
}

_cgm_current_shell_loaded() {
  emulate -L zsh

  local parameter_kind=${parameters[$1]-}

  # CGM exports scalar parameters.  Inspecting the parameter type and export
  # flag gives a names-only status without expanding or printing its value.
  [[ $parameter_kind == scalar-export* ]]
}

_cgm_catalog_root() {
  emulate -L zsh

  if [[ -n ${XDG_DATA_HOME:-} && $XDG_DATA_HOME == /* ]]; then
    print -r -- "$XDG_DATA_HOME/cgm"
    return 0
  fi

  if [[ -n ${HOME:-} && $HOME == /* ]]; then
    print -r -- "$HOME/.local/share/cgm"
    return 0
  fi

  _cgm_error 'HOME and XDG_DATA_HOME do not provide an absolute path; the credential catalogue has no safe location.'
  return 1
}

_cgm_catalog_dir() {
  local root

  root=$(_cgm_catalog_root) || return 1
  print -r -- "$root/entries"
}

_cgm_prepare_catalog() {
  emulate -L zsh

  local root entries

  root=$(_cgm_catalog_root) || return 1
  entries="$root/entries"

  if [[ -L $root || ( -e $root && ! -d $root ) ]]; then
    _cgm_error "credential catalogue root is not a private directory: $root"
    return 1
  fi
  if [[ -L $entries || ( -e $entries && ! -d $entries ) ]]; then
    _cgm_error "credential catalogue is not a private directory: $entries"
    return 1
  fi

  ( umask 077; command mkdir -p -- "$entries" ) || {
    _cgm_error "could not create the credential catalogue: $entries"
    return 1
  }
  command chmod 700 -- "$root" "$entries" || {
    _cgm_error "could not secure the credential catalogue: $entries"
    return 1
  }
}

_cgm_catalog_has() {
  emulate -L zsh

  local root entries marker

  root=$(_cgm_catalog_root) || return 1
  entries="$root/entries"
  [[ -d $root && ! -L $root && -d $entries && ! -L $entries ]] || return 1
  marker="$entries/$1"
  [[ -f $marker && ! -L $marker ]]
}

_cgm_catalog_add() {
  emulate -L zsh

  local entries marker

  _cgm_prepare_catalog || return 1
  entries=$(_cgm_catalog_dir) || return 1
  marker="$entries/$1"

  if [[ -L $marker || ( -e $marker && ! -f $marker ) ]]; then
    _cgm_error "credential catalogue entry is not a regular file: $marker"
    return 1
  fi

  if [[ ! -e $marker ]]; then
    ( umask 077; setopt noclobber; : > "$marker" ) 2>/dev/null || {
      if [[ ! -f $marker || -L $marker ]]; then
        _cgm_error "could not create the credential catalogue entry for $1."
        return 1
      fi
    }
  fi

  command chmod 600 -- "$marker" || {
    _cgm_error "could not secure the credential catalogue entry for $1."
    return 1
  }
}

_cgm_catalog_can_remove() {
  emulate -L zsh

  local root entries marker

  root=$(_cgm_catalog_root) || return 1
  entries="$root/entries"

  if [[ -L $root || ( -e $root && ! -d $root ) ]]; then
    _cgm_error "credential catalogue root is not a private directory: $root"
    return 1
  fi
  if [[ -L $entries || ( -e $entries && ! -d $entries ) ]]; then
    _cgm_error "credential catalogue is not a private directory: $entries"
    return 1
  fi
  [[ -d $entries ]] || return 0

  marker="$entries/$1"
  [[ -e $marker || -L $marker ]] || return 0

  if [[ -L $marker || ! -f $marker ]]; then
    _cgm_error "refusing to remove a non-regular credential catalogue entry: $marker"
    return 1
  fi

  return 0
}

_cgm_catalog_remove() {
  emulate -L zsh

  local entries marker

  _cgm_catalog_can_remove "$1" || return 1
  entries=$(_cgm_catalog_dir) || return 1
  [[ -d $entries ]] || return 0
  marker="$entries/$1"
  [[ -e $marker || -L $marker ]] || return 0

  command rm -- "$marker" || {
    _cgm_error "could not remove the credential catalogue entry for $1."
    return 1
  }
}

_cgm_catalog_names() {
  emulate -L zsh
  setopt localoptions nullglob

  local root entries marker candidate
  typeset -ga reply
  reply=()

  root=$(_cgm_catalog_root) || return 1
  entries="$root/entries"

  if [[ -L $root || ( -e $root && ! -d $root ) ]]; then
    _cgm_error "credential catalogue root is not a private directory: $root"
    return 1
  fi
  if [[ -L $entries || ( -e $entries && ! -d $entries ) ]]; then
    _cgm_error "credential catalogue is not a private directory: $entries"
    return 1
  fi
  [[ -d $entries ]] || return 0

  for marker in "$entries"/*(N); do
    [[ -f $marker && ! -L $marker ]] || continue
    candidate=${marker:t}
    _cgm_validate_name "$candidate" || continue
    reply+=("$candidate")
  done
}

_cgm_confirm() {
  emulate -L zsh

  local prompt=$1 answer

  _cgm_require_terminal || return 1
  print -n -u2 -r -- "$prompt [y/N] "
  IFS= read -r answer
  [[ ${(L)answer} == y || ${(L)answer} == yes ]]
}

_cgm_export_one() {
  typeset -gx -- "$1=$2"
}

_cgm_unset_one() {
  unset "$1"
}

_cgm_usage() {
  emulate -L zsh

  if ! _ui_plain_mode; then
    _ui_title_line 'Credential Global Manager' 'cgm help' accent '󰌆' '*'
    _ui_section_break
    _ui_panel_kv 'Usage' 'cgm <command> [credential ...]' muted text
    _ui_section_break
    _ui_panel_kv 'set <name>' 'Securely store or replace one credential' accent text
    _ui_panel_kv 'list' 'List saved names without retrieving values' accent text
    _ui_panel_kv 'status' 'Show saved names and current-shell loaded state' accent text
    _ui_panel_kv 'check' 'Check Secret Service availability without retrieving values' accent text
    _ui_panel_kv 'env <name ...>' 'Load selected credentials into this shell' accent text
    _ui_panel_kv 'env --all' 'Load every saved credential into this shell' accent text
    _ui_panel_kv 'unset <name ...>' 'Remove selected variables from this shell' accent text
    _ui_panel_kv 'delete <name ...>' 'Delete stored credentials and unset them here' accent text
    _ui_panel_kv 'help' 'Show this help text' accent text
    _ui_section_break
    _ui_panel_kv 'Storage' 'Linux Secret Service via secret-tool' muted text
    _ui_panel_kv 'Scope' 'The current shell and child processes started after loading' muted text
    _ui_panel_kv 'Values' 'Never shown by cgm list, help, or completion' muted text
    _ui_panel_kv 'Delete' 'Returns nonzero if a current-shell variable cannot be unset' muted text
    return 0
  fi

  print 'Usage: cgm <command> [credential ...]'
  print ''
  print 'Commands:'
  print '  set <name>          Securely store or replace one credential'
  print '  list                List saved names without retrieving values'
  print '  status              Show saved names and current-shell loaded state'
  print '  check               Check Secret Service availability without retrieving values'
  print '  env <name ...>      Load selected credentials into this shell'
  print '  env --all           Load every saved credential into this shell'
  print '  unset <name ...>    Remove selected variables from this shell'
  print '  delete <name ...>   Delete stored credentials and unset them here'
  print '  help                Show this help text'
  print ''
  print 'Notes:'
  print '  Secrets are stored by Linux Secret Service through secret-tool.'
  print '  cgm list and completion use credential names only; values stay hidden.'
  print '  cgm env changes this shell and child processes started afterward.'
  print '  Other open shells and already-running processes are not changed.'
  print '  cgm delete returns nonzero if a current-shell variable cannot be unset.'
}

_cgm_render_saved() {
  emulate -L zsh

  local name=$1

  if _ui_plain_mode; then
    print -r -- "Saved $name."
    print -r -- "Run 'cgm env $name' to load it into this shell."
    return 0
  fi

  _ui_title_line 'Credential Saved' 'Linux Secret Service' success '󰌆' '*'
  _ui_section_break
  _ui_panel_kv 'Name' "$name" accent text
  _ui_panel_kv 'Value' 'hidden' muted muted
  _ui_panel_kv 'Next' "cgm env $name" muted text
}

_cgm_render_list() {
  emulate -L zsh

  local name
  local -a names=( "$@" )

  if (( ${#names[@]} == 0 )); then
    if _ui_plain_mode; then
      print 'No credentials saved.'
    else
      _ui_title_line 'Credentials' '0 saved' muted '󰌆' '*'
      _ui_section_break
      _ui_panel_kv 'Status' 'No credentials saved' muted text
    fi
    return 0
  fi

  if _ui_plain_mode; then
    print -l -- "${names[@]}"
    return 0
  fi

  _ui_title_line 'Credentials' "${#names[@]} saved" accent '󰌆' '*'
  _ui_section_break
  for name in "${names[@]}"; do
    _ui_panel_kv "$name" 'saved' accent muted
  done
  _ui_section_break
  _ui_panel_kv 'Values' 'hidden' muted muted
}

_cgm_render_loaded() {
  emulate -L zsh

  local name
  local -a names=( "$@" )

  if _ui_plain_mode; then
    for name in "${names[@]}"; do
      print -r -- "Loaded $name into this shell."
    done
    return 0
  fi

  _ui_title_line 'Credentials Loaded' "${#names[@]} in current shell" success '󰌆' '*'
  _ui_section_break
  for name in "${names[@]}"; do
    _ui_panel_kv "$name" 'exported' accent success
  done
  _ui_section_break
  _ui_panel_kv 'Scope' 'Current shell and future child processes' muted text
}

_cgm_render_unset() {
  emulate -L zsh

  local name
  local -a names=( "$@" )

  if _ui_plain_mode; then
    for name in "${names[@]}"; do
      print -r -- "Unset $name from this shell."
    done
    return 0
  fi

  _ui_title_line 'Credentials Unset' "${#names[@]} from current shell" warning '󰌆' '*'
  _ui_section_break
  for name in "${names[@]}"; do
    _ui_panel_kv "$name" 'unset' accent warning
  done
  _ui_section_break
  _ui_panel_kv 'Storage' 'Saved values were not deleted' muted text
}

_cgm_render_deleted() {
  emulate -L zsh

  local name
  local -a names=( "$@" )

  if _ui_plain_mode; then
    for name in "${names[@]}"; do
      print -r -- "Deleted $name."
    done
    return 0
  fi

  _ui_title_line 'Credentials Deleted' "${#names[@]} removed" danger '󰌆' '*'
  _ui_section_break
  for name in "${names[@]}"; do
    _ui_panel_kv "$name" 'deleted' accent danger
  done
  _ui_section_break
  _ui_panel_kv 'Other processes' 'Already-running processes may retain earlier values' muted text
}

_cgm_set() {
  emulate -L zsh

  local name=${1-}
  local backend_status created_marker=0

  (( $# == 1 )) || {
    _cgm_error 'usage: cgm set <name>'
    return 1
  }
  _cgm_require_export_name "$name" || return 1
  _cgm_require_backend || return 1
  _cgm_require_terminal || return 1

  if _cgm_catalog_has "$name"; then
    if ! _cgm_confirm "Replace the saved credential $name?"; then
      _cgm_error 'cancelled.'
      return 1
    fi
  else
    created_marker=1
  fi
  _cgm_catalog_add "$name" || return 1

  if ! _ui_plain_mode; then
    _ui_title_line 'Store Credential' "$name" accent '󰌆' '*'
    _ui_section_break
    _ui_panel_kv 'Storage' 'Linux Secret Service' muted text
    _ui_panel_kv 'Input' 'Hidden while typing' muted text
    _ui_section_break
  else
    print -r -- "Store $name in Linux Secret Service."
  fi

  command secret-tool store --label="cgm: $name" application cgm variable "$name"
  backend_status=$?
  if (( backend_status != 0 )); then
    (( created_marker )) && _cgm_catalog_remove "$name" >/dev/null 2>&1
    if (( backend_status == 130 )); then
      _cgm_error 'cancelled.'
    else
      _cgm_error "could not save $name in Linux Secret Service."
    fi
    return "$backend_status"
  fi

  _cgm_render_saved "$name"
}

_cgm_list() {
  emulate -L zsh

  (( $# == 0 )) || {
    _cgm_error 'usage: cgm list'
    return 1
  }

  _cgm_catalog_names || return 1
  _cgm_render_list "${reply[@]}"
}

_cgm_render_status() {
  emulate -L zsh

  local name state
  local -a names=( "$@" )

  if (( ${#names[@]} == 0 )); then
    if _ui_plain_mode; then
      print 'No saved credential names.'
    else
      _ui_title_line 'Credential Status' '0 saved names' muted '󰌆' '*'
      _ui_section_break
      _ui_panel_kv 'Status' 'No saved credential names' muted text
    fi
    return 0
  fi

  if _ui_plain_mode; then
    for name in "${names[@]}"; do
      if _cgm_current_shell_loaded "$name"; then
        state='loaded in current shell'
      else
        state='saved, not loaded'
      fi
      print -r -- "$name: $state"
    done
    return 0
  fi

  _ui_title_line 'Credential Status' "${#names[@]} saved names" accent '󰌆' '*'
  _ui_section_break
  for name in "${names[@]}"; do
    if _cgm_current_shell_loaded "$name"; then
      _ui_panel_kv "$name" 'loaded in current shell' accent success
    else
      _ui_panel_kv "$name" 'saved, not loaded' accent muted
    fi
  done
  _ui_section_break
  _ui_panel_kv 'Values' 'hidden; status reads names and parameter metadata only' muted text
}

_cgm_status() {
  emulate -L zsh

  (( $# == 0 )) || {
    _cgm_error 'usage: cgm status'
    return 1
  }

  _cgm_catalog_names || return 1
  _cgm_render_status "${reply[@]}"
}

_cgm_check() {
  emulate -L zsh

  (( $# == 0 )) || {
    _cgm_error 'usage: cgm check'
    return 1
  }

  _cgm_backend_check || return $?
  if _ui_plain_mode; then
    print -r -- 'Secret Service backend is reachable; no credential values were retrieved.'
  else
    _ui_title_line 'Credential Backend' 'Secret Service' success '󰌆' '*'
    _ui_section_break
    _ui_panel_kv 'Status' 'Reachable' accent success
    _ui_panel_kv 'Values' 'Not retrieved' muted text
  fi
}

_cgm_env() {
  emulate -L zsh
  unsetopt xtrace

  local name value backend_status
  local load_all=0
  local -a names values
  local -A seen
  integer index

  (( $# > 0 )) || {
    _cgm_error 'usage: cgm env <name ...> | cgm env --all'
    return 1
  }
  _cgm_require_current_shell 'cgm env ...' || return 1
  _cgm_require_backend || return 1

  if [[ $1 == --all ]]; then
    (( $# == 1 )) || {
      _cgm_error 'do not combine --all with credential names.'
      return 1
    }
    load_all=1
    _cgm_catalog_names || return 1
    names=( "${reply[@]}" )
    if (( ${#names[@]} == 0 )); then
      _cgm_render_list
      return 0
    fi
    for name in "${names[@]}"; do
      _cgm_require_export_name "$name" || return 1
    done
  else
    for name in "$@"; do
      _cgm_require_export_name "$name" || return 1
      [[ -z ${seen[$name]-} ]] || continue
      seen[$name]=1
      names+=("$name")
    done
  fi

  for name in "${names[@]}"; do
    # Keep a sentinel after lookup output so command substitution cannot strip
    # trailing newlines from the stored value before validation.
    value=$(
      command secret-tool lookup application cgm variable "$name"
      backend_status=$?
      print -nr -- .
      exit "$backend_status"
    )
    backend_status=$?
    if (( backend_status != 0 )); then
      values=()
      value=''
      _cgm_error "could not load $name from Linux Secret Service."
      return "$backend_status"
    fi
    value=${value[1,-2]}
    if [[ -z $value ]]; then
      values=()
      _cgm_error "stored credential is empty: $name"
      return 1
    fi
    if [[ $value == *$'\n'* || $value == *$'\r'* ]]; then
      values=()
      value=''
      _cgm_error "stored credential is not a single-line value: $name"
      return 1
    fi
    values+=("$value")
    value=''
  done

  if (( ! load_all )); then
    for name in "${names[@]}"; do
      _cgm_catalog_add "$name" || {
        values=()
        return 1
      }
    done
  fi

  for (( index = 1; index <= ${#names[@]}; index++ )); do
    _cgm_export_one "${names[$index]}" "${values[$index]}" 2>/dev/null || {
      values=()
      _cgm_error "could not export ${names[$index]} into this shell."
      return 1
    }
  done
  values=()

  _cgm_render_loaded "${names[@]}"
}

_cgm_unset() {
  emulate -L zsh

  local name
  local -a names
  local -A seen

  (( $# > 0 )) || {
    _cgm_error 'usage: cgm unset <name ...>'
    return 1
  }
  _cgm_require_current_shell 'cgm unset ...' || return 1

  for name in "$@"; do
    _cgm_require_export_name "$name" || return 1
    [[ -z ${seen[$name]-} ]] || continue
    seen[$name]=1
    names+=("$name")
  done

  for name in "${names[@]}"; do
    _cgm_unset_one "$name" 2>/dev/null || {
      _cgm_error "could not unset $name from this shell."
      return 1
    }
  done

  _cgm_render_unset "${names[@]}"
}

_cgm_delete() {
  emulate -L zsh

  local name prompt
  local -a names deleted retained failed
  local -A seen

  (( $# > 0 )) || {
    _cgm_error 'usage: cgm delete <name ...>'
    return 1
  }
  _cgm_require_current_shell 'cgm delete ...' || return 1
  _cgm_require_backend || return 1

  for name in "$@"; do
    _cgm_require_name "$name" || return 1
    [[ -z ${seen[$name]-} ]] || continue
    seen[$name]=1
    names+=("$name")
  done

  for name in "${names[@]}"; do
    _cgm_catalog_can_remove "$name" || return 1
  done

  if (( ${#names[@]} == 1 )); then
    prompt="Delete the saved credential ${names[1]}?"
  else
    prompt="Delete ${#names[@]} saved credentials?"
  fi
  if ! _cgm_confirm "$prompt"; then
    _cgm_error 'cancelled.'
    return 1
  fi

  for name in "${names[@]}"; do
    if command secret-tool clear application cgm variable "$name"; then
      if _cgm_catalog_remove "$name"; then
        if _cgm_validate_export_name "$name" && _cgm_unset_one "$name" 2>/dev/null; then
          deleted+=("$name")
        else
          _cgm_error "deleted $name from Linux Secret Service, but could not unset it from this shell."
          retained+=("$name")
        fi
      else
        failed+=("$name")
      fi
    else
      _cgm_error "could not delete $name from Linux Secret Service."
      failed+=("$name")
    fi
  done

  (( ${#deleted[@]} > 0 )) && _cgm_render_deleted "${deleted[@]}"
  if (( ${#retained[@]} > 0 )); then
    _cgm_error "current-shell variables still set: ${(j:, :)retained}"
  fi
  if (( ${#failed[@]} > 0 )); then
    _cgm_error "delete incomplete; failed: ${(j:, :)failed}"
  fi
  (( ${#retained[@]} == 0 && ${#failed[@]} == 0 ))
}

cgm() {
  emulate -L zsh

  local command_name=${1:-help}

  (( $# > 0 )) && shift
  case $command_name in
    set)
      _cgm_set "$@"
      ;;
    list)
      _cgm_list "$@"
      ;;
    status)
      _cgm_status "$@"
      ;;
    check)
      _cgm_check "$@"
      ;;
    env)
      _cgm_env "$@"
      ;;
    unset)
      _cgm_unset "$@"
      ;;
    delete)
      _cgm_delete "$@"
      ;;
    help|-h|--help)
      (( $# == 0 )) || {
        _cgm_error 'usage: cgm help'
        return 1
      }
      _cgm_usage
      ;;
    *)
      _cgm_error "unknown command: $command_name"
      _cgm_usage >&2
      return 1
      ;;
  esac
}
