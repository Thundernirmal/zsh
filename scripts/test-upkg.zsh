#!/usr/bin/env zsh

set -u

repo_dir=${0:A:h:h}
original_path=$PATH
fakebin=$(mktemp -d)
tmp_prefix=$(mktemp -d)
trap 'rm -rf "$fakebin" "$tmp_prefix"' EXIT INT TERM

write_fake() {
  local name=$1
  shift

  {
    print '#!/bin/sh'
    print "$@"
  } >"$fakebin/$name"
  /usr/bin/chmod +x "$fakebin/$name"
}

assert_contains() {
  local haystack=$1
  local needle=$2
  local label=$3

  if [[ $haystack != *"$needle"* ]]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "missing: $needle"
    print -u2 -- "$haystack"
    return 1
  fi

  print -- "ok: $label"
}

assert_not_contains() {
  local haystack=$1
  local needle=$2
  local label=$3

  if [[ $haystack == *"$needle"* ]]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "unexpected: $needle"
    print -u2 -- "$haystack"
    return 1
  fi

  print -- "ok: $label"
}

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

assert_order() {
  local haystack=$1
  local first=$2
  local second=$3
  local label=$4

  if [[ $haystack != *"$first"*"$second"* ]]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "expected order: $first before $second"
    print -u2 -- "$haystack"
    return 1
  fi

  print -- "ok: $label"
}

main() {
  local output cmd_status inspect_tmp

write_fake pacman '
case "$*" in
  "-Qu") printf "%s\n" "coreutils 9.5-1 -> 9.6-1" ;;
  "-Syu") printf "%s\n" "pacman upgrade" ;;
  *) exit 2 ;;
esac
'

write_fake paru '
case "$*" in
  "-Qua") printf "%s\n" "yay-bin 12.4.2-1 -> 12.5.0-1" ;;
  "-Syu") printf "%s\n" "paru upgrade" ;;
  *) exit 2 ;;
esac
'

write_fake flatpak '
case "$*" in
  "remote-ls --user --updates") printf "%s\n" "org.example.App stable" ;;
  "update --user") printf "%s\n" "flatpak upgrade" ;;
  *) exit 2 ;;
esac
'

write_fake npm '
case "$*" in
  "config get prefix") printf "%s\n" "$UPKG_TEST_NPM_PREFIX" ;;
  "outdated -g --depth=0") printf "%s\n" "Package Current Wanted Latest Location"; printf "%s\n" "eslint 8.0.0 8.1.0 9.0.0 global"; exit 1 ;;
  "update -g") printf "%s\n" "npm upgrade" ;;
  *) exit 2 ;;
esac
'

write_fake mktemp '
exec /usr/bin/mktemp "$@"
'

write_fake rm '
exec /usr/bin/rm "$@"
'

  export PATH=$fakebin:$original_path
export UPKG_TEST_NPM_PREFIX=$tmp_prefix

source "$repo_dir/55-ui-helpers.zsh"
source "$repo_dir/60-functions.zsh"

  output=$(upkg managers)
  assert_contains "$output" 'paru' 'detects paru' || return 1
  assert_not_contains "$output" 'paru (active)' 'active managers keep plain output stable' || return 1
  assert_not_contains "$output" 'title=' 'manager listing stays free of debug leaks' || return 1
  assert_contains "$output" 'pacman (available via --only pacman)' 'labels pacman alternate' || return 1

output=$(upkg --only=npm,flatpak)
assert_contains "$output" '==> npm' 'equals --only keeps first selected manager first' || return 1
assert_contains "$output" '==> Flatpak' 'equals --only includes second selected manager' || return 1
assert_order "$output" '==> npm' '==> Flatpak' 'selected manager order' || return 1

output=$(upkg managers --only=npm,flatpak)
assert_contains "$output" '  - npm (selected)' 'manager listing marks npm selected' || return 1
assert_contains "$output" '  - flatpak (selected)' 'manager listing marks flatpak selected' || return 1
assert_order "$output" '  - npm (selected)' '  - flatpak (selected)' 'manager listing follows selected order' || return 1

output=$(upkg plan --only=paru)
cmd_status=$?
assert_status "$cmd_status" 0 'paru plan succeeds when repo and AUR checks succeed' || return 1
assert_contains "$output" 'Repo updates:' 'paru plan includes repo updates' || return 1
assert_contains "$output" 'AUR updates:' 'paru plan includes AUR updates' || return 1

  output=$(upkg upgrade --dry-run --only=npm)
  assert_contains "$output" 'eslint 8.0.0 8.1.0 9.0.0 global' 'dry-run previews npm instead of upgrading' || return 1

  write_fake npm '
case "$*" in
  "config get prefix") printf "%s\n" "$UPKG_TEST_NPM_PREFIX" ;;
  "outdated -g --depth=0") printf "%s\n" "npm notice using cached metadata"; printf "%s\n" "Package Current Wanted Latest Location"; printf "%s\n" "eslint 8.0.0 8.1.0 9.0.0 global"; exit 1 ;;
  "update -g") printf "%s\n" "npm upgrade" ;;
  *) exit 2 ;;
esac
'

  output=$(upkg --only=npm)
  cmd_status=$?
  assert_status "$cmd_status" 0 'npm outdated accepts header after a notice line' || return 1
  assert_contains "$output" 'eslint 8.0.0 8.1.0 9.0.0 global' 'npm outdated still prints package rows after a notice line' || return 1

  output=$(upkg --dry-run --only=flatpak)
  assert_contains "$output" 'org.example.App stable' 'bare dry-run previews selected managers' || return 1

write_fake pacman '
exit 1
'

write_fake paru '
case "$*" in
  "-Qua"|"-Qu") exit 1 ;;
  "-Syu") printf "%s\n" "paru upgrade" ;;
  *) exit 2 ;;
esac
'

output=$(upkg plan --only=paru)
cmd_status=$?
assert_status "$cmd_status" 0 'paru plan treats empty Arch rc=1 checks as up to date' || return 1
assert_contains "$output" 'No updates available.' 'paru plan reports no updates for empty Arch rc=1 checks' || return 1

write_fake pacman '
printf "%s\n" "pacman database is locked" >&2
exit 1
'

write_fake paru '
case "$*" in
  "-Qua") printf "%s\n" "yay-bin 12.4.2-1 -> 12.5.0-1" ;;
  "-Syu") printf "%s\n" "paru upgrade" ;;
  *) exit 2 ;;
esac
'

output=$(upkg plan --only=paru 2>&1)
cmd_status=$?
assert_status "$cmd_status" 1 'paru plan returns nonzero on repo check failure' || return 1
assert_contains "$output" 'Repo update check failed; continuing with AUR preview.' 'paru plan warns when repo preview fails' || return 1
assert_contains "$output" 'AUR updates:' 'paru plan still shows AUR updates when repo preview fails' || return 1

  output=$(upkg upgrade --only=paru 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'paru upgrade remains gated' || return 1
  assert_contains "$output" 'rerun with: upkg upgrade --sudo --only paru' 'paru upgrade remains gated' || return 1

  inspect_tmp=$(mktemp -d)
  /usr/bin/mkdir -p "$inspect_tmp/readable-dir" "$inspect_tmp/blocked-dir/inner" "$inspect_tmp/readable-tree" "$inspect_tmp/blocked-tree/inner"
  print -r -- 'ok' >"$inspect_tmp/readable-dir/file.txt"
  print -r -- 'ok' >"$inspect_tmp/blocked-dir/inner/file.txt"
  print -r -- 'ok' >"$inspect_tmp/readable-tree/visible.txt"
  print -r -- 'ok' >"$inspect_tmp/blocked-tree/inner/hidden.txt"
  /usr/bin/chmod 000 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"

  output=$(dusage "$inspect_tmp" 5 2>/dev/null)
  cmd_status=$?
  assert_status "$cmd_status" 0 'dusage tolerates unreadable entries when readable data exists' || {
    /usr/bin/chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"
    /usr/bin/rm -rf "$inspect_tmp"
    return 1
  }
  assert_contains "$output" 'readable-dir' 'dusage still reports readable entries' || {
    /usr/bin/chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"
    /usr/bin/rm -rf "$inspect_tmp"
    return 1
  }

  output=$(bigfiles "$inspect_tmp" 5 2>/dev/null)
  cmd_status=$?
  assert_status "$cmd_status" 0 'bigfiles tolerates unreadable subtrees when readable data exists' || {
    /usr/bin/chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"
    /usr/bin/rm -rf "$inspect_tmp"
    return 1
  }
  assert_contains "$output" 'visible.txt' 'bigfiles still reports readable files' || {
    /usr/bin/chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"
    /usr/bin/rm -rf "$inspect_tmp"
    return 1
  }

  /usr/bin/chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"
  /usr/bin/rm -rf "$inspect_tmp"
}

main "$@"
