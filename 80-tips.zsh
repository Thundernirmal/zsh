# Fixed lazy loader for hook-free, on-demand tips in lib/tips-catalogue.zsh.
# Extraction preserves native input-link handling.
# Extraction reminders require an existing, nonempty destination directory.
# Reminders cover native file semantics and search errors, package selection,
# cancellation, configured Paru scope, metadata freshness, and cleanup previews.
# Credential reminders use ordinary scalar variables for exact-value exports.
# Theme reminders distinguish inspecting a palette from applying it.
# Finder reminders include restarting after a blocked integration is repaired.
# Navigation reminders include startup diagnostics after cache settings change.
# Cleanup reminders require checking the summary for failed phases.
# npm inventory reminders cover stable formatting and visible diagnostics.
# Package queries may use the network and write caches without changing packages.

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
