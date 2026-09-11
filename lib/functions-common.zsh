# Trusted lazy common implementations; loaded by functions-catalogue.zsh.

_zsh_require_fzf() {
  if (( ! $+functions[_fzf_require_ready] )); then
    print -u2 -r -- 'zsh config: fzf 0.68.0 or newer is required (found: configuration guard unavailable). Upgrade fzf and restart the shell.'
    return 1
  fi
  _fzf_require_ready
}

_ui_usage_entry_icon() {
  local target=$1

  if [ -L "$target" ]; then
    _ui_icon '󰌷' '@'
  elif [ -d "$target" ]; then
    _ui_icon '󰉋' '/'
  else
    _ui_icon '󰈔' '-'
  fi
}

_ui_safe_text_reply() {
  emulate -L zsh
  setopt MULTIBYTE

  local value=$1
  local char escaped output=''
  integer index code

  for (( index = 1; index <= ${#value}; index++ )); do
    char=${value[$index]}

    case $char in
      $'\n') output+='\n' ;;
      $'\r') output+='\r' ;;
      $'\t') output+='\t' ;;
      $'\e') output+='\e' ;;
      $'\a') output+='\a' ;;
      $'\b') output+='\b' ;;
      $'\f') output+='\f' ;;
      $'\v') output+='\v' ;;
      *)
        printf -v code '%d' "'$char"
        if (( code < 32 || code == 127 || (code >= 128 && code <= 159) )); then
          printf -v escaped '\\x%02x' "$code"
          output+=$escaped
        else
          output+=$char
        fi
        ;;
    esac
  done

  REPLY=$output
}

_ui_safe_text() {
  _ui_safe_text_reply "$@"
  print -r -- "$REPLY"
}

_ui_safe_truncate() {
  emulate -L zsh

  local width=$1
  shift

  local text="$*"
  local marker='…'
  local token pair quad prefix='' suffix=''
  local -a tokens
  integer index left right token_width prefix_width suffix_width text_width marker_width
  integer have_display_width=$(( $+functions[_ui_display_width] ))

  (( width > 0 )) || {
    print -r -- ''
    return 0
  }

  if _ui_ascii_mode; then
    marker='...'
  fi

  if (( have_display_width )); then
    _ui_display_width "$text"
    text_width=$REPLY
    _ui_display_width "$marker"
    marker_width=$REPLY
  else
    text_width=${#text}
    marker_width=${#marker}
  fi

  if (( text_width <= width )); then
    print -r -- "$text"
    return 0
  fi

  if (( width <= marker_width )); then
    print -r -- "${marker[1,width]}"
    return 0
  fi

  for (( index = 1; index <= ${#text}; index++ )); do
    token=${text[$index]}

    if [[ $token == $'\\' ]]; then
      pair=${text[$index,$(( index + 1 ))]}
      quad=${text[$index,$(( index + 3 ))]}

      if [[ $quad == \\x[0-9a-fA-F][0-9a-fA-F] ]]; then
        token=$quad
        (( index += 3 ))
      else
        case $pair in
          '\n'|'\r'|'\t'|'\e'|'\a'|'\b'|'\f'|'\v')
            token=$pair
            (( index++ ))
            ;;
        esac
      fi
    fi

    tokens+=("$token")
  done

  left=$(( (width - marker_width) / 2 ))
  right=$(( width - marker_width - left ))

  prefix_width=0
  for token in "${tokens[@]}"; do
    if (( have_display_width )); then
      _ui_display_width "$token"
      token_width=$REPLY
    else
      token_width=${#token}
    fi
    (( prefix_width + token_width <= left )) || break
    prefix+=$token
    (( prefix_width += token_width ))
  done

  suffix_width=0
  for (( index = ${#tokens[@]}; index >= 1; index-- )); do
    token=${tokens[$index]}
    if (( have_display_width )); then
      _ui_display_width "$token"
      token_width=$REPLY
    else
      token_width=${#token}
    fi
    (( suffix_width + token_width <= right )) || break
    suffix="${token}${suffix}"
    (( suffix_width += token_width ))
  done

  if (( $+functions[_ui_strip_leading_marks_reply] )); then
    _ui_strip_leading_marks_reply "$suffix"
    suffix=$REPLY
  fi
  print -r -- "${prefix}${marker}${suffix}"
}

_ui_profile_role() {
  case $1 in
    silent|quiet|low-power) print -r -- 'success' ;;
    balanced|balanced-performance|cool|normal) print -r -- 'info' ;;
    performance|overboost|turbo) print -r -- 'danger' ;;
    *) print -r -- 'accent' ;;
  esac
}

# Minimal fallbacks when UI helpers are unavailable so functions degrade to plain output.
if ! (( $+functions[_ui_plain_mode] )); then
  _ui_plain_mode() { return 0; }
fi
if ! (( $+functions[_ui_ascii_mode] )); then
  _ui_ascii_mode() { return 0; }
fi
if ! (( $+functions[_ui_term_width] )); then
  _ui_term_width() { print -r -- 80; }
fi
if ! (( $+functions[_ui_repeat] )); then
  _ui_repeat() {
    emulate -L zsh
    local count=${1:-0} chunk=${2:- }
    local out=''
    integer i

    (( count > 0 )) || return 0

    for (( i = 0; i < count; i++ )); do
      out+="$chunk"
    done

    print -nr -- "$out"
  }
fi
if ! (( $+functions[_ui_color] )); then
  _ui_color() { :; }
fi
if ! (( $+functions[_ui_reset] )); then
  _ui_reset() { :; }
fi
if ! (( $+functions[_ui_bold] )); then
  _ui_bold() { :; }
fi
if ! (( $+functions[_ui_icon] )); then
  _ui_icon() {
    emulate -L zsh
    print -nr -- "${2:-*}"
  }
fi
if ! (( $+functions[_ui_title_line] )); then
  _ui_title_line() {
    emulate -L zsh
    local title=$1 meta=${2:-}
    if [ -n "$meta" ]; then
      print -r -- "$title - $meta"
    else
      print -r -- "$title"
    fi
  }
fi
if ! (( $+functions[_ui_section_break] )); then
  _ui_section_break() { :; }
fi
if ! (( $+functions[_ui_panel_prefix] )); then
  _ui_panel_prefix() { :; }
fi
if ! (( $+functions[_ui_panel_kv] )); then
  _ui_panel_kv() {
    emulate -L zsh
    print -r -- "$1: $2"
  }
fi
if ! (( $+functions[_ui_badge] )); then
  _ui_badge() {
    emulate -L zsh
    print -nr -- "[$1]"
  }
fi
if ! (( $+functions[_ui_human_kib] )); then
  _ui_human_kib() {
    emulate -L zsh
    print -r -- "$1 KiB"
  }
fi
if ! (( $+functions[_ui_usage_entry_icon] )); then
  _ui_usage_entry_icon() {
    emulate -L zsh
    print -nr -- '*'
  }
fi
if ! (( $+functions[_ui_truncate] )); then
  _ui_truncate() {
    emulate -L zsh
    shift
    print -r -- "$*"
  }
fi
if ! (( $+functions[_ui_pad] )); then
  _ui_pad() {
    emulate -L zsh
    local align=$1 width=$2
    shift 2
    if [ "$align" = 'right' ]; then
      printf '%*s' "$width" "$*"
    else
      printf '%-*s' "$width" "$*"
    fi
  }
fi
if ! (( $+functions[_ui_pad_reply] )); then
  _ui_pad_reply() {
    emulate -L zsh
    local align=$1 width=$2
    shift 2
    if [ "$align" = 'right' ]; then
      printf -v REPLY '%*s' "$width" "$*"
    else
      printf -v REPLY '%-*s' "$width" "$*"
    fi
  }
fi
if ! (( $+functions[_ui_bar] )); then
  _ui_bar() { :; }
fi
if ! (( $+functions[_ui_visible_count] )); then
  _ui_visible_count() {
    emulate -L zsh
    integer requested=$1 total=$2 reserve=${3:-6} height available

    if (( $+functions[_ui_term_height] )); then
      height=$(_ui_term_height)
    else
      height=${LINES:-24}
      case $height in
        ''|*[!0-9]*) height=24 ;;
      esac
    fi
    available=$(( height - reserve ))

    (( available < 1 )) && available=1
    (( requested > total )) && requested=$total
    (( requested > available )) && requested=$available
    (( requested < 0 )) && requested=0
    print -r -- "$requested"
  }
fi

