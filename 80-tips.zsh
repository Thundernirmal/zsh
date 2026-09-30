# Fixed lazy loader for hook-free, on-demand tips. Command help, glyph previews,
# and credential-status reminders stay in lib/tips-catalogue.zsh. Destructive
# file commands keep native semantics across domain loading. Package-search
# reminders apply on first use, including the independently loaded Nix backend.
# Nix inventory reminders cover every active profile entry, including other flakes.
# Nix removal reminders operate on active profile entries.
# APT reminders require successful metadata refresh before an upgrade.
# Plan reminders describe an update inventory; native upgrades resolve transactions.
# Update-check reminders preserve separate query diagnostics.
# DNF search reminders apply to both DNF4 and DNF5.
# Cancellation stops later package managers and cleanup phases.
# Manager-selection reminders expose every installed backend with explicit lists that reject empty IDs.
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
