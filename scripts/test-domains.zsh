#!/usr/bin/env zsh
emulate -L zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL
repo_dir=${0:A:h:h}
tmp_dir=$(command mktemp -d)
trap 'command rm -rf -- "$tmp_dir"' EXIT

zsh -fc '
  source "$1/55-ui-helpers.zsh"
  source "$1/60-functions.zsh"
  (( ! $+functions[_upkg_usage] && ! $+functions[_ui_safe_text] )) || exit 1
  mkcd "$2/new" || exit 2
  [[ $PWD == "$2/new" ]] || exit 3
  (( ${_ZSH_FUNCTION_DOMAINS_LOADED[files]:-0} && ! ${_ZSH_FUNCTION_DOMAINS_LOADED[system]:-0} && ! $+functions[_upkg_usage] )) || exit 4
  path >/dev/null || exit 5
  (( ${_ZSH_FUNCTION_DOMAINS_LOADED[system]:-0} && ! $+functions[_upkg_usage] && ! $+functions[_npkg_usage] )) || exit 6
  fbr --help >/dev/null || exit 7
  (( ${_ZSH_FUNCTION_DOMAINS_LOADED[git]:-0} && ! $+functions[_upkg_usage] )) || exit 8
  upkg --help >/dev/null || exit 9
  (( ${_ZSH_FUNCTION_DOMAINS_LOADED[upkg]:-0} && $+functions[_upkg_run_search_apt] && ! $+functions[_npkg_usage] )) || exit 10
  _zsh_functions_load ../../unexpected && exit 11
  source "$1/60-functions.zsh"
  path >/dev/null || exit 12
  print -r -- "ok: public calls load only their fixed domains and survive re-sourcing"
' zsh "$repo_dir" "$tmp_dir"

# A tool removed between startup and first use must not leave a recursive loader.
zsh_bin=$commands[zsh]
rm_bin=$commands[rm]
command mkdir -p -- "$tmp_dir/bin"
print -r -- '#!/bin/sh
exit 88' > "$tmp_dir/bin/nix"
command chmod +x -- "$tmp_dir/bin/nix"
PATH="$tmp_dir/bin" "$zsh_bin" -fc '
  source "$1/60-functions.zsh"
  (( $+functions[npkg] )) || exit 20
  "$3" -- "$2/bin/nix"
  rehash
  npkg --help >/dev/null || exit 21
  npkg list >/dev/null 2>&1
  (( $? == 127 )) || exit 22
  print -r -- "ok: removing Nix after startup fails normally without recursive lazy dispatch"
' zsh "$repo_dir" "$tmp_dir" "$rm_bin"

# Exercise the cross-domain search from a fresh shell, before any npkg call.
print -r -- '#!/bin/sh
printf "%s\n" "$*" > "$NIX_SEARCH_LOG"
case "$*" in
  "--extra-experimental-features nix-command flakes search nixpkgs ripgrep")
    printf "* legacyPackages.x86_64-linux.ripgrep (14.1.0)\n  Search text\n"
    exit 0 ;;
  *) exit 88 ;;
esac' > "$tmp_dir/bin/nix"
command chmod +x -- "$tmp_dir/bin/nix"
PATH="$tmp_dir/bin:$PATH" NIX_SEARCH_LOG="$tmp_dir/nix-search.log" "$zsh_bin" -fc '
  source "$1/55-ui-helpers.zsh"
  source "$1/60-functions.zsh"
  (( ! $+functions[_npkg_nix] )) || exit 30
  upkg search ripgrep --only=nix > "$2/search.out" 2>&1
  rc=$?
  if (( rc )); then
    command cat "$2/search.out" >&2
    print -u2 -r -- "not ok: fresh-shell Nix search exits $rc"
    exit 31
  fi
  [[ $(<"$2/search.out") == *ripgrep* && -s $NIX_SEARCH_LOG ]] || exit 32
  print -r -- "ok: fresh-shell upkg Nix search loads its adapter without prior npkg use"
' zsh "$repo_dir" "$tmp_dir"
