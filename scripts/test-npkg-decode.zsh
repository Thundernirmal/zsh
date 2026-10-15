#!/usr/bin/env zsh
emulate -L zsh
setopt NO_UNSET
command -v jq >/dev/null 2>&1 || { print 'skip: Nix decode checks require jq'; exit 0; }
typeset -r repo_dir=${0:A:h:h} jq_binary=${commands[jq]}
typeset scratch=$(command mktemp -d) || exit 1
trap 'command rm -rf -- "$scratch"' EXIT
source "$repo_dir/55-ui-helpers.zsh"
source "$repo_dir/lib/functions-common.zsh"
source "$repo_dir/lib/functions-nix.zsh"
assert() { "$@" || { print -u2 -r -- "not ok: $*"; exit 1; }; }

typeset encoded field
typeset -a fields expected=( '' $'a\tb\nc\rd' 'literal\n\0\t' $'a\0b' 'é雪😀' '"quotes"' $'tail\n\n' )
encoded=$(command jq -nr '["", "a\tb\nc\rd", "literal\\n\\0\\t", "a\u0000b", "é雪😀", "\"quotes\"", "tail\n\n"] | @tsv | gsub("\u0000"; "\\0")') || exit 1
fields=( "${(@ps:\t:)encoded}" )
assert test "${#fields}" -eq "${#expected}"
integer index
for ((index=1;index<=${#fields};index++)); do
  _npkg_decode_field "$fields[$index]" || exit 1
  [[ $REPLY == "$expected[$index]" ]] || exit 1
done
for field in '\x' 'trailing\'; do
  _npkg_decode_field "$field"
  assert test "$?" -eq 1
done
print 'ok: Nix field framing preserves empty/control/NUL/Unicode/backslash/trailing-newline data and rejects bad escapes'

command mkdir "$scratch/bin"
print -rl -- '#!/bin/sh' 'printf "jq\n" >> "$NPKG_JQ_LOG"' "exec ${(q)jq_binary} \"\$@\"" > "$scratch/bin/jq"
command chmod +x "$scratch/bin/jq"
export NPKG_JQ_LOG="$scratch/jq-calls"
path=("$scratch/bin" $path)
_zsh_run_owned_query() { "$@"; }
_npkg_nix() { print -r -- "$fixture"; }
_npkg_eval_installable_record() { print -u2 -- 'unexpected evaluation'; return 99; }
typeset fixture
integer count
for count in 0 20 100; do
  fixture=$("$jq_binary" -nc --argjson n "$count" '{elements: [range($n) | {name: ("pkg" + tostring)}]}') || exit 1
  : > "$NPKG_JQ_LOG"
  _npkg_outdated > "$scratch/output"
  assert test "$?" -eq "$(( count > 0 ))"
  fields=( "${(@f)$(<"$NPKG_JQ_LOG")}" )
  assert test "${#fields}" -eq 2
  assert test "$_NPKG_OUTDATED_TOTAL" -eq "$count"
  assert test "$_NPKG_OUTDATED_UNKNOWN" -eq "$count"
done
print 'ok: Nix initial decoding uses two jq processes independent of profile size'

fixture='{"elements":[{"name":"tab\tzero\u0000slash\\n\n\n"}]}'
_npkg_outdated > "$scratch/output"
assert test "$?" -eq 1
[[ $(<"$scratch/output") == *'tab\tzero\x00slash\n'* ]] || exit 1
[[ $(<"$scratch/output") != *'slash\n\n\n'* ]] || exit 1
assert test "$_NPKG_OUTDATED_UNKNOWN" -eq 1
fixture='{"elements":false}'
_npkg_outdated > "$scratch/output" 2> "$scratch/error"
assert test "$?" -eq 1
assert test "$_NPKG_OUTDATED_STATE" = partial
print 'ok: Nix decoded rows preserve visible escaping and trailing-newline compatibility; malformed profiles fail'

# Valid single-record current/locked results need one jq pass each.
fixture='{"elements":[{"name":"sample","attrPath":"pkg","originalUrl":"current","uri":"locked","storePaths":["/store/b","/store/a","/store/a"]}]}'
_npkg_eval_installable_record() {
  if [[ $1 == locked ]]; then
    print -r -- '{"version":"old\n\n"}'
  else
    print -r -- '{"paths":["/store/a","/store/b"],"version":"new\tline\u0000\\n\n"}'
  fi
}
: > "$NPKG_JQ_LOG"
_npkg_outdated > "$scratch/output"
assert test "$?" -eq 0
assert test "$_NPKG_OUTDATED_STATE" = current
fields=( "${(@f)$(<"$NPKG_JQ_LOG")}" )
assert test "${#fields}" -eq 4
[[ $(<"$scratch/output") == *'new\tline\x00\n'* ]] || exit 1
print 'ok: single evaluation records combine validation, versions and normalized path comparison in one jq pass each'

for record in '{}' '{"paths":[]}' '{"paths":["/store/a"],"version":false}' 'not-json'; do
  encoded=$(_npkg_eval_summary current '["/store/a"]' "$record") || encoded=invalid
  [[ $encoded == invalid ]] || exit 1
done
encoded=$(_npkg_eval_summary current '["/store/a"]' $'{"paths":["/store/a"],"version":"1"}\n{"paths":["/store/b"],"version":"2"}') || exit 1
[[ $encoded == stream ]] || exit 1
# The legacy stream path remains visible as a changed result, with joined versions.
_npkg_eval_installable_record() {
  print -r -- '{"paths":["/store/a"],"version":"1"}' '{"paths":["/store/b"],"version":"2"}'
}
_npkg_outdated > "$scratch/output"
assert test "$?" -eq 0
assert test "$_NPKG_OUTDATED_STATE" = changed
[[ $(<"$scratch/output") == *'1\n2'* ]] || exit 1
print 'ok: invalid evaluation records stay unknown and multi-record streams preserve legacy decoding'

# A slow first worker must not hold the next batch behind it.
fixture=$("$jq_binary" -nc '{elements: [range(1;17) | {name:("pkg"+tostring),attrPath:tostring,originalUrl:"current",storePaths:["/store/a"]}]}') || exit 1
_npkg_eval_installable_record() {
  print -r -- "start $2" >> "$scratch/events"
  if [[ $2 == 1 ]]; then
    integer attempts=0
    while [[ ! -e $scratch/refilled ]] && (( attempts++ < 300 )); do
      command sleep 0.01
    done
    [[ -e $scratch/refilled ]] || return 99
  elif [[ $2 == 9 ]]; then
    : > "$scratch/refilled"
  fi
  print -r -- "end $2" >> "$scratch/events"
  print -r -- '{"paths":["/store/a"],"version":"1"}'
}
_npkg_outdated > "$scratch/output"
assert test "$?" -eq 0
assert test "$_NPKG_OUTDATED_STATE" = current
assert test "$_NPKG_OUTDATED_TOTAL" -eq 16
integer active=0 peak=0 finished=0
for field in "${(@f)$(<"$scratch/events")}"; do
  if [[ $field == start* ]]; then
    (( active++ ))
    (( active > peak )) && peak=$active
  else
    (( active--, finished++ ))
  fi
  (( active >= 0 && active <= 8 )) || exit 1
done
assert test "$active" -eq 0
assert test "$finished" -eq 16
print 'ok: Nix refills slots before the slow first worker finishes and retains the eight-worker bound'

# Missing optional polling module retains the portable batch-drain fallback.
zmodload() {
  [[ $1 == zsh/zselect ]] && return 1
  builtin zmodload "$@"
}
_npkg_outdated > "$scratch/output"
assert test "$?" -eq 0
assert test "$_NPKG_OUTDATED_STATE" = current
unfunction zmodload
print 'ok: missing zselect falls back to complete batch draining'

for count in 129 130 143; do
  command rm -f "$scratch/refilled"
  _npkg_eval_installable_record() {
    if [[ $2 == 1 ]]; then
      integer attempts=0
      while [[ ! -e $scratch/refilled ]] && (( attempts++ < 300 )); do
        command sleep 0.01
      done
    elif [[ $2 == 9 ]]; then
      : > "$scratch/refilled"
      return "$count"
    fi
    print -r -- '{"paths":["/store/a"],"version":"1"}'
  }
  _npkg_outdated > "$scratch/output"
  assert test "$?" -eq "$count"
done
print 'ok: cancellation in refilled Nix workers retains HUP/INT/TERM exit statuses'

# Immediate worker exits can remove /proc records between eligibility and read.
fixture=$("$jq_binary" -nc '{elements: [range(100) | {name:("pkg"+tostring),attrPath:"pkg",originalUrl:"current",storePaths:["/store/a"]}]}') || exit 1
_npkg_eval_installable_record() { print -r -- '{"paths":["/store/a"],"version":"1"}'; }
for count in 1 2 3; do
  _npkg_outdated > "$scratch/output" 2> "$scratch/error"
  assert test "$?" -eq 0
  assert test "$_NPKG_OUTDATED_TOTAL" -eq 100
  assert test ! -s "$scratch/error"
done
print 'ok: immediate Nix worker exits retain status and do not leak process-read diagnostics'
