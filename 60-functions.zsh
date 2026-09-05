# Lazy registration for user-facing shell functions.

typeset -g _ZSH_FUNCTIONS_MODULE_DIR=${${(%):-%N}:A:h}
typeset -gi _ZSH_FUNCTIONS_CATALOGUE_LOADED=${_ZSH_FUNCTIONS_CATALOGUE_LOADED:-0}

typeset -g _ZSH_CONFIG_FUNCTIONS_DIR=$_ZSH_FUNCTIONS_MODULE_DIR/functions
if (( ! ${fpath[(Ie)$_ZSH_CONFIG_FUNCTIONS_DIR]} )); then
  fpath=( "$_ZSH_CONFIG_FUNCTIONS_DIR" "${fpath[@]}" )
fi
(( $+functions[ztheme] )) || autoload -Uz ztheme
(( $+functions[_fbr_format_entry] )) || autoload -Uz _fbr_format_entry

# Completion and availability checks share this small declarative registry.
source "$_ZSH_FUNCTIONS_MODULE_DIR/lib/upkg-registry.zsh"

_zsh_functions_load() {
  if (( ! _ZSH_FUNCTIONS_CATALOGUE_LOADED )); then
    [[ -r $_ZSH_FUNCTIONS_MODULE_DIR/lib/functions-catalogue.zsh ]] || return 1
    source "$_ZSH_FUNCTIONS_MODULE_DIR/lib/functions-catalogue.zsh" || return 1
    typeset -gi _ZSH_FUNCTIONS_CATALOGUE_LOADED=1
  fi
  _zsh_functions_load_domain "${1:-all}"
}

_zsh_functions_dispatch() {
  emulate -L zsh
  local command_name=$1
  shift

  local domain
  case $command_name in
    extract|mkcd|ff|ft|peek|dusage|bigfiles) domain=files ;;
    fkill|headers|fanprofile|ports|weather|myip|path|zdoctor) domain=system ;;
    croot|gitcount|fbr) domain=git ;;
    upkg) domain=upkg ;;
    npkg|_npkg_cache_dir) domain=nix ;;
    *) return 1 ;;
  esac
  _zsh_functions_load "$domain" || {
    print -u2 -r -- "$command_name: failed to load the trusted function catalogue"
    return 1
  }
  "$command_name" "$@"
}

if (( ! _ZSH_FUNCTIONS_CATALOGUE_LOADED )); then
  extract() { _zsh_functions_dispatch extract "$@"; }
  mkcd() { _zsh_functions_dispatch mkcd "$@"; }
  ff() { _zsh_functions_dispatch ff "$@"; }
  ft() { _zsh_functions_dispatch ft "$@"; }
  fkill() { _zsh_functions_dispatch fkill "$@"; }
  headers() { _zsh_functions_dispatch headers "$@"; }
  peek() { _zsh_functions_dispatch peek "$@"; }
  fanprofile() { _zsh_functions_dispatch fanprofile "$@"; }
  dusage() { _zsh_functions_dispatch dusage "$@"; }
  bigfiles() { _zsh_functions_dispatch bigfiles "$@"; }
  ports() { _zsh_functions_dispatch ports "$@"; }
  weather() { _zsh_functions_dispatch weather "$@"; }
  myip() { _zsh_functions_dispatch myip "$@"; }
  croot() { _zsh_functions_dispatch croot "$@"; }
  function gitcount() { _zsh_functions_dispatch gitcount "$@"; }
  path() { _zsh_functions_dispatch path "$@"; }
  fbr() { _zsh_functions_dispatch fbr "$@"; }
  zdoctor() { _zsh_functions_dispatch zdoctor "$@"; }
  upkg() { _zsh_functions_dispatch upkg "$@"; }

  if (( $+commands[nix] )); then
    npkg() { _zsh_functions_dispatch npkg "$@"; }
    _npkg_cache_dir() { _zsh_functions_dispatch _npkg_cache_dir "$@"; }
  fi
fi
