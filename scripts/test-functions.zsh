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
  local fixture_dir="$tmp_dir/control-paths"
  local filename=$'line\nbreak.txt'
  local output
  local -a output_lines

  command mkdir -p -- "$fixture_dir"
  print -r -- 'fixture data' >"$fixture_dir/$filename"

  output=$(dusage "$fixture_dir" 10)
  output_lines=( "${(f)output}" )
  assert_equals "${#output_lines[@]}" 1 'dusage keeps a newline filename in one output record' || return 1
  assert_contains "$output" '\n' 'dusage escapes a newline filename for display' || return 1

  output=$(bigfiles "$fixture_dir" 10)
  output_lines=( "${(f)output}" )
  assert_equals "${#output_lines[@]}" 1 'bigfiles keeps a newline filename in one output record' || return 1
  assert_contains "$output" '\n' 'bigfiles escapes a newline filename for display' || return 1
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

main() {
  source "$repo_dir/55-ui-helpers.zsh"
  source "$repo_dir/60-functions.zsh"

  functions[_ui_plain_mode]='return 0'

  test_missing_arguments || return 1
  test_path_empty_entries || return 1
  test_control_character_paths || return 1
  test_alias_probes_are_quiet || return 1
  test_fkill_default_signal || return 1
}

main "$@"
