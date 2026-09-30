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
(
  write_fake dnf '
case "$*" in
  "-q --color=never list --available *ripgrep*")
    printf "%s\n" "Updating and loading repositories:" "Repositories loaded." "Available packages" "ripgrep.x86_64 15.2.0-1.fc44 updates"
    printf "%s\n" "metadata warning" >&2 ;;
  "-q --color=never list --available *empty4*") printf "%s\n" "Error: No matching Packages to list" >&2; exit 1 ;;
  "-q --color=never list --available *empty5*") printf "%s\n" "No matches found." >&2; exit 1 ;;
  *) printf "%s\n" "repository failure" >&2; exit 1 ;;
esac'
  PATH="$scratch:$original_path"
  _UPKG_SEARCH_ROWS=()
  _upkg_run_search_dnf ripgrep >"$scratch/dnf-out" 2>"$scratch/dnf-err"
  assert test "$?" -eq 0
  assert test "${#_UPKG_SEARCH_ROWS}" -eq 1
  assert test "${_UPKG_SEARCH_ROWS[1]}" = $'dnf\tripgrep.x86_64\t15.2.0-1.fc44\t'
  assert test "$(<"$scratch/dnf-err")" = 'metadata warning'
  for query in empty4 empty5; do
    _upkg_run_search_dnf "$query" >/dev/null 2>&1
    assert test "$?" -eq 0
    assert test "$_UPKG_LAST_STATE" = 'no matches'
  done
  _upkg_run_search_dnf broken >/dev/null 2>&1
  assert test "$?" -eq 1
  assert test "$_UPKG_LAST_STATE" = failed
) || exit 1
print 'ok: DNF4/5 search distinguishes packages, diagnostics, no matches, and failures'
if command -v jq >/dev/null 2>&1; then
  (
    _zsh_functions_load_domain nix || exit 1
    _npkg_nix() { print -r -- "$AUDIT_PROFILE"; }
    _npkg_eval_installable_record() { print -r -- '{"paths":["/nix/store/pkg"],"version":"1"}'; }
    inactive='{"active":false,"originalUrl":"nixpkgs","attrPath":"packages.test.inactive","storePaths":[]}'
    active='{"originalUrl":"nixpkgs","url":"github:NixOS/nixpkgs/rev","attrPath":"packages.test.pkg","storePaths":["/nix/store/pkg"]}'
    for AUDIT_PROFILE in "{\"elements\":{\"inactive\":$inactive,\"active\":$active}}" "{\"elements\":[$inactive,$active]}"; do
      npkg outdated >/dev/null 2>&1
      assert test "$?" -eq 0
      assert test "$_NPKG_OUTDATED_TOTAL" -eq 1
      assert test "$_NPKG_OUTDATED_STATE" = current
      # Capture actual picker candidates, cancel before any removal operation.
      _npkg_require_picker() { return 0; }
      _fzf_picker_multi_args() { REPLY=''; reply=(); }
      _fzf_picker_context_args() { reply=(); }
      _fzf_picker_preview_args() { reply=(); }
      export AUDIT_CANDIDATES="$scratch/nix-candidates"
      write_fake fzf 'cat > "$AUDIT_CANDIDATES"; exit 1'
      PATH="$scratch:$original_path"
      command rm -f -- "$scratch/jq"
      npkg remove >/dev/null 2>&1
      candidate_text=$(<"$AUDIT_CANDIDATES")
      assert test "${candidate_text#*inactive}" = "$candidate_text"
      assert test -n "$candidate_text"
    done
  ) || exit 1
  print 'ok: inactive object/array Nix elements are excluded from checks and removal'
fi
(
  for audit_manager in brew flatpak pacman paru; do
    write_fake "$audit_manager" 'printf "%s\n" "query warning" >&2; exit "${AUDIT_RC:-0}"'
  done
  PATH="$scratch:$original_path"
  for audit_manager in brew flatpak pacman paru; do
    _upkg_detect_managers() {
      typeset -ga _UPKG_ACTIVE_MANAGERS=("$audit_manager")
      typeset -ga _UPKG_ALTERNATE_MANAGERS=()
    }
    AUDIT_RC=0; export AUDIT_RC
    upkg outdated --only "$audit_manager" >"$scratch/warning-out" 2>"$scratch/warning-err"
    assert test "$?" -eq 0
    assert test "${_UPKG_SUMMARY_STATE[$audit_manager]}" = 'up to date'
    assert test -s "$scratch/warning-err"
    output=$(<"$scratch/warning-out")
    assert test "${output#*query warning}" = "$output"
    if [[ $audit_manager == pacman || $audit_manager == paru ]]; then
      AUDIT_RC=1
      upkg outdated --only "$audit_manager" >/dev/null 2>&1
      assert test "$?" -eq 1
    fi
  done
) || exit 1
print 'ok: warning-only update checks stay current and Arch errors remain failures'
