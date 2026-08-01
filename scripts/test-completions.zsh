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

spec_values() {
  local spec

  reply=()
  for spec in "$@"; do
    reply+=("${spec%%:*}")
  done
}

assert_unique() {
  local label=$1 value
  shift
  local -A seen

  for value in "$@"; do
    if [[ -n ${seen[$value]-} ]]; then
      print -u2 -- "not ok: $label"
      print -u2 -- "duplicate value: $value"
      return 1
    fi
    seen[$value]=1
  done

  print -- "ok: $label"
}

file_contents() {
  local file=$1

  [[ -r $file ]] && print -r -- "$(<"$file")"
}

test_without_compinit() {
  "$zsh_bin" -f -c '
    source "$1"
    (( ! $+functions[_zsh_upkg] ))
    (( ! $+parameters[_ZSH_UPKG_MANAGERS] ))
  ' zsh "$repo_dir/66-compdefs.zsh"
  assert_status "$?" 0 'module is a no-op before compinit'
}

test_registration() {
  local command_name expected
  local -A mappings=(
    upkg _zsh_upkg
    extract _zsh_extract
    peek _zsh_peek
    mkcd _zsh_mkcd
    ff _zsh_find_helper
    ft _zsh_find_helper
    dusage _zsh_dusage
    bigfiles _zsh_bigfiles
    fkill _zsh_fkill
    headers _zsh_headers
    zhelp _zsh_zhelp
    fbr _zsh_no_arguments
    croot _zsh_no_arguments
    path _zsh_no_arguments
    ports _zsh_no_arguments
    myip _zsh_no_arguments
    gitcount _zsh_no_arguments
    fanprofile _zsh_no_arguments
    tips _zsh_no_arguments
  )

  autoload -Uz compinit
  compinit -D -i

  unset '_comps[npkg]'
  unfunction npkg 2>/dev/null || true
  source "$repo_dir/65-help.zsh"
  source "$repo_dir/66-compdefs.zsh"

  for command_name expected in ${(kv)mappings}; do
    assert_equals "${_comps[$command_name]-}" "$expected" "$command_name uses $expected" || return 1
  done

  assert_equals "${_comps[npkg]-}" '' 'npkg is not registered when its function is unavailable' || return 1

  npkg() { :; }
  source "$repo_dir/66-compdefs.zsh"
  assert_equals "${_comps[npkg]-}" '_zsh_npkg' 'npkg is registered when its function exists' || return 1
}

test_zhelp_values() {
  local spec
  local -a captured values

  _describe() { captured=( "${(@P)4}" ); }
  _zsh_zhelp_commands
  for spec in "${captured[@]}"; do
    values+=("${spec%%:*}")
  done
  unfunction _describe

  assert_equals "${(j: :)values}" "${(j: :)_ZSH_HELP_ORDER}" 'zhelp completion offers every catalogue command' || return 1
}

test_static_values() {
  local -a values captured manager_values

  spec_values "${_ZSH_UPKG_COMMAND_SPECS[@]}"
  values=( "${reply[@]}" )
  assert_equals "${(j: :)values}" 'outdated check list search upgrade up update plan managers help' 'upkg commands match the public interface' || return 1
  assert_unique 'upkg command values are unique' "${values[@]}" || return 1

  spec_values "${_ZSH_UPKG_FLAGS[@]}"
  values=( "${reply[@]}" )
  assert_equals "${(j: :)values}" '--only --skip --sudo --dry-run --help' 'upkg flags match the public interface' || return 1
  assert_unique 'upkg flag values are unique' "${values[@]}" || return 1

  assert_equals "${(j: :)_ZSH_UPKG_MANAGERS}" 'apt dnf pacman paru brew flatpak nix npm' 'upkg manager IDs match the supported backends' || return 1
  assert_unique 'upkg manager IDs are unique' "${_ZSH_UPKG_MANAGERS[@]}" || return 1

  _values() { captured=( "$@" ); }
  _zsh_upkg_managers
  assert_equals "${captured[1]-} ${captured[2]-}" '-s ,' 'upkg manager completion uses a comma separator' || return 1
  manager_values=( "${(@)captured[4,-1]%%\[*}" )
  assert_equals "${(j: :)manager_values}" 'apt dnf pacman paru brew flatpak nix npm' 'comma completion offers every upkg manager ID' || return 1
  unfunction _values

  spec_values "${_ZSH_NPKG_COMMAND_SPECS[@]}"
  values=( "${reply[@]}" )
  assert_equals "${(j: :)values}" 'add install i find pick fzf search s list ls remove rm uninstall delete outdated check diff refresh upgrade up update help' 'npkg commands and aliases match the public interface' || return 1
  assert_unique 'npkg command values are unique' "${values[@]}" || return 1

  assert_equals "${(j: :)_ZSH_EXTRACT_EXTENSIONS}" 'tar.bz2 tar.gz tar.xz tar.zst bz2 rar gz tar tbz2 tgz tzst zip Z 7z' 'extract completion covers every supported extension' || return 1
  assert_unique 'extract extensions are unique' "${_ZSH_EXTRACT_EXTENSIONS[@]}" || return 1
}

test_cached_npkg_attributes() {
  local cache_root="$tmp_dir/cache"
  local fakebin="$tmp_dir/cache-fakebin"
  local invocation_log="$tmp_dir/cache-invocations"
  local old_path=$PATH rc
  local -a offered

  command mkdir -p -- "$cache_root/npkg" "$fakebin"
  print -r -- '#!/bin/sh
printenv _ZSH_COMPLETION_INVOCATION >> "$_ZSH_COMPLETION_LOG"' > "$fakebin/nix"
  command chmod +x "$fakebin/nix"

  XDG_CACHE_HOME=$cache_root
  _ZSH_COMPLETION_LOG=$invocation_log
  _ZSH_COMPLETION_INVOCATION=nix
  export _ZSH_COMPLETION_LOG _ZSH_COMPLETION_INVOCATION
  PATH="$fakebin:$PATH"

  _zsh_npkg_cached_attributes
  assert_equals "${#reply[@]}" 0 'missing npkg cache returns no candidates' || return 1
  assert_equals "$(file_contents "$invocation_log")" '' 'missing npkg cache does not invoke Nix' || return 1

  _wanted() { offered=( "${reply[@]}" ); }
  _zsh_npkg_cached_packages
  rc=$?
  assert_status "$rc" 1 'missing npkg cache declines package completion cleanly' || return 1

  print -l -- zoxide ripgrep > "$cache_root/npkg/nixpkgs-attrs-aarch64-linux.txt"
  print -l -- ripgrep bat > "$cache_root/npkg/nixpkgs-attrs-x86_64-linux.txt"

  _zsh_npkg_cached_attributes
  assert_equals "${(j: :)reply}" 'zoxide ripgrep bat' 'existing npkg caches provide deduplicated attributes' || return 1
  assert_equals "$(file_contents "$invocation_log")" '' 'cached npkg completion does not invoke Nix' || return 1

  _zsh_npkg_cached_packages
  assert_status "$?" 0 'existing npkg cache activates package completion' || return 1
  assert_equals "${(j: :)offered}" 'zoxide ripgrep bat' 'npkg package completion offers cached attributes' || return 1
  unfunction _wanted

  PATH=$old_path
  unset XDG_CACHE_HOME _ZSH_COMPLETION_LOG _ZSH_COMPLETION_INVOCATION
}

test_source_has_no_subprocesses() {
  local fakebin="$tmp_dir/source-fakebin"
  local invocation_log="$tmp_dir/source-invocations"
  local tool

  command mkdir -p -- "$fakebin"
  for tool in git nix fzf find jq; do
    print -r -- '#!/bin/sh
printf "%s\n" "$0" >> "$_ZSH_COMPLETION_LOG"' > "$fakebin/$tool"
    command chmod +x "$fakebin/$tool"
  done

  _ZSH_COMPLETION_LOG=$invocation_log PATH=$fakebin "$zsh_bin" -f -c '
    compdef() { :; }
    npkg() { :; }
    source "$1"
  ' zsh "$repo_dir/66-compdefs.zsh"
  assert_status "$?" 0 'completion module sources with fake external tools on PATH' || return 1
  assert_equals "$(file_contents "$invocation_log")" '' 'completion module sourcing invokes no external tools' || return 1
}

main() {
  test_without_compinit || return 1
  test_registration || return 1
  test_zhelp_values || return 1
  test_static_values || return 1
  test_cached_npkg_attributes || return 1
  test_source_has_no_subprocesses || return 1
}

main "$@"
