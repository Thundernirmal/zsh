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
