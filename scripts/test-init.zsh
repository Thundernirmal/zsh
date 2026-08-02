#!/usr/bin/env zsh

set -u

repo_dir=${0:A:h:h}
tmp_home=$(mktemp -d) || { print -u2 -- 'fatal: mktemp failed for tmp_home'; exit 1; }
[ -n "$tmp_home" ] || { print -u2 -- 'fatal: mktemp returned empty tmp_home'; exit 1; }

cleanup() {
  command rm -rf "$tmp_home"
}

trap cleanup EXIT INT TERM

assert_status() {
  local actual=$1
  local expected=$2
  local label=$3

  if [[ $actual != "$expected" ]]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "expected status: $expected"
    print -u2 -- "actual status: $actual"
    return 1
  fi

  print -- "ok: $label"
}

assert_no_output() {
  local file=$1
  local label=$2

  if [[ -s $file ]]; then
    print -u2 -- "not ok: $label"
    command cat "$file" >&2
    return 1
  fi

  print -- "ok: $label"
}

assert_equals() {
  local actual=$1
  local expected=$2
  local label=$3

  if [[ $actual != "$expected" ]]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "expected: $expected"
    print -u2 -- "actual: $actual"
    return 1
  fi

  print -- "ok: $label"
}

run_init_case() {
  local label=$1
  local setup=${2-}
  local command_text cmd_status stdout_file stderr_file

  stdout_file=$(mktemp) || { print -u2 -- 'fatal: mktemp failed for stdout_file'; return 1; }
  stderr_file=$(mktemp) || { print -u2 -- 'fatal: mktemp failed for stderr_file'; command rm -f "$stdout_file"; return 1; }

  command_text=$setup
  if [[ -n $command_text ]]; then
    command_text+=$'\n'
  fi
  command_text+='source "$HOME/.config/zsh/init.zsh"'

  HOME="$tmp_home" zsh -fc "$command_text" >"$stdout_file" 2>"$stderr_file"
  cmd_status=$?

  assert_status "$cmd_status" 0 "$label exits cleanly" || {
    command cat "$stderr_file" >&2
    command rm -f "$stdout_file" "$stderr_file"
    return 1
  }
  assert_no_output "$stdout_file" "$label keeps stdout clean" || {
    command rm -f "$stdout_file" "$stderr_file"
    return 1
  }
  assert_no_output "$stderr_file" "$label keeps stderr clean" || {
    command rm -f "$stdout_file" "$stderr_file"
    return 1
  }

  command rm -f "$stdout_file" "$stderr_file"
}

test_glob_policy() {
  local fixture_dir="$tmp_home/glob-fixture"
  local fakebin="$tmp_home/glob-fakebin"
  local glob_log="$tmp_home/glob-stub.log"
  local ordinary_file="$tmp_home/glob-ordinary.out"
  local recursive_file="$tmp_home/glob-recursive.out"
  local explicit_file="$tmp_home/glob-explicit.out"
  local stdout_file="$tmp_home/glob.stdout"
  local stderr_file="$tmp_home/glob.stderr"
  local cmd_status output

  command mkdir -p -- "$fixture_dir/.git" "$fixture_dir/tree" "$fakebin" || return 1
  : > "$fixture_dir/visible"
  : > "$fixture_dir/.hidden"
  : > "$fixture_dir/.git/config"
  : > "$fixture_dir/tree/child"

  print -r -- '#!/bin/sh
printf "%s\n" "$@" > "$GLOB_STUB_LOG"' > "$fakebin/rm"
  command chmod +x "$fakebin/rm"

  HOME="$tmp_home" \
    PATH="$fakebin:$PATH" \
    GLOB_FIXTURE_DIR="$fixture_dir" \
    GLOB_ORDINARY_FILE="$ordinary_file" \
    GLOB_RECURSIVE_FILE="$recursive_file" \
    GLOB_EXPLICIT_FILE="$explicit_file" \
    GLOB_STUB_LOG="$glob_log" \
    zsh -fc '
      setopt GLOB_DOTS
      source "$HOME/.config/zsh/init.zsh"
      cd "$GLOB_FIXTURE_DIR" || exit 1
      print -rl -- * > "$GLOB_ORDINARY_FILE"
      print -rl -- **/* > "$GLOB_RECURSIVE_FILE"
      print -rl -- *(D) > "$GLOB_EXPLICIT_FILE"
      eval "rm -rf *"
    ' >"$stdout_file" 2>"$stderr_file"
  cmd_status=$?

  assert_status "$cmd_status" 0 'glob policy fixture exits cleanly' || {
    command cat "$stderr_file" >&2
    return 1
  }
  assert_no_output "$stdout_file" 'glob policy fixture keeps stdout clean' || return 1
  assert_no_output "$stderr_file" 'glob policy fixture keeps stderr clean' || return 1

  output=$(<"$ordinary_file")
  assert_equals "$output" $'tree\nvisible' 'ordinary glob excludes hidden entries after an inherited GLOB_DOTS setting' || return 1

  output=$(<"$recursive_file")
  assert_equals "$output" $'tree\ntree/child\nvisible' 'recursive ordinary glob excludes hidden entries' || return 1

  output=$(<"$explicit_file")
  assert_equals "$output" $'.git\n.hidden\ntree\nvisible' 'explicit (D) glob includes hidden entries' || return 1

  output=$(<"$glob_log")
  assert_equals "$output" $'-iv\n-rf\ntree\nvisible' 'stubbed destructive command receives visible matches only' || return 1

  [[ -e "$fixture_dir/visible" && -e "$fixture_dir/.hidden" && -d "$fixture_dir/.git" ]] || {
    print -u2 -- 'not ok: destructive-command fixture never removes real files'
    return 1
  }
  print -- 'ok: destructive-command fixture never removes real files'
}

main() {
  local -a high_risk_aliases
  local high_risk_alias_setup

  command mkdir -p "$tmp_home/.config" || { print -u2 -- 'fatal: mkdir failed for temp HOME'; return 1; }
  ln -s "$repo_dir" "$tmp_home/.config/zsh" || { print -u2 -- 'fatal: failed to link repo into temp HOME'; return 1; }

  high_risk_aliases=(
    'alias gcount="git shortlog --summary --numbered"'
    'alias gitcount="git shortlog --summary --numbered"'
    'alias gst="git status"'
    'alias grt="cd repo-root"'
  )
  high_risk_alias_setup=$(printf '%s\n' "${high_risk_aliases[@]}")

  run_init_case 'clean init smoke test' || return 1
  run_init_case 'high-risk alias init smoke test' "$high_risk_alias_setup" || return 1
  test_glob_policy || return 1
}

main "$@"
