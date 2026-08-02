# Shared fzf validation, settings, and bindings.
if (( ! ${+_FZF_MIN_VERSION} )); then
  typeset -gr _FZF_MIN_VERSION='0.52.0'
fi
if (( ! ${+_FZF_CACHE_SCHEMA} )); then
  typeset -gr _FZF_CACHE_SCHEMA='1'
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

_fzf_check_version_token() {
  emulate -L zsh

  local version_token=$1 patch_component
  local prerelease_pattern='^[0-9]+\.[0-9]+(\.[0-9]+)?-[A-Za-z0-9._-]+$'
  local -a components
  integer major minor

  if [[ $version_token != <->.<-> && $version_token != <->.<->.<-> ]]; then
    if [[ $version_token =~ $prerelease_pattern ]]; then
      REPLY=$version_token
    else
      REPLY='unparseable version'
    fi
    return 1
  fi

  components=( "${(@s:.:)version_token}" )
  patch_component=${components[3]:-0}
  if (( ${#components[1]} > 9 || ${#components[2]} > 9 || ${#patch_component} > 9 )); then
    REPLY='unparseable version'
    return 1
  fi

  major=$(( 10#${components[1]} ))
  minor=$(( 10#${components[2]} ))
  if (( major == 0 && minor < 52 )); then
    REPLY=$version_token
    return 1
  fi

  REPLY=$version_token
}

_fzf_validate() {
  emulate -L zsh

  local requested_path=${1:-}
  local fzf_path version_output version_line version_token cached_state found

  if [[ -n $requested_path ]]; then
    fzf_path=$requested_path
  else
    fzf_path=$(command -v fzf 2>/dev/null) || {
      _fzf_set_state '<missing>' blocked missing
      return 1
    }
  fi
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
  if ! _fzf_check_version_token "$version_token"; then
    found=$REPLY
    _FZF_VERSION_STATE_BY_PATH[$fzf_path]=blocked
    _FZF_VERSION_FOUND_BY_PATH[$fzf_path]=$found
    _fzf_set_state "$fzf_path" blocked "$found"
    return 1
  fi
  version_token=$REPLY

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

_fzf_cache_file_for_path() {
  emulate -L zsh

  local fzf_path=$1 cache_home field
  local -A file_info

  zmodload -F zsh/stat b:zstat 2>/dev/null || return 1
  zstat -H file_info -- "$fzf_path" 2>/dev/null || return 1
  for field in device inode size mtime ctime; do
    [[ ${file_info[$field]-} == <-> ]] || return 1
  done

  if [[ -n ${XDG_CACHE_HOME:-} && ${XDG_CACHE_HOME} == /* ]]; then
    cache_home=$XDG_CACHE_HOME
  elif [[ -n ${HOME:-} ]]; then
    cache_home=$HOME/.cache
  else
    return 1
  fi

  REPLY="${cache_home}/zsh/fzf/integration-${_FZF_CACHE_SCHEMA}-${file_info[device]}-${file_info[inode]}-${file_info[size]}-${file_info[mtime]}-${file_info[ctime]}-zsh-${ZSH_VERSION}.zsh"
}

_fzf_cache_file_is_safe() {
  emulate -L zsh

  local cache_file=$1 cache_dir=${1:h}
  local -A file_info dir_info

  [[ -f $cache_file && -r $cache_file && -O $cache_file && ! -L $cache_file ]] || return 1
  [[ -d $cache_dir && -O $cache_dir && ! -L $cache_dir ]] || return 1
  zstat -H file_info -- "$cache_file" 2>/dev/null || return 1
  zstat -H dir_info -- "$cache_dir" 2>/dev/null || return 1
  (( (file_info[mode] & 0022) == 0 && (dir_info[mode] & 0022) == 0 ))
}

_fzf_cache_header_version() {
  emulate -L zsh

  local cache_file=$1 fzf_path=$2
  local schema_line path_line version_line version_token

  {
    IFS= read -r schema_line &&
      IFS= read -r path_line &&
      IFS= read -r version_line
  } < "$cache_file" || return 1

  [[ $schema_line == "# zsh-fzf-cache ${_FZF_CACHE_SCHEMA}" ]] || return 1
  [[ $path_line == "# path ${(q)fzf_path}" ]] || return 1
  [[ $version_line == '# version '* ]] || return 1
  version_token=${version_line#\# version }
  _fzf_check_version_token "$version_token" || return 1
}

_fzf_activate_integration_file() {
  emulate -L zsh

  local integration_file=$1 fzf_path=$2 expected_version=$3

  typeset -g _FZF_CACHE_LOADED_SCHEMA=''
  typeset -g _FZF_CACHE_LOADED_VERSION=''
  typeset -gi _FZF_CACHE_LOADED_STATUS=1
  source "$integration_file" 2>/dev/null || return 1
  (( _FZF_CACHE_LOADED_STATUS == 0 )) || return 1
  [[ $_FZF_CACHE_LOADED_SCHEMA == "$_FZF_CACHE_SCHEMA" ]] || return 1
  [[ $_FZF_CACHE_LOADED_VERSION == "$expected_version" ]] || return 1

  _FZF_VERSION_STATE_BY_PATH[$fzf_path]=ready
  _FZF_VERSION_FOUND_BY_PATH[$fzf_path]=$expected_version
  _FZF_INTEGRATION_STATE_BY_PATH[$fzf_path]=ready
  _fzf_set_state "$fzf_path" ready "$expected_version"
  _fzf_wrap_generated_entry_points
  _fzf_export_config
}

_fzf_load_cached_integration() {
  emulate -L zsh

  local fzf_path=$1 cache_file=$2 version_token

  _fzf_cache_file_is_safe "$cache_file" || return 1
  _fzf_cache_header_version "$cache_file" "$fzf_path" || return 1
  version_token=$REPLY
  _fzf_activate_integration_file "$cache_file" "$fzf_path" "$version_token"
}

_fzf_block_integration() {
  local fzf_path=$1 reason=$2

  _FZF_INTEGRATION_STATE_BY_PATH[$fzf_path]=blocked
  _FZF_INTEGRATION_REASON_BY_PATH[$fzf_path]=$reason
  _fzf_set_state "$fzf_path" blocked "$reason"
  return 1
}

_fzf_initialize_zsh() {
  emulate -L zsh
  setopt localtraps

  local fzf_path=${1:-${_FZF_CHECKED_PATH:-}}
  local cache_file='' cache_dir temp_file='' integration_file generated zsh_path reason
  integer rc persistent=0

  if [[ -z $fzf_path || $fzf_path == '<missing>' ]]; then
    fzf_path=$(command -v fzf 2>/dev/null) || {
      _fzf_set_state '<missing>' blocked missing
      return 1
    }
  fi
  fzf_path=${fzf_path:A}

  if [[ ${_FZF_INTEGRATION_STATE_BY_PATH[$fzf_path]-} == ready ]]; then
    _fzf_set_state "$fzf_path" ready "${_FZF_VERSION_FOUND_BY_PATH[$fzf_path]}"
    _fzf_export_config
    return 0
  fi
  if [[ ${_FZF_INTEGRATION_STATE_BY_PATH[$fzf_path]-} == blocked ]]; then
    _fzf_set_state "$fzf_path" blocked "${_FZF_INTEGRATION_REASON_BY_PATH[$fzf_path]}"
    return 1
  fi

  if _fzf_cache_file_for_path "$fzf_path"; then
    cache_file=$REPLY
    _fzf_load_cached_integration "$fzf_path" "$cache_file" && return 0
  fi

  _fzf_validate "$fzf_path" || return 1

  generated=$(command "$fzf_path" --zsh 2>/dev/null)
  rc=$?

  if (( rc != 0 )); then
    reason='integration generation failed'
  elif [[ -z ${generated//[[:space:]]/} ]]; then
    reason='empty integration output'
  else
    reason=''
  fi

  if [[ -n $reason ]]; then
    _fzf_block_integration "$fzf_path" "$reason"
    return $?
  fi

  if [[ -n $cache_file ]]; then
    cache_dir=${cache_file:h}
    if command mkdir -p -- "$cache_dir" 2>/dev/null &&
      [[ -d $cache_dir && -O $cache_dir && ! -L $cache_dir ]] &&
      command chmod 700 -- "$cache_dir" 2>/dev/null; then
      temp_file=$(command mktemp "$cache_dir/.integration.XXXXXX" 2>/dev/null) && persistent=1
    fi
  fi
  if [[ -z $temp_file ]]; then
    temp_file=$(command mktemp "${TMPDIR:-/tmp}/fzf-zsh.XXXXXX" 2>/dev/null) || {
      _fzf_block_integration "$fzf_path" 'integration setup failed'
      return $?
    }
  fi
  trap '[[ -n $temp_file ]] && command rm -f -- "$temp_file"' EXIT INT TERM

  {
    print -r -- "# zsh-fzf-cache ${_FZF_CACHE_SCHEMA}"
    print -r -- "# path ${(q)fzf_path}"
    print -r -- "# version ${_FZF_FOUND}"
    print -r -- "$generated"
    print -r -- 'typeset -gi _FZF_CACHE_LOADED_STATUS=$?'
    print -r -- "typeset -g _FZF_CACHE_LOADED_SCHEMA=${(q)_FZF_CACHE_SCHEMA}"
    print -r -- "typeset -g _FZF_CACHE_LOADED_VERSION=${(q)_FZF_FOUND}"
  } > "$temp_file" || reason='integration setup failed'

  if [[ -z $reason ]]; then
    zsh_path=$(command -v zsh 2>/dev/null) || zsh_path=''
    if [[ -z $zsh_path ]] || ! command "$zsh_path" -fn "$temp_file" >/dev/null 2>&1; then
      reason='invalid integration output'
    fi
  fi

  if [[ -n $reason ]]; then
    command rm -f -- "$temp_file"
    temp_file=''
    trap - EXIT INT TERM
    _fzf_block_integration "$fzf_path" "$reason"
    return $?
  fi

  integration_file=$temp_file
  if (( persistent )) && command mv -f -- "$temp_file" "$cache_file" 2>/dev/null; then
    integration_file=$cache_file
    temp_file=''
  fi

  if ! _fzf_activate_integration_file "$integration_file" "$fzf_path" "$_FZF_FOUND"; then
    [[ $integration_file == "$cache_file" ]] && command rm -f -- "$cache_file"
    [[ -n $temp_file ]] && command rm -f -- "$temp_file"
    temp_file=''
    trap - EXIT INT TERM
    _fzf_block_integration "$fzf_path" 'integration initialization failed'
    return $?
  fi

  [[ -n $temp_file ]] && command rm -f -- "$temp_file"
  temp_file=''
  trap - EXIT INT TERM
}

# Normal prompts load a private validated cache with builtins only. A missing or
# stale cache performs the external version, generation, and syntax checks once.
if [[ -o interactive ]] && [[ -z ${ZSH_EXECUTION_STRING:-} ]]; then
  if (( $+commands[fzf] )); then
    _fzf_initialize_zsh "$commands[fzf]" || _fzf_startup_diagnostic
  else
    _fzf_set_state '<missing>' blocked missing
    _fzf_startup_diagnostic
  fi
fi
