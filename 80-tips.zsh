# Manager-specific reminders require their own tools when the catalogue loads.
# Fixed lazy loader for hook-free, on-demand tips in lib/tips-catalogue.zsh.
# Extraction preserves native input-link handling.
# Extraction reminders require an existing, nonempty destination directory.
# Reminders cover native file semantics and search errors, package selection,
# cancellation summaries, private-session query cleanup, and completed search results, configured Paru scope, metadata freshness, and cleanup previews.
# Credential reminders distinguish exact-value scalar exports from scalar removal.
# Theme reminders distinguish inspecting a palette from applying it.
# Finder activation tolerates stale widget names while preserving bindings.
# Finder reminders include restarting after a blocked integration is repaired.
# Navigation reminders include startup diagnostics after cache settings change.
# Cleanup cancellation retains earlier phase counts and identifies the interrupted phase.
# Package inventory reminders cover visible diagnostics and hidden Flatpak refs.
# Git picker reminders keep display labels separate from validated canonical identities.
# Nix inventory reminders preserve visible evaluation diagnostics.
# Nix helper reminders cover help before work and literal picker queries.
# Nix search uses native quiet logging while retaining diagnostics.
# npm search reminders apply across native parseable column layouts.
# DNF search reminders cover native no-match classification.
# Fresh Arch inventory setup includes checkupdates and its fakeroot prerequisite.
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
