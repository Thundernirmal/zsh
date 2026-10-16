# Fixed lazy loader for hook-free, on-demand tips in lib/tips-catalogue.zsh.
# Finder percentage requests, minimum-height limits, and preview boundaries follow GUIDE.md.
# Doctor reminders cover blocked integration failures, restarting after repair, and the Secret Service ping.
# Zoxide reminders cover the zi preview and its retained ranking; Nix reminders cover option passthrough.
# The catalogue checks matching tool capabilities when it loads on first use.
# Package reminders include automatic elapsed summaries and follow GUIDE.md ownership boundaries.

typeset -g _ZSH_TIPS_MODULE_DIR=${${(%):-%N}:A:h}
typeset -gi _ZSH_TIPS_CATALOGUE_LOADED=${_ZSH_TIPS_CATALOGUE_LOADED:-0}

_zsh_tips_load() {
  (( _ZSH_TIPS_CATALOGUE_LOADED )) && return 0
  # Parse trusted helpers without user or global alias expansion.
  setopt localoptions no_aliases
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

# Ctrl+T plain file previews stop at line 200; full-file inspection is a separate action.

# Nix Tab completion reuses unchanged cached candidates without refreshing the index.

# Nix outdated keeps incomplete entries visible as unknown and reports malformed profiles as errors.

# Nix outdated refills up to eight evaluation slots; result order remains stable.
