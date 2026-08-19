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
