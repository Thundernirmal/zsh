# Shared zoxide integration.
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi