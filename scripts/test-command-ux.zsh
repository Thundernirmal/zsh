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

assert_file_contains() {
  local file=$1 needle=$2 label=$3
  local contents=$(<"$file")
  assert_contains "$contents" "$needle" "$label"
}

write_fakebin() {
  local fakebin=$1

  command mkdir -p -- "$fakebin"
  print -r -- '#!/bin/sh
printf "fd %s\n" "$*" >> "$COMMAND_UX_LOG"
exit 0' >"$fakebin/fd"
  print -r -- '#!/bin/sh
printf "rg %s\n" "$*" >> "$COMMAND_UX_LOG"
exit 0' >"$fakebin/rg"
  print -r -- '#!/bin/sh
printf "grep %s\n" "$*" >> "$COMMAND_UX_LOG"
exit 0' >"$fakebin/grep"
  print -r -- '#!/bin/sh
printf "curl %s\n" "$*" >> "$COMMAND_UX_LOG"
printf "%s\n" "fixture-response"
exit 0' >"$fakebin/curl"
  command chmod +x -- "$fakebin"/*
}

test_help() {
  local command_name output rc
  local -a commands_to_check=(
    extract mkcd ff ft fkill headers peek fanprofile dusage bigfiles
    ports weather myip croot gitcount path fbr
  )

  for command_name in "${commands_to_check[@]}"; do
    output=$($command_name --help 2>&1); rc=$?
    assert_status "$rc" 0 "$command_name supports --help" || return 1
    assert_contains "$output" 'Usage:' "$command_name help prints usage" || return 1
  done

  output=$(ff --unknown 2>&1); rc=$?
  assert_status "$rc" 1 'ff rejects unknown options with the established usage status' || return 1
  assert_contains "$output" 'unknown option' 'ff identifies an unknown option' || return 1
}

test_search_options() {
  local fakebin="$tmp_dir/fakebin" log_file="$tmp_dir/commands.log" old_path=$PATH
  local output rc

  write_fakebin "$fakebin"
  : >"$log_file"
  PATH="$fakebin:$old_path"
  export COMMAND_UX_LOG=$log_file
  rehash

  ff --hidden --no-ignore --follow needle "$tmp_dir" >/dev/null; rc=$?
  assert_status "$rc" 0 'ff accepts explicit backend search controls' || return 1
  assert_file_contains "$log_file" 'fd --hidden --no-ignore --follow --glob --ignore-case' 'ff passes hidden, ignore, and follow controls to fd' || return 1

  ft --hidden --no-ignore --follow --fixed-strings 'a.b' "$tmp_dir" >/dev/null; rc=$?
  assert_status "$rc" 0 'ft accepts explicit rg search controls' || return 1
  assert_file_contains "$log_file" 'rg --hidden --no-ignore --follow --fixed-strings' 'ft passes all controls to rg' || return 1

  command rm -f -- "$fakebin/rg"
  PATH=$fakebin
  rehash
  output=$(ft --hidden --no-ignore --follow --fixed-strings 'a.b' "$tmp_dir" 2>&1); rc=$?
  assert_status "$rc" 0 'ft keeps the grep fallback usable with explicit controls' || return 1
  assert_contains "$output" 'grep fallback includes hidden files' 'ft explains hidden fallback behavior' || return 1
  assert_contains "$output" 'grep fallback has no ignore-file filtering' 'ft explains ignore fallback behavior' || return 1
  assert_file_contains "$log_file" 'grep -RnI -F' 'ft maps follow and fixed-string controls to grep' || return 1

  PATH=$old_path
  unset COMMAND_UX_LOG
  rehash
}

test_network_timeouts() {
  local fakebin="$tmp_dir/network-bin" log_file="$tmp_dir/network.log" old_path=$PATH
  local output rc

  write_fakebin "$fakebin"
  : >"$log_file"
  PATH="$fakebin:$old_path"
  export COMMAND_UX_LOG=$log_file
  rehash

  ZSH_HTTP_CONNECT_TIMEOUT=2 ZSH_HTTP_MAX_TIME=7 headers https://example.invalid >/dev/null; rc=$?
  assert_status "$rc" 0 'headers uses bounded default-compatible curl options' || return 1
  ZSH_HTTP_CONNECT_TIMEOUT=2 ZSH_HTTP_MAX_TIME=7 myip >/dev/null; rc=$?
  assert_status "$rc" 0 'myip uses bounded curl options' || return 1
  ZSH_HTTP_CONNECT_TIMEOUT=2 ZSH_HTTP_MAX_TIME=7 weather >/dev/null; rc=$?
  assert_status "$rc" 0 'weather uses bounded curl options' || return 1
  assert_file_contains "$log_file" '--connect-timeout 2 --max-time 7' 'network helpers pass explicit timeout overrides' || return 1

  output=$(ZSH_HTTP_MAX_TIME=0 headers https://example.invalid 2>&1); rc=$?
  assert_status "$rc" 1 'network helpers reject an unbounded timeout override' || return 1
  assert_contains "$output" 'timeout must be positive' 'network helper explains invalid timeout overrides' || return 1

  PATH=$old_path
  unset COMMAND_UX_LOG
  rehash
}

test_extract_destination() {
  local root="$tmp_dir/extract" source_dir="$tmp_dir/extract/source" destination="$tmp_dir/extract/destination"
  local archive="$root/payload.tar.gz" output rc

  command mkdir -p -- "$source_dir" "$destination"
  print -r -- 'archive payload' >"$source_dir/payload.txt"
  command tar -czf "$archive" -C "$source_dir" payload.txt

  output=$(extract --destination "$destination" "$archive" 2>&1); rc=$?
  assert_status "$rc" 0 'extract sends tar output to an explicit destination' || {
    print -u2 -- "$output"
    return 1
  }
  assert_file_contains "$destination/payload.txt" 'archive payload' 'extract writes the expected destination file' || return 1
  [[ -f $archive ]] || {
    print -u2 -- 'not ok: archive input remains after destination extraction'
    return 1
  }
  print -- 'ok: archive input remains after destination extraction'
}

test_extract_stream_safety() {
  local root="$tmp_dir/stream" fakebin="$tmp_dir/stream-bin" old_path=$PATH rc
  command mkdir -p -- "$root/dest" "$fakebin"
  print -r -- payload > "$root/input"
  command gzip -c -- "$root/input" > "$root/input.gz"
  extract --destination "$root/dest" "$root/input.gz" || return 1
  assert_file_contains "$root/dest/input" payload 'bare compressed destination contains decompressed bytes' || return 1
  [[ -f $root/input.gz ]] || return 1
  print -r -- keep > "$root/dest/input"
  extract --destination "$root/dest" "$root/input.gz" >/dev/null 2>&1; rc=$?
  assert_status "$rc" 1 'destination extraction refuses an existing output' || return 1
  assert_file_contains "$root/dest/input" keep 'existing output remains unchanged' || return 1
  command rm -- "$root/dest/input"
  command ln -s -- "$root/absent" "$root/dest/input"
  extract --destination "$root/dest" "$root/input.gz" >/dev/null 2>&1; rc=$?
  assert_status "$rc" 1 'destination extraction refuses a dangling symlink' || return 1
  [[ ! -e $root/absent ]] || return 1
  command rm -- "$root/dest/input"
  print -r -- '#!/bin/sh
printf partial
exit 7' > "$fakebin/gunzip"
  command chmod +x -- "$fakebin/gunzip"
  PATH="$fakebin:$old_path" extract --destination "$root/dest" "$root/input.gz" >/dev/null 2>&1; rc=$?
  assert_status "$rc" 7 'decompression failure preserves its status' || return 1
  local -a leftovers=( "$root/dest"/*(DN) )
  assert_status "${#leftovers}" 0 'failed decompression publishes no partial output and cleans staging files' || return 1
}

main() {
  source "$repo_dir/55-ui-helpers.zsh"
  source "$repo_dir/lib/functions-catalogue.zsh"
  functions[_ui_plain_mode]='return 0'

  test_help || return 1
  test_search_options || return 1
  test_network_timeouts || return 1
  test_extract_destination || return 1
  test_extract_stream_safety || return 1
}

main "$@"
