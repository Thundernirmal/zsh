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
  catppuccin-mocha:base       1e1e2e
  catppuccin-mocha:surface    313244
  catppuccin-mocha:selected   45475a
  catppuccin-mocha:border     6c7086
  catppuccin-mocha:gutter     1e1e2e
  catppuccin-mocha:text       cdd6f4
  catppuccin-mocha:muted      a6adc8
  catppuccin-mocha:accent     cba6f7
  catppuccin-mocha:query      a6e3a1
  catppuccin-mocha:match      f38ba8
  catppuccin-mocha:focus      f5e0dc
  catppuccin-mocha:info       89b4fa
  catppuccin-mocha:success    a6e3a1
  catppuccin-mocha:warning    f9e2af
  catppuccin-mocha:danger     f38ba8

  catppuccin-latte:base       eff1f5
  catppuccin-latte:surface    e6e9ef
  catppuccin-latte:selected   ccd0da
  catppuccin-latte:border     9ca0b0
  catppuccin-latte:gutter     eff1f5
  catppuccin-latte:text       4c4f69
  catppuccin-latte:muted      6c6f85
  catppuccin-latte:accent     8839ef
  catppuccin-latte:query      40a02b
  catppuccin-latte:match      d20f39
  catppuccin-latte:focus      dc8a78
  catppuccin-latte:info       1e66f5
  catppuccin-latte:success    40a02b
  catppuccin-latte:warning    df8e1d
  catppuccin-latte:danger     d20f39

  nord:base                   2e3440
  nord:surface                3b4252
  nord:selected               434c5e
  nord:border                 4c566a
  nord:gutter                 2e3440
  nord:text                   eceff4
  nord:muted                  d8dee9
  nord:accent                 b48ead
  nord:query                  a3be8c
  nord:match                  bf616a
  nord:focus                  88c0d0
  nord:info                   81a1c1
  nord:success                a3be8c
  nord:warning                ebcb8b
  nord:danger                 bf616a

  gruvbox-dark:base           282828
  gruvbox-dark:surface        3c3836
  gruvbox-dark:selected       504945
  gruvbox-dark:border         665c54
  gruvbox-dark:gutter         282828
  gruvbox-dark:text           ebdbb2
  gruvbox-dark:muted          a89984
  gruvbox-dark:accent         d3869b
  gruvbox-dark:query          b8bb26
  gruvbox-dark:match          fb4934
  gruvbox-dark:focus          fe8019
  gruvbox-dark:info           83a598
  gruvbox-dark:success        b8bb26
  gruvbox-dark:warning        fabd2f
  gruvbox-dark:danger         fb4934
)
typeset -gA _ZSH_THEME_CUSTOM_COLORS
typeset -ga _ZSH_THEME_RESOLUTION_ISSUES
typeset -gi _ZSH_THEME_STARTUP_DIAGNOSTIC_SHOWN=${_ZSH_THEME_STARTUP_DIAGNOSTIC_SHOWN:-0}

if (( ! ${+ZSH_UI_THEME} )); then
  typeset -g ZSH_UI_THEME=catppuccin-mocha
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

_zsh_theme_has_role() {
  (( ${_ZSH_UI_THEME_ROLES[(Ie)$1]} ))
}

_zsh_theme_is_builtin() {
  (( ${_ZSH_UI_THEME_NAMES[(Ie)$1]} ))
}

_zsh_theme_validate_hex() {
  emulate -L zsh

  local value=$1
  local pattern='^[[:xdigit:]]{6}$'
  [[ $value =~ $pattern ]]
}

_zsh_theme_capture_custom() {
  emulate -L zsh

  local role key value
  local parameter_type=${(t)ZSH_UI_CUSTOM_COLORS}
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
    REPLY=${_ZSH_THEME_COLORS[${theme}:${role}]-}
  fi

  [[ -n $REPLY ]]
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
      elif [[ -n ${NO_NERD_FONT:-} ]]; then
        REPLY=unicode
      else
        REPLY=nerd
      fi
      ;;
    *) return 1 ;;
  esac
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

_zsh_theme_rgb_components() {
  emulate -L zsh

  local hex=$1
  _zsh_theme_validate_hex "$hex" || return 1
  reply=(
    $(( 16#${hex[1,2]} ))
    $(( 16#${hex[3,4]} ))
    $(( 16#${hex[5,6]} ))
  )
}

_zsh_theme_rgb_to_256() {
  emulate -L zsh

  local hex=$1
  local -a rgb levels=(0 95 135 175 215 255)
  integer component level_index best_index best_distance distance
  local -a cube_indexes
  integer cube_r cube_g cube_b cube_code cube_distance
  integer gray_index gray_value gray_code gray_distance

  _zsh_theme_rgb_components "$hex" || return 1
  rgb=( "${reply[@]}" )

  for component in "${rgb[@]}"; do
    best_index=0
    best_distance=65536
    for (( level_index = 1; level_index <= ${#levels}; level_index++ )); do
      distance=$(( (component - levels[level_index]) ** 2 ))
      if (( distance < best_distance )); then
        best_distance=$distance
        best_index=$(( level_index - 1 ))
      fi
    done
    cube_indexes+=( $best_index )
  done

  cube_r=${levels[$(( cube_indexes[1] + 1 ))]}
  cube_g=${levels[$(( cube_indexes[2] + 1 ))]}
  cube_b=${levels[$(( cube_indexes[3] + 1 ))]}
  cube_code=$(( 16 + 36 * cube_indexes[1] + 6 * cube_indexes[2] + cube_indexes[3] ))
  cube_distance=$((
    (rgb[1] - cube_r) ** 2 +
    (rgb[2] - cube_g) ** 2 +
    (rgb[3] - cube_b) ** 2
  ))

  best_distance=196608
  gray_code=232
  for (( gray_index = 0; gray_index < 24; gray_index++ )); do
    gray_value=$(( 8 + gray_index * 10 ))
    distance=$((
      (rgb[1] - gray_value) ** 2 +
      (rgb[2] - gray_value) ** 2 +
      (rgb[3] - gray_value) ** 2
    ))
    if (( distance < best_distance )); then
      best_distance=$distance
      gray_distance=$distance
      gray_code=$(( 232 + gray_index ))
    fi
  done

  if (( gray_distance < cube_distance )); then
    REPLY=$gray_code
  else
    REPLY=$cube_code
  fi
}

_zsh_theme_rgb_to_ansi() {
  emulate -L zsh

  local hex=$1 ansi_hex
  local -a rgb ansi_rgb
  local -a ansi_palette=(
    000000 800000 008000 808000 000080 800080 008080 c0c0c0
    808080 ff0000 00ff00 ffff00 0000ff ff00ff 00ffff ffffff
  )
  integer ansi_index best_index=0 best_distance=196608 distance

  _zsh_theme_rgb_components "$hex" || return 1
  rgb=( "${reply[@]}" )

  for (( ansi_index = 1; ansi_index <= ${#ansi_palette}; ansi_index++ )); do
    ansi_hex=${ansi_palette[$ansi_index]}
    _zsh_theme_rgb_components "$ansi_hex" || return 1
    ansi_rgb=( "${reply[@]}" )
    distance=$((
      (rgb[1] - ansi_rgb[1]) ** 2 +
      (rgb[2] - ansi_rgb[2]) ** 2 +
      (rgb[3] - ansi_rgb[3]) ** 2
    ))
    if (( distance < best_distance )); then
      best_distance=$distance
      best_index=$(( ansi_index - 1 ))
    fi
  done

  REPLY=$best_index
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

  local role=$1 scope=${2:-ui} depth=${3:-${_ZSH_UI_COLOR_DEPTH:-ansi}}
  local theme hex

  _zsh_theme_scope_name "$scope" || return 1
  theme=$REPLY
  [[ $depth != none ]] || {
    REPLY=''
    return 1
  }

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

_zsh_theme_sgr() {
  emulate -L zsh

  local role=$1 layer=${2:-fg} scope=${3:-ui}
  local depth=${_ZSH_UI_COLOR_DEPTH:-ansi} value hex theme
  integer base=38 code

  [[ $layer == fg || $layer == bg ]] || return 1
  [[ $layer == bg ]] && base=48
  _zsh_theme_scope_name "$scope" || return 1
  theme=$REPLY
  [[ $theme == terminal && $depth != none ]] && depth=ansi
  _zsh_theme_color_value "$role" "$scope" "$depth" || {
    REPLY=''
    return 1
  }
  value=$REPLY

  case $depth in
    truecolor)
      hex=${value#\#}
      _zsh_theme_rgb_components "$hex" || return 1
      REPLY=$'\e'"[${base};2;${reply[1]};${reply[2]};${reply[3]}m"
      ;;
    256)
      REPLY=$'\e'"[${base};5;${value}m"
      ;;
    ansi)
      if (( value < 0 )); then
        [[ $layer == bg ]] && code=49 || code=39
      elif (( value < 8 )); then
        [[ $layer == bg ]] && code=$(( 40 + value )) || code=$(( 30 + value ))
      else
        [[ $layer == bg ]] && code=$(( 100 + value - 8 )) || code=$(( 90 + value - 8 ))
      fi
      REPLY=$'\e'"[${code}m"
      ;;
    *) return 1 ;;
  esac
}

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
  local theme=${_ZSH_FZF_ACTIVE_THEME:-catppuccin-mocha}
  local role target value
  local -a mappings args

  if [[ -n ${NO_COLOR:-} || $depth == none ]]; then
    reply=( --no-color )
    return 0
  fi

  local -a target_roles=(
    bg base list-bg base preview-bg base
    input-bg surface header-bg surface footer-bg surface
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
  local pointer marker gutter scrollbar separator wrap
  local -a args color_args

  case $layout in
    compact)
      args=( '--height=~60%' --layout=reverse --style=full:line --info=inline-right )
      ;;
    roomy)
      args=( '--height=80%' --layout=reverse --style=full:rounded --info=inline-right )
      ;;
    minimal)
      args=( '--height=~45%' --layout=reverse --style=minimal --info=inline-right )
      ;;
    *) return 1 ;;
  esac

  _zsh_theme_glyph pointer; pointer=$REPLY
  _zsh_theme_glyph marker; marker=$REPLY
  _zsh_theme_glyph gutter; gutter=$REPLY
  _zsh_theme_glyph scrollbar; scrollbar=$REPLY
  _zsh_theme_glyph separator; separator=$REPLY
  _zsh_theme_glyph wrap; wrap=$REPLY
  args+=(
    --border
    --highlight-line
    --cycle
    --scroll-off=3
    "--pointer=$pointer"
    "--marker=$marker"
    "--gutter=$gutter"
    "--scrollbar=$scrollbar"
    "--separator=$separator"
    "--wrap-sign=$wrap"
    "--preview-wrap-sign=$wrap"
  )

  _zsh_theme_fzf_color_args || return 1
  color_args=( "${reply[@]}" )
  reply=( "${args[@]}" "${color_args[@]}" )
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
    "--list-label=$list_label"
    --input-label=Search
    "--ghost=$ghost"
    "--footer=$footer"
  )
}

_zsh_theme_signature() {
  REPLY="${_ZSH_UI_ACTIVE_THEME:-}:${_ZSH_FZF_ACTIVE_THEME:-}:${_ZSH_UI_COLOR_DEPTH:-}:${_ZSH_UI_GLYPH_TIER:-}:${ZSH_FZF_LAYOUT:-}:${ZSH_FZF_EXTRA_OPTS:-}"
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
      requested_ui=catppuccin-mocha
    fi
  elif ! _zsh_theme_is_builtin "$requested_ui"; then
    _ZSH_THEME_RESOLUTION_ISSUES+=( "unknown UI theme: ${requested_ui:-<empty>}" )
    requested_ui=catppuccin-mocha
  fi

  if [[ -z $requested_fzf ]]; then
    requested_fzf=$requested_ui
  elif [[ $requested_fzf == custom ]]; then
    if (( ! custom_valid )); then
      _ZSH_THEME_RESOLUTION_ISSUES+=( 'invalid custom fzf palette' )
      requested_fzf=catppuccin-mocha
    fi
  elif ! _zsh_theme_is_builtin "$requested_fzf"; then
    _ZSH_THEME_RESOLUTION_ISSUES+=( "unknown fzf theme: $requested_fzf" )
    requested_fzf=catppuccin-mocha
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
