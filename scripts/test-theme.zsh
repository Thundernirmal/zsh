#!/usr/bin/env zsh

set -u

typeset -r repo_dir=${0:A:h:h}
typeset -r zsh_bin=${commands[zsh]}
typeset test_tmp
test_tmp=$(mktemp -d) || exit 1
trap 'command rm -rf -- "$test_tmp"' EXIT INT TERM

assert_equals() {
  local actual=$1 expected=$2 label=$3
  if [[ $actual != "$expected" ]]; then
    print -u2 -r -- "not ok: $label"
    print -u2 -r -- "expected: $expected"
    print -u2 -r -- "actual:   $actual"
    return 1
  fi
  print -r -- "ok: $label"
}

assert_status() {
  local actual=$1 expected=$2 label=$3
  assert_equals "$actual" "$expected" "$label"
}

run_theme_case() {
  local setup=$1 body=$2
  local command_text
  command_text=$setup$'\n'
  command_text+="source ${(q)repo_dir}/25-theme.zsh"$'\n'
  command_text+=$body
  NO_COLOR= TERM=xterm-256color COLORTERM=truecolor LANG=en_US.UTF-8 \
    "$zsh_bin" -dfc "$command_text"
}

test_defaults_and_builtins() {
  local output
  output=$(run_theme_case '' '
print -r -- "$ZSH_UI_THEME|$ZSH_FZF_THEME|$_ZSH_UI_ACTIVE_THEME|$_ZSH_FZF_ACTIVE_THEME|$_ZSH_UI_COLOR_DEPTH|$_ZSH_UI_GLYPH_TIER"
print -r -- "themes=${#_ZSH_UI_THEME_NAMES} roles=${#_ZSH_UI_THEME_ROLES} colors=${#_ZSH_THEME_COLORS}"
for theme in catppuccin-mocha catppuccin-latte nord gruvbox-dark; do
  for role in "${_ZSH_UI_THEME_ROLES[@]}"; do
    _zsh_theme_role_hex "$theme" "$role" || exit 11
    _zsh_theme_validate_hex "$REPLY" || exit 12
  done
done')
  assert_status "$?" 0 'every fixed built-in defines valid RGB values' || return 1
  assert_equals "${${(f)output}[1]}" 'catppuccin-mocha||catppuccin-mocha|catppuccin-mocha|truecolor|nerd' 'defaults resolve to Mocha, truecolor, and Nerd glyphs' || return 1
  assert_equals "${${(f)output}[2]}" 'themes=5 roles=15 colors=60' 'registry exposes five themes and fifteen semantic roles' || return 1
}

test_color_resolution() {
  local output
  output=$(run_theme_case '' '
_zsh_theme_color_value accent ui truecolor; print -r -- "$REPLY"
_zsh_theme_color_value accent ui 256; print -r -- "$REPLY"
_zsh_theme_color_value danger ui ansi; print -r -- "$REPLY"
_zsh_theme_sgr accent fg; print -r -- "${(V)REPLY}"
_zsh_theme_signature; print -r -- "$REPLY"')
  assert_equals "$output" $'#cba6f7\n183\n9\n^[[38;2;203;166;247m\ncatppuccin-mocha:catppuccin-mocha:truecolor:nerd:compact:' 'theme APIs resolve deterministic RGB, 256, ANSI, SGR, and signature values' || return 1

  output=$(run_theme_case 'typeset -g ZSH_UI_THEME=terminal' '
_zsh_theme_color_value base ui truecolor; print -r -- "$REPLY"
_zsh_theme_color_value accent ui truecolor; print -r -- "$REPLY"
_zsh_theme_sgr accent fg; print -r -- "${(V)REPLY}"')
  assert_equals "$output" $'-1\n5\n^[[35m' 'terminal theme uses terminal defaults and ANSI accents at every detected depth' || return 1
}

test_custom_palette() {
  local output
  local custom_setup='typeset -gA ZSH_UI_CUSTOM_COLORS=(
    base 101010 surface 202020 selected 303030 border 404040 gutter 101010
    text F0F0F0 muted A0A0A0 accent AA00FF query 00FF00 match FF0055
    focus FFFFFF info 0088FF success 00FF00 warning FFCC00 danger FF0055
  )
  typeset -g ZSH_UI_THEME=custom'
  output=$(run_theme_case "$custom_setup" '
_zsh_theme_role_hex custom accent; print -r -- "$ZSH_UI_THEME|$_ZSH_UI_ACTIVE_THEME|$REPLY|${#_ZSH_THEME_CUSTOM_COLORS}"')
  assert_equals "$output" 'custom|custom|aa00ff|15' 'valid custom palette is copied and normalized atomically' || return 1

  output=$(run_theme_case 'typeset -gA ZSH_UI_CUSTOM_COLORS=(base 101010); typeset -g ZSH_UI_THEME=custom' '
print -r -- "$ZSH_UI_THEME|$_ZSH_UI_ACTIVE_THEME|${(j:,:)_ZSH_THEME_RESOLUTION_ISSUES}"')
  assert_equals "$output" 'catppuccin-mocha|catppuccin-mocha|invalid custom UI palette' 'incomplete custom palette falls back atomically' || return 1

  output=$(run_theme_case "${custom_setup/AA00FF/not-a-color}" '
print -r -- "$ZSH_UI_THEME|${(j:,:)_ZSH_THEME_RESOLUTION_ISSUES}"')
  assert_equals "$output" 'catppuccin-mocha|invalid custom UI palette' 'malformed custom values are rejected' || return 1
}

test_fallbacks_and_modes() {
  local output
  output=$(run_theme_case 'typeset -g ZSH_UI_THEME=unknown; typeset -g ZSH_FZF_THEME=also-unknown; typeset -g ZSH_FZF_LAYOUT=huge; typeset -g ZSH_UI_GLYPHS=emoji' '
print -r -- "$ZSH_UI_THEME|$ZSH_FZF_THEME|$ZSH_FZF_LAYOUT|$ZSH_UI_GLYPHS|$_ZSH_UI_GLYPH_TIER|${#_ZSH_THEME_RESOLUTION_ISSUES}"')
  assert_equals "$output" 'catppuccin-mocha|catppuccin-mocha|compact|auto|nerd|4' 'unknown public settings fall back without partial application' || return 1

  output=$(NO_COLOR=1 NO_NERD_FONT=1 TERM=xterm-256color COLORTERM=truecolor LANG=en_US.UTF-8 \
    "$zsh_bin" -dfc "source ${(q)repo_dir}/25-theme.zsh; print -r -- \"\$_ZSH_UI_COLOR_DEPTH|\$_ZSH_UI_GLYPH_TIER\"")
  assert_equals "$output" 'none|unicode' 'NO_COLOR and NO_NERD_FONT resolve independently' || return 1

  output=$(NO_COLOR= TERM=xterm-256color COLORTERM= LC_ALL=C LC_CTYPE=C LANG=C \
    "$zsh_bin" -dfc "source ${(q)repo_dir}/25-theme.zsh; print -r -- \"\$_ZSH_UI_COLOR_DEPTH|\$_ZSH_UI_GLYPH_TIER\"")
  assert_equals "$output" '256|ascii' 'non-UTF-8 locales select ASCII without changing color depth' || return 1

  output=$(run_theme_case 'typeset -g ZSH_UI_GLYPHS=ascii' '
typeset glyphs=""
for key in pointer marker gutter scrollbar separator wrap; do
  _zsh_theme_glyph "$key" || exit 13
  glyphs+="$REPLY,"
done
print -r -- "$glyphs"')
  assert_equals "$output" '>,+,|,|,-,>,' 'ASCII glyph mode contains only the frozen ASCII symbols' || return 1
}

test_idempotence_and_safety() {
  local output marker="$test_tmp/executed"
  output=$(run_theme_case "typeset -g ZSH_UI_THEME='\$(touch ${(q)marker})'" '
_zsh_theme_signature; first=$REPLY
source '"${repo_dir}"'/25-theme.zsh
_zsh_theme_signature; print -r -- "$first|$REPLY|${#_ZSH_UI_THEME_NAMES}|${#_ZSH_THEME_COLORS}"')
  assert_equals "$output" 'catppuccin-mocha:catppuccin-mocha:truecolor:nerd:compact:|catppuccin-mocha:catppuccin-mocha:truecolor:nerd:compact:|5|60' 're-sourcing is idempotent after an unsafe theme name fallback' || return 1
  [[ ! -e $marker ]]
  assert_status "$?" 0 'theme names are data and cannot execute shell syntax' || return 1

  local fakebin="$test_tmp/fakebin" invocation_log="$test_tmp/invocations"
  command mkdir -p -- "$fakebin"
  local tool
  for tool in fzf tput jq python python3 zoxide; do
    print -r -- '#!/bin/sh
printf "%s\n" "$0 $*" >> "$THEME_TEST_INVOCATIONS"
exit 99' > "$fakebin/$tool"
    command chmod +x -- "$fakebin/$tool"
  done
  PATH="$fakebin" THEME_TEST_INVOCATIONS="$invocation_log" NO_COLOR= TERM=xterm-256color COLORTERM=truecolor LANG=en_US.UTF-8 \
    "$zsh_bin" -dfc "source ${(q)repo_dir}/25-theme.zsh" || return 1
  [[ ! -s $invocation_log ]]
  assert_status "$?" 0 'theme module sourcing invokes no external tools' || return 1
}

main() {
  test_defaults_and_builtins || return 1
  test_color_resolution || return 1
  test_custom_palette || return 1
  test_fallbacks_and_modes || return 1
  test_idempotence_and_safety || return 1
}

main
