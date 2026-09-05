# Fixed domain loader. Runtime callers cannot provide a path or discover code.
typeset -gA _ZSH_FUNCTION_DOMAINS_LOADED

_zsh_functions_load_domain() {
  emulate -L zsh
  local domain=$1
  case $domain in
    all)
      _zsh_functions_load_domain files &&
        _zsh_functions_load_domain system &&
        _zsh_functions_load_domain git &&
        _zsh_functions_load_domain upkg &&
        _zsh_functions_load_domain nix
      return $?
      ;;
    common|files|system|git|upkg|nix) ;;
    *) return 1 ;;
  esac
  (( ${_ZSH_FUNCTION_DOMAINS_LOADED[$domain]:-0} )) && return 0
  if [[ $domain != common ]]; then
    _zsh_functions_load_domain common || return 1
  fi
  case $domain in
    common) source "$_ZSH_FUNCTIONS_MODULE_DIR/lib/functions-common.zsh" || return 1 ;;
    files) source "$_ZSH_FUNCTIONS_MODULE_DIR/lib/functions-files.zsh" || return 1 ;;
    system) source "$_ZSH_FUNCTIONS_MODULE_DIR/lib/functions-system.zsh" || return 1 ;;
    git) source "$_ZSH_FUNCTIONS_MODULE_DIR/lib/functions-git.zsh" || return 1 ;;
    upkg)
      source "$_ZSH_FUNCTIONS_MODULE_DIR/lib/functions-upkg.zsh" || return 1
      source "$_ZSH_FUNCTIONS_MODULE_DIR/lib/functions-upkg-backends.zsh" || return 1
      ;;
    nix) source "$_ZSH_FUNCTIONS_MODULE_DIR/lib/functions-nix.zsh" || return 1 ;;
  esac
  _ZSH_FUNCTION_DOMAINS_LOADED[$domain]=1
  return 0
}
