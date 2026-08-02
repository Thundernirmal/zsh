# Shared zoxide integration.
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"

  # zoxide owns the picker implementation; keep its generated function intact
  # while routing every interactive invocation through the shared fzf gate.
  if (( $+functions[__zoxide_zi] )); then
    functions[_zsh_zoxide_generated_zi]=${functions[__zoxide_zi]}
    __zoxide_zi() {
      if (( ! $+functions[_fzf_require_ready] )); then
        print -u2 -r -- 'zsh config: fzf 0.52.0 or newer is required (found: configuration guard unavailable). Upgrade fzf and restart the shell.'
        return 1
      fi
      _fzf_require_ready || return 1
      _zsh_zoxide_generated_zi "$@"
    }
  fi
fi
