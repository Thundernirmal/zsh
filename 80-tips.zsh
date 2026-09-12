# Fixed lazy loader for hook-free, on-demand tips. Command help, glyph previews,
# and credential-status reminders stay in lib/tips-catalogue.zsh. Destructive
# file commands keep native semantics across domain loading. Package-search
# reminders apply on first use, including the independently loaded Nix backend.
# The zdoctor reminder covers checking navigation after shell startup changes.

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
