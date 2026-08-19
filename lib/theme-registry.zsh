# Lazily loaded palette validation and color lookup helpers.

_zsh_theme_has_role() {
  (( ${_ZSH_UI_THEME_ROLES[(Ie)$1]} ))
}

_zsh_theme_validate_hex() {
  emulate -L zsh
  local value=$1 pattern='^[[:xdigit:]]{6}$'
  [[ $value =~ $pattern ]]
}

_zsh_theme_capture_custom() {
  emulate -L zsh
  local role key value parameter_type=${(t)ZSH_UI_CUSTOM_COLORS}
  local -A captured

  [[ $parameter_type == *association* ]] || return 1
  (( ${#ZSH_UI_CUSTOM_COLORS} == ${#_ZSH_UI_THEME_ROLES} )) || return 1
  for role in "${_ZSH_UI_THEME_ROLES[@]}"; do
    value=${ZSH_UI_CUSTOM_COLORS[$role]-}
    _zsh_theme_validate_hex "$value" || return 1
    captured[$role]=${(L)value}
  done
  for key in "${(@k)ZSH_UI_CUSTOM_COLORS}"; do
    _zsh_theme_has_role "$key" || return 1
  done
  _ZSH_THEME_CUSTOM_COLORS=( "${(@kv)captured}" )
}

_zsh_theme_role_hex() {
  emulate -L zsh
  local theme=$1 role=$2
  _zsh_theme_has_role "$role" || return 1

  if [[ $theme == custom ]]; then
    REPLY=${_ZSH_THEME_CUSTOM_COLORS[$role]-}
  elif [[ $theme == terminal ]]; then
    REPLY=''
    return 1
  else
    if (( ! _ZSH_THEME_BUILTIN_PALETTES_LOADED )); then
      [[ -r $_ZSH_THEME_MODULE_DIR/lib/theme-palettes.zsh ]] || return 1
      source "$_ZSH_THEME_MODULE_DIR/lib/theme-palettes.zsh" || return 1
      typeset -gi _ZSH_THEME_BUILTIN_PALETTES_LOADED=1
    fi
    REPLY=${_ZSH_THEME_COLORS[${theme}:${role}]-}
  fi
  [[ -n $REPLY ]]
}

_zsh_theme_terminal_code() {
  case $1 in
    base|surface|gutter|text) REPLY=-1 ;;
    selected|border|muted) REPLY=8 ;;
    accent) REPLY=5 ;;
    query|success) REPLY=2 ;;
    match|danger) REPLY=1 ;;
    focus|warning) REPLY=3 ;;
    info) REPLY=4 ;;
    *) return 1 ;;
  esac
}

_zsh_theme_ansi_code() {
  local theme=$1 role=$2
  if [[ $theme == terminal ]]; then
    _zsh_theme_terminal_code "$role"
    return
  fi
  if [[ $theme == catppuccin-latte ]]; then
    case $role in
      base|gutter) REPLY=15 ;;
      surface|selected) REPLY=7 ;;
      border|muted) REPLY=8 ;;
      text) REPLY=0 ;;
      accent) REPLY=5 ;;
      query|success) REPLY=2 ;;
      match|danger) REPLY=1 ;;
      focus|warning) REPLY=3 ;;
      info) REPLY=4 ;;
      *) return 1 ;;
    esac
    return
  fi
  case $role in
    base|gutter) REPLY=0 ;;
    surface|selected|border) REPLY=8 ;;
    text|focus) REPLY=15 ;;
    muted) REPLY=7 ;;
    accent) REPLY=13 ;;
    query|success) REPLY=10 ;;
    match|danger) REPLY=9 ;;
    info) REPLY=12 ;;
    warning) REPLY=11 ;;
    *) return 1 ;;
  esac
}

_zsh_theme_scope_name() {
  case ${1:-ui} in
    ui) REPLY=${_ZSH_UI_ACTIVE_THEME:-catppuccin-mocha} ;;
    fzf) REPLY=${_ZSH_FZF_ACTIVE_THEME:-${_ZSH_UI_ACTIVE_THEME:-catppuccin-mocha}} ;;
    *) return 1 ;;
  esac
}

_zsh_theme_color_value() {
  emulate -L zsh
  local role=$1 scope=${2:-ui} depth=${3:-${_ZSH_UI_COLOR_DEPTH:-ansi}} theme hex

  _zsh_theme_scope_name "$scope" || return 1
  theme=$REPLY
  [[ $depth != none ]] || { REPLY=''; return 1; }
  if [[ $theme == terminal ]]; then
    _zsh_theme_terminal_code "$role"
    return
  fi
  _zsh_theme_role_hex "$theme" "$role" || return 1
  hex=$REPLY
  case $depth in
    truecolor) REPLY="#$hex" ;;
    256) _zsh_theme_rgb_to_256 "$hex" ;;
    ansi) _zsh_theme_ansi_code "$theme" "$role" ;;
    *) return 1 ;;
  esac
}
