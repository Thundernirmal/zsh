# Fixed lazy loader for hook-free, on-demand tips in lib/tips-catalogue.zsh.
# Finder percentage requests, minimum-height limits, and preview boundaries follow GUIDE.md.
# Doctor reminders cover blocked integration failures and restarting after repair.
# The catalogue checks matching tool capabilities when it loads on first use.
# Package reminders follow the current workflows and ownership boundaries in GUIDE.md.

typeset -g _ZSH_TIPS_MODULE_DIR=${${(%):-%N}:A:h}
typeset -gi _ZSH_TIPS_CATALOGUE_LOADED=${_ZSH_TIPS_CATALOGUE_LOADED:-0}

_zsh_tips_load() {
  (( _ZSH_TIPS_CATALOGUE_LOADED )) && return 0
  [[ -r $_ZSH_TIPS_MODULE_DIR/lib/tips-catalogue.zsh ]] || return 1
  source "$_ZSH_TIPS_MODULE_DIR/lib/tips-catalogue.zsh" || return 1
  typeset -gi _ZSH_TIPS_CATALOGUE_LOADED=1
}

if (( ! _ZSH_TIPS_CATALOGUE_LOADED )); then
  tips() {
    _zsh_tips_load || {
      print -u2 -r -- 'tips: failed to load the trusted tips catalogue'
      return 1
    }
    tips "$@"
  }
fi

# Query ownership, deterministic process parsing, and discovery limits are documented in GUIDE.md.
