# Shared zoxide integration.
if (( ! ${+_ZSH_ZOXIDE_FZF_OPTS_CAPTURED} )); then
typeset -g _ZSH_ZOXIDE_INHERITED_FZF_OPTS=${_ZO_FZF_OPTS-}
  typeset -gi _ZSH_ZOXIDE_FZF_OPTS_CAPTURED=1
fi
typeset -g _ZSH_ZOXIDE_FZF_CONFIG_SIGNATURE=${_ZSH_ZOXIDE_FZF_CONFIG_SIGNATURE:-}

_zsh_zoxide_refresh_fzf_opts() {
  emulate -L zsh

  local managed context inherited=${_ZSH_ZOXIDE_INHERITED_FZF_OPTS:-} signature
  local -a context_args

  (( $+functions[_zsh_theme_fzf_chrome_opts] )) || return 0
  signature="${_ZSH_FZF_ACTIVE_THEME:-}:${_ZSH_UI_COLOR_DEPTH:-}:${_ZSH_UI_GLYPH_TIER:-}:${ZSH_FZF_LAYOUT:-}:${(j:,:)_ZSH_THEME_CUSTOM_COLORS}:${inherited}:${NO_COLOR:-}"
  [[ $_ZSH_ZOXIDE_FZF_CONFIG_SIGNATURE == "$signature" ]] && return 0

  _zsh_theme_fzf_chrome_opts || return 1
  managed=$REPLY
  _zsh_theme_fzf_context_args Directories 'Type to filter directories' 'Enter jump  Esc close'
  context_args=( "${reply[@]}" )
  _zsh_theme_join_shell_args --scheme=path --no-multi "${context_args[@]}"
  context=$REPLY

  typeset -gx _ZO_FZF_OPTS="$managed $context"
  [[ -n $inherited ]] && _ZO_FZF_OPTS+=" $inherited"
  [[ -n ${NO_COLOR:-} ]] && _ZO_FZF_OPTS+=" $_ZSH_FZF_NO_COLOR_OPTS"
  typeset -g _ZSH_ZOXIDE_FZF_CONFIG_SIGNATURE=$signature
}

typeset -gi _ZSH_ZOXIDE_CACHE_SCHEMA=2

_zsh_zoxide_cache_file_for_path() {
  emulate -L zsh

  local zoxide_path=$1 cache_home
  local -A file_info

  if [[ -n ${XDG_CACHE_HOME:-} && $XDG_CACHE_HOME == /* ]]; then
    cache_home=$XDG_CACHE_HOME
  elif [[ -n ${HOME:-} && $HOME == /* ]]; then
    cache_home=$HOME/.cache
  else
    return 1
  fi

  zmodload zsh/stat 2>/dev/null || return 1
  zstat -H file_info -- "$zoxide_path" 2>/dev/null || return 1
  REPLY="${cache_home}/zsh/zoxide/init-${_ZSH_ZOXIDE_CACHE_SCHEMA}-${file_info[device]}-${file_info[inode]}-${file_info[size]}-${file_info[mtime]}-${file_info[ctime]}-zsh-${ZSH_VERSION}.zsh"
}

_zsh_zoxide_cache_file_is_safe() {
  emulate -L zsh

  local cache_file=$1 cache_dir=${1:h}
  local -A file_info dir_info

  [[ -f $cache_file && -r $cache_file && -O $cache_file && ! -L $cache_file ]] || return 1
  [[ -d $cache_dir && -O $cache_dir && ! -L $cache_dir ]] || return 1
  zmodload zsh/stat 2>/dev/null || return 1
  zstat -H file_info -- "$cache_file" 2>/dev/null || return 1
  zstat -H dir_info -- "$cache_dir" 2>/dev/null || return 1
  (( (file_info[mode] & 0022) == 0 && (dir_info[mode] & 0022) == 0 ))
}

_zsh_zoxide_cache_header_matches() {
  emulate -L zsh

  local cache_file=$1 zoxide_path=$2 schema_line path_line
  {
    IFS= read -r schema_line && IFS= read -r path_line
  } < "$cache_file" || return 1

  [[ $schema_line == "# zsh-zoxide-cache ${_ZSH_ZOXIDE_CACHE_SCHEMA}" ]] || return 1
  [[ $path_line == "# path ${(q)zoxide_path}" ]]
}

_zsh_zoxide_activate_file() {
  emulate -L zsh

  local integration_file=$1 zoxide_path=$2
  typeset -gi _ZSH_ZOXIDE_CACHE_LOADED_STATUS=1
  typeset -g _ZSH_ZOXIDE_CACHE_LOADED_SCHEMA=''
  typeset -g _ZSH_ZOXIDE_CACHE_LOADED_PATH=''

  if [[ -o interactive ]] && [[ -z ${ZSH_EXECUTION_STRING:-} ]]; then
    source "$integration_file"
  else
    source "$integration_file" 2>/dev/null
  fi

  (( _ZSH_ZOXIDE_CACHE_LOADED_STATUS == 0 )) || return 1
  [[ $_ZSH_ZOXIDE_CACHE_LOADED_SCHEMA == $_ZSH_ZOXIDE_CACHE_SCHEMA ]] || return 1
  [[ $_ZSH_ZOXIDE_CACHE_LOADED_PATH == "$zoxide_path" ]] || return 1
  (( $+functions[z] && $+functions[zi] && $+functions[__zoxide_zi] ))
}

if (( $+commands[zoxide] )); then
  if [[ -o interactive ]] && [[ -z ${ZSH_EXECUTION_STRING:-} ]]; then
    _zsh_zoxide_refresh_fzf_opts
  fi

  typeset _zsh_zoxide_init_output _zsh_zoxide_path=${commands[zoxide]:A}
  typeset _zsh_zoxide_cache_file='' _zsh_zoxide_cache_dir=''
  typeset _zsh_zoxide_temp_file='' _zsh_zoxide_zsh_path=${commands[zsh]:-}
  typeset _zsh_zoxide_function_name
  typeset -a _zsh_zoxide_function_names=(
    z zi __zoxide_pwd __zoxide_cd __zoxide_hook __zoxide_doctor
    __zoxide_z __zoxide_zi __zoxide_z_complete __zoxide_z_complete_helper
  )
  typeset -A _zsh_zoxide_saved_functions _zsh_zoxide_had_functions
  for _zsh_zoxide_function_name in "${_zsh_zoxide_function_names[@]}"; do
    if (( $+functions[$_zsh_zoxide_function_name] )); then
      _zsh_zoxide_had_functions[$_zsh_zoxide_function_name]=1
      _zsh_zoxide_saved_functions[$_zsh_zoxide_function_name]=${functions[$_zsh_zoxide_function_name]}
    fi
  done
  integer _zsh_zoxide_had_precmd_functions=${+precmd_functions}
  integer _zsh_zoxide_had_chpwd_functions=${+chpwd_functions}
  typeset -a _zsh_zoxide_saved_precmd_functions=() _zsh_zoxide_saved_chpwd_functions=()
  # Hook arrays may not exist in a standalone shell with NO_UNSET enabled.
  # Preserve absence separately from an explicitly empty array for rollback.
  if (( _zsh_zoxide_had_precmd_functions )); then
    _zsh_zoxide_saved_precmd_functions=( "${precmd_functions[@]}" )
  fi
  if (( _zsh_zoxide_had_chpwd_functions )); then
    _zsh_zoxide_saved_chpwd_functions=( "${chpwd_functions[@]}" )
  fi
  integer _zsh_zoxide_init_status
  if _zsh_zoxide_cache_file_for_path "$_zsh_zoxide_path"; then
    _zsh_zoxide_cache_file=$REPLY
  fi

  if [[ -n $_zsh_zoxide_cache_file ]] &&
    _zsh_zoxide_cache_file_is_safe "$_zsh_zoxide_cache_file" &&
    _zsh_zoxide_cache_header_matches "$_zsh_zoxide_cache_file" "$_zsh_zoxide_path"; then
    _zsh_zoxide_activate_file "$_zsh_zoxide_cache_file" "$_zsh_zoxide_path"
    _zsh_zoxide_init_status=$?
  else
    _zsh_zoxide_init_output=$(command "$_zsh_zoxide_path" init zsh 2>/dev/null)
    _zsh_zoxide_init_status=$?

    if (( _zsh_zoxide_init_status == 0 )) && [[ -n ${_zsh_zoxide_init_output//[[:space:]]/} ]] && [[ -n $_zsh_zoxide_zsh_path ]]; then
      if [[ -n $_zsh_zoxide_cache_file ]]; then
        _zsh_zoxide_cache_dir=${_zsh_zoxide_cache_file:h}
        if command mkdir -p -- "$_zsh_zoxide_cache_dir" 2>/dev/null &&
          [[ -d $_zsh_zoxide_cache_dir && -O $_zsh_zoxide_cache_dir && ! -L $_zsh_zoxide_cache_dir ]] &&
          command chmod 700 -- "$_zsh_zoxide_cache_dir" 2>/dev/null; then
          _zsh_zoxide_temp_file=$(command mktemp "$_zsh_zoxide_cache_dir/.integration.XXXXXX" 2>/dev/null)
        fi
      fi
      if [[ -z $_zsh_zoxide_temp_file ]]; then
        _zsh_zoxide_temp_file=$(command mktemp "${TMPDIR:-/tmp}/zoxide-zsh.XXXXXX" 2>/dev/null)
      fi

      if [[ -n $_zsh_zoxide_temp_file ]]; then
        {
          print -r -- "# zsh-zoxide-cache ${_ZSH_ZOXIDE_CACHE_SCHEMA}"
          print -r -- "# path ${(q)_zsh_zoxide_path}"
          print -r -- "$_zsh_zoxide_init_output"
          # Reaching this marker and installing the public functions is the
          # runtime contract. zoxide's generated final conditional may return
          # 1 normally when compdef is unavailable.
          print -r -- 'typeset -gi _ZSH_ZOXIDE_CACHE_LOADED_STATUS=0'
          print -r -- "typeset -g _ZSH_ZOXIDE_CACHE_LOADED_SCHEMA=${(q)_ZSH_ZOXIDE_CACHE_SCHEMA}"
          print -r -- "typeset -g _ZSH_ZOXIDE_CACHE_LOADED_PATH=${(q)_zsh_zoxide_path}"
        } >| "$_zsh_zoxide_temp_file" || _zsh_zoxide_init_status=1

        if (( _zsh_zoxide_init_status == 0 )) &&
          ! command "$_zsh_zoxide_zsh_path" -fn "$_zsh_zoxide_temp_file" >/dev/null 2>&1; then
          _zsh_zoxide_init_status=1
        fi

        if (( _zsh_zoxide_init_status == 0 )); then
          if [[ -n $_zsh_zoxide_cache_file ]] &&
            command mv -f -- "$_zsh_zoxide_temp_file" "$_zsh_zoxide_cache_file" 2>/dev/null; then
            _zsh_zoxide_temp_file=''
            _zsh_zoxide_activate_file "$_zsh_zoxide_cache_file" "$_zsh_zoxide_path"
          else
            _zsh_zoxide_activate_file "$_zsh_zoxide_temp_file" "$_zsh_zoxide_path"
          fi
          _zsh_zoxide_init_status=$?
        fi
      else
        _zsh_zoxide_init_status=1
      fi
    else
      (( _zsh_zoxide_init_status == 0 )) && _zsh_zoxide_init_status=1
    fi
  fi

  [[ -n $_zsh_zoxide_temp_file ]] && command rm -f -- "$_zsh_zoxide_temp_file"
  if (( _zsh_zoxide_init_status != 0 )) && [[ -n $_zsh_zoxide_cache_file ]]; then
    command rm -f -- "$_zsh_zoxide_cache_file" 2>/dev/null
  fi

  if (( _zsh_zoxide_init_status != 0 )); then
    for _zsh_zoxide_function_name in "${_zsh_zoxide_function_names[@]}"; do
      if (( ${_zsh_zoxide_had_functions[$_zsh_zoxide_function_name]:-0} )); then
        functions[$_zsh_zoxide_function_name]=${_zsh_zoxide_saved_functions[$_zsh_zoxide_function_name]}
      else
        unfunction "$_zsh_zoxide_function_name" 2>/dev/null || true
      fi
    done
    if (( _zsh_zoxide_had_precmd_functions )); then
      precmd_functions=( "${_zsh_zoxide_saved_precmd_functions[@]}" )
    else
      unset precmd_functions
    fi
    if (( _zsh_zoxide_had_chpwd_functions )); then
      chpwd_functions=( "${_zsh_zoxide_saved_chpwd_functions[@]}" )
    else
      unset chpwd_functions
    fi
    if [[ -o interactive ]] && [[ -z ${ZSH_EXECUTION_STRING:-} ]]; then
      print -u2 -r -- 'zsh config: zoxide initialization failed; z and zi are unavailable.'
    fi
  fi

  # zoxide owns the picker implementation; keep its generated function intact
  # while routing every interactive invocation through the shared fzf gate.
  if (( _zsh_zoxide_init_status == 0 && $+functions[__zoxide_zi] )); then
    functions[_zsh_zoxide_generated_zi]=${functions[__zoxide_zi]}
    __zoxide_zi() {
      _zsh_zoxide_refresh_fzf_opts || return 1
      if (( ! $+functions[_fzf_require_ready] )); then
        print -u2 -r -- 'zsh config: fzf 0.68.0 or newer is required (found: configuration guard unavailable). Upgrade fzf and restart the shell.'
        return 1
      fi
      _fzf_require_ready || return 1
      _zsh_zoxide_generated_zi "$@"
    }
  fi

  unset _zsh_zoxide_init_output _zsh_zoxide_init_status _zsh_zoxide_path \
    _zsh_zoxide_cache_file _zsh_zoxide_cache_dir _zsh_zoxide_temp_file \
    _zsh_zoxide_zsh_path \
    _zsh_zoxide_function_name _zsh_zoxide_function_names \
    _zsh_zoxide_saved_functions _zsh_zoxide_had_functions \
    _zsh_zoxide_saved_precmd_functions _zsh_zoxide_saved_chpwd_functions \
    _zsh_zoxide_had_precmd_functions _zsh_zoxide_had_chpwd_functions
fi
