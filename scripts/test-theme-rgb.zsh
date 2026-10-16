#!/usr/bin/env zsh
emulate -L zsh
setopt NO_UNSET
repo_dir=${0:A:h:h}
source "$repo_dir/25-theme.zsh"
source "$repo_dir/lib/theme-color.zsh"
# Frozen pre-C07b strict-search reference; keep independent of production math.
_reference_rgb_to_256() {
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

integer checks=0 expected_status actual_status
local_hex=''
check_rgb() {
  local hex=$1 expected actual
  REPLY=sentinel; reply=(sentinel)
  _reference_rgb_to_256 "$hex"
  expected_status=$?
  expected="$REPLY|${(j:,:)reply}"
  REPLY=sentinel; reply=(sentinel)
  _zsh_theme_rgb_to_256 "$hex"
  actual_status=$?
  actual="$REPLY|${(j:,:)reply}"
  [[ $actual_status == $expected_status && $actual == "$expected" ]] || {
    print -u2 -r -- "not ok: RGB $hex expected $expected_status/$expected got $actual_status/$actual"
    exit 1
  }
  (( checks++ ))
}
# Every channel value on gray and near-gray diagonals, including ramp ties.
integer r g b offset
for ((r=0;r<256;r++)); do
  for offset in -1 0 1; do
    ((g=r+offset, b=r-offset))
    ((g>=0 && g<=255 && b>=0 && b<=255)) || continue
    printf -v local_hex '%02x%02x%02x' $r $g $b
    check_rgb "$local_hex"
  done
done
# Cartesian boundary grid spans every cube decision boundary on every axis.
local -a boundaries=(0 47 48 95 115 116 155 156 195 196 235 236 255)
for r in $boundaries; do
  for g in $boundaries; do
    for b in $boundaries; do
      printf -v local_hex '%02x%02x%02x' $r $g $b
      check_rgb "$local_hex"
    done
  done
done
for theme in catppuccin-mocha catppuccin-latte nord gruvbox-dark; do
  for role in "${_ZSH_UI_THEME_ROLES[@]}"; do
    _zsh_theme_role_hex "$theme" "$role" || exit 1
    local_hex=$REPLY
    check_rgb "$local_hex"
    check_rgb "${(U)local_hex}"
  done
done
for local_hex in '' 00000 0000000 xyzxyz '#abcdef' abcdeg; do check_rgb "$local_hex"; done
print -r -- "ok: $checks production RGB comparisons preserve status, REPLY, reply, strict ties and validation"
