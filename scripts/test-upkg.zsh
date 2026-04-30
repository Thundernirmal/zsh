#!/usr/bin/env zsh

set -u

repo_dir=${0:A:h:h}
original_path=$PATH
fakebin=$(mktemp -d)
tmp_prefix=$(mktemp -d)
inspect_tmp=''

cleanup() {
  if [ -n "${inspect_tmp:-}" ] && [ -d "$inspect_tmp" ]; then
    /usr/bin/chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree" 2>/dev/null || true
    /usr/bin/rm -rf "$inspect_tmp"
  fi
  /usr/bin/rm -rf "$fakebin" "$tmp_prefix"
}

trap cleanup EXIT INT TERM

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

assert_file_contains() {
  local file=$1
  local needle=$2
  local label=$3
  local content

  content=$(/usr/bin/cat -- "$file") || {
    print -u2 -- "not ok: $label"
    print -u2 -- "failed to read: $file"
    return 1
  }

  assert_contains "$content" "$needle" "$label"
}

main() {
  local output cmd_status

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

write_fake ss '
cat <<'"'"'EOF'"'"'
Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
tcp LISTEN 0 128 0.0.0.0:3000 0.0.0.0:* users:(("node",pid=111,fd=20),("node",pid=112,fd=21),("node",pid=113,fd=22))
EOF
'

write_fake nix '
while [ "$1" = "--extra-experimental-features" ]; do
  shift 2
done

case "$*" in
  "profile list --json")
    cat <<'"'"'EOF'"'"'
{"elements":[
  {"active":true,"originalUrl":"nixpkgs","attrPath":"pkg.one","storePaths":["/nix/store/hash-pkg-one-1.0"]},
  {"active":true,"originalUrl":"nixpkgs","attrPath":"pkg.two","storePaths":["/nix/store/hash-pkg-two-1.0"]},
  {"active":true,"originalUrl":"nixpkgs","attrPath":"pkg.three","storePaths":["/nix/store/hash-pkg-three-1.0"]},
  {"active":true,"originalUrl":"nixpkgs","attrPath":"pkg.four","storePaths":["/nix/store/hash-pkg-four-1.0"]}
]}
EOF
    ;;
  "eval --raw nixpkgs#pkg.one.version") printf "%s\n" "1.0" ;;
  "eval --raw nixpkgs#pkg.two.version") printf "%s\n" "2.0" ;;
  "eval --raw nixpkgs#pkg.three.version") printf "%s\n" "1.0" ;;
  "eval --raw nixpkgs#pkg.four.version") printf "%s\n" "3.0" ;;
  *) exit 2 ;;
esac
'

  export PATH=$fakebin:$original_path
  export UPKG_TEST_NPM_PREFIX=$tmp_prefix

  local fallback_file rich_check_file
  fallback_file="$tmp_prefix/fallback-load.zsh"
  rich_check_file="$tmp_prefix/rich-check.zsh"

  {
    print -- 'unset -f _ui_plain_mode _ui_ascii_mode _ui_repeat _ui_color _ui_reset _ui_bold _ui_has_icons _ui_icon _ui_title_line _ui_section_break _ui_panel_prefix _ui_panel_kv _ui_badge _ui_human_kib _ui_usage_entry_icon _ui_truncate _ui_pad _ui_bar _ui_visible_count _ui_term_width 2>/dev/null || true'
    print -- "source '$repo_dir/60-functions.zsh'"
    print -- '_ui_truncate 10 "My File.txt"'
    print -- '_ui_pad left 20 "My File.txt"'
  } > "$fallback_file"
  output=$(TERM=xterm zsh "$fallback_file")
  cmd_status=$?
  assert_status "$cmd_status" 0 '60-functions fallback helpers load without ui module' || return 1
  assert_contains "$output" 'My File.txt' 'fallback helpers preserve spaced text' || return 1

  {
    print -- "source '$repo_dir/55-ui-helpers.zsh'"
    print -- 'if _ui_is_rich_terminal; then print -- rich; else print -- plain; fi'
  } > "$rich_check_file"
  output=$(TERM= LANG=en_US.UTF-8 zsh "$rich_check_file")
  cmd_status=$?
  assert_status "$cmd_status" 0 'ui helper TERM check script runs' || return 1
  assert_contains "$output" 'plain' 'unset TERM no longer enables rich mode' || return 1

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

  inspect_tmp=$(mktemp -d) || {
    print -u2 -- 'not ok: mktemp creates inspect tmpdir'
    return 1
  }
  if [ -z "$inspect_tmp" ]; then
    print -u2 -- 'not ok: mktemp returned empty inspect tmpdir'
    return 1
  fi
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

  functions[_ui_is_rich_terminal]='return 0'
  functions[_ui_plain_mode]='return 1'
  functions[_ui_term_width]='print -r -- 120'
  functions[_ui_term_height]='print -r -- 12'
  functions[_ui_color]=':'
  functions[_ui_reset]=':'
  functions[_ui_bold]=':'
  functions[_ui_has_icons]='return 1'

  output=$(ports)
  cmd_status=$?
  assert_status "$cmd_status" 0 'ports rich parser succeeds for multi-owner sockets' || return 1
  assert_contains "$output" 'node, node, node' 'ports preserves all socket owners' || return 1
  assert_contains "$output" 'pid=111,112,113' 'ports preserves all socket pids' || return 1

  if command -v jq >/dev/null 2>&1; then
    output=$(npkg outdated)
    cmd_status=$?
    assert_status "$cmd_status" 0 'npkg outdated rich mode succeeds with fake nix data' || return 1
    assert_contains "$output" '2 upgrade(s) available. Run npkg upgrade to apply.' 'npkg rich summary counts hidden upgrades' || return 1

    functions[_ui_is_rich_terminal]='return 1'
    functions[_ui_plain_mode]='return 0'
    output=$(npkg outdated)
    cmd_status=$?
    assert_status "$cmd_status" 0 'npkg outdated plain mode succeeds with full-width formatting' || return 1
    assert_contains "$output" 'Package                   Installed            Available            Status' 'npkg plain output restores wide columns' || return 1
  fi

  /usr/bin/chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"
  /usr/bin/rm -rf "$inspect_tmp"
}

main "$@"
