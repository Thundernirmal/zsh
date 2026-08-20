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
done
print -r -- "loaded=$_ZSH_THEME_BUILTIN_PALETTES_LOADED colors=${#_ZSH_THEME_COLORS}"')
  assert_status "$?" 0 'every fixed built-in defines valid RGB values' || return 1
  assert_equals "${${(f)output}[1]}" 'catppuccin-mocha||catppuccin-mocha|catppuccin-mocha|truecolor|nerd' 'defaults resolve to Mocha, truecolor, and Nerd glyphs' || return 1
  assert_equals "${${(f)output}[2]}" 'themes=5 roles=15 colors=0' 'startup defers fixed palette data until a color is requested' || return 1
  assert_equals "${${(f)output}[3]}" 'loaded=1 colors=60' 'first fixed-color lookup loads every built-in palette' || return 1
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

test_dashboard_renderer() {
  local output
  output=$(run_theme_case '' '
source '"${repo_dir}"'/55-ui-helpers.zsh
functions[_ui_is_rich_terminal]="return 0"
mocha=$(_ui_color accent)
ZSH_UI_THEME=nord
_zsh_theme_resolve_settings
nord=$(_ui_color accent)
print -r -- "${(V)mocha}|${(V)nord}|${+functions[_ui_palette_hex]}|${+functions[_ui_palette_256]}"')
  assert_equals "$output" '^[[38;2;203;166;247m|^[[38;2;180;142;173m|0|0' 'dashboard colors follow the active semantic theme without private palettes' || return 1

  output=$(run_theme_case 'typeset -g ZSH_UI_GLYPHS=unicode' '
source '"${repo_dir}"'/55-ui-helpers.zsh
functions[_ui_is_rich_terminal]="return 0"
icon=$(_ui_icon "󰄬" "*")
_ui_ascii_mode; ascii_rc=$?
print -r -- "$icon|$ascii_rc|$_ZSH_UI_GLYPH_TIER"')
  assert_equals "$output" '✓|1|unicode' 'Unicode mode uses ordinary Unicode rather than Nerd or ASCII glyphs' || return 1

  output=$(run_theme_case 'typeset -g ZSH_UI_GLYPHS=nerd' '
source '"${repo_dir}"'/55-ui-helpers.zsh
functions[_ui_is_rich_terminal]="return 1"
color=$(_ui_color danger)
icon=$(_ui_icon "󰅚" "x")
print -r -- "${#color}|$icon"')
  assert_equals "$output" '0|x' 'plain dashboard mode remains colorless and ASCII-safe' || return 1
}

test_fzf_compiler() {
  local output
  output=$(run_theme_case '' '
for layout in compact roomy minimal; do
  ZSH_FZF_LAYOUT=$layout
  _zsh_theme_resolve_settings
  _zsh_theme_fzf_chrome_args || exit 15
  _zsh_theme_join_shell_args "${reply[@]}"
  [[ $REPLY == *current-bg* && $REPLY == *selected-bg* && $REPLY == *input-bg:\#1e1e2e* && $REPLY == *footer-bg:\#1e1e2e* && $REPLY != *input-bg:\#313244* && $REPLY != *footer-bg:\#313244* && $REPLY == *footer-border* && $REPLY == *ghost* && $REPLY == *gutter* ]] || exit 16
  [[ $REPLY == *--border=rounded* && $REPLY == *--list-border=none* && $REPLY == *--input-border=bottom* && $REPLY == *--header-border=bottom* && $REPLY == *--footer-border=top* ]] || exit 20
  [[ $REPLY != *--style=full:line* && $REPLY != *--style=full:rounded* ]] || exit 21
  [[ $REPLY != *--separator=* ]] || exit 22
  print -r -- "$layout:${#reply}:${reply[3]}:${reply[5]}"
done
NO_COLOR=1
_zsh_theme_detect_color_depth; _ZSH_UI_COLOR_DEPTH=$REPLY
_zsh_theme_fzf_color_args || exit 17
print -r -- "nocolor=${(j:,:)reply}"')
  assert_equals "$output" $'compact:20:--style=default:--padding=0,1\nroomy:20:--style=default:--padding=1,2\nminimal:20:--style=minimal:--padding=0,1\nnocolor=--no-color' 'fzf compiler covers every cohesive frame, semantic target, and no-color mode' || return 1

  if (( $+commands[fzf] )); then
    (
      unset NO_COLOR
      export TERM=xterm-256color COLORTERM=truecolor COLUMNS=120
      source "$repo_dir/25-theme.zsh"
      local layout
      for layout in compact roomy minimal; do
        ZSH_FZF_LAYOUT=$layout
        _zsh_theme_resolve_settings
        _zsh_theme_fzf_chrome_args || exit 18
        print -r -- alpha | command fzf --filter alpha "${reply[@]}" >/dev/null || exit 19
      done
    )
    assert_status "$?" 0 'installed fzf accepts every compiled layout at the supported floor' || return 1
  fi
}

test_picker_presentation() {
  local output
  output=$(run_theme_case '' '
source '"${repo_dir}"'/40-fzf.zsh
_zsh_theme_fzf_context_args Files "Type to filter files" "Enter insert  Esc close"
print -r -- "context:${reply[1]}:${reply[2]}"
for width in 99 100; do
  COLUMNS=$width
  _fzf_picker_preview_args Usage || exit 20
  print -r -- "$width:${reply[1]}:${reply[2]}:${reply[3]}"
done
_fzf_picker_multi_args remove || exit 21
print -r -- "$REPLY"
print -r -- "${(j:|:)reply}"')
  assert_equals "${${(f)output}[1]}" 'context:--border-label=Files:--input-label=Search' 'picker context labels the cohesive outer frame and input divider' || return 1
  assert_equals "${${(f)output}[2]}" '99:--preview-label=Usage:--preview-window=down,40%,border-top,wrap-word:--bind=ctrl-p:toggle-preview,ctrl-/:toggle-preview-wrap-word' 'picker previews move below at 99 columns' || return 1
  assert_equals "${${(f)output}[3]}" '100:--preview-label=Usage:--preview-window=right,50%,border-left,wrap-word,<100(down,40%,border-top,wrap-word):--bind=ctrl-p:toggle-preview,ctrl-/:toggle-preview-wrap-word' 'picker previews move right at 100 columns' || return 1
  assert_equals "${${(f)output}[4]}" 'Enter remove  Tab mark  Selected 0  Esc close' 'multi-picker footer starts at zero selected items' || return 1
  [[ ${${(f)output}[5]} == *'--multi'* && ${${(f)output}[5]} == *'transform-footer'* && ${${(f)output}[5]} == *'$FZF_SELECT_COUNT'* ]]
  assert_status "$?" 0 'multi-picker footer updates from the fzf selection count' || return 1

  if (( $+commands[fzf] )); then
    (
      unset NO_COLOR
      export TERM=xterm-256color COLORTERM=truecolor COLUMNS=100
      source "$repo_dir/25-theme.zsh"
      source "$repo_dir/40-fzf.zsh"
      local -a args
      _fzf_picker_context_args Packages 'Type to filter packages' 'Enter add  Esc close'
      args=( "${reply[@]}" )
      _fzf_picker_preview_args Package
      args+=( "${reply[@]}" '--preview=printf %s {}' )
      _fzf_picker_multi_args add
      args+=( "${reply[@]}" )
      print -r -- alpha | command fzf --filter alpha "${args[@]}" >/dev/null
      projected=$(print -r -- $'visible\tmetadata\tdetail\traw-value' |
        command fzf --filter visible --delimiter=$'\t' --accept-nth=4)
      [[ $projected == raw-value ]]
    )
    assert_status "$?" 0 'installed fzf accepts shared arguments and projects stable result fields' || return 1
  fi
}

test_ztheme_command() {
  local output marker="$test_tmp/ztheme-executed"
  output=$(run_theme_case '' '
source '"${repo_dir}"'/55-ui-helpers.zsh
source '"${repo_dir}"'/60-functions.zsh
typeset -gi ZTHEME_REFRESHES=0 ZTHEME_FAIL=0
typeset -g _FZF_STATE=ready FZF_DEFAULT_OPTS=""
_fzf_export_config() {
  (( ZTHEME_REFRESHES++ ))
  typeset -g FZF_DEFAULT_OPTS="theme=$ZSH_UI_THEME"
  (( ! ZTHEME_FAIL ))
}

ztheme use nord >/dev/null || exit 22
print -r -- "$ZSH_UI_THEME|${ZSH_FZF_THEME-}|$_ZSH_UI_ACTIVE_THEME|$_ZSH_FZF_ACTIVE_THEME|$FZF_DEFAULT_OPTS|$ZTHEME_REFRESHES"
before=$ZTHEME_REFRESHES
ztheme use '\''$(touch '"${(q)marker}"')'\'' >/dev/null 2>&1
invalid_rc=$?
print -r -- "$invalid_rc|$ZSH_UI_THEME|$FZF_DEFAULT_OPTS|$(( ZTHEME_REFRESHES - before ))"
ZTHEME_FAIL=1
ztheme use catppuccin-latte >/dev/null 2>&1
failed_refresh_rc=$?
print -r -- "$failed_refresh_rc|$ZSH_UI_THEME|$_ZSH_UI_ACTIVE_THEME|$FZF_DEFAULT_OPTS"
ZTHEME_FAIL=0
ztheme reset >/dev/null || exit 23
print -r -- "$ZSH_UI_THEME|$_ZSH_FZF_ACTIVE_THEME"
functions[_ui_is_rich_terminal]="return 1"
shown=$(ztheme show nord) || exit 24
esc=$(printf '\033')
[[ $shown == *$esc* ]] && ansi=1 || ansi=0
print -r -- "${${(f)shown}[1]}|${${(f)shown}[3]}|ansi=$ansi|active=$ZSH_UI_THEME"
_FZF_INHERITED_DEFAULT_OPTS="--color=fg:red"
current=$(ztheme current)
print -r -- "${${(f)current}[1]}|${${(f)current}[2]}|${${(f)current}[6]}"
exported=$(ztheme export gruvbox-dark) || exit 25
print -r -- "${(j:|:)${(f)exported}}"
listed=$(ztheme list)
print -r -- "${(j:|:)${(f)listed}}"
typeset -gA ZSH_UI_CUSTOM_COLORS
for role in "${_ZSH_UI_THEME_ROLES[@]}"; do
  ZSH_UI_CUSTOM_COLORS[$role]=101010
done
custom_export=$(ztheme export custom) || exit 26
custom_lines=( "${(f)custom_export}" )
print -r -- "$custom_lines[1]|$custom_lines[2]|$custom_lines[16]|$custom_lines[17]|$custom_lines[18]|$custom_lines[19]"')

  assert_equals "${${(f)output}[1]}" 'nord||nord|nord|theme=nord|1' 'ztheme use applies UI and inherited fzf themes and refreshes exports' || return 1
  assert_equals "${${(f)output}[2]}" '1|nord|theme=nord|0' 'invalid ztheme input leaves settings and integrations untouched' || return 1
  [[ ! -e $marker ]]
  assert_status "$?" 0 'ztheme names cannot execute shell syntax' || return 1
  assert_equals "${${(f)output}[3]}" '1|nord|nord|theme=nord' 'failed finder refresh rolls the active theme and exports back' || return 1
  assert_equals "${${(f)output}[4]}" 'catppuccin-mocha|catppuccin-mocha' 'ztheme reset restores the compatibility default' || return 1
  assert_equals "${${(f)output}[5]}" 'Theme: nord|base        #2e3440|ansi=0|active=catppuccin-mocha' 'ztheme show has stable plain output and does not switch themes' || return 1
  assert_equals "${${(f)output}[6]}" 'UI theme: catppuccin-mocha|fzf theme: catppuccin-mocha (inherits UI)|external fzf options: yes' 'ztheme current reports inheritance and external option layers' || return 1
  assert_equals "${${(f)output}[7]}" "typeset -g ZSH_UI_THEME=gruvbox-dark|typeset -g ZSH_FZF_THEME=''" 'ztheme export prints safe machine-local assignments' || return 1
  assert_equals "${${(f)output}[8]}" 'Theme|catppuccin-mocha [ui fzf default]|catppuccin-latte|nord|gruvbox-dark|terminal' 'ztheme list is stable and marks active and default themes' || return 1
  assert_equals "${${(f)output}[9]}" "typeset -gA ZSH_UI_CUSTOM_COLORS=(|  base 101010|  danger 101010|)|typeset -g ZSH_UI_THEME=custom|typeset -g ZSH_FZF_THEME=''" 'ztheme export serializes a validated custom palette in stable role order' || return 1
}

test_lazy_loading() {
  local output
  output=$(run_theme_case '' '
source '"${repo_dir}"'/55-ui-helpers.zsh
source '"${repo_dir}"'/60-functions.zsh
print -r -- "ztheme=${+functions[ztheme]} helpers=${+functions[_ztheme_usage]} colors=$_ZSH_THEME_COLOR_HELPERS_LOADED registry=$_ZSH_THEME_REGISTRY_LOADED palettes=$_ZSH_THEME_BUILTIN_PALETTES_LOADED"
ztheme current >/dev/null || exit 27
_zsh_theme_sgr accent fg ui || exit 28
print -r -- "helpers=${+functions[_ztheme_usage]} colors=$_ZSH_THEME_COLOR_HELPERS_LOADED registry=$_ZSH_THEME_REGISTRY_LOADED palettes=$_ZSH_THEME_BUILTIN_PALETTES_LOADED sgr=${(V)REPLY}"
source '"${repo_dir}"'/25-theme.zsh
_zsh_theme_sgr accent fg ui || exit 29
source '"${repo_dir}"'/60-functions.zsh
function_path='"${repo_dir}"'/functions
integer function_path_count=0
for directory in "${fpath[@]}"; do
  [[ $directory == "$function_path" ]] && (( function_path_count++ ))
done
print -r -- "resourced=${(V)REPLY} paths=$function_path_count"')

  assert_equals "${${(f)output}[1]}" 'ztheme=1 helpers=0 colors=0 registry=0 palettes=0' 'startup registers ztheme without parsing command-only or color registry helpers' || return 1
  assert_equals "${${(f)output}[2]}" 'helpers=1 colors=1 registry=1 palettes=1 sgr=^[[38;2;203;166;247m' 'first color use loads trusted command, registry, palette, and SGR helpers' || return 1
  assert_equals "${${(f)output}[3]}" 'resourced=^[[38;2;203;166;247m paths=1' 're-sourcing preserves lazy helpers and one private function path' || return 1
}

test_idempotence_and_safety() {
  local output marker="$test_tmp/executed"
  output=$(run_theme_case "typeset -g ZSH_UI_THEME='\$(touch ${(q)marker})'" '
_zsh_theme_signature; first=$REPLY
source '"${repo_dir}"'/25-theme.zsh
_zsh_theme_signature; print -r -- "$first|$REPLY|${#_ZSH_UI_THEME_NAMES}|${#_ZSH_THEME_COLORS}"')
  assert_equals "$output" 'catppuccin-mocha:catppuccin-mocha:truecolor:nerd:compact:|catppuccin-mocha:catppuccin-mocha:truecolor:nerd:compact:|5|0' 're-sourcing is idempotent after an unsafe theme name fallback' || return 1
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
  test_dashboard_renderer || return 1
  test_fzf_compiler || return 1
  test_picker_presentation || return 1
  test_ztheme_command || return 1
  test_lazy_loading || return 1
  test_idempotence_and_safety || return 1
}

main
