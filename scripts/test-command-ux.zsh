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

assert_file_contains() {
  local file=$1 needle=$2 label=$3
  local contents=$(<"$file")
  assert_contains "$contents" "$needle" "$label"
}

write_fakebin() {
  local fakebin=$1

  command mkdir -p -- "$fakebin"
  print -r -- '#!/bin/sh
printf "fd %s\n" "$*" >> "$COMMAND_UX_LOG"
[ -n "${COMMAND_UX_FD_STATUS:-}" ] && exit "$COMMAND_UX_FD_STATUS"
[ "${COMMAND_UX_FD_MATCH:-0}" = 1 ] && printf "%s\n" fixture-match
exit 0' >"$fakebin/fd"
  print -r -- '#!/bin/sh
printf "rg %s\n" "$*" >> "$COMMAND_UX_LOG"
exit 0' >"$fakebin/rg"
  print -r -- '#!/bin/sh
printf "grep %s\n" "$*" >> "$COMMAND_UX_LOG"
exit 0' >"$fakebin/grep"
  print -r -- '#!/bin/sh
printf "curl %s\n" "$*" >> "$COMMAND_UX_LOG"
case "$*" in *ifconfig.me*) printf "%s\n" "203.0.113.42"; exit 0 ;; esac
printf "%s\n" "fixture-response"
exit 0' >"$fakebin/curl"
  command chmod +x -- "$fakebin"/*
}

test_help() {
  local command_name output rc
  local -a commands_to_check=(
    extract mkcd ff ft fkill headers peek fanprofile dusage bigfiles
    ports weather myip croot gitcount path fbr
  )

  for command_name in "${commands_to_check[@]}"; do
    output=$($command_name --help 2>&1); rc=$?
    assert_status "$rc" 0 "$command_name supports --help" || return 1
    assert_contains "$output" 'Usage:' "$command_name help prints usage" || return 1
  done

  output=$(ff --unknown 2>&1); rc=$?
  assert_status "$rc" 1 'ff rejects unknown options with the established usage status' || return 1
  assert_contains "$output" 'unknown option' 'ff identifies an unknown option' || return 1
}

test_search_options() {
  local fakebin="$tmp_dir/fakebin" log_file="$tmp_dir/commands.log" old_path=$PATH
  local output rc

  write_fakebin "$fakebin"
  : >"$log_file"
  PATH="$fakebin:$old_path"
  export COMMAND_UX_LOG=$log_file
  rehash

  COMMAND_UX_FD_MATCH=1 ff --hidden --no-ignore --follow needle "$tmp_dir" >/dev/null; rc=$?
  assert_status "$rc" 0 'ff accepts explicit backend search controls' || return 1
  assert_file_contains "$log_file" 'fd --hidden --no-ignore --follow --glob --ignore-case' 'ff passes hidden, ignore, and follow controls to fd' || return 1

  ff needle "$tmp_dir" >/dev/null; rc=$?
  assert_status "$rc" 1 'ff returns 1 when the backend finds nothing' || return 1
  output=$(COMMAND_UX_FD_STATUS=3 ff needle "$tmp_dir" 2>&1); rc=$?
  assert_status "$rc" 3 'ff keeps a real backend failure status instead of reporting no match' || return 1
  output=$(COMMAND_UX_FD_MATCH=1 ff needle "$tmp_dir")
  assert_equals "$output" fixture-match 'ff prints backend results unchanged' || return 1
  ft --hidden --no-ignore --follow --fixed-strings 'a.b' "$tmp_dir" >/dev/null; rc=$?
  assert_status "$rc" 0 'ft accepts explicit rg search controls' || return 1
  assert_file_contains "$log_file" 'rg --hidden --no-ignore --follow --fixed-strings' 'ft passes all controls to rg' || return 1
  ft -i 'a.b' "$tmp_dir" >/dev/null; rc=$?
  assert_status "$rc" 0 'ft accepts -i with rg' || return 1
  assert_file_contains "$log_file" 'rg --ignore-case --color=auto' 'ft passes -i to rg' || return 1

  command rm -f -- "$fakebin/rg"
  PATH=$fakebin
  rehash
  output=$(ft --hidden --no-ignore --follow --fixed-strings 'a.b' "$tmp_dir" 2>&1); rc=$?
  assert_status "$rc" 0 'ft keeps the grep fallback usable with explicit controls' || return 1
  assert_contains "$output" 'grep fallback includes hidden files' 'ft explains hidden fallback behavior' || return 1
  assert_contains "$output" 'grep fallback has no ignore-file filtering' 'ft explains ignore fallback behavior' || return 1
  assert_file_contains "$log_file" 'grep -RnI -F' 'ft maps follow and fixed-string controls to grep' || return 1
  ft --ignore-case 'a.b' "$tmp_dir" >/dev/null 2>&1; rc=$?
  assert_status "$rc" 0 'ft accepts --ignore-case with grep' || return 1
  assert_file_contains "$log_file" 'grep -rnI -E -i --color=auto' 'ft maps --ignore-case to grep -i' || return 1

  PATH=$old_path
  unset COMMAND_UX_LOG
  rehash
}

test_ff_streams_and_backends() {
  local fakebin="$tmp_dir/stream-fakebin" log_file="$tmp_dir/stream.log" flag="$tmp_dir/stream-flag" old_path=$PATH
  local fixture="$tmp_dir/ff-find" find_only="$tmp_dir/ff-find-bin" output rc

  # Results reach the consumer while the backend is still running.
  command mkdir -p -- "$fakebin"
  print -r -- '#!/bin/sh
printf "%s\n" first-line
i=0
while [ ! -e "$COMMAND_UX_FLAG" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
if [ -e "$COMMAND_UX_FLAG" ]; then printf "%s\n" consumer-saw-first; else printf "%s\n" buffered; fi' >"$fakebin/fd"
  command chmod +x -- "$fakebin/fd"
  PATH="$fakebin:$old_path"
  export COMMAND_UX_FLAG=$flag
  rehash
  ff needle "$tmp_dir" | {
    local line
    while IFS= read -r line; do
      print -r -- "$line"
      [[ $line == first-line ]] && : >"$flag"
    done
  } >"$tmp_dir/stream.out"
  assert_equals "$(<"$tmp_dir/stream.out")" $'first-line\nconsumer-saw-first' 'ff streams the first result before the backend finishes' || return 1
  unset COMMAND_UX_FLAG
  PATH=$old_path
  rehash

  # The find fallback has the same status contract.
  command mkdir -p -- "$fixture" "$find_only"
  : >"$fixture/present.txt"
  command ln -sf -- "${commands[find]}" "$find_only/find"
  output=$(builtin cd -- "$fixture" && PATH=$find_only ff present); rc=$?
  assert_status "$rc" 0 'ff with the find fallback succeeds on a match' || return 1
  assert_equals "$output" ./present.txt 'ff with the find fallback prints the match' || return 1
  output=$(builtin cd -- "$fixture" && PATH=$find_only ff absentpattern); rc=$?
  assert_status "$rc" 1 'ff with the find fallback returns 1 on no match' || return 1
  assert_equals "$output" '' 'ff with the find fallback prints nothing on no match' || return 1
  output=$(builtin cd -- "$fixture" && PATH=$find_only ff present /nonexistent/dir 2>&1); rc=$?
  assert_status "$rc" 1 'ff rejects a missing search directory' || return 1
  assert_contains "$output" "ff: '/nonexistent/dir' is not a directory" 'ff names itself in directory errors' || return 1
}

test_pick_guards_and_editor() (
  local output rc fakebin="$tmp_dir/editor-bin" old_path=$PATH
  # The terminal check comes after the fzf guard, which this suite has no fzf for.
  functions[_zsh_require_fzf]='return 0'

  output=$(ff --pick needle . </dev/null 2>&1); rc=$?
  assert_status "$rc" 1 'ff --pick needs a terminal' || return 1
  assert_contains "$output" 'ff: --pick requires an interactive terminal' 'ff --pick explains the terminal requirement' || return 1
  output=$(ft --pick needle . </dev/null 2>&1); rc=$?
  assert_status "$rc" 1 'ft --pick needs a terminal' || return 1
  assert_contains "$output" 'ft: --pick requires an interactive terminal' 'ft --pick explains the terminal requirement' || return 1
  assert_contains "$(ff --help)" '--pick' 'ff help documents --pick' || return 1
  assert_contains "$(ft --help)" '--pick' 'ft help documents --pick' || return 1

  output=$(VISUAL='' EDITOR='' _search_pick_open './note one.txt')
  assert_equals "$output" './note one.txt' 'a pick prints the path when no editor is configured' || return 1
  output=$(VISUAL='' EDITOR='' _search_pick_open ./we:ird.txt 3)
  assert_equals "$output" './we:ird.txt:3' 'a pick prints path:line when no editor is configured' || return 1

  command mkdir -p -- "$fakebin"
  print -r -- '#!/bin/sh
for a in "$@"; do printf "<%s>" "$a"; done; printf "\n"' >"$fakebin/vim"
  command cp -- "$fakebin/vim" "$fakebin/code"
  command cp -- "$fakebin/vim" "$fakebin/nvim"
  command chmod +x -- "$fakebin/vim" "$fakebin/code" "$fakebin/nvim"
  PATH="$fakebin:$old_path"; rehash
  output=$(VISUAL='' EDITOR=vim _search_pick_open './note one.txt' 7)
  assert_equals "$output" '<+7><./note one.txt>' 'a line-aware editor receives +line before the file' || return 1
  output=$(VISUAL='' EDITOR=code _search_pick_open ./note.txt 7)
  assert_equals "$output" '<./note.txt>' 'an editor that cannot take +line is not given one' || return 1
  output=$(VISUAL=nvim EDITOR=code _search_pick_open -dash.txt 2)
  assert_equals "$output" '<+2><./-dash.txt>' 'VISUAL wins and a leading-dash name cannot become an option' || return 1
  output=$(VISUAL='' EDITOR="$fakebin/vim -p" _search_pick_open 'sp ace.txt' 4)
  assert_equals "$output" '<-p><+4><sp ace.txt>' 'editor arguments are split and the file stays one argument' || return 1
  output=$(VISUAL='' EDITOR=vim _search_pick_open ./plain.txt)
  assert_equals "$output" '<./plain.txt>' 'a file pick passes no line' || return 1
)

test_error_prefixes_and_status() (
  local output rc root="$tmp_dir/prefix-case"
  # The terminal check comes after the fzf guard, which this suite has no fzf for.
  functions[_zsh_require_fzf]='return 0'

  command mkdir -p -- "$root"
  output=$(builtin cd -- "$root" && croot 2>&1); rc=$?
  assert_status "$rc" 1 'croot fails outside a repository' || return 1
  assert_equals "$output" 'croot: not in a Git repository' 'croot names itself when not in a repository' || return 1
  output=$(builtin cd -- "$root" && gitcount 2>&1); rc=$?
  assert_equals "$output" 'gitcount: not in a Git repository' 'gitcount names itself when not in a repository' || return 1
  output=$(extract "$root/nosuch.zip" 2>&1); rc=$?
  assert_status "$rc" 1 'extract rejects a missing file' || return 1
  assert_contains "$output" "extract: '$root/nosuch.zip' is not a valid file" 'extract names itself for a missing file' || return 1
  output=$(fkill </dev/null 2>&1); rc=$?
  assert_status "$rc" 1 'fkill needs a terminal' || return 1
  assert_contains "$output" 'fkill: an interactive terminal is required' 'fkill names itself without a terminal' || return 1
  output=$(fbr </dev/null 2>&1); rc=$?
  assert_status "$rc" 1 'fbr needs a terminal' || return 1
  assert_contains "$output" 'fbr: an interactive terminal is required' 'fbr names itself without a terminal' || return 1
  output=$(fbr --bogus 2>&1); rc=$?
  assert_status "$rc" 1 'fbr rejects unknown options' || return 1
  assert_contains "$output" 'fbr: unknown option: --bogus' 'fbr names itself for unknown options' || return 1
  output=$(mkcd 2>&1); rc=$?
  assert_contains "$output" 'mkcd: expected exactly one directory' 'mkcd names itself on a usage error' || return 1
  output=$(dusage . 5 6 2>&1); rc=$?
  assert_contains "$output" 'dusage: too many arguments' 'dusage names itself on a usage error' || return 1
  output=$(bigfiles "$root/none" 2>&1); rc=$?
  assert_contains "$output" "bigfiles: '$root/none' does not exist" 'bigfiles names itself for a missing path' || return 1
  output=$(ztheme use 2>&1); rc=$?
  assert_status "$rc" 1 'ztheme use without a theme is a usage error' || return 1
  assert_contains "$output" 'ztheme: use needs exactly one theme' 'ztheme names the problem before its usage' || return 1
  assert_equals "${#${(@f)output}}" 3 'a ztheme argument error is the short three-line form, not the full usage' || return 1
  assert_equals "${${(@f)output}[2]}" 'Usage: ztheme <command> [theme]' 'a ztheme argument error shows one usage line' || return 1
  assert_equals "${${(@f)output}[3]}" "Run 'ztheme --help' for the full reference." 'a ztheme argument error points to --help' || return 1
  output=$(ztheme lst 2>&1 >/dev/null); rc=$?
  assert_status "$rc" 1 'ztheme rejects a mistyped subcommand' || return 1
  assert_equals "${#${(@f)output}}" 4 'an unknown ztheme subcommand is the four-line form' || return 1
  assert_contains "$output" 'Did you mean: list?' 'ztheme suggests the nearest subcommand' || return 1
  output=$(ztheme bogus 2>&1 >/dev/null)
  assert_equals "${#${(@f)output}}" 3 'ztheme does not guess when nothing is close' || return 1
  output=$(ztheme list extra 2>&1 >/dev/null)
  assert_contains "$output" 'ztheme: list takes no arguments' 'ztheme names a surplus-argument error' || return 1
  ztheme --help | command grep -q 'Commands:'
  assert_status "$?" 0 'ztheme --help still prints the full usage on stdout' || return 1
  output=$(ztheme bogus 2>&1 >/dev/null); rc=$?
  assert_status "$rc" 1 'ztheme rejects an unknown subcommand with status 1' || return 1
  assert_contains "$output" 'ztheme: unknown command: bogus' 'ztheme names an unknown subcommand' || return 1
  output=$(ztheme 2>/dev/null); rc=$?
  assert_status "$rc" 0 'bare ztheme prints its usage and succeeds' || return 1
  assert_contains "$output" 'Usage: ztheme' 'bare ztheme prints its usage on stdout' || return 1
  output=$(npkg 2>/dev/null); rc=$?
  assert_status "$rc" 0 'bare npkg prints its usage and succeeds' || return 1
  output=$(cgm 2>/dev/null); rc=$?
  assert_status "$rc" 0 'bare cgm prints its usage and succeeds' || return 1
)

test_network_timeouts() {
  local fakebin="$tmp_dir/network-bin" log_file="$tmp_dir/network.log" old_path=$PATH
  local output rc

  write_fakebin "$fakebin"
  : >"$log_file"
  PATH="$fakebin:$old_path"
  export COMMAND_UX_LOG=$log_file
  rehash

  ZSH_HTTP_CONNECT_TIMEOUT=2 ZSH_HTTP_MAX_TIME=7 headers https://example.invalid >/dev/null; rc=$?
  assert_status "$rc" 0 'headers uses bounded default-compatible curl options' || return 1
  ZSH_HTTP_CONNECT_TIMEOUT=2 ZSH_HTTP_MAX_TIME=7 myip >/dev/null; rc=$?
  assert_status "$rc" 0 'myip uses bounded curl options' || return 1
  ZSH_HTTP_CONNECT_TIMEOUT=2 ZSH_HTTP_MAX_TIME=7 weather >/dev/null; rc=$?
  assert_status "$rc" 0 'weather uses bounded curl options' || return 1
  assert_file_contains "$log_file" '--connect-timeout 2 --max-time 7' 'network helpers pass explicit timeout overrides' || return 1

  output=$(ZSH_HTTP_MAX_TIME=0 headers https://example.invalid 2>&1); rc=$?
  assert_status "$rc" 1 'network helpers reject an unbounded timeout override' || return 1
  assert_contains "$output" 'timeout must be positive' 'network helper explains invalid timeout overrides' || return 1

  PATH=$old_path
  unset COMMAND_UX_LOG
  rehash
}

test_extract_destination() {
  local root="$tmp_dir/extract" source_dir="$tmp_dir/extract/source" destination="$tmp_dir/extract/destination"
  local archive="$root/payload.tar.gz" output rc

  command mkdir -p -- "$source_dir" "$destination"
  print -r -- 'archive payload' >"$source_dir/payload.txt"
  command tar -czf "$archive" -C "$source_dir" payload.txt

  output=$(extract --destination "$destination" "$archive" 2>&1); rc=$?
  assert_status "$rc" 0 'extract sends tar output to an explicit destination' || {
    print -u2 -- "$output"
    return 1
  }
  assert_file_contains "$destination/payload.txt" 'archive payload' 'extract writes the expected destination file' || return 1
  [[ -f $archive ]] || {
    print -u2 -- 'not ok: archive input remains after destination extraction'
    return 1
  }
  print -- 'ok: archive input remains after destination extraction'
}

test_extract_additional_formats() {
  local root="$tmp_dir/extract-formats" source_dir="$tmp_dir/extract-formats/source" rc

  command mkdir -p -- "$source_dir" "$root/upper" "$root/txz"
  print -r -- 'format payload' >"$source_dir/payload.txt"
  command tar -czf "$root/UPPER.TAR.GZ" -C "$source_dir" payload.txt
  extract --destination "$root/upper" "$root/UPPER.TAR.GZ" >/dev/null 2>&1; rc=$?
  assert_status "$rc" 0 'extract matches uppercase archive suffixes' || return 1
  assert_file_contains "$root/upper/payload.txt" 'format payload' 'uppercase suffix extraction writes the payload' || return 1

  if command -v xz >/dev/null 2>&1; then
    command tar -cJf "$root/payload.txz" -C "$source_dir" payload.txt
    extract --destination "$root/txz" "$root/payload.txz" >/dev/null 2>&1; rc=$?
    assert_status "$rc" 0 'extract unpacks .txz archives' || return 1
    print -r -- 'bare xz' >"$root/bare.txt"
    command xz -- "$root/bare.txt"
    extract --keep "$root/bare.txt.xz" >/dev/null 2>&1; rc=$?
    assert_status "$rc" 0 'extract decompresses bare .xz input' || return 1
    assert_file_contains "$root/bare.txt" 'bare xz' 'bare .xz extraction writes the payload' || return 1
    [[ -f $root/bare.txt.xz ]]
    assert_status "$?" 0 'extract --keep preserves bare .xz input' || return 1
  fi

  if command -v zstd >/dev/null 2>&1 && command -v unzstd >/dev/null 2>&1; then
    print -r -- 'bare zstd' >"$root/bare-zst.txt"
    command zstd -q --rm -- "$root/bare-zst.txt"
    extract "$root/bare-zst.txt.zst" >/dev/null 2>&1; rc=$?
    assert_status "$rc" 0 'extract decompresses bare .zst input' || return 1
    assert_file_contains "$root/bare-zst.txt" 'bare zstd' 'bare .zst extraction writes the payload' || return 1
  fi
}

test_extract_empty_destination() {
  local root="$tmp_dir/empty-destination" fakebin="$tmp_dir/empty-destination/bin"
  local option output rc suffix
  command mkdir -p -- "$fakebin"
  print -r -- '#!/bin/sh
printf invoked >> "$EXTRACT_EMPTY_LOG"
exit 99' > "$fakebin/gunzip"
  command cp -- "$fakebin/gunzip" "$fakebin/bunzip2"
  command cp -- "$fakebin/gunzip" "$fakebin/uncompress"
  command chmod +x -- "$fakebin"/*
  local old_path=$PATH
  export EXTRACT_EMPTY_LOG="$root/calls"
  for suffix in gz bz2 Z; do
    print -r -- retained > "$root/input.$suffix"
    for option in -C --destination --dest; do
      output=$(PATH="$fakebin:$old_path" extract "$option" '' "$root/input.$suffix" 2>&1); rc=$?
      assert_status "$rc" 1 "$option empty destination rejects .$suffix" || return 1
      assert_contains "$output" 'requires a directory' 'empty destination explains invalid value' || return 1
      assert_file_contains "$root/input.$suffix" retained 'invalid destination retains input' || return 1
    done
  done
  [[ ! -e $EXTRACT_EMPTY_LOG ]] || return 1
  print -- 'ok: empty destinations invoke no decompressor'
  unset EXTRACT_EMPTY_LOG
}

test_extract_stream_safety() {
  local root="$tmp_dir/stream" fakebin="$tmp_dir/stream-bin" old_path=$PATH rc
  command mkdir -p -- "$root/dest" "$fakebin"
  print -r -- payload > "$root/input"
  command gzip -c -- "$root/input" > "$root/input.gz"
  command chmod 644 -- "$root/input.gz"
  extract --destination "$root/dest" "$root/input.gz" || return 1
  assert_file_contains "$root/dest/input" payload 'bare compressed destination contains decompressed bytes' || return 1
  local -a output_mode
  zmodload -F zsh/stat b:zstat
  zstat -A output_mode +mode -- "$root/dest/input" || return 1
  assert_status "$(( output_mode[1] & 8#777 ))" "$(( 8#644 ))" 'destination output keeps the input permissions' || return 1
  [[ -f $root/input.gz ]] || return 1
  print -r -- keep > "$root/dest/input"
  extract --destination "$root/dest" "$root/input.gz" >/dev/null 2>&1; rc=$?
  assert_status "$rc" 1 'destination extraction refuses an existing output' || return 1
  assert_file_contains "$root/dest/input" keep 'existing output remains unchanged' || return 1
  command rm -- "$root/dest/input"
  command ln -s -- "$root/absent" "$root/dest/input"
  extract --destination "$root/dest" "$root/input.gz" >/dev/null 2>&1; rc=$?
  assert_status "$rc" 1 'destination extraction refuses a dangling symlink' || return 1
  [[ ! -e $root/absent ]] || return 1
  command rm -- "$root/dest/input"
  print -r -- '#!/bin/sh
printf partial
exit 7' > "$fakebin/gunzip"
  command chmod +x -- "$fakebin/gunzip"
  PATH="$fakebin:$old_path" extract --destination "$root/dest" "$root/input.gz" >/dev/null 2>&1; rc=$?
  assert_status "$rc" 7 'decompression failure preserves its status' || return 1
  local -a leftovers=( "$root/dest"/*(DN) )
  assert_status "${#leftovers}" 0 'failed decompression publishes no partial output and cleans staging files' || return 1
}

test_extract_input_symlinks() {
  local root="$tmp_dir/input-links" rc
  command mkdir -p -- "$root/links" "$root/dest" "$root/tar-source"
  print -r -- linked-payload > "$root/payload"
  command gzip -c -- "$root/payload" > "$root/target.gz"
  command ln -s -- "$root/target.gz" "$root/links/alias.gz"
  extract "$root/links/alias.gz" >/dev/null 2>&1; rc=$?
  assert_status "$rc" 1 'native gunzip refuses default symlink extraction' || return 1
  [[ -f $root/target.gz && -L $root/links/alias.gz && ! -e $root/links/alias ]] || return 1
  print -- 'ok: default symlink extraction leaves target and link untouched'
  extract --destination "$root/dest" "$root/links/alias.gz" || return 1
  assert_file_contains "$root/dest/alias" linked-payload 'destination uses link filename and retains target' || return 1
  [[ -f $root/target.gz && -L $root/links/alias.gz ]] || return 1
  extract --keep "$root/links/alias.gz" >/dev/null 2>&1; rc=$?
  assert_status "$rc" 1 'keep preserves native gzip symlink refusal' || return 1
  [[ -f $root/target.gz && ! -e $root/links/alias ]] || return 1
  print -r -- tar-payload > "$root/tar-source/member"
  command tar -czf "$root/archive.data" -C "$root/tar-source" member
  command ln -s -- "$root/archive.data" "$root/links/alias.tar.gz"
  extract --destination "$root/dest" "$root/links/alias.tar.gz" || return 1
  assert_file_contains "$root/dest/member" tar-payload 'archive link dispatch uses supplied suffix' || return 1
  [[ -f $root/archive.data && -L $root/links/alias.tar.gz ]] || return 1
}

test_npkg_helper_arguments() (
  _zsh_functions_load nix || return 1
  local log_file="$tmp_dir/npkg-argument-calls" marker="$tmp_dir/npkg-cache-marker"
  local output rc command_name flag expected
  print -r -- untouched > "$marker"
  _npkg_cache_dir() { print -r -- cache >> "$log_file"; print -r -- changed > "$marker"; }
  _npkg_refresh_index() { print -r -- refresh >> "$log_file"; print -r -- changed > "$marker"; }
  _npkg_outdated() { print -r -- outdated >> "$log_file"; print -r -- changed > "$marker"; }
  _npkg_pick_installables() { print -r -- "picker:${(j:|:)@}" >> "$log_file"; }
  _npkg_remove_picker() { print -r -- remove-picker >> "$log_file"; }
  _npkg_nix() { print -r -- "native:${(j:|:)@}" >> "$log_file"; }
  # Help/validation must work even when all external dependencies are absent.
  local PATH=''
  for command_name in refresh outdated check diff find pick fzf; do
    for flag in -h --help; do
      : > "$log_file"
      output=$(npkg "$command_name" "$flag" 2>&1); rc=$?
      assert_status "$rc" 0 "npkg $command_name honors $flag without dependencies" || return 1
      assert_contains "$output" "Usage: npkg $command_name" 'helper help names its selected subcommand' || return 1
      [[ ! -s $log_file && $(<"$marker") == untouched ]] || return 1
      print -r -- "ok: npkg $command_name $flag does no Nix/cache/picker work"
    done
  done
  for command_name in refresh outdated check diff; do
    for flag in operand --unknown '--profile /fixture/other'; do
      : > "$log_file"
      output=$(npkg "$command_name" ${=flag} 2>&1); rc=$?
      assert_status "$rc" 1 "npkg $command_name rejects unsupported arguments" || return 1
      assert_contains "$output" 'accepts no operands' 'npkg rejects unsupported profile/operand input clearly' || return 1
      [[ ! -s $log_file && $(<"$marker") == untouched ]] || return 1
    done
    : > "$log_file"
    npkg "$command_name" >/dev/null || return 1
    [[ $command_name == refresh ]] && expected=refresh || expected=outdated
    [[ $(<"$log_file") == $expected ]] || return 1
    print -r -- "ok: npkg $command_name invokes work only for valid no-operand input"
    print -r -- untouched > "$marker"
  done
  for command_name in find pick fzf; do
    : > "$log_file"
    npkg "$command_name" alpha 'two words' -leading || return 1
    [[ $(<"$log_file") == 'picker:alpha|two words|-leading' ]] || return 1
    : > "$log_file"
    npkg "$command_name" -- --help -h 'two words' || return 1
    [[ $(<"$log_file") == 'picker:--help|-h|two words' ]] || return 1
    : > "$log_file"
    npkg "$command_name" alpha -- -- --help || return 1
    [[ $(<"$log_file") == 'picker:alpha|--|--help' ]] || return 1
    : > "$log_file"
    npkg "$command_name" alpha --help >/dev/null || return 1
    [[ ! -s $log_file ]] || return 1
    : > "$log_file"
    npkg "$command_name" || return 1
    [[ $(<"$log_file") == 'picker:' ]] || return 1
    print -r -- "ok: npkg $command_name preserves multiword/literal/leading-dash queries"
  done
  for command_name in add install i remove rm uninstall delete list ls search s upgrade up update; do
    case $command_name in
      add|install|i) expected='native:profile|add|--help' ;;
      remove|rm|uninstall|delete) expected='native:profile|remove|--help' ;;
      list|ls) expected='native:profile|list|--help' ;;
      search|s) expected='native:search|--help' ;;
      upgrade|up|update) expected='native:profile|upgrade|--help' ;;
    esac
    : > "$log_file"
    npkg "$command_name" --help || return 1
    [[ $(<"$log_file") == $expected ]] || return 1
    print -r -- "ok: npkg $command_name preserves native help forwarding"
  done
  : > "$log_file"
  npkg add bat 'github:example/flake#pkg' || return 1
  [[ $(<"$log_file") == 'native:profile|add|nixpkgs#bat|github:example/flake#pkg' ]] || return 1
  : > "$log_file"
  npkg add hello --file default.nix || return 1
  [[ $(<"$log_file") == 'native:profile|add|hello|--file|default.nix' ]] || return 1
  print 'ok: npkg add passes every argument through when any option is present'
  : > "$log_file"
  npkg list --profile '/fixture/two words' || return 1
  [[ $(<"$log_file") == 'native:profile|list|--profile|/fixture/two words' ]] || return 1
  : > "$log_file"
  npkg search 'two words' || return 1
  [[ $(<"$log_file") == 'native:search|nixpkgs|two words' ]] || return 1
  print 'ok: npkg native operands retain expansion, quoting, and profile forwarding'
)

test_usage_errors() {
  local output rc
  local -a lines

  output=$(upkg serch foo 2>&1 >/dev/null); rc=$?
  assert_status "$rc" 1 'upkg rejects a mistyped command' || return 1
  lines=( "${(@f)output}" )
  assert_equals "${#lines}" 4 'upkg usage error is four lines, not the whole help' || return 1
  assert_equals "${lines[1]}" 'upkg: unknown command: serch' 'upkg usage error leads with the message' || return 1
  assert_equals "${lines[2]}" 'Did you mean: search?' 'upkg suggests the nearest command' || return 1
  assert_equals "${lines[3]}" 'Usage: upkg [command] [args] [flags]' 'upkg usage error shows one usage line' || return 1
  assert_equals "${lines[4]}" "Run 'upkg --help' for the full reference." 'upkg usage error points to --help' || return 1

  output=$(upkg bogus 2>&1 >/dev/null); rc=$?
  assert_not_contains "$output" 'Did you mean' 'upkg does not guess when nothing is close' || return 1
  output=$(upkg upp 2>&1 >/dev/null)
  assert_contains "$output" 'Did you mean: up?' 'upkg suggestions include command aliases' || return 1
  output=$(upkg --onyl x 2>&1 >/dev/null)
  assert_contains "$output" 'Did you mean: --only?' 'upkg suggests the nearest flag' || return 1
  output=$(upkg bogus 2>/dev/null); rc=$?
  assert_equals "$output" '' 'upkg usage errors print nothing on stdout' || return 1
  output=$(upkg --help 2>&1 >/dev/null)
  assert_equals "$output" '' 'upkg --help keeps stderr empty' || return 1
  upkg --help | command grep -q 'Supported manager IDs'
  assert_status "$?" 0 'upkg --help still prints the full reference on stdout' || return 1

  output=$(upkg --only bogus 2>&1 >/dev/null); rc=$?
  assert_status "$rc" 1 'upkg rejects an unsupported manager id' || return 1
  lines=( "${(@f)output}" )
  assert_equals "${lines[1]}" 'upkg: unsupported manager id: bogus' 'upkg names the unsupported id' || return 1
  assert_contains "${lines[2]}" 'Supported manager IDs: apt, dnf, pacman, paru, brew, flatpak, nix, npm' 'upkg lists the supported ids' || return 1
  assert_contains "${lines[3]}" 'Detected managers:' 'upkg lists the detected managers' || return 1

  output=$(npkg bogus 2>&1 >/dev/null); rc=$?
  assert_status "$rc" 1 'npkg rejects an unknown command' || return 1
  assert_equals "${#${(@f)output}}" 3 'npkg usage error is three lines when nothing is close' || return 1
  assert_contains "$output" 'npkg: unknown command: bogus' 'npkg names the unknown command' || return 1
  output=$(npkg lst 2>&1 >/dev/null)
  assert_contains "$output" 'Did you mean: list?' 'npkg suggests the nearest command' || return 1
  assert_contains "$output" "Run 'npkg --help' for the full reference." 'npkg points to --help' || return 1
  npkg --help | command grep -q 'Usage'
  assert_status "$?" 0 'npkg --help still prints the full help' || return 1

  output=$(cgm stats 2>&1 >/dev/null); rc=$?
  assert_status "$rc" 1 'cgm rejects an unknown command' || return 1
  assert_contains "$output" 'cgm: unknown command: stats' 'cgm names the unknown command' || return 1
  assert_contains "$output" 'Did you mean: status?' 'cgm suggests the nearest command' || return 1
  assert_contains "$output" "Run 'cgm --help' for the full reference." 'cgm points to --help' || return 1

  _ui_close_matches upgk upkg ports ztheme || return 1
  assert_equals "${reply[1]}" upkg 'the edit-distance helper finds a two-edit typo' || return 1
  _ui_close_matches zz upkg ports && return 1
  _ui_close_matches x a b && return 1
  print -- 'ok: the edit-distance helper rejects distant and one-letter words'
}

main() {
  source "$repo_dir/55-ui-helpers.zsh"
  source "$repo_dir/60-functions.zsh"
  # cgm only reads the catalogue and Secret Service when a command needs them.
  source "$repo_dir/62-cgm.zsh"
  _zsh_functions_load || return 1
  functions[_ui_plain_mode]='return 0'

  test_help || return 1
  test_usage_errors || return 1
  test_error_prefixes_and_status || return 1
  test_ff_streams_and_backends || return 1
  test_pick_guards_and_editor || return 1
  test_npkg_helper_arguments || return 1
  test_search_options || return 1
  test_network_timeouts || return 1
  test_extract_destination || return 1
  test_extract_additional_formats || return 1
  test_extract_empty_destination || return 1
  test_extract_stream_safety || return 1
  test_extract_input_symlinks || return 1
}

main "$@"
