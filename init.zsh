# Shared, git-friendly Zsh configuration.

# Zsh options that complement OMZ without clashing.
setopt AUTO_PUSHD           # Push directories onto stack
setopt PUSHD_IGNORE_DUPS    # No duplicate entries in directory stack
setopt PUSHD_SILENT         # Don't print directory stack after pushd/popd
setopt EXTENDED_GLOB        # Powerful glob patterns (e.g. **/*, ^pattern)
setopt GLOB_DOTS            # Include dotfiles in globs
setopt NUMERIC_GLOB_SORT    # Sort numbers numerically in globs
unsetopt CORRECT            # Disable spell-correction prompts, even if enabled earlier
setopt NO_BEEP              # No beeping
setopt INTERACTIVE_COMMENTS # Allow # comments in interactive shell

zsh_config_dir=${${(%):-%x}:A:h}

for zsh_config_file in \
  "$zsh_config_dir/10-history.zsh" \
  "$zsh_config_dir/20-aliases.zsh" \
  "$zsh_config_dir/30-zoxide.zsh" \
  "$zsh_config_dir/40-fzf.zsh" \
  "$zsh_config_dir/50-completion.zsh" \
  "$zsh_config_dir/55-ui-helpers.zsh" \
  "$zsh_config_dir/60-functions.zsh" \
  "$zsh_config_dir/70-globals.zsh" \
  "$zsh_config_dir/80-tips.zsh"; do
  if [ -r "$zsh_config_file" ]; then
    source "$zsh_config_file"
  fi
done

unset zsh_config_file zsh_config_dir
