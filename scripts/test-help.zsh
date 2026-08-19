#!/usr/bin/env zsh

set -u

repo_dir=${0:A:h:h}
zsh_bin=${commands[zsh]}
tmp_dir=$(mktemp -d) || { print -u2 -- 'fatal: mktemp failed'; exit 1; }
[[ -n $tmp_dir ]] || { print -u2 -- 'fatal: mktemp returned an empty path'; exit 1; }

cleanup() {
  command rm -rf -- "$tmp_dir"
}

trap cleanup EXIT INT TERM

assert_status() {
  local actual=$1 expected=$2 label=$3

  if [[ $actual != "$expected" ]]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "expected status: $expected"
    print -u2 -- "actual status: $actual"
    return 1
  fi

  print -- "ok: $label"
}

assert_equals() {
  local actual=$1 expected=$2 label=$3

  if [[ $actual != "$expected" ]]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "expected: $expected"
    print -u2 -- "actual: $actual"
    return 1
  fi

  print -- "ok: $label"
}

assert_contains() {
  local haystack=$1 needle=$2 label=$3

  if [[ $haystack != *$needle* ]]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "missing: $needle"
    print -u2 -- "output: $haystack"
    return 1
  fi

  print -- "ok: $label"
}

assert_not_contains() {
  local haystack=$1 needle=$2 label=$3

  if [[ $haystack == *$needle* ]]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "unexpected: $needle"
    print -u2 -- "output: $haystack"
    return 1
  fi

  print -- "ok: $label"
}

assert_unique() {
  local label=$1 value
  shift
  local -A seen

  for value in "$@"; do
    if [[ -n ${seen[$value]-} ]]; then
      print -u2 -- "not ok: $label"
      print -u2 -- "duplicate value: $value"
      return 1
    fi
    seen[$value]=1
  done

  print -- "ok: $label"
}

file_contents() {
  local file=$1

  [[ -r $file ]] && print -r -- "$(<"$file")"
}

test_catalogue() {
  local id before_count rc
  local expected='.. ... .... - z zi mkcd croot ls ll la lt mkdir cp mv rm cat extract peek dusage bigfiles grep diff ff ft glog gpr gun gitcount gcount fbr weather fkill headers fanprofile ports myip path cgm upkg npkg G L W H T NE NUL tips ztheme zhelp'

  assert_equals "${(j: :)_ZSH_HELP_ORDER}" "$expected" 'catalogue covers the public command suite in stable order' || return 1
  assert_unique 'catalogue IDs are unique' "${_ZSH_HELP_ORDER[@]}" || return 1

  for id in "${_ZSH_HELP_ORDER[@]}"; do
    [[ -n ${_ZSH_HELP_CATEGORY[$id]-} ]] || { print -u2 -- "not ok: $id has a category"; return 1; }
    [[ -n ${_ZSH_HELP_SUMMARY[$id]-} ]] || { print -u2 -- "not ok: $id has a summary"; return 1; }
    (( ${#_ZSH_HELP_SUMMARY[$id]} <= 60 )) || { print -u2 -- "not ok: $id has a concise summary"; return 1; }
    [[ -n ${_ZSH_HELP_USAGE[$id]-} ]] || { print -u2 -- "not ok: $id has usage"; return 1; }
    [[ -n ${_ZSH_HELP_EXAMPLE[$id]-} ]] || { print -u2 -- "not ok: $id has an example"; return 1; }
  done
  print -- 'ok: every catalogue entry has concise required help fields'

  assert_equals "${_ZSH_HELP_SUMMARY[upkg]}" 'Check, search, upgrade, and clean detected managers' 'upkg help summary is concise and includes cleanup' || return 1
  assert_equals "${_ZSH_HELP_USAGE[weather]}" 'weather' 'weather help does not promise an unsupported location argument' || return 1
  assert_equals "${_ZSH_HELP_DEPS[peek]}" 'bat or cat' 'peek help names its real fallback' || return 1
  assert_equals "${_ZSH_HELP_USAGE[ztheme]}" 'ztheme <list|current|show|use|reset|export> [theme]' 'ztheme help exposes every public subcommand' || return 1

  before_count=${#_ZSH_HELP_ORDER[@]}
  _zsh_help_register extract Files duplicate duplicate duplicate none function none
  rc=$?
  assert_status "$rc" 1 'duplicate catalogue registration is rejected' || return 1
  assert_equals "${#_ZSH_HELP_ORDER[@]}" "$before_count" 'duplicate registration leaves catalogue order unchanged' || return 1
}

test_matching() {
  _zsh_help_matches PACKAGES 1
  assert_equals "${(j: :)reply}" 'upkg npkg' 'query matching is case-insensitive across categories' || return 1

  _zsh_help_matches 'recursively by size' 1
  assert_equals "${(j: :)reply}" 'bigfiles' 'query matching searches summaries' || return 1

  _zsh_help_matches '[signal]' 1
  assert_equals "${(j: :)reply}" 'fkill' 'query matching searches usage strings literally' || return 1

  _zsh_help_matches '--only=apt,nix' 1
  assert_equals "${(j: :)reply}" 'upkg' 'query matching searches examples' || return 1
}

test_plain_rendering_and_availability() {
  local output cgm_output rc fakebin="$tmp_dir/availability-fakebin" old_path=$PATH

  unfunction npkg 2>/dev/null || true

  _zsh_help_matches '' 0
  assert_not_contains " ${(j: :)reply} " ' npkg ' 'default results omit unavailable commands' || return 1

  _zsh_help_matches '' 1
  assert_contains " ${(j: :)reply} " ' npkg ' '--all results include unavailable commands' || return 1

  output=$(zhelp --plain --all package)
  assert_contains "$output" 'Manage the current Nix profile [needs nix; jq and fzf 0.68.0+ for optional workflows]' '--all lists explain unavailable command requirements inline' || return 1

  output=$(zhelp --plain --all upkg)
  assert_contains "$output" 'upkg: Check, search, upgrade, and clean detected managers' 'exact lookup renders a concise command summary' || return 1
  assert_contains "$output" 'Usage:   upkg [command] [args] [flags]' 'exact lookup renders command usage' || return 1
  assert_contains "$output" 'Example: upkg search ripgrep --only=apt,nix' 'exact lookup renders the catalogue example' || return 1

  output=$(zhelp --plain npkg 2>&1)
  rc=$?
  assert_status "$rc" 1 'exact lookup rejects an unavailable command by default' || return 1
  assert_contains "$output" "Run 'zhelp --all npkg'" 'unavailable exact lookup explains how to include the command' || return 1

  output=$(zhelp --plain --all npkg)
  assert_contains "$output" 'Status:  unavailable (needs nix; jq and fzf 0.68.0+ for optional workflows)' '--all labels unavailable command requirements' || return 1

  output=$(zhelp --plain --all cgm)
  assert_contains "$output" 'cgm: Store and load shell credentials securely' 'cgm has a concise help record' || return 1
  assert_contains "$output" 'Status:  unavailable (needs secret-tool and a Secret Service provider)' 'cgm help explains its optional dependency' || return 1

  command mkdir -p -- "$fakebin"
  print -r -- '#!/bin/sh
exit 0' > "$fakebin/nix"
  print -r -- '#!/bin/sh
exit 0' > "$fakebin/secret-tool"
  command chmod +x "$fakebin/nix" "$fakebin/secret-tool"
  npkg() { :; }
  cgm() { :; }
  PATH="$fakebin:$PATH"
  output=$(zhelp --plain npkg)
  cgm_output=$(zhelp --plain cgm)
  PATH=$old_path
  unfunction npkg cgm
  assert_contains "$output" 'Status:  available' 'availability checks use the live function table and PATH' || return 1
  assert_contains "$cgm_output" 'Status:  available' 'cgm availability checks its live function and secret-tool path' || return 1

  output=$(TERM=dumb zhelp --all package)
  assert_contains "$output" 'Command        Category' 'unsuitable terminals use the plain table' || return 1
  assert_not_contains "$output" $'\e[' 'plain output contains no ANSI escapes' || return 1

  output=$(zhelp --plain --all upkgg 2>&1)
  rc=$?
  assert_status "$rc" 1 'unknown command or query returns failure' || return 1
  assert_contains "$output" 'No commands matched: upkgg' 'unknown query prints a concise error' || return 1
  assert_contains "$output" 'Close matches: upkg' 'unknown exact-like query suggests close commands' || return 1
}

test_palette_queue_and_cancel() {
  local fakebin="$tmp_dir/palette-fakebin"
  local marker_file="$tmp_dir/example-executed"
  local dangerous_example="print -r -- executed > ${(q)marker_file}"
  local queued old_path=$PATH rc

  assert_contains "${functions[_zsh_help_palette]}" '--accept-nth=5' 'zhelp asks fzf to return only the editable example' || return 1
  assert_contains "${functions[_zsh_help_palette]}" '_fzf_picker_preview_args Usage' 'zhelp uses the shared responsive preview policy' || return 1

  command mkdir -p -- "$fakebin"
  _zsh_help_register test-palette Meta 'Palette safety fixture' 'test-palette' "$dangerous_example" none function none || return 1
  functions[_fzf_require_ready]='return 0'

  print -r -- '#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    "$ZSH_HELP_TEST_ID	"*)
      tab=$(printf "\t")
      IFS="$tab" read -r id category summary usage example availability <<EOF
$line
EOF
      printf "%s\n" "$example"
      exit 0
      ;;
  esac
done
exit 1' > "$fakebin/fzf"
  command chmod +x "$fakebin/fzf"

  ZSH_HELP_TEST_ID=test-palette
  export ZSH_HELP_TEST_ID
  PATH="$fakebin:$PATH"
  _zsh_help_palette test-palette 1
  rc=$?
  read -z queued
  assert_status "$rc" 0 'palette selection returns success' || return 1
  assert_equals "$queued" "$dangerous_example" 'palette queues the selected example unchanged' || return 1
  [[ ! -e $marker_file ]] || { print -u2 -- 'not ok: palette selection never evaluates the example'; return 1; }
  print -- 'ok: palette selection never evaluates the example'

  print -r -- '#!/bin/sh
exit 130' > "$fakebin/fzf"
  command chmod +x "$fakebin/fzf"
  print -z -- 'existing command buffer'
  _zsh_help_palette '' 1
  rc=$?
  read -z queued
  PATH=$old_path
  unset ZSH_HELP_TEST_ID
  unfunction _fzf_require_ready
  assert_status "$rc" 0 'palette cancellation returns success' || return 1
  assert_equals "$queued" 'existing command buffer' 'palette cancellation leaves the command queue unchanged' || return 1
}

test_source_has_no_subprocesses() {
  local fakebin="$tmp_dir/source-fakebin"
  local invocation_log="$tmp_dir/source-invocations"
  local tool

  command mkdir -p -- "$fakebin"
  for tool in git nix fzf find jq curl secret-tool; do
    print -r -- '#!/bin/sh
printf "%s\n" "$0" >> "$_ZSH_HELP_INVOCATION_LOG"' > "$fakebin/$tool"
    command chmod +x "$fakebin/$tool"
  done

  _ZSH_HELP_INVOCATION_LOG=$invocation_log PATH=$fakebin "$zsh_bin" -f -c 'source "$1"' zsh "$repo_dir/65-help.zsh"
  assert_status "$?" 0 'help module sources with fake external tools on PATH' || return 1
  assert_equals "$(file_contents "$invocation_log")" '' 'help module sourcing invokes no external tools' || return 1
}

test_tips_are_concise() {
  local tip

  source "$repo_dir/80-tips.zsh"
  (( ${#_zsh_tip_pool[@]} > 0 && ${#_zsh_tip_pool[@]} <= 60 )) || {
    print -u2 -- 'not ok: tip pool stays focused'
    return 1
  }

  for tip in "${_zsh_tip_pool[@]}"; do
    (( ${#tip} <= 80 )) || {
      print -u2 -- "not ok: tip exceeds 80 characters: $tip"
      return 1
    }
    case $tip in
      Run\ *|Use\ *|Press\ *|Start\ *) ;;
      *)
        print -u2 -- "not ok: tip is not actionable: $tip"
        return 1
        ;;
    esac
  done

  print -- 'ok: tips stay focused, short, and actionable'
}

main() {
  source "$repo_dir/25-theme.zsh"
  source "$repo_dir/40-fzf.zsh"
  source "$repo_dir/65-help.zsh"

  test_catalogue || return 1
  test_matching || return 1
  test_plain_rendering_and_availability || return 1
  test_palette_queue_and_cancel || return 1
  test_source_has_no_subprocesses || return 1
  test_tips_are_concise || return 1
}

main "$@"
