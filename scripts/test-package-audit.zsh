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
(
  _upkg_detect_managers() {
    typeset -ga _UPKG_ACTIVE_MANAGERS=(brew flatpak)
    typeset -ga _UPKG_ALTERNATE_MANAGERS=()
  }
  export AUDIT_LOG="$scratch/cancel-calls"
  write_fake brew 'printf "%s\n" "brew $*" >> "$AUDIT_LOG"; exit "$AUDIT_RC"'
  write_fake flatpak 'printf "%s\n" "flatpak $*" >> "$AUDIT_LOG"; exit 0'
  PATH="$scratch:$original_path"
  for code in 129 130 143; do
    export AUDIT_RC=$code
    for operation in upgrade clean; do
      : > "$AUDIT_LOG"
      upkg "$operation" --only brew,flatpak >/dev/null 2>&1
      assert test "$?" -eq "$code"
      assert test "${_UPKG_SUMMARY_STATE[brew]}" = cancelled
      assert test "${#_UPKG_SUMMARY_ORDER}" -eq 1
      calls=$(<"$AUDIT_LOG")
      call_lines=( "${(@f)calls}" )
      assert test "${#call_lines}" -eq 1
    done
  done
  export AUDIT_RC=1
  upkg upgrade --only brew,flatpak >/dev/null 2>&1
  assert test "$?" -eq 1
  assert test "${#_UPKG_SUMMARY_ORDER}" -eq 2
) || exit 1
print 'ok: cancellation stops managers and cleanup phases while ordinary errors continue'
(
  _zsh_functions_load_domain nix || exit 1
  write_fake jq 'exit 0'
  PATH="$scratch:$original_path"
  _npkg_nix() { return "$AUDIT_RC"; }
  _upkg_detect_managers() {
    typeset -ga _UPKG_ACTIVE_MANAGERS=(nix brew)
    typeset -ga _UPKG_ALTERNATE_MANAGERS=()
  }
  for code in 129 130 143; do
    export AUDIT_RC=$code
    upkg outdated --only nix,brew >/dev/null 2>&1
    assert test "$?" -eq "$code"
    assert test "${#_UPKG_SUMMARY_ORDER}" -eq 1
    assert test "${_UPKG_SUMMARY_STATE[nix]}" = cancelled
  done
) || exit 1
print 'ok: cancelled Nix profile queries stop later package managers'
if command -v jq >/dev/null 2>&1; then
  (
    _zsh_functions_load_domain nix || exit 1
    _npkg_nix() {
      print -r -- '{"elements":{"pkg":{"active":true,"originalUrl":"nixpkgs","url":"github:NixOS/nixpkgs/rev","attrPath":"packages.test.pkg","storePaths":["/nix/store/pkg"]}}}'
    }
    _npkg_eval_installable_record() { return "$AUDIT_RC"; }
    _upkg_detect_managers() {
      typeset -ga _UPKG_ACTIVE_MANAGERS=(nix brew)
      typeset -ga _UPKG_ALTERNATE_MANAGERS=()
    }
    for code in 129 130 143; do
      AUDIT_RC=$code
      upkg outdated --only nix,brew >/dev/null 2>&1
      assert test "$?" -eq "$code"
      assert test "${#_UPKG_SUMMARY_ORDER}" -eq 1
    done
  ) || exit 1
  print 'ok: cancelled Nix evaluation workers stop later package managers'
fi
