# Shared zoxide integration.
if (( ! ${+_ZSH_ZOXIDE_FZF_OPTS_CAPTURED} )); then
  typeset -g _ZSH_ZOXIDE_INHERITED_FZF_OPTS=${_ZO_FZF_OPTS-}
  typeset -gi _ZSH_ZOXIDE_FZF_OPTS_CAPTURED=1
fi

_zsh_zoxide_refresh_fzf_opts() {
  emulate -L zsh

  local managed inherited=${_ZSH_ZOXIDE_INHERITED_FZF_OPTS:-}
  local -a args context_args

  (( $+functions[_zsh_theme_fzf_chrome_args] )) || return 0
  _zsh_theme_fzf_chrome_args || return 1
  args=( "${reply[@]:#--no-color}" --scheme=path --no-multi )
  _zsh_theme_fzf_context_args Directories 'Type to filter directories' 'Enter jump  Esc close'
  context_args=( "${reply[@]}" )
  args+=( "${context_args[@]}" )
  _zsh_theme_join_shell_args "${args[@]}"
  managed=$REPLY

  typeset -gx _ZO_FZF_OPTS=$managed
  [[ -n $inherited ]] && _ZO_FZF_OPTS+=" $inherited"
  [[ -n ${NO_COLOR:-} ]] && _ZO_FZF_OPTS+=' --no-color'
}

_zsh_zoxide_refresh_fzf_opts

if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"

  # zoxide owns the picker implementation; keep its generated function intact
  # while routing every interactive invocation through the shared fzf gate.
  if (( $+functions[__zoxide_zi] )); then
    functions[_zsh_zoxide_generated_zi]=${functions[__zoxide_zi]}
    __zoxide_zi() {
      if (( ! $+functions[_fzf_require_ready] )); then
        print -u2 -r -- 'zsh config: fzf 0.68.0 or newer is required (found: configuration guard unavailable). Upgrade fzf and restart the shell.'
        return 1
      fi
      _fzf_require_ready || return 1
      _zsh_zoxide_generated_zi "$@"
    }
  fi
fi
