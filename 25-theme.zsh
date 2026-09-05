# Shared theme registry and pure-Zsh resolver.

typeset -ga _ZSH_UI_THEME_NAMES=(
  catppuccin-mocha
  catppuccin-latte
  nord
  gruvbox-dark
  terminal
)
typeset -ga _ZSH_UI_THEME_ROLES=(
  base surface selected border gutter text muted accent query match focus
  info success warning danger
)
typeset -gA _ZSH_THEME_COLORS=(
)
typeset -gA _ZSH_THEME_CUSTOM_COLORS
typeset -ga _ZSH_THEME_RESOLUTION_ISSUES
typeset -gi _ZSH_THEME_STARTUP_DIAGNOSTIC_SHOWN=${_ZSH_THEME_STARTUP_DIAGNOSTIC_SHOWN:-0}
typeset -g _ZSH_THEME_FZF_CHROME_SIGNATURE=${_ZSH_THEME_FZF_CHROME_SIGNATURE:-}
typeset -g _ZSH_THEME_FZF_CHROME_OPTS=${_ZSH_THEME_FZF_CHROME_OPTS:-}
typeset -g _ZSH_THEME_MODULE_DIR=${${(%):-%N}:A:h}
typeset -gi _ZSH_THEME_COLOR_HELPERS_LOADED=${_ZSH_THEME_COLOR_HELPERS_LOADED:-0}
typeset -gi _ZSH_THEME_BUILTIN_PALETTES_LOADED=${_ZSH_THEME_BUILTIN_PALETTES_LOADED:-0}
typeset -gi _ZSH_THEME_REGISTRY_LOADED=${_ZSH_THEME_REGISTRY_LOADED:-0}

if (( _ZSH_THEME_BUILTIN_PALETTES_LOADED )); then
  source "$_ZSH_THEME_MODULE_DIR/lib/theme-palettes.zsh"
fi

if (( ! ${+ZSH_UI_THEME} )); then
  typeset -g ZSH_UI_THEME=terminal
fi
if (( ! ${+ZSH_FZF_THEME} )); then
  typeset -g ZSH_FZF_THEME=''
fi
if (( ! ${+ZSH_FZF_LAYOUT} )); then
  typeset -g ZSH_FZF_LAYOUT=compact
fi
if (( ! ${+ZSH_UI_GLYPHS} )); then
  typeset -g ZSH_UI_GLYPHS=auto
fi
if (( ! ${+ZSH_FZF_EXTRA_OPTS} )); then
  typeset -g ZSH_FZF_EXTRA_OPTS=''
fi

_zsh_theme_is_builtin() {
  (( ${_ZSH_UI_THEME_NAMES[(Ie)$1]} ))
}

_zsh_theme_load_registry() {
  (( _ZSH_THEME_REGISTRY_LOADED )) && return 0
  [[ -r $_ZSH_THEME_MODULE_DIR/lib/theme-registry.zsh ]] || return 1
  source "$_ZSH_THEME_MODULE_DIR/lib/theme-registry.zsh" || return 1
  typeset -gi _ZSH_THEME_REGISTRY_LOADED=1
}

_zsh_theme_has_role() {
  _zsh_theme_load_registry || return 1
  _zsh_theme_has_role "$@"
}

_zsh_theme_validate_hex() {
  _zsh_theme_load_registry || return 1
  _zsh_theme_validate_hex "$@"
}

_zsh_theme_capture_custom() {
  _zsh_theme_load_registry || return 1
  _zsh_theme_capture_custom "$@"
}

_zsh_theme_role_hex() {
  _zsh_theme_load_registry || return 1
  _zsh_theme_role_hex "$@"
}

_zsh_theme_detect_color_depth() {
  emulate -L zsh

  local colorterm=${(L)${COLORTERM:-}}
  local term=${(L)${TERM:-}}

  if [[ -n ${NO_COLOR:-} ]]; then
    REPLY=none
  elif [[ $colorterm == truecolor || $colorterm == 24bit ]]; then
    REPLY=truecolor
  elif [[ $term == *256color* ]]; then
    REPLY=256
  else
    REPLY=ansi
  fi
}

_zsh_theme_locale_is_utf8() {
  emulate -L zsh

  local locale=${(L)${LC_ALL:-${LC_CTYPE:-${LANG:-}}}}
  [[ $locale == *utf-8* || $locale == *utf8* ]]
}

_zsh_theme_resolve_glyph_tier() {
  emulate -L zsh

  local requested=$1
  case $requested in
    nerd|unicode|ascii) REPLY=$requested ;;
    auto)
      if ! _zsh_theme_locale_is_utf8; then
        REPLY=ascii
      else
        REPLY=unicode
      fi
      ;;
    *) return 1 ;;
  esac
  # NO_NERD_FONT records that the terminal lacks private-use glyphs, so it
  # always wins over a Nerd Font tier however that tier was requested.
  if [[ -n ${NO_NERD_FONT:-} && $REPLY == nerd ]]; then
    REPLY=unicode
  fi
}

_zsh_theme_terminal_code() {
  _zsh_theme_load_registry || return 1
  _zsh_theme_terminal_code "$@"
}

_zsh_theme_ansi_code() {
  _zsh_theme_load_registry || return 1
  _zsh_theme_ansi_code "$@"
}

_zsh_theme_load_color_helpers() {
  (( _ZSH_THEME_COLOR_HELPERS_LOADED )) && return 0
  [[ -r $_ZSH_THEME_MODULE_DIR/lib/theme-color.zsh ]] || return 1
  source "$_ZSH_THEME_MODULE_DIR/lib/theme-color.zsh" || return 1
  typeset -gi _ZSH_THEME_COLOR_HELPERS_LOADED=1
}

_zsh_theme_rgb_components() {
  _zsh_theme_load_color_helpers || return 1
  _zsh_theme_rgb_components "$@"
}

_zsh_theme_rgb_to_256() {
  _zsh_theme_load_color_helpers || return 1
  _zsh_theme_rgb_to_256 "$@"
}

_zsh_theme_scope_name() {
  _zsh_theme_load_registry || return 1
  _zsh_theme_scope_name "$@"
}

_zsh_theme_color_value() {
  _zsh_theme_load_registry || return 1
  _zsh_theme_color_value "$@"
}

_zsh_theme_sgr() {
  _zsh_theme_load_color_helpers || return 1
  _zsh_theme_sgr "$@"
}

if (( _ZSH_THEME_COLOR_HELPERS_LOADED )); then
  source "$_ZSH_THEME_MODULE_DIR/lib/theme-color.zsh"
fi
if (( _ZSH_THEME_REGISTRY_LOADED )); then
  source "$_ZSH_THEME_MODULE_DIR/lib/theme-registry.zsh"
fi

_zsh_theme_glyph() {
  emulate -L zsh

  local key=$1 tier=${2:-${_ZSH_UI_GLYPH_TIER:-ascii}}
  case ${tier}:${key} in
    nerd:pointer) REPLY='󰘳' ;;
    nerd:marker) REPLY='󰄬' ;;
    nerd:gutter|unicode:gutter) REPLY='│' ;;
    nerd:scrollbar|unicode:scrollbar) REPLY='┃' ;;
    nerd:separator|unicode:separator) REPLY='─' ;;
    nerd:wrap|unicode:wrap) REPLY='↳' ;;
    unicode:pointer) REPLY='›' ;;
    unicode:marker) REPLY='✓' ;;
    ascii:pointer|ascii:wrap) REPLY='>' ;;
    ascii:marker) REPLY='+' ;;
    ascii:gutter|ascii:scrollbar) REPLY='|' ;;
    ascii:separator) REPLY='-' ;;
    *) return 1 ;;
  esac
}

_zsh_theme_join_shell_args() {
  emulate -L zsh

  local arg output=''
  for arg in "$@"; do
    [[ -n $output ]] && output+=' '
    output+=${(qq)arg}
  done
  REPLY=$output
}

_zsh_theme_fzf_color_args() {
  emulate -L zsh

  local depth=${_ZSH_UI_COLOR_DEPTH:-ansi}
  local theme=${_ZSH_FZF_ACTIVE_THEME:-terminal}
  local role target value
  local -a mappings args

  if [[ -n ${NO_COLOR:-} || $depth == none ]]; then
    reply=( --no-color )
    return 0
  fi

  local -a target_roles=(
    bg base list-bg base preview-bg base
    input-bg base header-bg surface footer-bg base
    fg text list-fg text preview-fg text current-fg text selected-fg text
    current-bg selected selected-bg surface
    query query prompt accent ghost muted info muted spinner info
    hl match current-hl match selected-hl match
    header muted footer muted
    border border label accent
    list-border border list-label accent
    input-border border input-label accent
    header-border border header-label muted
    footer-border border footer-label muted
    preview-border border preview-label accent
    pointer focus marker success gutter gutter scrollbar border separator border
  )
  [[ ${ZSH_FZF_LAYOUT:-compact} == roomy ]] && target_roles+=( alt-bg surface )

  integer index
  for (( index = 1; index <= ${#target_roles}; index += 2 )); do
    target=${target_roles[$index]}
    role=${target_roles[$(( index + 1 ))]}
    _zsh_theme_color_value "$role" fzf "$depth" || return 1
    value=$REPLY
    mappings+=( "${target}:${value}" )
  done

  args=( "--color=${(j:,:)mappings}" )
  reply=( "${args[@]}" )
}

_zsh_theme_fzf_chrome_args() {
  emulate -L zsh

  local layout=${ZSH_FZF_LAYOUT:-compact}
  local pointer marker gutter scrollbar wrap
  local -a args color_args

  case $layout in
    compact)
      args=( '--height=~60%' --layout=reverse --style=default --info=inline-right --padding=0,1 )
      ;;
    roomy)
      args=( '--height=80%' --layout=reverse --style=default --info=inline-right --padding=1,2 )
      ;;
    minimal)
      args=( '--height=~45%' --layout=reverse --style=minimal --info=inline-right --padding=0,1 )
      ;;
    *) return 1 ;;
  esac

  _zsh_theme_glyph pointer; pointer=$REPLY
  _zsh_theme_glyph marker; marker=$REPLY
  _zsh_theme_glyph gutter; gutter=$REPLY
  _zsh_theme_glyph scrollbar; scrollbar=$REPLY
  _zsh_theme_glyph wrap; wrap=$REPLY
  args+=(
    --border=rounded
    --list-border=none
    --input-border=bottom
    --header-border=bottom
    --footer-border=top
    --highlight-line
    --cycle
    --scroll-off=3
    "--pointer=$pointer"
    "--marker=$marker"
    "--gutter=$gutter"
    "--scrollbar=$scrollbar"
    "--wrap-sign=$wrap"
    "--preview-wrap-sign=$wrap"
  )

  _zsh_theme_fzf_color_args || return 1
  color_args=( "${reply[@]}" )
  reply=( "${args[@]}" "${color_args[@]}" )
}

_zsh_theme_fzf_chrome_opts() {
  emulate -L zsh

  local signature="${_ZSH_FZF_ACTIVE_THEME:-}:${_ZSH_UI_COLOR_DEPTH:-}:${_ZSH_UI_GLYPH_TIER:-}:${ZSH_FZF_LAYOUT:-}:${(j:,:)_ZSH_THEME_CUSTOM_COLORS}"
  local -a args
  if [[ $_ZSH_THEME_FZF_CHROME_SIGNATURE == "$signature" ]]; then
    REPLY=$_ZSH_THEME_FZF_CHROME_OPTS
    return 0
  fi

  _zsh_theme_fzf_chrome_args || return 1
  args=( "${reply[@]:#--no-color}" )
  _zsh_theme_join_shell_args "${args[@]}"
  typeset -g _ZSH_THEME_FZF_CHROME_SIGNATURE=$signature
  typeset -g _ZSH_THEME_FZF_CHROME_OPTS=$REPLY
}

_zsh_theme_fzf_preview_window() {
  emulate -L zsh

  integer width=${COLUMNS:-80}
  local layout=${ZSH_FZF_LAYOUT:-compact}
  local wide narrow

  case $width in
    ''|*[!0-9]*) width=80 ;;
  esac
  case $layout in
    compact) wide=50; narrow=40 ;;
    roomy) wide=55; narrow=45 ;;
    minimal) wide=45; narrow=35 ;;
    *) return 1 ;;
  esac

  if (( width >= 100 )); then
    REPLY="right,${wide}%,border-left,wrap-word,<100(down,${narrow}%,border-top,wrap-word)"
  else
    REPLY="down,${narrow}%,border-top,wrap-word"
  fi
}

_zsh_theme_fzf_context_args() {
  emulate -L zsh

  local list_label=$1 ghost=$2 footer=$3
  reply=(
    "--border-label=$list_label"
    --input-label=Search
    "--ghost=$ghost"
    "--footer=$footer"
  )
}

_zsh_theme_signature() {
  local custom_identity=${(j:,:)_ZSH_THEME_CUSTOM_COLORS}
  REPLY="${_ZSH_UI_ACTIVE_THEME:-}:${_ZSH_FZF_ACTIVE_THEME:-}:${_ZSH_UI_COLOR_DEPTH:-}:${_ZSH_UI_GLYPH_TIER:-}:${ZSH_FZF_LAYOUT:-}:${ZSH_FZF_EXTRA_OPTS:-}"
  [[ -n $custom_identity ]] && REPLY+=":$custom_identity"
}

_zsh_theme_startup_diagnostic() {
  (( _ZSH_THEME_STARTUP_DIAGNOSTIC_SHOWN == 0 )) || return 0
  [[ -o interactive && -z ${ZSH_EXECUTION_STRING:-} ]] || return 0
  _ZSH_THEME_STARTUP_DIAGNOSTIC_SHOWN=1
  print -u2 -r -- "zsh config: invalid theme settings (${(j:, :)_ZSH_THEME_RESOLUTION_ISSUES}); using safe defaults."
}

_zsh_theme_resolve_settings() {
  emulate -L zsh

  local requested_ui=${ZSH_UI_THEME-}
  local requested_fzf=${ZSH_FZF_THEME-}
  local requested_layout=${ZSH_FZF_LAYOUT-}
  local requested_glyphs=${ZSH_UI_GLYPHS-}
  integer custom_needed=0 custom_valid=0

  _ZSH_THEME_RESOLUTION_ISSUES=()
  [[ $requested_ui == custom || $requested_fzf == custom ]] && custom_needed=1
  if (( custom_needed )) && (( ${+ZSH_UI_CUSTOM_COLORS} )) && _zsh_theme_capture_custom; then
    custom_valid=1
  fi

  if [[ $requested_ui == custom ]]; then
    if (( ! custom_valid )); then
      _ZSH_THEME_RESOLUTION_ISSUES+=( 'invalid custom UI palette' )
      requested_ui=terminal
    fi
  elif ! _zsh_theme_is_builtin "$requested_ui"; then
    _ZSH_THEME_RESOLUTION_ISSUES+=( "unknown UI theme: ${requested_ui:-<empty>}" )
    requested_ui=terminal
  fi

  if [[ -z $requested_fzf ]]; then
    requested_fzf=$requested_ui
  elif [[ $requested_fzf == custom ]]; then
    if (( ! custom_valid )); then
      _ZSH_THEME_RESOLUTION_ISSUES+=( 'invalid custom fzf palette' )
      requested_fzf=terminal
    fi
  elif ! _zsh_theme_is_builtin "$requested_fzf"; then
    _ZSH_THEME_RESOLUTION_ISSUES+=( "unknown fzf theme: $requested_fzf" )
    requested_fzf=terminal
  fi

  case $requested_layout in
    compact|roomy|minimal) ;;
    *)
      _ZSH_THEME_RESOLUTION_ISSUES+=( "unknown fzf layout: ${requested_layout:-<empty>}" )
      requested_layout=compact
      ;;
  esac

  if ! _zsh_theme_resolve_glyph_tier "$requested_glyphs"; then
    _ZSH_THEME_RESOLUTION_ISSUES+=( "unknown glyph mode: ${requested_glyphs:-<empty>}" )
    requested_glyphs=auto
    _zsh_theme_resolve_glyph_tier auto
  fi

  typeset -g ZSH_UI_THEME=$requested_ui
  if [[ -z ${ZSH_FZF_THEME-} ]]; then
    typeset -g ZSH_FZF_THEME=''
  else
    typeset -g ZSH_FZF_THEME=$requested_fzf
  fi
  typeset -g ZSH_FZF_LAYOUT=$requested_layout
  typeset -g ZSH_UI_GLYPHS=$requested_glyphs
  typeset -g _ZSH_UI_ACTIVE_THEME=$requested_ui
  typeset -g _ZSH_FZF_ACTIVE_THEME=$requested_fzf
  typeset -g _ZSH_UI_GLYPH_TIER=$REPLY
  _zsh_theme_detect_color_depth
  typeset -g _ZSH_UI_COLOR_DEPTH=$REPLY

  (( ${#_ZSH_THEME_RESOLUTION_ISSUES} == 0 )) || _zsh_theme_startup_diagnostic
}

_zsh_theme_resolve_settings
