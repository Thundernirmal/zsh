# Shared terminal UI helpers.

_ui_term_width() {
  emulate -L zsh

  local cols=${COLUMNS:-}

  case $cols in
    ''|*[!0-9]*) cols=$(command tput cols 2>/dev/null) ;;
  esac

  case $cols in
    ''|*[!0-9]*) cols=80 ;;
  esac

  print -r -- "$cols"
}

_ui_term_height() {
  emulate -L zsh

  local lines=${LINES:-}

  case $lines in
    ''|*[!0-9]*) lines=$(command tput lines 2>/dev/null) ;;
  esac

  case $lines in
    ''|*[!0-9]*) lines=24 ;;
  esac

  print -r -- "$lines"
}

_ui_locale_is_utf8() {
  emulate -L zsh

  local locale=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
  locale=${(L)locale}

  [[ $locale == *utf-8* || $locale == *utf8* ]]
}

_ui_is_rich_terminal() {
  emulate -L zsh

  local width

  [[ -t 1 ]] || return 1
  [[ ${TERM:-} != dumb ]] || return 1
  [[ -z ${NO_COLOR:-} ]] || return 1
  _ui_locale_is_utf8 || return 1

  width=$(_ui_term_width)
  (( width >= 60 ))
}

_ui_plain_mode() {
  ! _ui_is_rich_terminal
}

_ui_ascii_mode() {
  emulate -L zsh

  if _ui_plain_mode; then
    return 0
  fi

  [[ -n ${NO_NERD_FONT:-} ]]
}

_ui_has_truecolor() {
  emulate -L zsh

  local colorterm=${(L)${COLORTERM:-}}
  [[ $colorterm == truecolor || $colorterm == 24bit ]]
}

_ui_has_icons() {
  _ui_is_rich_terminal && [[ -z ${NO_NERD_FONT:-} ]]
}

_ui_palette_hex() {
  case $1 in
    accent|rosewater) print -r -- 'f5e0dc' ;;
    base) print -r -- '1e1e2e' ;;
    surface|surface0) print -r -- '313244' ;;
    surface1) print -r -- '45475a' ;;
    border|overlay|overlay0) print -r -- '6c7086' ;;
    text) print -r -- 'cdd6f4' ;;
    muted|subtext0) print -r -- 'a6adc8' ;;
    subtext1) print -r -- 'bac2de' ;;
    success|green) print -r -- 'a6e3a1' ;;
    warning|yellow) print -r -- 'f9e2af' ;;
    danger|red) print -r -- 'f38ba8' ;;
    info|blue) print -r -- '89b4fa' ;;
    lavender) print -r -- 'b4befe' ;;
    mauve) print -r -- 'cba6f7' ;;
    peach) print -r -- 'fab387' ;;
    teal) print -r -- '94e2d5' ;;
    sky) print -r -- '89dceb' ;;
    *) return 1 ;;
  esac
}

_ui_palette_256() {
  case $1 in
    accent|rosewater) print -r -- '224' ;;
    base) print -r -- '235' ;;
    surface|surface0) print -r -- '237' ;;
    surface1) print -r -- '238' ;;
    border|overlay|overlay0) print -r -- '60' ;;
    text) print -r -- '189' ;;
    muted|subtext0) print -r -- '145' ;;
    subtext1) print -r -- '152' ;;
    success|green) print -r -- '151' ;;
    warning|yellow) print -r -- '223' ;;
    danger|red) print -r -- '210' ;;
    info|blue) print -r -- '111' ;;
    lavender) print -r -- '147' ;;
    mauve) print -r -- '183' ;;
    peach) print -r -- '216' ;;
    teal) print -r -- '116' ;;
    sky) print -r -- '117' ;;
    *) return 1 ;;
  esac
}

_ui_color() {
  emulate -L zsh

  local role=$1
  local layer=${2:-fg}
  local prefix=38
  local hex code r g b

  _ui_is_rich_terminal || return 0
  [[ $layer == bg ]] && prefix=48

  if _ui_has_truecolor; then
    hex=$(_ui_palette_hex "$role") || return 0
    r=$(( 16#${hex[1,2]} ))
    g=$(( 16#${hex[3,4]} ))
    b=$(( 16#${hex[5,6]} ))
    printf '\033[%s;2;%s;%s;%sm' "$prefix" "$r" "$g" "$b"
    return 0
  fi

  code=$(_ui_palette_256 "$role") || return 0
  printf '\033[%s;5;%sm' "$prefix" "$code"
}

_ui_reset() {
  _ui_is_rich_terminal && printf '\033[0m'
}

_ui_icon() {
  emulate -L zsh

  local glyph=$1
  local fallback=$2

  if _ui_has_icons; then
    print -nr -- "$glyph"
  else
    print -nr -- "$fallback"
  fi
}

_ui_status_icon() {
  emulate -L zsh

  local state=$1

  case $state in
    'up to date'|upgraded)
      _ui_icon '󰄬' '*'
      ;;
    'updates available')
      _ui_icon '󰚰' '!'
      ;;
    blocked)
      _ui_icon '󰍛' '-'
      ;;
    failed)
      _ui_icon '󰅚' 'x'
      ;;
    skipped)
      _ui_icon '󰒭' '~'
      ;;
    *)
      _ui_icon '󰘥' '>'
      ;;
  esac
}

_ui_manager_icon() {
  emulate -L zsh

  case $1 in
    apt) _ui_icon '󰏖' '*' ;;
    dnf) _ui_icon '󰏖' '*' ;;
    pacman) _ui_icon '󰮯' '*' ;;
    paru) _ui_icon '󰣇' '*' ;;
    flatpak) _ui_icon '󰏖' '*' ;;
    nix) _ui_icon '󱄅' '*' ;;
    npm) _ui_icon '' '*' ;;
    *) _ui_icon '󰈔' '*' ;;
  esac
}

_ui_repeat() {
  emulate -L zsh

  local count=$1
  local chunk=$2
  local out=''
  integer i

  (( count > 0 )) || return 0

  for (( i = 0; i < count; i++ )); do
    out+="$chunk"
  done

  print -nr -- "$out"
}

_ui_truncate() {
  emulate -L zsh

  local width=$1
  shift

  local text="$*"
  local marker='…'
  integer left right

  (( width > 0 )) || {
    print -r -- ''
    return 0
  }

  if _ui_ascii_mode; then
    marker='...'
  fi

  if (( ${#text} <= width )); then
    print -r -- "$text"
    return 0
  fi

  if (( width <= ${#marker} + 1 )); then
    print -r -- "${text[1,width]}"
    return 0
  fi

  left=$(( (width - ${#marker}) / 2 ))
  right=$(( width - ${#marker} - left ))

  if (( right > 0 )); then
    print -r -- "${text[1,left]}${marker}${text[-$right,-1]}"
  else
    print -r -- "${text[1,left]}${marker}"
  fi
}

_ui_pad() {
  emulate -L zsh

  # 'right' = right-align text (leading spaces); 'left' = left-align (trailing spaces)
  local align=$1
  local width=$2
  shift 2

  local text=$(_ui_truncate "$width" "$*")
  local padding=$(( width - ${#text} ))

  (( padding < 0 )) && padding=0

  if [[ $align == right ]]; then
    printf '%*s%s' "$padding" '' "$text"
  else
    printf '%s%*s' "$text" "$padding" ''
  fi
}

_ui_human_bytes() {
  emulate -L zsh

  local bytes=${1:-0}
  local -a units=(B KiB MiB GiB TiB PiB)
  local divisor=1
  local scaled rounded
  integer unit_index=1

  case $bytes in
    ''|*[!0-9]*) bytes=0 ;;
  esac

  while (( unit_index < ${#units[@]} && bytes / divisor >= 1024 )); do
    divisor=$(( divisor * 1024 ))
    (( unit_index++ ))
  done

  if (( unit_index == 1 )); then
    print -r -- "${bytes}${units[$unit_index]}"
    return 0
  fi

  scaled=$(( (bytes * 10 + divisor / 2) / divisor ))
  if (( scaled >= 100 )); then
    rounded=$(( (bytes + divisor / 2) / divisor ))
    print -r -- "${rounded}${units[$unit_index]}"
  else
    print -r -- "$(( scaled / 10 )).$(( scaled % 10 ))${units[$unit_index]}"
  fi
}

_ui_human_kib() {
  emulate -L zsh

  local kib=${1:-0}

  case $kib in
    ''|*[!0-9]*) kib=0 ;;
  esac

  _ui_human_bytes $(( kib * 1024 ))
}

_ui_bar() {
  emulate -L zsh

  integer width=$1
  integer value=$2
  integer total=$3
  local role=${4:-accent}
  local filled_char='█'
  local empty_char='░'
  integer filled=0

  (( width > 0 )) || return 0

  if _ui_ascii_mode; then
    filled_char='#'
    empty_char='-'
  fi

  if (( total > 0 && value > 0 )); then
    filled=$(( value * width / total ))
    if (( value > 0 && filled == 0 )); then
      filled=1
    fi
    (( filled > width )) && filled=$width
  fi

  if _ui_is_rich_terminal; then
    _ui_color "$role"
    _ui_repeat "$filled" "$filled_char"
    _ui_color muted
    _ui_repeat "$(( width - filled ))" "$empty_char"
    _ui_reset
  else
    _ui_repeat "$filled" "$filled_char"
    _ui_repeat "$(( width - filled ))" "$empty_char"
  fi
}

_ui_badge() {
  emulate -L zsh

  local label=$1
  local role=${2:-accent}

  if _ui_plain_mode; then
    print -nr -- "[$label]"
    return 0
  fi

  _ui_color "$role"
  print -nr -- '['
  _ui_reset
  print -nr -- "$label"
  _ui_color "$role"
  print -nr -- ']'
  _ui_reset
}

_ui_bold() {
  _ui_is_rich_terminal && printf '\033[1m'
}

_ui_title_line() {
  emulate -L zsh

  local title=$1
  local meta=${2:-}
  local role=${3:-accent}
  local icon=${4:-}
  local fallback=${5:-*}

  if _ui_plain_mode; then
    if [ -n "$meta" ]; then
      print -r -- "$title - $meta"
    else
      print -r -- "$title"
    fi
    return 0
  fi

  print ''
  if [ -n "$icon" ]; then
    _ui_color "$role"
    _ui_icon "$icon" "$fallback"
    _ui_reset
    print -nr -- ' '
  fi
  _ui_color "$role"
  _ui_bold
  print -nr -- "$title"
  _ui_reset
  if [ -n "$meta" ]; then
    print -nr -- '  '
    _ui_color muted
    print -nr -- "$meta"
    _ui_reset
  fi
  print ''
}

_ui_section_break() {
  emulate -L zsh

  local width fill='─' lead='─ '

  if _ui_plain_mode; then
    return 0
  fi

  width=$(( $(_ui_term_width) - 2 ))
  (( width < 32 )) && width=32

  if _ui_ascii_mode; then
    fill='-'
    lead='- '
  fi

  print ''
  _ui_color border
  print -nr -- "$lead"
  _ui_repeat "$width" "$fill"
  _ui_reset
  print ''
}

_ui_panel_header() {
  emulate -L zsh

  local title=$1
  local meta=${2:-}
  local role=${3:-accent}
  local lead='╭─ '

  if _ui_plain_mode; then
    if [ -n "$meta" ]; then
      print -r -- "$title - $meta"
    else
      print -r -- "$title"
    fi
    return 0
  fi

  if _ui_ascii_mode; then
    lead='+- '
  fi

  _ui_color "$role"
  print -nr -- "$lead"
  _ui_reset
  print -nr -- "$title"
  if [ -n "$meta" ]; then
    print -nr -- ' '
    _ui_color muted
    print -nr -- "$meta"
    _ui_reset
  fi
  print ''
}

_ui_panel_prefix() {
  emulate -L zsh

  if _ui_plain_mode; then
    return 0
  fi

  _ui_color border
  if _ui_ascii_mode; then
    print -nr -- '| '
  else
    print -nr -- '│ '
  fi
  _ui_reset
}

_ui_panel_divider() {
  emulate -L zsh

  local width
  local lead='├'
  local fill='─'

  if _ui_plain_mode; then
    return 0
  fi

  width=$(( $(_ui_term_width) - 3 ))
  (( width < 8 )) && width=8

  if _ui_ascii_mode; then
    lead='|-'
    fill='-'
  fi

  _ui_color border
  print -nr -- "$lead"
  _ui_repeat "$width" "$fill"
  _ui_reset
  print ''
}

_ui_panel_footer() {
  emulate -L zsh

  local text=${1:-}
  local role=${2:-accent}
  local lead='╰─ '

  if _ui_plain_mode; then
    [ -n "$text" ] && print -r -- "$text"
    return 0
  fi

  if _ui_ascii_mode; then
    lead='+- '
  fi

  _ui_color "$role"
  print -nr -- "$lead"
  _ui_reset
  [ -n "$text" ] && print -nr -- "$text"
  print ''
}

_ui_panel_kv() {
  emulate -L zsh

  local label=$1
  local value=$2
  local label_role=${3:-muted}
  local value_role=${4:-text}

  if _ui_plain_mode; then
    print -r -- "$label: $value"
    return 0
  fi

  _ui_panel_prefix
  _ui_color "$label_role"
  print -nr -- "$label"
  _ui_reset
  print -nr -- ': '
  _ui_color "$value_role"
  print -nr -- "$value"
  _ui_reset
  print ''
}

_ui_visible_count() {
  emulate -L zsh

  integer requested=$1
  integer total=$2
  integer reserve=${3:-6}
  integer height=$(_ui_term_height)
  integer available=$(( height - reserve ))

  (( available < 1 )) && available=1
  (( requested > total )) && requested=$total
  (( requested > available )) && requested=$available
  (( requested < 0 )) && requested=0

  print -r -- "$requested"
}
