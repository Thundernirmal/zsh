# Lazily loaded color conversion and SGR helpers.

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

_zsh_theme_sgr_for_theme() {
  emulate -L zsh

  local theme=$1 role=$2 layer=${3:-fg} depth=${4:-${_ZSH_UI_COLOR_DEPTH:-ansi}}
  local value hex
  integer base=38 code

  [[ $layer == fg || $layer == bg ]] || return 1
  [[ $layer == bg ]] && base=48
  [[ $depth != none ]] || { REPLY=''; return 1; }
  [[ $theme == terminal && $depth != none ]] && depth=ansi

  case $depth in
    truecolor)
      _zsh_theme_role_hex "$theme" "$role" || return 1
      hex=$REPLY
      _zsh_theme_rgb_components "$hex" || return 1
      REPLY=$'\e'"[${base};2;${reply[1]};${reply[2]};${reply[3]}m"
      return 0
      ;;
    256)
      _zsh_theme_role_hex "$theme" "$role" || return 1
      _zsh_theme_rgb_to_256 "$REPLY" || return 1
      REPLY=$'\e'"[${base};5;${REPLY}m"
      return 0
      ;;
    ansi)
      _zsh_theme_ansi_code "$theme" "$role" || return 1
      value=$REPLY
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

_zsh_theme_sgr() {
  emulate -L zsh

  local role=$1 layer=${2:-fg} scope=${3:-ui} theme
  _zsh_theme_scope_name "$scope" || return 1
  theme=$REPLY
  _zsh_theme_sgr_for_theme "$theme" "$role" "$layer" "${_ZSH_UI_COLOR_DEPTH:-ansi}"
}
