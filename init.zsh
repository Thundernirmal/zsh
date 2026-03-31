# Shared, git-friendly Zsh configuration.

for zsh_config_file in \
  "$HOME/.config/zsh/10-history.zsh" \
  "$HOME/.config/zsh/20-aliases.zsh" \
  "$HOME/.config/zsh/30-zoxide.zsh" \
  "$HOME/.config/zsh/40-fzf.zsh"; do
  if [ -r "$zsh_config_file" ]; then
    source "$zsh_config_file"
  fi
done

unset zsh_config_file