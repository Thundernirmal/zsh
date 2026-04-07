# Shared fzf settings and bindings.
export FZF_DEFAULT_OPTS='--height=45% --layout=reverse --border=rounded --inline-info --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc --color=marker:#f5a97f,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 --color=selected-bg:#45475a --color=border:#585b70,label:#cdd6f4,query:#a6e3a1'

export FZF_CTRL_T_OPTS="--preview 'if [[ -d {} ]]; then if command -v lsd >/dev/null 2>&1; then lsd --tree --depth=2 --color=always --group-dirs=first {}; elif command -v tree >/dev/null 2>&1; then tree -L 2 -a -C {}; else command ls -la {}; fi; elif command -v bat >/dev/null 2>&1; then bat --style=numbers --color=always --line-range=:200 {}; else sed -n \"1,200p\" {}; fi' --preview-window=right,60%,border-left,wrap"
export FZF_ALT_C_OPTS='--height=50% --preview-window=hidden'

# Fuzzy history search with preview
export FZF_CTRL_R_OPTS="
  --preview 'echo {}' --preview-window down:3:hidden:wrap
  --bind '?:toggle-preview'
  --color header:italic
  --header 'Press CTRL-Y to copy command into clipboard'"

if command -v fzf >/dev/null 2>&1 && [[ -o interactive ]] && [[ -z "$ZSH_EXECUTION_STRING" ]]; then
  eval "$(fzf --zsh)"
fi
