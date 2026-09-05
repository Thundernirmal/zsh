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

make_fakebin() {
  local fakebin=$1 tool

  command mkdir -p -- "$fakebin"
  for tool in zsh git curl ss lsd zoxide bat tree jq secret-tool nix fd; do
    print -r -- '#!/bin/sh
exit 0' >"$fakebin/$tool"
    command chmod +x -- "$fakebin/$tool"
  done
  print -r -- '#!/bin/sh
if [ "$1" = "--version" ]; then
  printf "%s\n" "0.74.0"
  exit 0
fi
exit 0' >"$fakebin/fzf"
  command chmod +x -- "$fakebin/fzf"
  print -r -- '#!/bin/sh
printf "%s\n" "$*" >> "$ZDOCTOR_CURL_LOG"
exit ${ZDOCTOR_CURL_STATUS:-0}' >"$fakebin/curl"
  command chmod +x -- "$fakebin/curl"
}

test_usage() {
  local output rc

  output=$(zdoctor --help)
  assert_status "$?" 0 'zdoctor documents its explicit probe flags' || return 1
  assert_contains "$output" 'Usage: zdoctor [--network] [--secrets]' 'zdoctor usage names both probes' || return 1

  output=$(zdoctor --bogus 2>&1); rc=$?
  assert_status "$rc" 1 'zdoctor rejects unknown options' || return 1
  assert_contains "$output" 'Unknown zdoctor option' 'zdoctor names the rejected option' || return 1

  output=$(zdoctor surplus 2>&1); rc=$?
  assert_status "$rc" 1 'zdoctor rejects positional arguments' || return 1
}

test_healthy_fixture() {
  local fixture_home="$tmp_dir/doctor-home" fakebin="$tmp_dir/doctor-fakebin"
  local old_path=$PATH output rc

  command mkdir -p -- "$fixture_home/.config"
  command ln -s -- "$repo_dir" "$fixture_home/.config/zsh"
  make_fakebin "$fakebin"
  PATH="$fakebin:$old_path"
  rehash
  unfunction cgm npkg zi 2>/dev/null || true

  output=$(HOME="$fixture_home" zdoctor 2>&1); rc=$?
  assert_status "$rc" 0 'zdoctor passes a healthy fixture' || {
    print -u2 -- "$output"
    return 1
  }
  assert_contains "$output" 'ok: install location' 'zdoctor verifies the fixed install path' || return 1
  assert_contains "$output" 'ok: all expected modules are readable' 'zdoctor verifies module readability' || return 1
  assert_contains "$output" 'compinit has not run' 'zdoctor explains silent completion loss' || return 1
  assert_contains "$output" 'ok: required tool: fzf 0.74.0 (minimum 0.68.0)' 'zdoctor gates the fzf minimum version' || return 1
  assert_contains "$output" 'ok: optional tool: nix' 'zdoctor separates optional tools from required ones' || return 1
  assert_contains "$output" 'global aliases are disabled' 'zdoctor reports the global-alias state' || return 1
  assert_contains "$output" 'network endpoints not probed' 'zdoctor skips network probes by default' || return 1
  assert_contains "$output" 'Secret Service not contacted' 'zdoctor skips secret probes by default' || return 1
  assert_contains "$output" 'zdoctor: healthy' 'zdoctor summarizes a healthy setup' || return 1
  [[ ! -e $tmp_dir/doctor-curl.log ]] || {
    print -u2 -- 'not ok: default zdoctor never invokes curl'
    PATH=$old_path
    rehash
    return 1
  }
  print -- 'ok: default zdoctor never invokes curl'
  PATH=$old_path
  rehash
}

test_bad_install_location() {
  local fixture_home="$tmp_dir/doctor-nowhere" fakebin="$tmp_dir/doctor-fakebin"
  local old_path=$PATH output rc

  command mkdir -p -- "$fixture_home"
  make_fakebin "$fakebin"
  PATH="$fakebin:$old_path"
  rehash

  output=$(HOME="$fixture_home" zdoctor 2>&1); rc=$?
  assert_status "$rc" 1 'zdoctor fails a missing install location' || return 1
  assert_contains "$output" 'fail: install location' 'zdoctor names the install problem' || return 1
  assert_contains "$output" 'unreadable modules' 'zdoctor names silently skipped modules' || { PATH=$old_path; rehash; return 1; }
  PATH=$old_path
  rehash
}

test_explicit_probes() {
  local fixture_home="$tmp_dir/doctor-home" fakebin="$tmp_dir/doctor-fakebin"
  local old_path=$PATH output rc log="$tmp_dir/doctor-probe-curl.log"

  command mkdir -p -- "$fixture_home/.config"
  command ln -sfn -- "$repo_dir" "$fixture_home/.config/zsh"
  make_fakebin "$fakebin"
  PATH="$fakebin:$old_path"
  rehash
  unfunction cgm npkg zi 2>/dev/null || true

  output=$(HOME="$fixture_home" ZDOCTOR_CURL_LOG=$log ZDOCTOR_CURL_STATUS=0 zdoctor --network 2>&1); rc=$?
  assert_status "$rc" 0 'zdoctor passes when probed endpoints answer' || {
    print -u2 -- "$output"
    return 1
  }
  assert_contains "$output" 'myip endpoint is reachable' 'zdoctor probes the myip endpoint explicitly' || return 1
  assert_contains "$output" 'weather endpoint is reachable' 'zdoctor probes the weather endpoint explicitly' || return 1
  assert_contains "$(<"$log")" 'ifconfig.me' 'network probes request the documented endpoint' || return 1
  assert_contains "$(<"$log")" 'wttr.in' 'network probes cover the forecast endpoint' || return 1

  command rm -f -- "$log"
  output=$(HOME="$fixture_home" ZDOCTOR_CURL_LOG=$log ZDOCTOR_CURL_STATUS=1 zdoctor --network 2>&1); rc=$?
  assert_status "$rc" 1 'zdoctor fails unreachable endpoints' || return 1
  assert_contains "$output" 'myip endpoint is unreachable' 'zdoctor reports endpoint failures' || return 1

  output=$(HOME="$fixture_home" zdoctor --secrets 2>&1); rc=$?
  assert_status "$rc" 0 'zdoctor checks secrets without failing a healthy fixture' || return 1
  assert_contains "$output" 'never retrieves credential values' 'zdoctor never retrieves secret values' || { PATH=$old_path; rehash; return 1; }
  PATH=$old_path
  rehash
}

test_old_fzf_is_a_failure() {
  local fixture_home="$tmp_dir/doctor-home" fakebin="$tmp_dir/doctor-oldfzf"
  local old_path=$PATH output rc

  command mkdir -p -- "$fixture_home/.config" "$fakebin"
  command ln -sfn -- "$repo_dir" "$fixture_home/.config/zsh"
  print -r -- '#!/bin/sh
printf "%s\n" "0.60.0"
exit 0' >"$fakebin/fzf"
  command chmod +x -- "$fakebin/fzf"
  PATH="$fakebin:$old_path"
  rehash

  output=$(HOME="$fixture_home" zdoctor 2>&1); rc=$?
  assert_status "$rc" 1 'zdoctor fails an fzf older than the minimum' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$output" 'older than the 0.68.0 minimum' 'zdoctor names the outdated fzf' || { PATH=$old_path; rehash; return 1; }
  PATH=$old_path
  rehash
}

test_glyph_reporting() {
  local fixture_home="$tmp_dir/doctor-home" fakebin="$tmp_dir/doctor-fakebin"
  local old_path=$PATH output rc

  command mkdir -p -- "$fixture_home/.config"
  command ln -sfn -- "$repo_dir" "$fixture_home/.config/zsh"
  make_fakebin "$fakebin"
  PATH="$fakebin:$old_path"
  rehash
  unfunction cgm npkg zi 2>/dev/null || true
  source "$repo_dir/25-theme.zsh"

  output=$(HOME="$fixture_home" ZSH_UI_GLYPHS=nerd zdoctor 2>&1); rc=$?
  assert_status "$rc" 0 'zdoctor passes an explicit glyph tier' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$output" 'glyphs resolve to nerd' 'zdoctor reports the resolved glyph tier' || { PATH=$old_path; rehash; return 1; }

  output=$(HOME="$fixture_home" ZSH_UI_GLYPHS=bogus zdoctor 2>&1); rc=$?
  assert_status "$rc" 1 'zdoctor fails an invalid glyph setting' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$output" 'is invalid (use auto, nerd, unicode, or ascii)' 'zdoctor explains valid glyph tiers' || { PATH=$old_path; rehash; return 1; }
  PATH=$old_path
  rehash
}

main() {
  source "$repo_dir/55-ui-helpers.zsh"
  source "$repo_dir/60-functions.zsh"

  functions[_ui_plain_mode]='return 0'

  test_usage || return 1
  test_healthy_fixture || return 1
  test_bad_install_location || return 1
  test_explicit_probes || return 1
  test_old_fzf_is_a_failure || return 1
  test_glyph_reporting || return 1
}

main "$@"
