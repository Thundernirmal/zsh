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
  [[ -n ${NO_COLOR:-} ]] && _ZO_FZF_OPTS+=' --no-color'
  typeset -g _ZSH_ZOXIDE_FZF_CONFIG_SIGNATURE=$signature
}

if (( $+commands[zoxide] )); then
  if [[ -o interactive ]] && [[ -z ${ZSH_EXECUTION_STRING:-} ]]; then
    _zsh_zoxide_refresh_fzf_opts
  fi

  typeset _zsh_zoxide_init_output
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
  typeset -a _zsh_zoxide_saved_precmd_functions=( "${precmd_functions[@]}" )
  typeset -a _zsh_zoxide_saved_chpwd_functions=( "${chpwd_functions[@]}" )
  integer _zsh_zoxide_had_precmd_functions=${+precmd_functions}
  integer _zsh_zoxide_had_chpwd_functions=${+chpwd_functions}
  integer _zsh_zoxide_init_status
  _zsh_zoxide_init_output=$(zoxide init zsh 2>/dev/null)
  _zsh_zoxide_init_status=$?

  if (( _zsh_zoxide_init_status == 0 )) && [[ -n $_zsh_zoxide_init_output ]]; then
    if [[ -o interactive ]] && [[ -z ${ZSH_EXECUTION_STRING:-} ]]; then
      eval "$_zsh_zoxide_init_output"
    else
      eval "$_zsh_zoxide_init_output" 2>/dev/null
    fi
    _zsh_zoxide_init_status=$?
  else
    (( _zsh_zoxide_init_status == 0 )) && _zsh_zoxide_init_status=1
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

  unset _zsh_zoxide_init_output _zsh_zoxide_init_status \
    _zsh_zoxide_function_name _zsh_zoxide_function_names \
    _zsh_zoxide_saved_functions _zsh_zoxide_had_functions \
    _zsh_zoxide_saved_precmd_functions _zsh_zoxide_saved_chpwd_functions \
    _zsh_zoxide_had_precmd_functions _zsh_zoxide_had_chpwd_functions
fi
