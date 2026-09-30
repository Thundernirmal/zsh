#!/usr/bin/env zsh
# Cross-backend regressions from the package/system command audit.
emulate -L zsh
setopt NO_UNSET
repo_dir=${0:A:h:h}
scratch=$(mktemp -d) || exit 1
original_path=$PATH
trap 'PATH=$original_path; command rm -rf -- "$scratch"' EXIT
source "$repo_dir/60-functions.zsh"
upkg help >/dev/null || exit 1
_ui_plain_mode() { return 0; }
assert() {
  if ! "$@"; then
    print -u2 -r -- "not ok: $*"
    exit 1
  fi
}
write_fake() {
  print -r -- '#!/bin/sh' > "$scratch/$1"
  print -r -- "$2" >> "$scratch/$1"
  command chmod +x "$scratch/$1"
}
# Detection override and backends stay in subshells so later tests remain isolated.
(
  _upkg_detect_managers() {
    typeset -ga _UPKG_ACTIVE_MANAGERS=(brew flatpak)
    typeset -ga _UPKG_ALTERNATE_MANAGERS=()
  }
  _upkg_run_upgrade_brew() { print -r -- called >> "$scratch/calls"; }
  _upkg_run_upgrade_flatpak() { print -r -- called >> "$scratch/calls"; }
  for flag in --only --skip; do
    for empty in '' '   '; do
      upkg upgrade "$flag" "$empty" >/dev/null 2>&1
      assert test "$?" -eq 1
      upkg upgrade "$flag=$empty" >/dev/null 2>&1
      assert test "$?" -eq 1
    done
  done
  assert test ! -e "$scratch/calls"
) || exit 1
print 'ok: empty manager filters never invoke upgrade backends'
