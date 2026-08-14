#!/usr/bin/env zsh

set -u

repo_dir=${0:A:h:h}
tmp_dir=$(mktemp -d) || { print -u2 -- 'fatal: mktemp failed'; exit 1; }
[ -n "$tmp_dir" ] || { print -u2 -- 'fatal: mktemp returned an empty path'; exit 1; }

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

assert_safe_output_file() {
  emulate -L zsh
  setopt MULTIBYTE

  local file=$1 label=$2
  local content char
  integer index code

  content=$(<"$file")
  for (( index = 1; index <= ${#content}; index++ )); do
    char=${content[$index]}
    printf -v code '%d' "'$char"

    if (( (code >= 0 && code <= 9) || (code >= 11 && code <= 31) || code == 127 || (code >= 128 && code <= 159) )); then
      print -u2 -- "not ok: $label"
      printf 'unsafe codepoint: U+%04X\n' "$code" >&2
      return 1
    fi
  done

  print -- "ok: $label"
}

assert_missing_arg_usage() {
  local command_name=$1 expected_usage=$2
  local output rc

  output=$("$command_name" 2>&1)
  rc=$?
  assert_status "$rc" 1 "$command_name rejects a missing argument under NOUNSET" || return 1
  assert_contains "$output" "$expected_usage" "$command_name prints usage under NOUNSET" || return 1
}

test_missing_arguments() {
  assert_missing_arg_usage extract 'Usage: extract <file>' || return 1
  assert_missing_arg_usage mkcd 'Usage: mkcd <directory>' || return 1
  assert_missing_arg_usage ff 'Usage: ff <pattern> [path]' || return 1
  assert_missing_arg_usage ft 'Usage: ft <pattern> [path]' || return 1
  assert_missing_arg_usage headers 'Usage: headers <url>' || return 1
  assert_missing_arg_usage peek 'Usage: peek <file>' || return 1
}

test_path_empty_entries() {
  local output_file="$tmp_dir/path-output"
  local old_path=$PATH entry
  local -a actual

  PATH=:/bin::/usr/bin:
  path >"$output_file"
  PATH=$old_path

  while IFS= read -r entry; do
    actual+=("$entry")
  done <"$output_file"

  assert_equals "${#actual[@]}" 5 'path preserves every PATH component' || return 1
  assert_equals "${actual[1]}" '' 'path preserves a leading current-directory component' || return 1
  assert_equals "${actual[2]}" '/bin' 'path preserves the first named component' || return 1
  assert_equals "${actual[3]}" '' 'path preserves an interior current-directory component' || return 1
  assert_equals "${actual[4]}" '/usr/bin' 'path preserves the second named component' || return 1
  assert_equals "${actual[5]}" '' 'path preserves a trailing current-directory component' || return 1
}

test_control_character_paths() {
  local fixture_dir="$tmp_dir/"$'target-\e-λ'
  local plain_dusage="$tmp_dir/dusage-plain.out"
  local plain_bigfiles="$tmp_dir/bigfiles-plain.out"
  local plain_path="$tmp_dir/path-plain.out"
  local rich_dusage="$tmp_dir/dusage-rich.out"
  local rich_bigfiles="$tmp_dir/bigfiles-rich.out"
  local rich_path="$tmp_dir/path-rich.out"
  local stripped="$tmp_dir/rich-stripped.out"
  local filename output old_path=$PATH safe truncated
  integer token_index
  local -a filenames safe_tokens safe_labels
  local -a output_lines

  command mkdir -p -- "$fixture_dir"
  filenames=(
    $'esc-\e[31m-red.txt'
    $'bel-\a-ring.txt'
    $'backspace-\b-hide.txt'
    $'del-\x7f-delete.txt'
    $'newline-\n-row.txt'
    $'carriage-\r-return.txt'
    $'tab-\t-column.txt'
    $'form-\f-feed.txt'
    $'vertical-\v-tab.txt'
    $'other-\x01-control.txt'
    $'c1-\u0085-control.txt'
    'unicode-λ-雪.txt'
  )

  for filename in "${filenames[@]}"; do
    print -r -- 'fixture data' >"$fixture_dir/$filename"
  done

  dusage "$fixture_dir" 50 >"$plain_dusage"
  assert_status "$?" 0 'dusage renders hostile plain paths successfully' || return 1
  output=$(<"$plain_dusage")
  output_lines=( "${(f)output}" )
  assert_equals "${#output_lines[@]}" "${#filenames[@]}" 'dusage keeps every hostile filename on one plain output row' || return 1
  assert_safe_output_file "$plain_dusage" 'dusage plain output contains no active control data' || return 1

  bigfiles "$fixture_dir" 50 >"$plain_bigfiles"
  assert_status "$?" 0 'bigfiles renders hostile plain paths successfully' || return 1
  output=$(<"$plain_bigfiles")
  output_lines=( "${(f)output}" )
  assert_equals "${#output_lines[@]}" "${#filenames[@]}" 'bigfiles keeps every hostile filename on one plain output row' || return 1
  assert_safe_output_file "$plain_bigfiles" 'bigfiles plain output contains no active control data' || return 1

  output="$(<"$plain_dusage")"$'\n'"$(<"$plain_bigfiles")"
  safe_tokens=( '\e' '\a' '\b' '\x7f' '\n' '\r' '\t' '\f' '\v' '\x01' '\x85' 'unicode-λ-雪.txt' 'target-\e-λ' )
  safe_labels=( ESC BEL backspace DEL newline 'carriage return' tab 'form feed' 'vertical tab' 'other C0' C1 Unicode 'hostile target' )
  for (( token_index = 1; token_index <= ${#safe_tokens[@]}; token_index++ )); do
    assert_contains "$output" "${safe_tokens[$token_index]}" "filesystem output preserves ${safe_labels[$token_index]} safely" || return 1
  done

  PATH="$fixture_dir:$tmp_dir/"$'path-\a-entry'":/bin"
  path >"$plain_path"
  PATH=$old_path
  output=$(<"$plain_path")
  assert_contains "$output" 'target-\e-λ' 'path sanitizes its hostile target entry' || return 1
  assert_contains "$output" 'path-\a-entry' 'path renders BEL as a visible escape' || return 1
  assert_safe_output_file "$plain_path" 'path plain output contains no active control data' || return 1

  safe=$(_ui_safe_text $'plain λ 雪')
  assert_equals "$safe" 'plain λ 雪' 'safe-text helper preserves ordinary Unicode' || return 1
  safe=$(_ui_safe_text $'123456\eABCDEFGHIJKLMNO')
  truncated=$(_ui_safe_truncate 17 "$safe")
  assert_equals "$truncated" '123456...IJKLMNO' 'safe truncation never splits a short visible escape' || return 1
  safe=$(_ui_safe_text $'1234\x7fABCDEFGHIJKLMNO')
  truncated=$(_ui_safe_truncate 17 "$safe")
  assert_equals "$truncated" '1234...IJKLMNO' 'safe truncation never splits a hexadecimal escape' || return 1
  assert_not_contains "$truncated" '\x...' 'safe truncation emits no partial hexadecimal escape' || return 1

  (
    functions[_ui_plain_mode]='return 1'
    functions[_ui_term_width]='print -r -- 60'
    functions[_ui_term_height]='print -r -- 100'
    functions[_ui_color]='printf "\e[35m"'
    functions[_ui_reset]='printf "\e[0m"'
    functions[_ui_bold]=':'
    functions[_ui_icon]='print -nr -- "$2"'
    dusage "$fixture_dir" 50
  ) >"$rich_dusage"
  assert_status "$?" 0 'dusage renders hostile rich paths successfully' || return 1

  (
    functions[_ui_plain_mode]='return 1'
    functions[_ui_term_width]='print -r -- 60'
    functions[_ui_term_height]='print -r -- 100'
    functions[_ui_color]='printf "\e[35m"'
    functions[_ui_reset]='printf "\e[0m"'
    functions[_ui_bold]=':'
    functions[_ui_icon]='print -nr -- "$2"'
    bigfiles "$fixture_dir" 50
  ) >"$rich_bigfiles"
  assert_status "$?" 0 'bigfiles renders hostile rich paths successfully' || return 1

  (
    functions[_ui_plain_mode]='return 1'
    functions[_ui_term_width]='print -r -- 60'
    functions[_ui_color]='printf "\e[35m"'
    functions[_ui_reset]='printf "\e[0m"'
    functions[_ui_bold]=':'
    functions[_ui_icon]='print -nr -- "$2"'
    PATH="$fixture_dir:$tmp_dir/"$'path-\a-entry'":/bin"
    path
  ) >"$rich_path"
  assert_status "$?" 0 'path renders hostile rich entries successfully' || return 1

  for filename in "$rich_dusage" "$rich_bigfiles" "$rich_path"; do
    output=$(<"$filename")
    assert_contains "$output" $'\e[35m' "${filename:t} contains the expected UI styling" || return 1
    assert_not_contains "$output" $'\e[31m' "${filename:t} does not activate filename-provided styling" || return 1
    command sed $'s/\033\\[35m//g; s/\033\\[0m//g' "$filename" >"$stripped"
    assert_safe_output_file "$stripped" "${filename:t} is safe after expected UI styling is removed" || return 1
  done
}

test_alias_probes_are_quiet() {
  local fakebin="$tmp_dir/fakebin"
  local stdout_file="$tmp_dir/aliases.stdout"
  local stderr_file="$tmp_dir/aliases.stderr"
  local output zsh_bin=${commands[zsh]}

  command mkdir -p -- "$fakebin"

  print -r -- '#!/bin/sh
printf "%s\n" "unsupported ls option" >&2
exit 2' >"$fakebin/ls"
  print -r -- '#!/bin/sh
exit 1' >"$fakebin/grep"
  print -r -- '#!/bin/sh
printf "%s\n" "unsupported diff option" >&2
exit 2' >"$fakebin/diff"
  command chmod +x "$fakebin/ls" "$fakebin/grep" "$fakebin/diff"

  PATH="$fakebin" "$zsh_bin" -fc "source ${(q)repo_dir}/20-aliases.zsh" >"$stdout_file" 2>"$stderr_file"
  assert_status "$?" 0 'alias fallback probes complete when color flags are unsupported' || return 1

  output=$(<"$stdout_file")
  assert_equals "$output" '' 'alias fallback probes keep stdout quiet' || return 1
  output=$(<"$stderr_file")
  assert_equals "$output" '' 'alias fallback probes keep stderr quiet' || return 1
}

test_fkill_default_signal() {
  assert_contains "${functions[fkill]}" 'local signal=${1:-15}' 'fkill defaults to SIGTERM' || return 1
}

test_fbr_worktree_navigation() {
  local fixture_repo="$tmp_dir/fbr-repo"
  local worktree_dir="$tmp_dir/fbr worktree"
  local original_dir=$PWD branch worktree_path
  local -A worktree_paths

  command git init -q "$fixture_repo" || return 1
  print -r -- 'fixture' >"$fixture_repo/tracked.txt"
  command git -C "$fixture_repo" add tracked.txt || return 1
  command git -C "$fixture_repo" -c user.name='Zsh Tests' -c user.email='zsh-tests@example.invalid' \
    commit -qm 'Initial commit' || return 1
  command git -C "$fixture_repo" worktree add -q -b worktree-test "$worktree_dir" || return 1

  builtin cd -- "$fixture_repo" || return 1
  while IFS= read -r -d '' branch && IFS= read -r -d '' worktree_path; do
    worktree_paths[$branch]=$worktree_path
  done < <(_fbr_worktree_entries)

  assert_equals "${worktree_paths[worktree-test]-}" "$worktree_dir" 'fbr maps a checked-out branch to its worktree path' || {
    builtin cd -- "$original_dir"
    return 1
  }

  _fbr_activate worktree-test "${worktree_paths[worktree-test]}"
  assert_status "$?" 0 'fbr can activate a branch attached to a worktree' || {
    builtin cd -- "$original_dir"
    return 1
  }
  assert_equals "$PWD" "$worktree_dir" 'fbr enters the selected branch worktree, including paths with spaces' || {
    builtin cd -- "$original_dir"
    return 1
  }

  builtin cd -- "$original_dir"
}

main() {
  source "$repo_dir/55-ui-helpers.zsh"
  source "$repo_dir/60-functions.zsh"

  functions[_ui_plain_mode]='return 0'

  test_missing_arguments || return 1
  test_path_empty_entries || return 1
  test_control_character_paths || return 1
  test_alias_probes_are_quiet || return 1
  test_fkill_default_signal || return 1
  test_fbr_worktree_navigation || return 1
}

main "$@"
