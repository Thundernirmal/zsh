# Shared terminal UI helpers.
typeset -g _ZSH_UI_HELPERS_DIR=${${(%):-%N}:A:h}

if (( ! $+functions[_zsh_theme_sgr] )); then
  typeset _ui_theme_module=${${(%):-%x}:A:h}/25-theme.zsh
  [[ -r $_ui_theme_module ]] && source "$_ui_theme_module"
  unset _ui_theme_module
fi

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

  if (( $+functions[_zsh_theme_locale_is_utf8] )); then
    _zsh_theme_locale_is_utf8
    return
  fi

  local locale=${(L)${LC_ALL:-${LC_CTYPE:-${LANG:-}}}}
  [[ $locale == *utf-8* || $locale == *utf8* ]]
}

_ui_is_rich_terminal() {
  emulate -L zsh

  local width

  [[ -t 1 ]] || return 1
  [[ -n ${TERM:-} ]] || return 1
  [[ ${TERM} != dumb ]] || return 1
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

  [[ ${_ZSH_UI_GLYPH_TIER:-ascii} == ascii ]]
}

_ui_color() {
  emulate -L zsh

  local role=$1
  local layer=${2:-fg}

  _ui_is_rich_terminal || return 0
  (( $+functions[_zsh_theme_sgr] )) || return 0
  _zsh_theme_sgr "$role" "$layer" ui || return 0
  print -nr -- "$REPLY"
}

_ui_reset() {
  _ui_is_rich_terminal && printf '\033[0m'
}

_ui_unicode_icon() {
  local glyph=$1 fallback=$2

  case $glyph in
    '󰄬') REPLY='✓' ;;
    '󰚰') REPLY='↑' ;;
    '󰍉') REPLY='⌕' ;;
    '󰋼'|'󰘥'|'󰍹') REPLY='›' ;;
    '󰀦') REPLY='!' ;;
    '󰍛') REPLY='−' ;;
    '󰅚') REPLY='×' ;;
    '󰒭') REPLY='~' ;;
    '󰏖'|'󰈔'|'󰈐'|'') REPLY='◇' ;;
    '󰮯'|'󰣇') REPLY='△' ;;
    '󰂚') REPLY='●' ;;
    '󱄅') REPLY='❄' ;;
    '󰌷') REPLY='↗' ;;
    '󰉋') REPLY='▣' ;;
    '󰔟') REPLY='◌' ;;
    *) REPLY=$fallback ;;
  esac
}

_ui_icon() {
  emulate -L zsh

  local glyph=$1
  local fallback=$2
  local unicode=${3:-}

  if _ui_plain_mode || [[ ${_ZSH_UI_GLYPH_TIER:-ascii} == ascii ]]; then
    print -nr -- "$fallback"
    return
  fi

  if [[ ${_ZSH_UI_GLYPH_TIER:-ascii} == nerd ]]; then
    print -nr -- "$glyph"
    return
  fi

  if [[ -z $unicode ]]; then
    _ui_unicode_icon "$glyph" "$fallback"
    unicode=$REPLY
  fi
  print -nr -- "$unicode"
}

_ui_status_metadata() {
  emulate -L zsh

  case $1 in
    'up to date'|upgraded) print -r -- $'success\tok\tpackage\t󰄬\t*' ;;
    cleaned)               print -r -- $'success\tcleaned\tcleanup\t󰄬\t*' ;;
    'updates available')   print -r -- $'warning\tupdates\tpackage\t󰚰\t!' ;;
    'matches found')       print -r -- $'info\tmatches\tsearch\t󰍉\t?' ;;
    'no matches')          print -r -- $'muted\tempty\tsearch\t󰍉\t0' ;;
    planned)               print -r -- $'info\tplanned\tcleanup\t󰋼\t>' ;;
    partial)               print -r -- $'danger\tpartial\tcleanup\t󰀦\t!' ;;
    blocked)               print -r -- $'warning\tblocked\tneutral\t󰍛\t-' ;;
    failed)                print -r -- $'danger\tfailed\tneutral\t󰅚\tx' ;;
    skipped)               print -r -- $'muted\tskipped\tneutral\t󰒭\t~' ;;
    *)                     print -r -- $'accent\tother\tneutral\t󰘥\t>' ;;
  esac
}

_ui_status_icon() {
  emulate -L zsh

  local role bucket family glyph fallback

  IFS=$'\t' read -r role bucket family glyph fallback <<< "$(_ui_status_metadata "$1")"
  _ui_icon "$glyph" "$fallback"
}

_ui_manager_icon() {
  emulate -L zsh

  case $1 in
    apt) _ui_icon '󰏖' '*' ;;
    dnf) _ui_icon '󰏖' '*' ;;
    pacman) _ui_icon '󰮯' '*' ;;
    paru) _ui_icon '󰣇' '*' ;;
    brew) _ui_icon '󰂚' '*' ;;
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

# Terminal cells for one sanitized code point. Binary search over committed
# Unicode intervals stays pure Zsh and covers combining scripts beyond Latin.
_ui_char_width() {
  emulate -L zsh
  integer code=$1 low high middle
  if (( code < 128 )); then
    REPLY=1
    return 0
  fi
  if (( ! ${_ZSH_UI_WIDTH_DATA_LOADED:-0} )); then
    source "$_ZSH_UI_HELPERS_DIR/lib/ui-width-data.zsh" || return 1
  fi
  low=1
  high=${#_ZSH_UI_ZERO_START}
  while (( low <= high )); do
    middle=$(( (low + high) / 2 ))
    if (( code < _ZSH_UI_ZERO_START[middle] )); then
      high=$(( middle - 1 ))
    elif (( code > _ZSH_UI_ZERO_END[middle] )); then
      low=$(( middle + 1 ))
    else
      REPLY=0
      return 0
    fi
  done
  low=1
  high=${#_ZSH_UI_WIDE_START}
  while (( low <= high )); do
    middle=$(( (low + high) / 2 ))
    if (( code < _ZSH_UI_WIDE_START[middle] )); then
      high=$(( middle - 1 ))
    elif (( code > _ZSH_UI_WIDE_END[middle] )); then
      low=$(( middle + 1 ))
    else
      REPLY=2
      return 0
    fi
  done
  REPLY=1
}

# Terminal-cell width of already-sanitized text. Visible escapes are plain
# ASCII, so they measure one cell per character; wide characters measure two
# and combining marks zero. Pure Zsh, no subprocesses.
_ui_display_width() {
  emulate -L zsh
  setopt MULTIBYTE

  local text=$1 char
  local non_ascii_pattern='*[^ -~]*'
  integer index code width=0

  if [[ $text != ${~non_ascii_pattern} ]]; then
    REPLY=${#text}
    return 0
  fi

  for (( index = 1; index <= ${#text}; index++ )); do
    char=${text[$index]}
    printf -v code '%d' "'$char"
    _ui_char_width $code
    (( width += REPLY ))
  done
  REPLY=$width
}

_ui_strip_leading_marks_reply() {
  emulate -L zsh
  setopt MULTIBYTE
  local text=$1 char
  integer code
  while [[ -n $text ]]; do
    char=$text[1]
    printf -v code '%d' "'$char"
    _ui_char_width $code
    (( REPLY == 0 )) || break
    text=${text[2,-1]}
  done
  REPLY=$text
}

_ui_truncate_reply() {
  emulate -L zsh
  setopt MULTIBYTE

  local width=$1
  shift

  local text="$*"
  local marker='…'
  local char prefix='' suffix=''
  integer index code char_width text_width marker_width left right prefix_width suffix_width

  (( width > 0 )) || {
    REPLY=''
    return 0
  }

  if _ui_ascii_mode; then
    marker='...'
  fi

  _ui_display_width "$text"
  text_width=$REPLY
  if (( text_width <= width )); then
    REPLY=$text
    return 0
  fi

  _ui_display_width "$marker"
  marker_width=$REPLY
  if (( width <= marker_width + 1 )); then
    prefix=''
    prefix_width=0
    for (( index = 1; index <= ${#text}; index++ )); do
      char=${text[$index]}
      printf -v code '%d' "'$char"
      _ui_char_width $code
      char_width=$REPLY
      (( prefix_width + char_width > width )) && break
      prefix+=$char
      (( prefix_width += char_width ))
    done
    REPLY=$prefix
    return 0
  fi

  left=$(( (width - marker_width) / 2 ))
  right=$(( width - marker_width - left ))

  prefix=''
  prefix_width=0
  for (( index = 1; index <= ${#text}; index++ )); do
    char=${text[$index]}
    printf -v code '%d' "'$char"
    _ui_char_width $code
    char_width=$REPLY
    (( prefix_width + char_width > left )) && break
    prefix+=$char
    (( prefix_width += char_width ))
  done

  suffix=''
  suffix_width=0
  for (( index = ${#text}; index >= 1; index-- )); do
    char=${text[$index]}
    printf -v code '%d' "'$char"
    _ui_char_width $code
    char_width=$REPLY
    (( suffix_width + char_width > right )) && break
    suffix="${char}${suffix}"
    (( suffix_width += char_width ))
  done

  # A suffix must not attach a discarded base character's combining marks
  # to the ellipsis. Keep complete base-plus-mark sequences at the cut.
  _ui_strip_leading_marks_reply "$suffix"
  REPLY="${prefix}${marker}${REPLY}"
}

_ui_truncate() {
  _ui_truncate_reply "$@"
  print -r -- "$REPLY"
}

_ui_pad_reply() {
  emulate -L zsh

  # 'right' = right-align text (leading spaces); 'left' = left-align (trailing spaces)
  local align=$1
  local width=$2
  shift 2

  _ui_truncate_reply "$width" "$*"
  local text=$REPLY
  local text_width
  integer padding_width

  _ui_display_width "$text"
  text_width=$REPLY
  padding_width=$(( width - text_width ))

  (( padding_width < 0 )) && padding_width=0

  if [[ $align == right ]]; then
    printf -v REPLY '%*s%s' "$padding_width" '' "$text"
  else
    printf -v REPLY '%s%*s' "$text" "$padding_width" ''
  fi
}

_ui_pad() {
  _ui_pad_reply "$@"
  print -nr -- "$REPLY"
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
