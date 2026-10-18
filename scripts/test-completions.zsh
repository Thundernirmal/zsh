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
    zdoctor _zsh_zdoctor
    ztheme _zsh_ztheme
    cgm _zsh_cgm
    fbr _zsh_no_arguments
    croot _zsh_no_arguments
    path _zsh_no_arguments
    ports _zsh_no_arguments
    weather _zsh_no_arguments
    myip _zsh_no_arguments
    gitcount _zsh_no_arguments
    fanprofile _zsh_no_arguments
    tips _zsh_no_arguments
  )

  autoload -Uz compinit
  compinit -D -i

  unset '_comps[npkg]'
  unfunction npkg 2>/dev/null || true
  source "$repo_dir/62-cgm.zsh"
  source "$repo_dir/65-help.zsh"
  source "$repo_dir/66-compdefs.zsh"

  for command_name expected in ${(kv)mappings}; do
    assert_equals "${_comps[$command_name]-}" "$expected" "$command_name uses $expected" || return 1
  done

  assert_equals "${_comps[npkg]-}" '' 'npkg is not registered when its function is unavailable' || return 1

  npkg() { :; }
  _npkg_cache_dir() {
    if [[ -n ${XDG_CACHE_HOME:-} && $XDG_CACHE_HOME == /* ]]; then
      print -r -- "$XDG_CACHE_HOME/npkg"
    elif [[ -n ${HOME:-} && $HOME == /* ]]; then
      print -r -- "$HOME/.cache/npkg"
    else
      return 1
    fi
  }
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
  assert_equals "${(j: :)values}" 'outdated check list search upgrade up update plan clean managers help' 'upkg commands match the public interface' || return 1
  assert_unique 'upkg command values are unique' "${values[@]}" || return 1
  assert_equals "${_ZSH_UPKG_COMMAND_SPECS[9]}" 'clean:Remove unused packages and manager-owned caches' 'upkg completion describes cleanup explicitly' || return 1

  spec_values "${_ZSH_UPKG_FLAGS[@]}"
  values=( "${reply[@]}" )
  assert_equals "${(j: :)values}" '--only --skip --sudo --dry-run --help' 'upkg flags match the public interface' || return 1
  assert_unique 'upkg flag values are unique' "${values[@]}" || return 1
  assert_equals "${_ZSH_UPKG_FLAGS[3]}" '--sudo:Authorize privileged upgrade and cleanup backends' 'upkg sudo completion describes cleanup authorization' || return 1
  assert_equals "${_ZSH_UPKG_FLAGS[4]}" '--dry-run:Inventory updates or preview cleanup without changing packages' 'upkg dry-run completion covers cleanup previews' || return 1

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

  spec_values "${_ZSH_ZTHEME_COMMAND_SPECS[@]}"
  values=( "${reply[@]}" )
  assert_equals "${(j: :)values}" 'list current show use reset export' 'ztheme completion covers every public subcommand' || return 1
  assert_equals "${(j: :)_ZSH_ZTHEME_NAMES}" "${(j: :)_ZSH_UI_THEME_NAMES}" 'ztheme completion reuses the built-in theme owner' || return 1
  assert_unique 'ztheme completion values are unique' "${_ZSH_ZTHEME_NAMES[@]}" || return 1

  spec_values "${_ZSH_CGM_COMMAND_SPECS[@]}"
  values=( "${reply[@]}" )
  assert_equals "${(j: :)values}" 'set list status check env unset delete help' 'cgm commands match the public interface' || return 1
  assert_unique 'cgm command values are unique' "${values[@]}" || return 1

  assert_equals "${(j: :)_ZSH_EXTRACT_EXTENSIONS}" 'tar.bz2 tar.gz tar.xz tar.zst tar.lzma tar.lz bz2 rar gz xz lzma zst tar tbz tbz2 tgz txz tzst zip Z 7z' 'extract completion covers every supported extension' || return 1
  assert_unique 'extract extensions are unique' "${_ZSH_EXTRACT_EXTENSIONS[@]}" || return 1
}

test_extract_completion_drift() {
  local line extension
  local -a dispatch_extensions

  source "$repo_dir/60-functions.zsh"
  _zsh_functions_load || return 1
  for line in "${(f)functions[extract]}"; do
    if [[ $line == *'(*.'*') '* ]]; then
      extension=${line#*\(\*.}
      extension=${extension%%\)*}
      dispatch_extensions+=( "$extension" )
    fi
  done

  dispatch_extensions=( "${(@o)dispatch_extensions}" )
  local -a completion_extensions=( "${(@o)_ZSH_EXTRACT_EXTENSIONS}" )
  assert_equals "${(j: :)dispatch_extensions}" "${(j: :)completion_extensions}" 'extract completion stays synchronized with dispatch suffixes' || return 1
}

test_cached_cgm_names() {
  local data_root="$tmp_dir/cgm-data"
  local invocation_log="$tmp_dir/cgm-invocations"
  local old_data_home=${XDG_DATA_HOME-}
  local had_data_home=${+XDG_DATA_HOME}
  local -a offered

  command mkdir -p -- "$data_root/cgm/entries"
  : > "$data_root/cgm/entries/OPENAI_KEY"
  : > "$data_root/cgm/entries/GITHUB_PAT"
  : > "$data_root/cgm/entries/not-valid-name"
  command ln -s -- "$invocation_log" "$data_root/cgm/entries/SYMLINK_KEY"
  : > "$invocation_log"

  XDG_DATA_HOME=$data_root
  _values() { offered=( "${(@)argv[2,-1]}" ); }
  _zsh_cgm_saved_credentials
  assert_status "$?" 0 'cgm completion reads the name catalogue successfully' || return 1
  assert_equals "${(j: :)offered}" 'GITHUB_PAT OPENAI_KEY' 'cgm completion offers only valid regular-file credential names' || return 1
  assert_equals "$(file_contents "$invocation_log")" '' 'cgm completion never invokes or follows a secret-bearing backend path' || return 1
  unfunction _values

  if (( had_data_home )); then
    XDG_DATA_HOME=$old_data_home
  else
    unset XDG_DATA_HOME
  fi
}

test_cached_npkg_attributes() {
  local cache_root="$tmp_dir/cache"
  local fallback_home="$tmp_dir/cache-home"
  local fakebin="$tmp_dir/cache-fakebin"
  local invocation_log="$tmp_dir/cache-invocations"
  local old_path=$PATH old_home=${HOME-} rc
  integer had_home=${+HOME}
  integer first_parse_count second_parse_count
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
  first_parse_count=$_ZSH_NPKG_COMPLETION_PARSE_COUNT

  _zsh_npkg_cached_attributes
  second_parse_count=$_ZSH_NPKG_COMPLETION_PARSE_COUNT
  assert_equals "$second_parse_count" "$first_parse_count" 'repeated npkg completion reuses parsed cache files in this shell' || return 1

  print -l -- zoxide ripgrep bat > "$cache_root/npkg/nixpkgs-attrs-aarch64-linux.txt"
  command touch -d @1 "$cache_root/npkg/nixpkgs-attrs-aarch64-linux.txt"
  _zsh_npkg_cached_attributes
  assert_equals "${(j: :)reply}" 'zoxide ripgrep bat' 'npkg completion reparses a cache file after its mtime changes' || return 1
  assert_equals "$((_ZSH_NPKG_COMPLETION_PARSE_COUNT))" "$((first_parse_count + 1))" 'npkg cache invalidation parses only the changed file' || return 1

  _zsh_npkg_cached_packages
  assert_status "$?" 0 'existing npkg cache activates package completion' || return 1
  assert_equals "${(j: :)offered}" 'zoxide ripgrep bat' 'npkg package completion offers cached attributes' || return 1
  unfunction _wanted

  command mkdir -p -- "$fallback_home/.cache/npkg"
  print -l -- fallback-package >"$fallback_home/.cache/npkg/nixpkgs-attrs-test.txt"
  XDG_CACHE_HOME=relative
  HOME=$fallback_home
  _zsh_npkg_cached_attributes
  assert_equals "${(j: :)reply}" 'fallback-package' 'npkg completion ignores a relative XDG cache home' || return 1

  PATH=$old_path
  if (( had_home )); then
    HOME=$old_home
  else
    unset HOME
  fi
  unset XDG_CACHE_HOME _ZSH_COMPLETION_LOG _ZSH_COMPLETION_INVOCATION
}

test_npkg_union_invalidation() (
  local XDG_CACHE_HOME="$tmp_dir/union-cache" first identity_before
  integer builds parses
  command mkdir -p -- "$XDG_CACHE_HOME/npkg"
  first="$XDG_CACHE_HOME/npkg/nixpkgs-attrs-a.txt"
  print -rn -- $'c\na\nc\nb\n\nlast' > "$first"
  _zsh_npkg_cached_attributes
  assert_equals "${(j: :)reply}" 'c a b' 'union preserves first order, skips empty lines and unterminated final record' || return 1
  builds=$_ZSH_NPKG_COMPLETION_BUILD_COUNT
  parses=$_ZSH_NPKG_COMPLETION_PARSE_COUNT
  reply=(caller-mutation)
  _zsh_npkg_cached_attributes
  assert_equals "${(j: :)reply}" 'c a b' 'warm union is independent of caller reply mutations' || return 1
  assert_equals "$_ZSH_NPKG_COMPLETION_BUILD_COUNT:$_ZSH_NPKG_COMPLETION_PARSE_COUNT" "$builds:$parses" 'warm union avoids both parsing and assembly' || return 1
  identity_before=${_ZSH_NPKG_COMPLETION_CACHE_PATH_KEYS[$first]}
  print -l -- d a > "$XDG_CACHE_HOME/new"
  command mv -- "$XDG_CACHE_HOME/new" "$first"
  _zsh_npkg_cached_attributes
  assert_equals "${(j: :)reply}" 'd a' 'same-path replacement invalidates union' || return 1
  assert_equals "${+_ZSH_NPKG_COMPLETION_CACHE_DATA[$identity_before]}" 0 'replaced identities are discarded' || return 1
  print -l -- a e > "$XDG_CACHE_HOME/npkg/nixpkgs-attrs-b.txt"
  : > "$XDG_CACHE_HOME/npkg/nixpkgs-attrs-empty.txt"
  command ln -s -- "$first" "$XDG_CACHE_HOME/npkg/nixpkgs-attrs-link.txt"
  _zsh_npkg_cached_attributes
  assert_equals "${(j: :)reply}" 'd a e' 'added and empty files retain ordered deduplication' || return 1
  assert_equals "${#_ZSH_NPKG_COMPLETION_CACHE_PATH_KEYS}" 3 'symlinked indexes are excluded from cached membership' || return 1
  command chmod 000 "$first"
  if [[ ! -r $first ]]; then
    _zsh_npkg_cached_attributes
    assert_equals "${(j: :)reply}" 'a e' 'readability change removes unavailable candidates' || return 1
  fi
  command chmod 600 "$first"
  _zsh_npkg_cache_identity() { return 1; }
  _zsh_npkg_cached_attributes
  parses=$_ZSH_NPKG_COMPLETION_PARSE_COUNT
  builds=$_ZSH_NPKG_COMPLETION_BUILD_COUNT
  _zsh_npkg_cached_attributes
  assert_equals "${(j: :)reply}" 'd a e' 'stat failure retains correct offline candidates' || return 1
  assert_equals "$_ZSH_NPKG_COMPLETION_BUILD_COUNT" "$((builds+1))" 'stat failure disables aggregate reuse' || return 1
  assert_equals "$_ZSH_NPKG_COMPLETION_PARSE_COUNT" "$((parses+3))" 'stat failure reparses all eligible files' || return 1
  command rm -- "$XDG_CACHE_HOME/npkg/"*.txt
  _zsh_npkg_cached_attributes
  assert_equals "${#reply}:${#_ZSH_NPKG_COMPLETION_CACHE_DATA}:${#_ZSH_NPKG_COMPLETION_CACHE_PATH_KEYS}" '0:0:0' 'removed indexes leave no candidates or obsolete per-file data'
)

test_npkg_completion_oracle() {
  local work="$tmp_dir/npkg-oracle" fakebin="$tmp_dir/npkg-oracle-bin"
  local legacy_file="$tmp_dir/npkg-oracle-legacy.zsh" scenario_file="$tmp_dir/npkg-oracle-scenario.zsh"
  local live frozen fallback mode

  command mkdir -p -- "$fakebin" "$work/live" "$work/frozen" "$work/no-system"
  print -r -- '#!/bin/sh
printf "%s\n" "$*" >> "$NPKG_ORACLE_NIX_LOG"
exit 97' > "$fakebin/nix"
  command chmod +x "$fakebin/nix"
  # Frozen pre-optimization helper; it captures _npkg_cache_dir and reads lines.
  command cat > "$legacy_file" <<'EOF_LEGACY'
  _zsh_npkg_cached_attributes() {
    emulate -L zsh
    setopt localoptions nullglob

    local cache_dir cache_file attribute identity signature=''
    local -a file_attributes cache_files attributes
    local -A identities retained_data
    integer cacheable=1
    typeset -ga reply
    reply=()

    cache_dir=$(_npkg_cache_dir) || return 1
    for cache_file in "$cache_dir"/nixpkgs-attrs-*.txt(N.); do
      [[ -r $cache_file && ! -L $cache_file ]] || continue

      cache_files+=( "$cache_file" )
      if _zsh_npkg_cache_identity "$cache_file"; then
        identities[$cache_file]=$REPLY
      else
        cacheable=0
      fi
      # Neither a filesystem path nor an identity can contain a NUL byte.
      signature+="$cache_file"$'\0'"${identities[$cache_file]-}"$'\0'
    done

    if (( cacheable && _ZSH_NPKG_COMPLETION_UNION_VALID )) &&
        [[ $signature == "$_ZSH_NPKG_COMPLETION_SIGNATURE" ]]; then
      reply=( "${_ZSH_NPKG_COMPLETION_UNION[@]}" )
      return 0
    fi

    for cache_file in "${cache_files[@]}"; do
      identity=${identities[$cache_file]-}
      if [[ -n $identity && ${+_ZSH_NPKG_COMPLETION_CACHE_DATA[$identity]} -eq 1 ]]; then
        if [[ -n ${_ZSH_NPKG_COMPLETION_CACHE_DATA[$identity]} ]]; then
          file_attributes=( "${(f)_ZSH_NPKG_COMPLETION_CACHE_DATA[$identity]}" )
        else
          file_attributes=()
        fi
      else
        file_attributes=()
        while IFS= read -r attribute; do
          [[ -n $attribute ]] || continue
          file_attributes+=("$attribute")
        done < "$cache_file"
        (( _ZSH_NPKG_COMPLETION_PARSE_COUNT++ ))
      fi
      [[ -z $identity ]] || retained_data[$identity]="${(F)file_attributes}"
      attributes+=( "${file_attributes[@]}" )
    done
    # Unique expansion retains first occurrence order without per-name appends.
    reply=( "${(@u)attributes}" )
    _ZSH_NPKG_COMPLETION_CACHE_DATA=( "${(@kv)retained_data}" )
    _ZSH_NPKG_COMPLETION_CACHE_PATH_KEYS=( "${(@kv)identities}" )
    _ZSH_NPKG_COMPLETION_UNION=( "${reply[@]}" )
    _ZSH_NPKG_COMPLETION_SIGNATURE=$signature
    _ZSH_NPKG_COMPLETION_UNION_VALID=$cacheable
    (( _ZSH_NPKG_COMPLETION_BUILD_COUNT++ ))
    return 0
  }
EOF_LEGACY
  command cat > "$scenario_file" <<'EOF_SCENARIO'
emulate -L zsh
setopt no_unset
repo=$1 work=$2 mode=$3 legacy=$4
compdef() { :; }
source "$repo/60-functions.zsh" || exit 2
source "$repo/66-compdefs.zsh" || exit 2
if [[ $mode == frozen ]]; then
  source "$legacy" || exit 3
elif [[ $mode == no-system ]]; then
  # Exercise the line-reader fallback used when zsh/system is unavailable.
  zmodload() {
    [[ $* == *zsh/system* ]] && return 1
    builtin zmodload "$@"
  }
fi
(( $+functions[_npkg_cache_dir_reply] )) || exit 4
nix_loaded() {
  if (( ${+_ZSH_FUNCTION_DOMAINS_LOADED} )); then
    print -r -- "${_ZSH_FUNCTION_DOMAINS_LOADED[nix]:-0}"
  else
    print -r -- 0
  fi
}
print -r -- "meta: nix-loaded-at-source=$(nix_loaded)"
step() {
  local label=$1 rc err
  REPLY=sentinel
  _zsh_npkg_cached_attributes 2>"$work/err"
  rc=$?
  err=$(<"$work/err")
  [[ $REPLY == <->:<->:<->:<-> ]] && REPLY=IDENTITY
  print -r -- "$label rc=$rc REPLY=${(q+)REPLY} n=${#reply} parse=$_ZSH_NPKG_COMPLETION_PARSE_COUNT build=$_ZSH_NPKG_COMPLETION_BUILD_COUNT err=${(q+)err}"
  print -rl -- "${(@q+)reply}"
}
export XDG_CACHE_HOME=$work/cache
d=$XDG_CACHE_HOME/npkg
step missing-dir
print -r -- "meta: nix-loaded-after-request=$(nix_loaded)"
command mkdir -p -- "$d" "$work/home/.cache/npkg"
step empty-dir
print -rn -- $'c\r\na\n\nb\nc\nlast' >"$d/nixpkgs-attrs-a.txt"
print -rn -- $'a\nz\n\n\n' >"$d/nixpkgs-attrs-b.txt"
: >"$d/nixpkgs-attrs-empty.txt"
print -rn -- $'x\0y\nq\n\\n\n' >"$d/nixpkgs-attrs-nul.txt"
print -rn -- $'\xe9\x9b\xbb\n\xff\n \n\t\n' >"$d/nixpkgs-attrs-utf8.txt"
print -rn -- 'no-newline-only' >"$d/nixpkgs-attrs-tail.txt"
{
  integer i
  for (( i = 1; i <= 20000; i++ )); do
    if (( i % 1009 == 0 )); then
      print -rn -- $'\n'
    elif (( i % 997 == 0 )); then
      print -rn -- "python3Packages.pkg-$i"$'\r\n'
    else
      print -r -- "python3Packages.pkg-$i"
    fi
  done
  print -rn -- 'big-tail'
} >"$d/nixpkgs-attrs-big.txt"
command ln -s -- "$d/nixpkgs-attrs-a.txt" "$d/nixpkgs-attrs-link.txt"
print -r -- ignored >"$d/other.txt"
print -r -- locked >"$d/nixpkgs-attrs-locked.txt"
command chmod 000 "$d/nixpkgs-attrs-locked.txt"
step populated
step warm
reply=(caller-mutation)
step warm-after-caller-mutation
print -rn -- $'d\na\n' >"$work/new"
command mv -- "$work/new" "$d/nixpkgs-attrs-a.txt"
step replaced
print -r -- extra >>"$d/nixpkgs-attrs-b.txt"
step appended
command rm -f -- "$d/nixpkgs-attrs-b.txt"
step deleted
_wanted() { print -r -- "wanted ${(j: :)${(@q+)@}} :: ${#reply} ${(q+)reply[1]}"; }
_zsh_npkg_cached_packages
print -r -- "adapter rc=$?"
_zsh_npkg_cache_identity() { return 1; }
step stat-unavailable
step stat-unavailable-again
command chmod 600 "$d/nixpkgs-attrs-locked.txt"
command rm -f -- "$d"/nixpkgs-attrs-*.txt
step emptied
_zsh_npkg_cached_packages
print -r -- "adapter-empty rc=$?"
print -r -- home-only >"$work/home/.cache/npkg/nixpkgs-attrs-home.txt"
XDG_CACHE_HOME=relative HOME=$work/home step relative-xdg
XDG_CACHE_HOME=relative HOME=relative step no-absolute-cache
EOF_SCENARIO

  for mode in live frozen no-system; do
    PATH="$fakebin:$PATH" NPKG_ORACLE_NIX_LOG="$tmp_dir/npkg-oracle-nix.log" \
      "$zsh_bin" -f "$scenario_file" "$repo_dir" "$work/$mode" "$mode" "$legacy_file" > "$work/$mode.out" 2>&1
    assert_status "$?" 0 "npkg completion oracle scenario runs ($mode)" || return 1
  done
  live=$(<"$work/live.out")
  frozen=$(<"$work/frozen.out")
  fallback=$(<"$work/no-system.out")
  assert_equals "${(F)${(@f)live:#meta: *}}" "${(F)${(@f)frozen:#meta: *}}" 'npkg completion candidates, order, counters, statuses and REPLY match the frozen helper' || return 1
  assert_equals "${(F)${(@f)fallback:#meta: *}}" "${(F)${(@f)frozen:#meta: *}}" 'npkg completion line-reader fallback matches the frozen helper' || return 1
  assert_equals "${(F)${(@M)${(@f)live}:#meta: *}}" $'meta: nix-loaded-at-source=0\nmeta: nix-loaded-after-request=1' 'npkg completion loads the Nix domain lazily in the parent shell' || return 1
  assert_equals "${(F)${(@M)${(@f)frozen}:#meta: *}}" $'meta: nix-loaded-at-source=0\nmeta: nix-loaded-after-request=0' 'frozen npkg completion loaded the Nix domain only in a child' || return 1
  assert_equals "${#${(@M)${(@f)live}:#populated rc=0 *}}" 1 'npkg completion oracle covers populated caches' || return 1
  assert_equals "$(file_contents "$tmp_dir/npkg-oracle-nix.log")" '' 'npkg completion oracle never invokes Nix' || return 1
}

test_source_has_no_subprocesses() {
  local fakebin="$tmp_dir/source-fakebin"
  local invocation_log="$tmp_dir/source-invocations"
  local tool

  command mkdir -p -- "$fakebin"
  for tool in git nix fzf find jq secret-tool; do
    print -r -- '#!/bin/sh
printf "%s\n" "$0" >> "$_ZSH_COMPLETION_LOG"' > "$fakebin/$tool"
    command chmod +x "$fakebin/$tool"
  done

  _ZSH_COMPLETION_LOG=$invocation_log PATH=$fakebin "$zsh_bin" -f -c '
    compdef() { :; }
    npkg() { :; }
    cgm() { :; }
    source "$1"
  ' zsh "$repo_dir/66-compdefs.zsh"
  assert_status "$?" 0 'completion module sources with fake external tools on PATH' || return 1
  assert_equals "$(file_contents "$invocation_log")" '' 'completion module sourcing invokes no external tools' || return 1
}

test_upkg_live_dry_run_description() (
  local -a captured_specs words=(upkg upgrade '')
  _arguments() { captured_specs=( "$@" ); return 0; }
  _zsh_upkg || return 1
  assert_equals "${captured_specs[(r)--dry-run*]}" "--dry-run[${_ZSH_UPKG_FLAGS[(r)--dry-run:*]#*:}]" 'live dry-run completion uses the shared inventory/cleanup contract' || return 1
)

test_npkg_helper_completion() (
  local -a captured_specs words
  local completion_command message
  local cache_calls=0
  _arguments() {
    captured_specs=( "$@" )
    state=argument
    line=( "$completion_command" )
    return 1
  }
  _message() { message=$1; }
  _zsh_npkg_cached_packages() { (( cache_calls++ )); return 0; }
  for completion_command in refresh outdated check diff; do
    words=(npkg "$completion_command" '')
    message=''
    _zsh_npkg || return 1
    assert_equals "$message" 'no operands; use -h or --help for usage' "npkg $completion_command completion explains helper arguments" || return 1
    assert_equals "$cache_calls" 0 'no-operand completion does not read package cache' || return 1
  done
  for completion_command in find pick fzf; do
    words=(npkg "$completion_command" '')
    _zsh_npkg || return 1
    [[ ${(j: :)captured_specs} == *'--[treat following words as literal picker query]'* ]] || return 1
    print -r -- "ok: npkg $completion_command completion offers literal query separator"
  done
)

# Completing upkg must not load the package domain, start timing, or run tools.
test_upkg_completion_isolation() {
  local fakebin="$tmp_dir/upkg-completion-fakebin"
  local invocation_log="$tmp_dir/upkg-completion-invocations"
  local tool

  command mkdir -p -- "$fakebin"
  for tool in apt dnf pacman paru brew flatpak nix npm tput; do
    print -r -- '#!/bin/sh
printf "%s\n" "$0" >> "$_ZSH_COMPLETION_LOG"' > "$fakebin/$tool"
    command chmod +x "$fakebin/$tool"
  done

  _ZSH_COMPLETION_LOG=$invocation_log PATH=$fakebin "$zsh_bin" -f -c '
    source "$1/55-ui-helpers.zsh" || exit 10
    source "$1/60-functions.zsh" || exit 11
    compdef() { :; }
    source "$1/66-compdefs.zsh" || exit 12
    _arguments() { return 0; }
    _values() { return 0; }
    local -a words
    local spec
    for spec in "upkg" "upkg upgrade" "upkg --only=" "upkg search rip"; do
      words=( ${=spec} "" )
      _zsh_upkg || exit 13
    done
    _zsh_upkg_managers || exit 14
    ! zmodload -e zsh/datetime || exit 15
    (( ! ${_ZSH_FUNCTION_DOMAINS_LOADED[upkg]:-0} && ! $+functions[_upkg_timing_start] )) || exit 16
  ' zsh "$repo_dir"
  assert_status "$?" 0 'upkg completion leaves the package domain and clock unloaded' || return 1
  assert_equals "$(file_contents "$invocation_log")" '' 'upkg completion invokes no package manager or tput' || return 1
}

main() {
  test_without_compinit || return 1
  test_registration || return 1
  test_zhelp_values || return 1
  test_static_values || return 1
  test_upkg_live_dry_run_description || return 1
  test_upkg_completion_isolation || return 1
  test_npkg_helper_completion || return 1
  test_extract_completion_drift || return 1
  test_cached_npkg_attributes || return 1
  test_npkg_union_invalidation || return 1
  test_npkg_completion_oracle || return 1
  test_cached_cgm_names || return 1
  test_source_has_no_subprocesses || return 1
}

main "$@"
