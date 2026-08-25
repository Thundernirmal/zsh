# Lazy registration for searchable help.

typeset -g _ZSH_HELP_MODULE_DIR=${${(%):-%N}:A:h}
typeset -gi _ZSH_HELP_CATALOGUE_LOADED=${_ZSH_HELP_CATALOGUE_LOADED:-0}

_zsh_help_load() {
  (( _ZSH_HELP_CATALOGUE_LOADED )) && return 0
  [[ -r $_ZSH_HELP_MODULE_DIR/lib/help-catalogue.zsh ]] || return 1
  source "$_ZSH_HELP_MODULE_DIR/lib/help-catalogue.zsh" || return 1
  typeset -gi _ZSH_HELP_CATALOGUE_LOADED=1
}

if (( ! _ZSH_HELP_CATALOGUE_LOADED )); then
  zhelp() {
    _zsh_help_load || {
      print -u2 -r -- 'zhelp: failed to load the trusted help catalogue'
      return 1
    }
    zhelp "$@"
  }
fi
