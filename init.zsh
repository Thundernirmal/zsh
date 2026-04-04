# Shared, git-friendly Zsh configuration.

# Zsh options that complement OMZ without clashing.
setopt AUTO_CD              # Type directory name to cd into it
setopt AUTO_PUSHD           # Push directories onto stack
setopt PUSHD_IGNORE_DUPS    # No duplicate entries in directory stack
setopt PUSHD_SILENT         # Don't print directory stack after pushd/popd
setopt EXTENDED_GLOB        # Powerful glob patterns (e.g. **/*, ^pattern)
setopt GLOB_DOTS            # Include dotfiles in globs
setopt NUMERIC_GLOB_SORT    # Sort numbers numerically in globs
setopt CORRECT              # Spell check commands before executing
setopt NO_BEEP              # No beeping
setopt INTERACTIVE_COMMENTS # Allow # comments in interactive shell

for zsh_config_file in \
  "$HOME/.config/zsh/10-history.zsh" \
  "$HOME/.config/zsh/20-aliases.zsh" \
  "$HOME/.config/zsh/30-zoxide.zsh" \
  "$HOME/.config/zsh/40-fzf.zsh" \
  "$HOME/.config/zsh/50-completion.zsh" \
  "$HOME/.config/zsh/60-functions.zsh" \
  "$HOME/.config/zsh/70-globals.zsh" \
  "$HOME/.config/zsh/80-tips.zsh"; do
  if [ -r "$zsh_config_file" ]; then
    source "$zsh_config_file"
  fi
done

unset zsh_config_file