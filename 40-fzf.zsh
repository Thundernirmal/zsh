# Shared fzf validation, settings, and bindings.
if (( ! ${+_FZF_MIN_VERSION} )); then
  typeset -gr _FZF_MIN_VERSION='0.52.0'
fi
typeset -gA _FZF_VERSION_STATE_BY_PATH
typeset -gA _FZF_VERSION_FOUND_BY_PATH
typeset -gA _FZF_INTEGRATION_STATE_BY_PATH
typeset -gA _FZF_INTEGRATION_REASON_BY_PATH
typeset -gA _FZF_CONFIGURED_BY_PATH
typeset -g _FZF_CHECKED_PATH=${_FZF_CHECKED_PATH:-}
typeset -g _FZF_STATE=${_FZF_STATE:-unchecked}
typeset -g _FZF_FOUND=${_FZF_FOUND:-not checked}
typeset -gi _FZF_STARTUP_DIAGNOSTIC_SHOWN=${_FZF_STARTUP_DIAGNOSTIC_SHOWN:-0}

_fzf_set_state() {
  typeset -g _FZF_CHECKED_PATH=$1
  typeset -g _FZF_STATE=$2
  typeset -g _FZF_FOUND=$3
}

_fzf_diagnostic() {
  print -u2 -r -- "zsh config: fzf ${_FZF_MIN_VERSION} or newer is required (found: ${_FZF_FOUND}). Upgrade fzf and restart the shell."
}

_fzf_startup_diagnostic() {
  (( _FZF_STARTUP_DIAGNOSTIC_SHOWN == 0 )) || return 0
  _FZF_STARTUP_DIAGNOSTIC_SHOWN=1
  _fzf_diagnostic
}

_fzf_export_config() {
  emulate -L zsh

  local fzf_path=${_FZF_CHECKED_PATH:-}
  [[ -n $fzf_path && $fzf_path != '<missing>' ]] || return 1
  [[ -z ${_FZF_CONFIGURED_BY_PATH[$fzf_path]-} ]] || return 0

  export FZF_DEFAULT_OPTS='--height=45% --layout=reverse --border=rounded --inline-info --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc --color=marker:#f5a97f,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 --color=selected-bg:#45475a --color=border:#585b70,label:#cdd6f4,query:#a6e3a1'

  export FZF_CTRL_T_OPTS="--preview 'if [[ -d {} ]]; then if command -v lsd >/dev/null 2>&1; then lsd --tree --depth=2 --color=always --group-dirs=first -- {}; elif command -v tree >/dev/null 2>&1; then tree -L 2 -a -C -- {}; else command ls -la -- {}; fi; elif command -v bat >/dev/null 2>&1; then bat --style=numbers --color=always --line-range=:200 -- {}; else sed -n \"1,200p\" -- {}; fi' --preview-window=right,60%,border-left,wrap"
  export FZF_ALT_C_OPTS='--height=50% --preview-window=hidden'

  # Fuzzy history search with preview.
  export FZF_CTRL_R_OPTS="
    --preview 'echo {}' --preview-window down:3:hidden:wrap
    --bind '?:toggle-preview'
    --color header:italic
    --header 'Press ? to toggle the command preview'"

  _FZF_CONFIGURED_BY_PATH[$fzf_path]=1
}

_fzf_validate() {
  emulate -L zsh

  local fzf_path version_output version_line version_token cached_state found patch_component
  local prerelease_pattern='^[0-9]+\.[0-9]+(\.[0-9]+)?-[A-Za-z0-9._-]+$'
  local -a components
  integer major minor patch

  fzf_path=$(command -v fzf 2>/dev/null) || {
    _fzf_set_state '<missing>' blocked missing
    return 1
  }
  [[ -n $fzf_path ]] || {
    _fzf_set_state '<missing>' blocked missing
    return 1
  }
  fzf_path=${fzf_path:A}

  if [[ ${_FZF_INTEGRATION_STATE_BY_PATH[$fzf_path]-} == blocked ]]; then
    _fzf_set_state "$fzf_path" blocked "${_FZF_INTEGRATION_REASON_BY_PATH[$fzf_path]}"
    return 1
  fi

  cached_state=${_FZF_VERSION_STATE_BY_PATH[$fzf_path]-}
  if [[ -n $cached_state ]]; then
    found=${_FZF_VERSION_FOUND_BY_PATH[$fzf_path]}
    if [[ $cached_state == ready ]]; then
      _fzf_set_state "$fzf_path" ready "$found"
      return 0
    fi
    _fzf_set_state "$fzf_path" blocked "$found"
    return 1
  fi

  version_output=$(command "$fzf_path" --version 2>/dev/null) || {
    _FZF_VERSION_STATE_BY_PATH[$fzf_path]=blocked
    _FZF_VERSION_FOUND_BY_PATH[$fzf_path]='version check failed'
    _fzf_set_state "$fzf_path" blocked 'version check failed'
    return 1
  }

  version_line=${version_output%%$'\n'*}
  version_token=${version_line%%[[:space:]]*}
  if [[ $version_token != <->.<-> && $version_token != <->.<->.<-> ]]; then
    if [[ $version_token =~ $prerelease_pattern ]]; then
      found=$version_token
    else
      found='unparseable version'
    fi
    _FZF_VERSION_STATE_BY_PATH[$fzf_path]=blocked
    _FZF_VERSION_FOUND_BY_PATH[$fzf_path]=$found
    _fzf_set_state "$fzf_path" blocked "$found"
    return 1
  fi

  components=( "${(@s:.:)version_token}" )
  patch_component=${components[3]:-0}
  if (( ${#components[1]} > 9 || ${#components[2]} > 9 || ${#patch_component} > 9 )); then
    _FZF_VERSION_STATE_BY_PATH[$fzf_path]=blocked
    _FZF_VERSION_FOUND_BY_PATH[$fzf_path]='unparseable version'
    _fzf_set_state "$fzf_path" blocked 'unparseable version'
    return 1
  fi
  major=$(( 10#${components[1]} ))
  minor=$(( 10#${components[2]} ))
  patch=$(( 10#${patch_component} ))

  if (( major == 0 && minor < 52 )); then
    _FZF_VERSION_STATE_BY_PATH[$fzf_path]=blocked
    _FZF_VERSION_FOUND_BY_PATH[$fzf_path]=$version_token
    _fzf_set_state "$fzf_path" blocked "$version_token"
    return 1
  fi

  _FZF_VERSION_STATE_BY_PATH[$fzf_path]=ready
  _FZF_VERSION_FOUND_BY_PATH[$fzf_path]=$version_token
  _fzf_set_state "$fzf_path" ready "$version_token"
}

_fzf_is_ready_cached() {
  emulate -L zsh

  local fzf_path
  fzf_path=$(command -v fzf 2>/dev/null) || return 1
  [[ -n $fzf_path ]] || return 1
  fzf_path=${fzf_path:A}
  [[ ${_FZF_VERSION_STATE_BY_PATH[$fzf_path]-} == ready ]] || return 1
  [[ ${_FZF_INTEGRATION_STATE_BY_PATH[$fzf_path]-} != blocked ]]
}

_fzf_is_ready() {
  _fzf_validate || return 1
  _fzf_export_config
}

_fzf_require_ready() {
  if _fzf_validate; then
    _fzf_export_config
    return $?
  fi

  _fzf_diagnostic
  return 1
}

_fzf_wrap_generated_entry_points() {
  if (( $+functions[fzf-file-widget] )); then
    functions[_fzf_generated_file_widget]=${functions[fzf-file-widget]}
    fzf-file-widget() {
      _fzf_require_ready || return 1
      _fzf_generated_file_widget "$@"
    }
  fi

  if (( $+functions[fzf-cd-widget] )); then
    functions[_fzf_generated_cd_widget]=${functions[fzf-cd-widget]}
    fzf-cd-widget() {
      _fzf_require_ready || return 1
      _fzf_generated_cd_widget "$@"
    }
  fi

  if (( $+functions[fzf-history-widget] )); then
    functions[_fzf_generated_history_widget]=${functions[fzf-history-widget]}
    fzf-history-widget() {
      _fzf_require_ready || return 1
      _fzf_generated_history_widget "$@"
    }
  fi

  if (( $+functions[__fzf_comprun] )); then
    functions[_fzf_generated_comprun]=${functions[__fzf_comprun]}
    __fzf_comprun() {
      _fzf_require_ready || return 1
      _fzf_generated_comprun "$@"
    }
  fi
}

_fzf_initialize_zsh() {
  emulate -L zsh
  setopt localtraps

  local fzf_path=${_FZF_CHECKED_PATH:-}
  local stdout_file stderr_file generated zsh_path reason
  integer rc

  [[ -n $fzf_path && $fzf_path != '<missing>' ]] || return 1
  if [[ ${_FZF_INTEGRATION_STATE_BY_PATH[$fzf_path]-} == ready ]]; then
    _fzf_export_config
    return 0
  fi

  stdout_file=$(command mktemp "${TMPDIR:-/tmp}/fzf-zsh.stdout.XXXXXX") || {
    _FZF_INTEGRATION_STATE_BY_PATH[$fzf_path]=blocked
    _FZF_INTEGRATION_REASON_BY_PATH[$fzf_path]='integration setup failed'
    _fzf_set_state "$fzf_path" blocked 'integration setup failed'
    return 1
  }
  stderr_file=$(command mktemp "${TMPDIR:-/tmp}/fzf-zsh.stderr.XXXXXX") || {
    command rm -f -- "$stdout_file"
    _FZF_INTEGRATION_STATE_BY_PATH[$fzf_path]=blocked
    _FZF_INTEGRATION_REASON_BY_PATH[$fzf_path]='integration setup failed'
    _fzf_set_state "$fzf_path" blocked 'integration setup failed'
    return 1
  }
  trap 'command rm -f -- "$stdout_file" "$stderr_file"' EXIT INT TERM

  command "$fzf_path" --zsh >"$stdout_file" 2>"$stderr_file"
  rc=$?
  generated=$(<"$stdout_file")

  if (( rc != 0 )); then
    reason='integration generation failed'
  elif [[ -z ${generated//[[:space:]]/} ]]; then
    reason='empty integration output'
  else
    zsh_path=$(command -v zsh 2>/dev/null) || zsh_path=''
    if [[ -z $zsh_path ]] || ! command "$zsh_path" -fn "$stdout_file" >/dev/null 2>&1; then
      reason='invalid integration output'
    else
      reason=''
    fi
  fi

  if [[ -n $reason ]]; then
    command rm -f -- "$stdout_file" "$stderr_file"
    trap - EXIT INT TERM
    _FZF_INTEGRATION_STATE_BY_PATH[$fzf_path]=blocked
    _FZF_INTEGRATION_REASON_BY_PATH[$fzf_path]=$reason
    _fzf_set_state "$fzf_path" blocked "$reason"
    return 1
  fi

  command rm -f -- "$stdout_file" "$stderr_file"
  trap - EXIT INT TERM

  eval "$generated" || {
    _FZF_INTEGRATION_STATE_BY_PATH[$fzf_path]=blocked
    _FZF_INTEGRATION_REASON_BY_PATH[$fzf_path]='integration initialization failed'
    _fzf_set_state "$fzf_path" blocked 'integration initialization failed'
    return 1
  }

  _fzf_wrap_generated_entry_points
  _FZF_INTEGRATION_STATE_BY_PATH[$fzf_path]=ready
  _fzf_set_state "$fzf_path" ready "${_FZF_VERSION_FOUND_BY_PATH[$fzf_path]}"
  _fzf_export_config
}

# Startup uses the prehashed command table and performs external inspection only
# for a normal interactive prompt, never for non-interactive or `zsh -i -c` paths.
if [[ -o interactive ]] && [[ -z ${ZSH_EXECUTION_STRING:-} ]]; then
  if (( $+commands[fzf] )); then
    if _fzf_validate; then
      _fzf_initialize_zsh || _fzf_startup_diagnostic
    else
      _fzf_startup_diagnostic
    fi
  else
    _fzf_set_state '<missing>' blocked missing
    _fzf_startup_diagnostic
  fi
fi
