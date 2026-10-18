#!/usr/bin/env zsh

set -u

repo_dir=${0:A:h:h}
tmp_dir=$(mktemp -d) || { print -u2 -- 'fatal: mktemp failed'; exit 1; }
[ -n "$tmp_dir" ] || { print -u2 -- 'fatal: mktemp returned an empty path'; exit 1; }

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

assert_safe_output_file() {
  emulate -L zsh
  setopt MULTIBYTE

  local file=$1 label=$2
  local content char
  integer index code

  content=$(<"$file")
  for (( index = 1; index <= ${#content}; index++ )); do
    char=${content[$index]}
    printf -v code '%d' "'$char"

    if (( (code >= 0 && code <= 9) || (code >= 11 && code <= 31) || code == 127 || (code >= 128 && code <= 159) )); then
      print -u2 -- "not ok: $label"
      printf 'unsafe codepoint: U+%04X\n' "$code" >&2
      return 1
    fi
  done

  print -- "ok: $label"
}

assert_missing_arg_usage() {
  local command_name=$1 expected_usage=$2
  local stdout_file="$tmp_dir/${command_name}.missing.stdout"
  local stderr_file="$tmp_dir/${command_name}.missing.stderr"
  local output rc

  "$command_name" >"$stdout_file" 2>"$stderr_file"
  rc=$?
  assert_status "$rc" 1 "$command_name rejects a missing argument under NOUNSET" || return 1
  assert_equals "$(<"$stdout_file")" '' "$command_name keeps missing-argument errors off stdout" || return 1
  output=$(<"$stderr_file")
  assert_contains "$output" "$expected_usage" "$command_name prints usage under NOUNSET" || return 1
}

test_missing_arguments() {
  assert_missing_arg_usage extract 'Usage: extract [--keep] [--destination <dir>] <file>' || return 1
  assert_missing_arg_usage mkcd 'Usage: mkcd <directory>' || return 1
  assert_missing_arg_usage ff 'Usage: ff [--hidden|--no-hidden] [--no-ignore] [--follow|--no-follow] <pattern> [path]' || return 1
  assert_missing_arg_usage ft 'Usage: ft [--hidden] [--no-ignore] [--follow] [--fixed-strings] <pattern> [path]' || return 1
  assert_missing_arg_usage headers 'Usage: headers <url>' || return 1
  assert_missing_arg_usage peek 'Usage: peek <file>' || return 1
}

test_local_emulation_and_leading_dash_operands() {
  local command_name archive_name tool original_dir=$PWD
  local fixture_dir="$tmp_dir/leading-operands"
  local fakebin="$tmp_dir/leading-fakebin"
  local gunzip_log="$tmp_dir/gunzip-args"
  local old_path=$PATH output
  local EXTRACT_TEST_LOG=$gunzip_log

  for command_name in extract mkcd ff ft fkill headers peek croot gitcount; do
    assert_contains "${functions[$command_name]}" 'emulate -L zsh' "$command_name isolates caller shell options" || return 1
    (
      setopt KSH_ARRAYS SH_WORD_SPLIT NO_UNSET
      builtin cd -- "$tmp_dir" || exit 2
      "$command_name" >/dev/null 2>&1
    )
    assert_status "$?" 1 "$command_name remains stable under hostile caller options" || return 1
  done

  command mkdir -p -- "$fixture_dir" "$fakebin"
  builtin cd -- "$fixture_dir" || return 1
  mkcd -created || {
    builtin cd -- "$original_dir"
    return 1
  }
  assert_equals "$PWD" "$fixture_dir/-created" 'mkcd accepts a leading-dash directory name' || {
    builtin cd -- "$original_dir"
    return 1
  }

  builtin cd -- "$fixture_dir" || return 1
  command mkdir -- -scan
  print -r -- data > -scan/file.txt
  output=$(bigfiles -scan 1) || return 1
  assert_contains "$output" 'file.txt' 'bigfiles canonicalizes a leading-dash target before find' || return 1

  builtin cd -- "$fixture_dir" || return 1
  local -a archive_names=(
    -archive.tar.bz2 -archive.tar.gz -archive.tar.xz -archive.tar.zst
    -archive.bz2 -archive.rar -archive.gz -archive.tar -archive.zip
    -archive.Z -archive.7z
  )
  for tool in tar bunzip2 unrar gunzip unzip uncompress 7z; do
    print -r -- '#!/bin/sh
last=
for argument in "$@"; do last=$argument; done
printf "%s\n" "$last" > "$EXTRACT_TEST_LOG"' >"$fakebin/$tool"
    command chmod +x -- "$fakebin/$tool"
  done
  PATH="$fakebin:$old_path"
  export EXTRACT_TEST_LOG
  rehash
  for archive_name in "${archive_names[@]}"; do
    : >"./$archive_name"
    extract -- "$archive_name" || {
      PATH=$old_path
      rehash
      builtin cd -- "$original_dir"
      return 1
    }
    assert_equals "$(<"$gunzip_log")" "$fixture_dir/$archive_name" "extract safely normalizes $archive_name" || return 1
  done
  PATH=$old_path
  rehash
  builtin cd -- "$original_dir"
}

test_usage_temp_cleanup() {
  local fixture_dir="$tmp_dir/usage-cleanup"
  local fakebin="$tmp_dir/usage-cleanup-bin"
  local old_path=$PATH old_tmpdir=${TMPDIR-} output rc
  integer had_tmpdir=${+TMPDIR}
  local -a leftovers

  command mkdir -p -- "$fixture_dir/entry" "$fakebin"
  print -r -- '#!/bin/sh
exit 7' >"$fakebin/du"
  print -r -- '#!/bin/sh
exit 7' >"$fakebin/find"
  command chmod +x -- "$fakebin/du" "$fakebin/find"
  PATH="$fakebin:$old_path"
  TMPDIR=$tmp_dir
  rehash

  output=$(dusage "$fixture_dir" 5 2>&1)
  rc=$?
  assert_status "$rc" 7 'dusage preserves a failed scan status' || return 1
  leftovers=( "$tmp_dir"/dusage.*(N) )
  assert_equals "${#leftovers[@]}" 0 'dusage removes every temporary file after scan failure' || return 1

  output=$(bigfiles "$fixture_dir" 5 2>&1)
  rc=$?
  assert_status "$rc" 7 'bigfiles preserves a failed find status' || return 1
  leftovers=( "$tmp_dir"/bigfiles.*(N) )
  assert_equals "${#leftovers[@]}" 0 'bigfiles removes every temporary file after scan failure' || return 1

  PATH=$old_path
  rehash
  if (( had_tmpdir )); then
    TMPDIR=$old_tmpdir
  else
    unset TMPDIR
  fi
}

test_usage_partial_scan() {
  local fixture_dir="$tmp_dir/usage-partial"
  local fakebin="$tmp_dir/usage-partial-bin"
  local old_path=$PATH output stdout_part stderr_part rc
  local stdout_file="$tmp_dir/usage-partial.stdout" stderr_file="$tmp_dir/usage-partial.stderr"
  local -a leftovers

  command mkdir -p -- "$fixture_dir/entry" "$fixture_dir/tree" "$fakebin"
  print -r -- 'data' >"$fixture_dir/tree/file.txt"

  # dusage: fake du emits one valid record then fails.
  print -r -- "#!/bin/sh
printf '4\t$fixture_dir/entry\0'
exit 1" >"$fakebin/du"
  command chmod +x -- "$fakebin/du"
  PATH="$fakebin:$old_path"
  rehash

  dusage "$fixture_dir" 5 >"$stdout_file" 2>"$stderr_file"; rc=$?
  output=$(<"$stdout_file"); stderr_part=$(<"$stderr_file")
  assert_status "$rc" 1 'dusage returns failure on a partial scan' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$output" 'entry' 'dusage preserves partial results' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$stderr_part" 'Incomplete scan' 'dusage reports an incomplete scan on stderr' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$stderr_part" 'du exit 1' 'dusage names the failed scan tool' || { PATH=$old_path; rehash; return 1; }
  leftovers=( "$tmp_dir"/dusage.*(N) )
  assert_equals "${#leftovers[@]}" 0 'dusage cleans up after a partial scan' || { PATH=$old_path; rehash; return 1; }

  # bigfiles: real find with failing du still preserves partial results.
  bigfiles "$fixture_dir/tree" 5 >"$stdout_file" 2>"$stderr_file"; rc=$?
  output=$(<"$stdout_file"); stderr_part=$(<"$stderr_file")
  assert_status "$rc" 1 'bigfiles returns failure when du is incomplete' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$stderr_part" 'Incomplete scan' 'bigfiles reports du failure on stderr' || { PATH=$old_path; rehash; return 1; }

  command rm -f -- "$fakebin/du"
  print -r -- "#!/bin/sh
printf '%s\0' \"$fixture_dir/tree/file.txt\"
exit 1" >"$fakebin/find"
  command chmod +x -- "$fakebin/find"
  rehash

  bigfiles "$fixture_dir/tree" 5 >"$stdout_file" 2>"$stderr_file"; rc=$?
  output=$(<"$stdout_file"); stderr_part=$(<"$stderr_file")
  assert_status "$rc" 1 'bigfiles returns failure when find is incomplete' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$output" 'file.txt' 'bigfiles preserves results when find is incomplete' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$stderr_part" 'find exit 1' 'bigfiles names the failed find scan' || { PATH=$old_path; rehash; return 1; }
  leftovers=( "$tmp_dir"/bigfiles.*(N) )
  assert_equals "${#leftovers[@]}" 0 'bigfiles cleans up after a partial find scan' || { PATH=$old_path; rehash; return 1; }

  command rm -f -- "$fakebin/find" "$fakebin/du"
  print -r -- "#!/bin/sh
printf '4\t$fixture_dir/entry\0'
exit 1" >"$fakebin/du"
  command chmod +x -- "$fakebin/du"
  rehash

  functions[_ui_plain_mode]='return 1'
  functions[_ui_term_width_reply]='REPLY=120'
  functions[_ui_term_height]='print -r -- 30'
  dusage "$fixture_dir" 5 >"$stdout_file" 2>"$stderr_file"; rc=$?
  output=$(<"$stdout_file"); stderr_part=$(<"$stderr_file")
  functions[_ui_plain_mode]='return 0'
  unset 'functions[_ui_term_width_reply]' 'functions[_ui_term_height]'
  source "$repo_dir/55-ui-helpers.zsh"
  functions[_ui_plain_mode]='return 0'
  assert_status "$rc" 1 'dusage rich mode returns failure on a partial scan' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$output" 'Incomplete scan' 'dusage rich output carries the partial state' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$output" '(incomplete scan)' 'dusage rich footer marks the partial state' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$stderr_part" 'Incomplete scan' 'dusage rich mode keeps the stderr diagnostic' || { PATH=$old_path; rehash; return 1; }

  PATH=$old_path
  rehash
}

test_usage_signal_cleanup() {
  emulate -L zsh
  setopt localtraps

  if ! zmodload zsh/zselect 2>/dev/null; then
    print -- 'ok: usage signal cleanup skipped without zsh/zselect'
    return 0
  fi

  local fixture_dir="$tmp_dir/usage-signal"
  local fakebin="$tmp_dir/usage-signal-bin"
  local old_path=$PATH old_tmpdir=${TMPDIR-}
  local started="$tmp_dir/usage-signal-started"
  local release="$tmp_dir/usage-signal-release"
  local status_file="$tmp_dir/usage-signal-status"
  local worker_pid rc
  integer had_tmpdir=${+TMPDIR} ticks
  local -a leftovers

  command mkdir -p -- "$fixture_dir/entry" "$fakebin"
  print -r -- '#!/bin/sh
: > "$USAGE_SIGNAL_STARTED"
while [ ! -e "$USAGE_SIGNAL_RELEASE" ]; do :; done
exit 0' >"$fakebin/du"
  command chmod +x -- "$fakebin/du"

  PATH="$fakebin:$old_path"
  TMPDIR=$tmp_dir
  export USAGE_SIGNAL_STARTED=$started USAGE_SIGNAL_RELEASE=$release
  rehash

  (dusage "$fixture_dir" 5 >/dev/null 2>&1; rc=$?; print -r -- "$rc" >"$status_file"; exit $rc) &
  worker_pid=$!
  ticks=0
  while [[ ! -e $started ]] && (( ticks < 100 )); do
    zselect -t 1
    (( ticks++ ))
  done
  [[ -e $started ]] || return 1
  kill -INT "$worker_pid"
  : >"$release"
  wait "$worker_pid" 2>/dev/null
  rc=$?
  assert_status "$rc" 130 'dusage preserves SIGINT status' || return 1
  assert_equals "$(<"$status_file")" 130 'dusage returns SIGINT status from its function body' || return 1
  leftovers=( "$tmp_dir"/dusage.*(N) )
  assert_equals "${#leftovers[@]}" 0 'dusage removes temporary files after SIGINT' || return 1

  command rm -f -- "$started" "$release" "$status_file"
  (dusage "$fixture_dir" 5 >/dev/null 2>&1; rc=$?; print -r -- "$rc" >"$status_file"; exit $rc) &
  worker_pid=$!
  ticks=0
  while [[ ! -e $started ]] && (( ticks < 100 )); do
    zselect -t 1
    (( ticks++ ))
  done
  [[ -e $started ]] || return 1
  kill -HUP "$worker_pid"
  : >"$release"
  wait "$worker_pid" 2>/dev/null
  rc=$?
  assert_status "$rc" 129 'dusage preserves SIGHUP status' || return 1
  assert_equals "$(<"$status_file")" 129 'dusage returns SIGHUP status from its function body' || return 1
  leftovers=( "$tmp_dir"/dusage.*(N) )
  assert_equals "${#leftovers[@]}" 0 'dusage removes temporary files after SIGHUP' || return 1

  command rm -f -- "$started" "$release" "$status_file" "$fakebin/du"
  print -r -- '#!/bin/sh
: > "$USAGE_SIGNAL_STARTED"
while [ ! -e "$USAGE_SIGNAL_RELEASE" ]; do :; done
exit 0' >"$fakebin/find"
  command chmod +x -- "$fakebin/find"
  rehash

  (bigfiles "$fixture_dir" 5 >/dev/null 2>&1; rc=$?; print -r -- "$rc" >"$status_file"; exit $rc) &
  worker_pid=$!
  ticks=0
  while [[ ! -e $started ]] && (( ticks < 100 )); do
    zselect -t 1
    (( ticks++ ))
  done
  [[ -e $started ]] || return 1
  kill -TERM "$worker_pid"
  : >"$release"
  wait "$worker_pid" 2>/dev/null
  rc=$?
  assert_status "$rc" 143 'bigfiles preserves SIGTERM status' || return 1
  assert_equals "$(<"$status_file")" 143 'bigfiles returns SIGTERM status from its function body' || return 1
  leftovers=( "$tmp_dir"/bigfiles.*(N) )
  assert_equals "${#leftovers[@]}" 0 'bigfiles removes temporary files after SIGTERM' || return 1

  PATH=$old_path
  rehash
  if (( had_tmpdir )); then
    TMPDIR=$old_tmpdir
  else
    unset TMPDIR
  fi
  unset USAGE_SIGNAL_STARTED USAGE_SIGNAL_RELEASE
}

test_dusage_oversized_operand_set() {
  emulate -L zsh

  local fixture_dir="$tmp_dir/dusage-oversized"
  local path_segment='segment-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-'
  local file_component='operand-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-'
  integer depth index rc aggregate_bytes arg_max operand_count operand_bytes

  command mkdir -p -- "$fixture_dir"
  for (( depth = 1; depth <= 14; depth++ )); do
    fixture_dir+="/${path_segment}${depth}"
    command mkdir -- "$fixture_dir" || return 1
  done
  arg_max=$(command getconf ARG_MAX) || return 1
  operand_bytes=$(( ${#fixture_dir} + ${#file_component} + 4 ))
  operand_count=$(( arg_max / operand_bytes + 2 ))

  for (( index = 1; index <= operand_count; index++ )); do
    print -rn -- "$fixture_dir/${file_component}${index}"$'\0'
  done | command xargs -0 touch -- || return 1

  aggregate_bytes=$(( operand_count * operand_bytes ))
  (( aggregate_bytes > arg_max )) || return 1

  dusage "$fixture_dir" 1 >/dev/null
  rc=$?
  assert_status "$rc" 0 'dusage completes with an operand set larger than ARG_MAX' || return 1
}

test_path_empty_entries() {
  local output_file="$tmp_dir/path-output"
  local old_path=$PATH entry
  local -a actual

  PATH=:/bin::/usr/bin:
  path >"$output_file"
  PATH=$old_path

  while IFS= read -r entry; do
    actual+=("$entry")
  done <"$output_file"

  assert_equals "${#actual[@]}" 5 'path preserves every PATH component' || return 1
  assert_equals "${actual[1]}" '' 'path preserves a leading current-directory component' || return 1
  assert_equals "${actual[2]}" '/bin' 'path preserves the first named component' || return 1
  assert_equals "${actual[3]}" '' 'path preserves an interior current-directory component' || return 1
  assert_equals "${actual[4]}" '/usr/bin' 'path preserves the second named component' || return 1
  assert_equals "${actual[5]}" '' 'path preserves a trailing current-directory component' || return 1
}

test_control_character_paths() {
  local fixture_dir="$tmp_dir/"$'target-\e-λ'
  local plain_dusage="$tmp_dir/dusage-plain.out"
  local plain_bigfiles="$tmp_dir/bigfiles-plain.out"
  local plain_path="$tmp_dir/path-plain.out"
  local rich_dusage="$tmp_dir/dusage-rich.out"
  local rich_bigfiles="$tmp_dir/bigfiles-rich.out"
  local rich_path="$tmp_dir/path-rich.out"
  local stripped="$tmp_dir/rich-stripped.out"
  local filename output old_path=$PATH safe truncated
  integer token_index
  local -a filenames safe_tokens safe_labels
  local -a output_lines

  command mkdir -p -- "$fixture_dir"
  filenames=(
    $'esc-\e[31m-red.txt'
    $'bel-\a-ring.txt'
    $'backspace-\b-hide.txt'
    $'del-\x7f-delete.txt'
    $'newline-\n-row.txt'
    $'carriage-\r-return.txt'
    $'tab-\t-column.txt'
    $'form-\f-feed.txt'
    $'vertical-\v-tab.txt'
    $'other-\x01-control.txt'
    $'c1-\u0085-control.txt'
    'unicode-λ-雪.txt'
  )

  for filename in "${filenames[@]}"; do
    print -r -- 'fixture data' >"$fixture_dir/$filename"
  done

  dusage "$fixture_dir" 50 >"$plain_dusage"
  assert_status "$?" 0 'dusage renders hostile plain paths successfully' || return 1
  output=$(<"$plain_dusage")
  output_lines=( "${(f)output}" )
  assert_equals "${#output_lines[@]}" "${#filenames[@]}" 'dusage keeps every hostile filename on one plain output row' || return 1
  assert_safe_output_file "$plain_dusage" 'dusage plain output contains no active control data' || return 1

  bigfiles "$fixture_dir" 50 >"$plain_bigfiles"
  assert_status "$?" 0 'bigfiles renders hostile plain paths successfully' || return 1
  output=$(<"$plain_bigfiles")
  output_lines=( "${(f)output}" )
  assert_equals "${#output_lines[@]}" "${#filenames[@]}" 'bigfiles keeps every hostile filename on one plain output row' || return 1
  assert_safe_output_file "$plain_bigfiles" 'bigfiles plain output contains no active control data' || return 1

  output="$(<"$plain_dusage")"$'\n'"$(<"$plain_bigfiles")"
  safe_tokens=( '\e' '\a' '\b' '\x7f' '\n' '\r' '\t' '\f' '\v' '\x01' '\x85' 'unicode-λ-雪.txt' 'target-\e-λ' )
  safe_labels=( ESC BEL backspace DEL newline 'carriage return' tab 'form feed' 'vertical tab' 'other C0' C1 Unicode 'hostile target' )
  for (( token_index = 1; token_index <= ${#safe_tokens[@]}; token_index++ )); do
    assert_contains "$output" "${safe_tokens[$token_index]}" "filesystem output preserves ${safe_labels[$token_index]} safely" || return 1
  done

  PATH="$fixture_dir:$tmp_dir/"$'path-\a-entry'":/bin"
  path >"$plain_path"
  PATH=$old_path
  output=$(<"$plain_path")
  assert_contains "$output" 'target-\e-λ' 'path sanitizes its hostile target entry' || return 1
  assert_contains "$output" 'path-\a-entry' 'path renders BEL as a visible escape' || return 1
  assert_safe_output_file "$plain_path" 'path plain output contains no active control data' || return 1

  safe=$(_ui_safe_text $'plain λ 雪')
  assert_equals "$safe" 'plain λ 雪' 'safe-text helper preserves ordinary Unicode' || return 1
  safe=$(_ui_safe_text $'123456\eABCDEFGHIJKLMNO')
  truncated=$(_ui_safe_truncate 17 "$safe")
  assert_equals "$truncated" '123456...IJKLMNO' 'safe truncation never splits a short visible escape' || return 1
  safe=$(_ui_safe_text $'1234\x7fABCDEFGHIJKLMNO')
  truncated=$(_ui_safe_truncate 17 "$safe")
  assert_equals "$truncated" '1234...IJKLMNO' 'safe truncation never splits a hexadecimal escape' || return 1
  assert_not_contains "$truncated" '\x...' 'safe truncation emits no partial hexadecimal escape' || return 1

  (
    functions[_ui_plain_mode]='return 1'
    functions[_ui_term_width_reply]='REPLY=60'
    functions[_ui_term_height]='print -r -- 100'
    functions[_ui_color]='printf "\e[35m"'
    functions[_ui_reset]='printf "\e[0m"'
    functions[_ui_bold]=':'
    functions[_ui_icon]='print -nr -- "$2"'
    dusage "$fixture_dir" 50
  ) >"$rich_dusage"
  assert_status "$?" 0 'dusage renders hostile rich paths successfully' || return 1

  (
    functions[_ui_plain_mode]='return 1'
    functions[_ui_term_width_reply]='REPLY=60'
    functions[_ui_term_height]='print -r -- 100'
    functions[_ui_color]='printf "\e[35m"'
    functions[_ui_reset]='printf "\e[0m"'
    functions[_ui_bold]=':'
    functions[_ui_icon]='print -nr -- "$2"'
    bigfiles "$fixture_dir" 50
  ) >"$rich_bigfiles"
  assert_status "$?" 0 'bigfiles renders hostile rich paths successfully' || return 1

  (
    functions[_ui_plain_mode]='return 1'
    functions[_ui_term_width_reply]='REPLY=60'
    functions[_ui_color]='printf "\e[35m"'
    functions[_ui_reset]='printf "\e[0m"'
    functions[_ui_bold]=':'
    functions[_ui_icon]='print -nr -- "$2"'
    PATH="$fixture_dir:$tmp_dir/"$'path-\a-entry'":/bin"
    path
  ) >"$rich_path"
  assert_status "$?" 0 'path renders hostile rich entries successfully' || return 1

  for filename in "$rich_dusage" "$rich_bigfiles" "$rich_path"; do
    output=$(<"$filename")
    assert_contains "$output" $'\e[35m' "${filename:t} contains the expected UI styling" || return 1
    assert_not_contains "$output" $'\e[31m' "${filename:t} does not activate filename-provided styling" || return 1
    command sed $'s/\033\\[35m//g; s/\033\\[0m//g' "$filename" >"$stripped"
    assert_safe_output_file "$stripped" "${filename:t} is safe after expected UI styling is removed" || return 1
  done
}

test_sanitizer_ascii_fast_path() (
  local locale value char escaped expected long=''
  integer code calls=0
  # All byte-range controls, plus printable Unicode and invalid UTF-8.
  for locale in C.UTF-8; do
    local LC_ALL=$locale
    for (( code=0; code<=159; code++ )); do
      builtin printf -v escaped '\\u%04x' "$code"
      builtin printf -v char '%b' "$escaped"
      case $code in
        7) expected='\a';; 8) expected='\b';; 9) expected='\t';;
        10) expected='\n';; 11) expected='\v';; 12) expected='\f';;
        13) expected='\r';; 27) expected='\e';;
        *)
          if (( code < 32 || code == 127 || (code >= 128 && code <= 159) )); then
            builtin printf -v expected '\\x%02x' "$code"
          else expected=$char
          fi ;;
      esac
      _ui_safe_text_reply "a${char}b"
      [[ $REPLY == "a${expected}b" ]] || {
        print -u2 -- "not ok: sanitizer control $code in $locale"
        return 1
      }
    done
  done
  LC_ALL=C.UTF-8
  for value in '' 'short ASCII ~' 'é雪😀' $'e\u0301' $'a\xffb'; do
    _ui_safe_text_reply "$value"
    [[ $REPLY == "$value" ]] || return 1
  done
  printf() { (( calls++ )); builtin printf "$@"; }
  for locale in C C.UTF-8; do
    LC_ALL=$locale
    for value in '' 'short' "${(l:4096::x:)long}"; do
      _ui_safe_text_reply "$value"
      [[ $REPLY == "$value" ]] || return 1
    done
  done
  (( calls == 0 )) || return 1
  _ui_safe_text_reply '雪'
  (( calls > 0 )) || return 1
  print -- 'ok: sanitizer ASCII skips character conversion; controls, Unicode, and invalid bytes retain output'
)

test_display_width() {
  local width padded truncated

  _ui_display_width 'hello'
  assert_equals "$REPLY" 5 'narrow text measures one cell per character' || return 1
  _ui_display_width 'a雪b'
  assert_equals "$REPLY" 4 'wide CJK characters measure two cells' || return 1
  _ui_display_width $'e\u0301'
  assert_equals "$REPLY" 1 'combining marks add no cells' || return 1
  _ui_display_width $'क\u094D'
  assert_equals "$REPLY" 1 'Devanagari nonspacing marks add no cells' || return 1
  _ui_display_width $'x\U0001E944'
  assert_equals "$REPLY" 1 'supplementary-plane combining marks add no cells' || return 1
  _ui_display_width '\n'
  assert_equals "$REPLY" 2 'sanitized visible escapes measure their shown cells' || return 1

  _ui_truncate_reply 5 $'abcd雪\u0301'
  assert_not_contains "$REPLY" $'.\u0301' 'truncation does not attach orphan marks to the marker' || return 1

  _ui_char_width 0x41
  assert_equals "$REPLY" 1 'ASCII measures one cell' || return 1
  _ui_char_width 0x4E00
  assert_equals "$REPLY" 2 'CJK Unified Ideographs measure two cells' || return 1
  _ui_char_width 0x0301
  assert_equals "$REPLY" 0 'combining code points measure zero cells' || return 1
  assert_not_contains "${functions[_ui_display_width]}" 'command ' 'cell measurement spawns no subprocesses' || return 1
  assert_not_contains "${functions[_ui_char_width]}" 'command ' 'cell lookup invokes no external command' || return 1

  _ui_pad_reply left 6 'a雪'
  padded=$REPLY
  assert_equals "$padded" 'a雪   ' 'padding aligns by cells rather than characters' || return 1
  _ui_display_width "$padded"
  assert_equals "$REPLY" 6 'padded CJK rows fill the requested cells' || return 1

  truncated=$(_ui_safe_truncate 6 'ab雪cd')
  assert_equals "$truncated" 'ab雪cd' 'fitting CJK text is left whole' || return 1
  truncated=$(_ui_safe_truncate 5 'ab雪cd')
  assert_equals "$truncated" 'a...d' 'CJK truncation keeps whole cells around the marker' || return 1
  _ui_display_width "$truncated"
  assert_equals "$REPLY" 5 'truncated CJK rows fit the requested cells' || return 1
  truncated=$(_ui_safe_truncate 3 $'e\u0301x')
  assert_equals "$truncated" $'e\u0301x' 'combining sequences survive truncation' || return 1
}

test_human_bytes() {
  local output

  output=$(_ui_human_bytes 0)
  assert_equals "$output" '0B' 'zero bytes stay unqualified' || return 1
  output=$(_ui_human_bytes 1023)
  assert_equals "$output" '1023B' 'byte counts below one KiB stay whole' || return 1
  output=$(_ui_human_bytes 1024)
  assert_equals "$output" '1.0KiB' 'one KiB keeps one decimal place' || return 1
  output=$(_ui_human_bytes 1536)
  assert_equals "$output" '1.5KiB' 'fractional KiB values keep their tenth' || return 1
  output=$(_ui_human_bytes 10240)
  assert_equals "$output" '10KiB' 'two-digit values drop the decimal place' || return 1
  output=$(_ui_human_kib 1048576)
  assert_equals "$output" '1.0GiB' 'KiB input converts through the byte formatter' || return 1

  # Regression: `bytes * 10` used to wrap near the signed 64-bit ceiling and
  # render negative text instead of the rounded unit value.
  output=$(_ui_human_bytes 999999999999999999)
  assert_equals "$output" '888PiB' 'large byte counts never overflow into negative text' || return 1
  output=$(_ui_human_bytes 9223372036854775807)
  assert_equals "$output" '8192PiB' 'the signed 64-bit ceiling formats without wrapping' || return 1
}

test_alias_probes_are_quiet() {
  local fakebin="$tmp_dir/fakebin"
  local stdout_file="$tmp_dir/aliases.stdout"
  local stderr_file="$tmp_dir/aliases.stderr"
  local invocation_log="$tmp_dir/aliases.invocations"
  local output zsh_bin=${commands[zsh]}

  command mkdir -p -- "$fakebin"

  print -r -- '#!/bin/sh
printf "%s\n" ls >> "$ALIAS_PROBE_LOG"
printf "%s\n" "unsupported ls option" >&2
exit 2' >"$fakebin/ls"
  print -r -- '#!/bin/sh
printf "%s\n" grep >> "$ALIAS_PROBE_LOG"
exit 1' >"$fakebin/grep"
  print -r -- '#!/bin/sh
printf "%s\n" diff >> "$ALIAS_PROBE_LOG"
printf "%s\n" "unsupported diff option" >&2
exit 2' >"$fakebin/diff"
  command chmod +x "$fakebin/ls" "$fakebin/grep" "$fakebin/diff"

  ALIAS_PROBE_LOG=$invocation_log PATH="$fakebin" "$zsh_bin" -fc "source ${(q)repo_dir}/20-aliases.zsh" >"$stdout_file" 2>"$stderr_file"
  assert_status "$?" 0 'alias fallback probes complete when color flags are unsupported' || return 1

  output=$(<"$stdout_file")
  assert_equals "$output" '' 'alias fallback probes keep stdout quiet' || return 1
  output=$(<"$stderr_file")
  assert_equals "$output" '' 'alias fallback probes keep stderr quiet' || return 1
  [[ ! -e $invocation_log ]] || output=$(<"$invocation_log")
  assert_equals "${output:-}" '' 'alias setup starts no capability-probe subprocesses' || return 1
}

test_small_helper_success_paths() {
  emulate -L zsh

  local fixture_dir="$tmp_dir/small-helper-success"
  local fakebin="$tmp_dir/small-helper-bin"
  local old_path=$PATH output original_dir=$PWD

  command mkdir -p -- "$fixture_dir/repo/nested/path" "$fakebin"
  print -r -- 'needle' >"$fixture_dir/preview.txt"

  output=$(peek "$fixture_dir/preview.txt") || return 1
  assert_equals "$output" 'needle' 'peek prints a readable file through its fallback' || return 1

  print -r -- '#!/bin/sh
printf "%s\n" "HTTP/1.1 204 No Content"' >"$fakebin/curl"
  command chmod +x -- "$fakebin/curl"
  output=$(PATH="$fakebin:$old_path" headers 'https://example.invalid/path') || return 1
  assert_contains "$output" '204 No Content' 'headers follows its successful curl path' || return 1

  command git init -q "$fixture_dir/repo" || return 1
  print -r -- one >"$fixture_dir/repo/file"
  command git -C "$fixture_dir/repo" add file || return 1
  command git -C "$fixture_dir/repo" -c user.name=One -c user.email=one@example.invalid commit -qm one || return 1
  print -r -- two >>"$fixture_dir/repo/file"
  command git -C "$fixture_dir/repo" add file || return 1
  command git -C "$fixture_dir/repo" -c user.name=Two -c user.email=two@example.invalid commit -qm two || return 1

  builtin cd -- "$fixture_dir/repo" || return 1
  output=$(gitcount) || return 1
  assert_contains "$output" 'One' 'gitcount reports the first contributor' || return 1
  assert_contains "$output" 'Two' 'gitcount reports the second contributor' || return 1
  builtin cd -- "$fixture_dir/repo/nested/path" || return 1
  croot || return 1
  assert_equals "$PWD" "$fixture_dir/repo" 'croot enters the repository root from a nested directory' || return 1
  builtin cd -- "$original_dir" || return 1

  print -r -- '#!/bin/sh
if [ "$1" = "--color=auto" ]; then
  printf "%s\n" "clean match"
else
  printf "\033[31mforced match\033[0m\n"
fi' >"$fakebin/rg"
  command chmod +x -- "$fakebin/rg"
  PATH="$fakebin:$old_path"
  rehash
  output=$(ft needle "$fixture_dir") || return 1
  PATH=$old_path
  rehash
  assert_equals "$output" 'clean match' 'ft keeps redirected ripgrep output free of ANSI escapes' || return 1

  print -r -- '#!/bin/sh
[ "$*" = "--http1.1 -fsSL --connect-timeout 5 --max-time 15 -- https://wttr.in" ] || exit 8
printf "%s\n" "Clear 20 C"' >"$fakebin/curl"
  command chmod +x -- "$fakebin/curl"
  output=$(PATH="$fakebin:$old_path" "$commands[zsh]" -fc "source ${(q)repo_dir}/60-functions.zsh; weather") || return 1
  assert_equals "$output" 'Clear 20 C' 'weather helper reaches its HTTPS forecast endpoint' || return 1

  local fanprofile_body=${functions[fanprofile]}
  local platform_fixture="$fixture_dir/platform-profile"
  local choices_fixture="$fixture_dir/platform-choices"
  print -r -- balanced >"$platform_fixture"
  print -r -- 'low-power balanced performance' >"$choices_fixture"
  fanprofile_body=${fanprofile_body//\/sys\/firmware\/acpi\/platform_profile_choices/$choices_fixture}
  fanprofile_body=${fanprofile_body//\/sys\/firmware\/acpi\/platform_profile/$platform_fixture}
  functions[_test_fanprofile]=$fanprofile_body
  output=$(_test_fanprofile) || return 1
  unfunction _test_fanprofile
  assert_equals "$output" 'balanced (platform_profile)' 'fanprofile reports a readable platform profile' || return 1
}

test_fkill_signals() {
  local input expected pair

  for pair in '15:TERM:15' '-15:TERM:15' 'TERM:TERM:15' 'SIGTERM:TERM:15'; do
    input=${pair%%:*}
    expected=${pair#*:}
    _fkill_normalize_signal "$input" || return 1
    assert_equals "$REPLY:$reply[1]" "$expected" "fkill normalizes $input" || return 1
  done

  typeset -gi FZF_REQUIRE_CALLED=0
  functions[_zsh_require_fzf]='(( FZF_REQUIRE_CALLED++ )); return 1'
  fkill SIG >/dev/null 2>"$tmp_dir/fkill-invalid.err"
  assert_status "$?" 1 'fkill rejects an empty normalized signal' || return 1
  assert_equals "$FZF_REQUIRE_CALLED" 0 'fkill rejects invalid signals before opening fzf' || return 1

  assert_contains "${functions[fkill]}" "signal='15'" 'fkill defaults to SIGTERM' || return 1
  assert_contains "${functions[fkill]}" '--accept-nth=1' 'fkill asks fzf to return PIDs directly' || return 1
  assert_contains "${functions[fkill]}" '_fzf_picker_multi_args kill' 'fkill uses the shared live multi-selection footer' || return 1
  assert_not_contains "${functions[fkill]}" '_fzf_pointer' 'fkill no longer duplicates pointer presentation' || return 1
  assert_not_contains "${functions[fkill]}" 'SIG${signal}' 'fkill never renders a duplicated SIG prefix' || return 1
  assert_contains "${functions[fkill]}" '--with-nth=1,2,3,4' 'fkill shows PID, owner, elapsed time, and command' || return 1
  assert_not_contains "${functions[fkill]}" '--with-nth=2..' 'fkill no longer hides process identity' || return 1
  assert_contains "${functions[fkill]}" '_fzf_picker_preview_args Process' 'fkill previews full process details' || return 1
  assert_contains "${functions[fkill]}" '--all' 'fkill offers an explicit all-users mode' || return 1
  assert_contains "${functions[fkill]}" 'ps -u "$current_user"' 'fkill defaults to the current user' || return 1
  assert_contains "${functions[fkill]}" 'signal_number == 9' 'fkill reviews SIGKILL before sending' || return 1
  assert_contains "${functions[fkill]}" 'failed to send SIG' 'fkill reports per-target outcomes' || return 1
  assert_not_contains "${functions[fkill]}" 'sudo' 'fkill never escalates privileges implicitly' || return 1
  assert_not_contains "${functions[fkill]}" 'su ' 'fkill never shells out to su' || return 1
}

test_fkill_scope_and_review() {
  local output rc formatted
  local -a fzf_calls

  functions[_zsh_require_fzf]='return 0'

  output=$(fkill --all BADSIGNAL 2>&1); rc=$?
  assert_status "$rc" 1 'fkill --all still rejects an invalid signal' || return 1
  assert_contains "$output" 'invalid signal' 'fkill --all reports the bad signal, not the flag' || return 1

  output=$(fkill --all 15 2>&1); rc=$?
  assert_status "$rc" 1 'fkill --all parses the flag and reaches the terminal gate' || return 1
  assert_contains "$output" 'requires an interactive terminal' 'fkill --all does not treat the flag as a signal' || return 1

  output=$(fkill -a 2>&1); rc=$?
  assert_status "$rc" 1 'fkill -a defaults to SIGTERM and reaches the terminal gate' || return 1

  output=$(fkill 15 --all 2>&1); rc=$?
  assert_status "$rc" 1 'fkill accepts the flag after the signal' || return 1
  assert_contains "$output" 'requires an interactive terminal' 'trailing --all is not a signal' || return 1

  output=$(fkill 15 9 2>&1); rc=$?
  assert_status "$rc" 1 'fkill rejects multiple signals' || return 1
  assert_contains "$output" 'too many arguments' 'fkill explains the extra signal' || return 1

  formatted=$(printf '%s\n' '  111 alice 00:01 sleep 100' | command awk '
    {
      pid = $1
      user = $2
      etime = $3
      $1 = $2 = $3 = ""
      sub(/^ +/, "")
      print pid "\t" user "\t" etime "\t" $0
    }')
  assert_equals "$formatted" $'111\talice\t00:01\tsleep 100' 'fkill formats PID, owner, elapsed, and command' || return 1

  functions[_zsh_require_fzf]='(( FZF_REQUIRE_CALLED++ )); return 1'
}

test_fbr_worktree_navigation() {
  local fixture_repo="$tmp_dir/fbr-repo"
  local remote_repo="$tmp_dir/fbr-remote.git"
  local worktree_dir="$tmp_dir/fbr worktree"
  local original_dir=$PWD branch current_branch first_row formatter_body projected second_row worktree_path
  integer private_fpath_count=0
  local -A worktree_paths

  assert_equals "${(V)functions[_fbr_format_entry]}" 'builtin autoload -XU' 'fbr formatter starts as a deferred repo-local autoload' || return 1
  _fbr_format_entry short '5 days ago' 'A subject' '' '' '' 16 12 refs/heads/short
  first_row=$REPLY
  assert_equals "$first_row" $'short           \t5 days ago  \tA subject\t\trefs/heads/short' 'fbr pads branch and relative-date display columns' || return 1
  formatter_body=${functions[_fbr_format_entry]}
  assert_not_contains "${(V)formatter_body}" 'builtin autoload -XU' 'first fbr formatting call loads the deferred implementation' || return 1

  _fbr_format_entry short '5 days ago' 'A subject' '' '' '' 16 12 refs/heads/short
  second_row=$REPLY
  assert_equals "$second_row" "$first_row" 'repeated fbr formatting stays deterministic' || return 1

  source "$repo_dir/60-functions.zsh"
  assert_equals "${functions[_fbr_format_entry]}" "$formatter_body" 're-sourcing preserves the loaded fbr formatter' || return 1
  for worktree_path in "${fpath[@]}"; do
    [[ $worktree_path == "$repo_dir/functions" ]] && (( private_fpath_count++ ))
  done
  assert_equals "$private_fpath_count" 1 're-sourcing keeps one trusted functions path' || return 1

  _fbr_format_entry worktree-test '21 hours ago' $'Tabbed\tsubject' '/tmp/work tree' '' '' 16 12 refs/heads/worktree-test
  assert_equals "$REPLY" $'[WT] w...ee-test\t21 hours ago\tTabbed\\tsubject\t/tmp/work tree\trefs/heads/worktree-test' 'fbr aligns and sanitizes worktree rows while preserving the raw branch' || return 1

  _fbr_format_entry 'unicode-λ-雪' 'now' $'control-\e[31m' '' '' '' 18 8 refs/heads/unicode-λ-雪
  assert_equals "$REPLY" $'unicode-λ-雪      \tnow     \tcontrol-\\e[31m\t\trefs/heads/unicode-λ-雪' 'fbr pads CJK rows by terminal cells while sanitizing controls byte-for-byte' || return 1
  _fbr_format_entry '1234567890' '1234567890' subject '' '' '' 5 4 refs/heads/1234567890
  assert_equals "$REPLY" $'1...0\t1234\tsubject\t\trefs/heads/1234567890' 'fbr preserves width-boundary truncation byte-for-byte' || return 1

  local invalid_ref
  for invalid_ref in '' short refs/tags/short refs/heads/ $'refs/heads/bad\tref'; do
    REPLY=stale
    _fbr_format_entry short now subject '' '' '' 16 12 "$invalid_ref" 2>/dev/null
    assert_status "$?" 1 'fbr formatter rejects missing or noncanonical identity' || return 1
    assert_equals "$REPLY" '' 'rejected formatter identity leaves no stale row' || return 1
  done
  _fbr_format_entry origin/topic now subject '' '' '' 16 12 refs/remotes/origin/topic || return 1
  assert_equals "${REPLY##*$'\t'}" refs/remotes/origin/topic 'remote display label retains canonical selection identity' || return 1

  assert_contains "${functions[fbr]}" '--accept-nth=5' 'fbr asks fzf to return the branch field directly' || return 1
  assert_contains "${functions[fbr]}" "git log --oneline --decorate --color=always -20 {5}" 'fbr relies on fzf quoting the undecorated branch preview field' || return 1
  assert_contains "${functions[fbr]}" '_fzf_picker_preview_args Log' 'fbr uses the shared responsive preview policy' || return 1
  assert_not_contains "${functions[fbr]}" '38;5;116' 'fbr worktree badges no longer embed a raw palette color' || return 1

  if (( $+commands[fzf] )); then
    projected=$(print -r -- $'visible padded                  \tdate padded   \tsubject\t/worktree path\traw-branch' |
      command fzf --filter visible --delimiter=$'\t' --with-nth=1,2,3 --nth=1,2,3 --accept-nth=5)
    assert_equals "$projected" 'raw-branch' 'fbr five-field rows project the raw branch identity' || return 1
  fi

  command git init -q "$fixture_repo" || return 1
  print -r -- 'fixture' >"$fixture_repo/tracked.txt"
  command git -C "$fixture_repo" add tracked.txt || return 1
  command git -C "$fixture_repo" -c user.name='Zsh Tests' -c user.email='zsh-tests@example.invalid' \
    commit -qm 'Initial commit' || return 1
  command git init -q --bare "$remote_repo" || return 1
  command git -C "$fixture_repo" remote add origin "$remote_repo" || return 1
  command git -C "$fixture_repo" push -q origin HEAD:refs/heads/remote-safe || return 1
  command git -C "$fixture_repo" fetch -q origin || return 1
  command git -C "$fixture_repo" worktree add -q -b worktree-test "$worktree_dir" || return 1

  builtin cd -- "$fixture_repo" || return 1
  while IFS= read -r -d '' branch && IFS= read -r -d '' worktree_path; do
    worktree_paths[$branch]=$worktree_path
  done < <(_fbr_worktree_entries)

  assert_equals "${worktree_paths[refs/heads/worktree-test]-}" "$worktree_dir" 'fbr maps a checked-out branch to its worktree path' || {
    builtin cd -- "$original_dir"
    return 1
  }

  current_branch=$(command git symbolic-ref --short HEAD) || return 1
  worktree_paths=()
  while IFS= read -r -d '' branch && IFS= read -r -d '' worktree_path; do
    worktree_paths[$branch]=$worktree_path
  done < <(_fbr_worktree_entries "$fixture_repo")
  assert_equals "${worktree_paths[refs/heads/$current_branch]-}" '' 'fbr does not mark the branch in the current checkout as another worktree' || {
    builtin cd -- "$original_dir"
    return 1
  }
  assert_equals "${worktree_paths[refs/heads/worktree-test]-}" "$worktree_dir" 'fbr still maps branches in other worktrees' || {
    builtin cd -- "$original_dir"
    return 1
  }

  command git update-ref refs/heads/-leading HEAD || return 1
  _fbr_activate refs/heads/-leading '' || return 1
  assert_equals "$(command git symbolic-ref --short HEAD)" '-leading' 'fbr safely activates a leading-dash local branch' || return 1
  command git switch -- "$current_branch" >/dev/null || return 1

  _fbr_activate refs/remotes/origin/remote-safe '' || return 1
  assert_equals "$(command git symbolic-ref --short HEAD)" 'remote-safe' 'fbr safely activates and tracks a remote branch' || return 1
  command git switch -- "$current_branch" >/dev/null || return 1

  _fbr_activate refs/heads/worktree-test "${worktree_paths[refs/heads/worktree-test]}"
  assert_status "$?" 0 'fbr can activate a branch attached to a worktree' || {
    builtin cd -- "$original_dir"
    return 1
  }
  assert_equals "$PWD" "$worktree_dir" 'fbr enters the selected branch worktree, including paths with spaces' || {
    builtin cd -- "$original_dir"
    return 1
  }

  builtin cd -- "$original_dir"
}

test_fbr_remote_collision() {
  local collision_repo="$tmp_dir/fbr-collision" collision_remote="$tmp_dir/fbr-collision.git"
  local collision_second="$tmp_dir/fbr-collision-second.git" original_dir=$PWD
  local base_branch before_ref after_ref output rc upstream

  command git init -q "$collision_repo" || return 1
  print -r -- 'base' >"$collision_repo/base.txt"
  command git -C "$collision_repo" add base.txt || return 1
  command git -C "$collision_repo" -c user.name='Zsh Tests' -c user.email='zsh-tests@example.invalid' \
    commit -qm 'Base commit' || return 1
  base_branch=$(command git -C "$collision_repo" symbolic-ref --short HEAD) || return 1

  command git -C "$collision_repo" checkout -qb topic || return 1
  print -r -- 'local' >>"$collision_repo/base.txt"
  command git -C "$collision_repo" add base.txt || return 1
  command git -C "$collision_repo" -c user.name='Zsh Tests' -c user.email='zsh-tests@example.invalid' \
    commit -qm 'Local topic' || return 1
  command git -C "$collision_repo" checkout -q "$base_branch" || return 1

  command git init -q --bare "$collision_remote" || return 1
  command git -C "$collision_repo" remote add origin "$collision_remote" || return 1
  command git -C "$collision_repo" checkout -qb divergent || return 1
  print -r -- 'remote' >"$collision_repo/remote.txt"
  command git -C "$collision_repo" add remote.txt || return 1
  command git -C "$collision_repo" -c user.name='Zsh Tests' -c user.email='zsh-tests@example.invalid' \
    commit -qm 'Remote topic' || return 1
  command git -C "$collision_repo" push -q origin divergent:refs/heads/topic || return 1
  command git -C "$collision_repo" fetch -q origin || return 1
  command git -C "$collision_repo" checkout -q "$base_branch" || return 1
  command git -C "$collision_repo" branch -D divergent -q || return 1

  builtin cd -- "$collision_repo" || return 1
  before_ref=$(command git rev-parse HEAD) || { builtin cd -- "$original_dir"; return 1; }

  output=$(_fbr_activate refs/remotes/origin/topic '' 2>&1); rc=$?
  assert_status "$rc" 1 'fbr refuses an unrelated same-name remote selection' || { builtin cd -- "$original_dir"; return 1; }
  after_ref=$(command git rev-parse HEAD) || { builtin cd -- "$original_dir"; return 1; }
  assert_equals "$after_ref" "$before_ref" 'fbr keeps the current checkout after refusing a collision' || { builtin cd -- "$original_dir"; return 1; }
  assert_contains "$output" 'does not track local' 'fbr explains the upstream mismatch' || { builtin cd -- "$original_dir"; return 1; }
  assert_contains "$output" "git switch -- topic" 'fbr offers entering the local branch' || { builtin cd -- "$original_dir"; return 1; }
  assert_contains "$output" "git switch --track -b NEW_BRANCH -- refs/remotes/origin/topic" 'fbr offers a differently named tracking branch' || { builtin cd -- "$original_dir"; return 1; }
  assert_contains "$output" "git switch --detach -- refs/remotes/origin/topic" 'fbr offers detached inspection' || { builtin cd -- "$original_dir"; return 1; }

  upstream=$(command git for-each-ref --format='%(upstream:short)' 'refs/heads/topic' 2>/dev/null) || upstream=''
  assert_equals "$upstream" '' 'unrelated local branch carries no matching upstream' || { builtin cd -- "$original_dir"; return 1; }

  command git init -q --bare "$collision_second" || { builtin cd -- "$original_dir"; return 1; }
  command git remote add upstream "$collision_second" || { builtin cd -- "$original_dir"; return 1; }
  command git checkout -qb second-divergent -q || { builtin cd -- "$original_dir"; return 1; }
  print -r -- 'second' >second.txt
  command git add second.txt || { builtin cd -- "$original_dir"; return 1; }
  command git -c user.name='Zsh Tests' -c user.email='zsh-tests@example.invalid' commit -qm 'Second remote topic' || { builtin cd -- "$original_dir"; return 1; }
  command git push -q upstream second-divergent:refs/heads/topic || { builtin cd -- "$original_dir"; return 1; }
  command git fetch -q upstream || { builtin cd -- "$original_dir"; return 1; }
  command git checkout -q "$base_branch" || { builtin cd -- "$original_dir"; return 1; }
  command git branch -D second-divergent -q || { builtin cd -- "$original_dir"; return 1; }
  command git branch --set-upstream-to=origin/topic topic -q || { builtin cd -- "$original_dir"; return 1; }

  output=$(_fbr_activate refs/remotes/upstream/topic '' 2>&1); rc=$?
  assert_status "$rc" 1 'fbr refuses when the local branch tracks a different remote' || { builtin cd -- "$original_dir"; return 1; }
  assert_contains "$output" "upstream: 'refs/remotes/origin/topic'" 'fbr names the actual upstream on mismatch' || { builtin cd -- "$original_dir"; return 1; }
  assert_equals "$(command git symbolic-ref --short HEAD)" "$base_branch" 'fbr stays put on a different-upstream collision' || { builtin cd -- "$original_dir"; return 1; }

  _fbr_activate refs/remotes/origin/topic '' >/dev/null 2>&1 || { builtin cd -- "$original_dir"; return 1; }
  assert_equals "$(command git symbolic-ref --short HEAD)" 'topic' 'fbr enters the local branch when it tracks the selected remote' || { builtin cd -- "$original_dir"; return 1; }
  command git switch -- "$base_branch" >/dev/null || { builtin cd -- "$original_dir"; return 1; }

  assert_contains "${functions[fbr]}" "upstream" 'fbr guards remote-to-worktree mapping by upstream' || { builtin cd -- "$original_dir"; return 1; }
  assert_contains "${functions[fbr]}" 'Enter worktree/checkout' 'fbr labels worktree and checkout actions distinctly' || { builtin cd -- "$original_dir"; return 1; }

  builtin cd -- "$original_dir"
}

test_fbr_canonical_refs() (
  local fixture_repo="$tmp_dir/fbr-canonical" worktree_dir="$tmp_dir/fbr canonical worktree"
  local base_branch local_oid remote_oid rows row selected worktree_branch worktree_path
  local -A worktree_paths row_by_ref
  local -a fields
  command git init -q "$fixture_repo" || return 1
  builtin cd -- "$fixture_repo" || return 1
  command git -c user.name='Zsh Tests' -c user.email='zsh-tests@example.invalid' commit --allow-empty -qm initial || return 1
  base_branch=$(command git symbolic-ref --short HEAD) || return 1
  local_oid=$(command git rev-parse HEAD) || return 1
  command git checkout -qb remote-source || return 1
  command git -c user.name='Zsh Tests' -c user.email='zsh-tests@example.invalid' commit --allow-empty -qm remote || return 1
  remote_oid=$(command git rev-parse HEAD) || return 1
  command git switch -- "$base_branch" >/dev/null || return 1
  command git branch -D remote-source -q || return 1
  command git remote add origin "$tmp_dir/unfetched-remote.git" || return 1
  command git update-ref refs/remotes/origin/topic "$remote_oid" || return 1
  command git update-ref refs/remotes/origin/actual/HEAD "$remote_oid" || return 1
  command git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/topic || return 1
  command git branch origin/topic "$local_oid" || return 1
  command git branch actual/HEAD "$local_oid" || return 1
  command git branch tagged "$local_oid" || return 1
  command git branch refs/remotes/unusual "$local_oid" || return 1
  command git tag tagged "$remote_oid" || return 1
  command git tag topic "$local_oid" || return 1
  command git tag origin/topic "$remote_oid" || return 1
  command git worktree add -q "$worktree_dir" origin/topic || return 1
  while IFS= read -r -d '' worktree_branch && IFS= read -r -d '' worktree_path; do
    worktree_paths[$worktree_branch]=$worktree_path
  done < <(_fbr_worktree_entries "$fixture_repo")
  rows=$(_fbr_ref_rows '' '' "${(@kv)worktree_paths}") || return 1
  for row in ${(f)rows}; do
    fields=("${(@ps:\t:)row}")
    row_by_ref[$fields[5]]=$row
  done
  assert_equals "${row_by_ref[refs/remotes/origin/HEAD]-}" '' 'fbr omits only symbolic remote HEAD aliases' || return 1
  assert_contains "$rows" 'refs/heads/actual/HEAD' 'fbr retains a local branch ending in HEAD' || return 1
  assert_contains "$rows" 'refs/remotes/origin/actual/HEAD' 'fbr retains a nonsymbolic remote branch ending in HEAD' || return 1
  assert_contains "${row_by_ref[refs/heads/refs/remotes/unusual]}" 'refs/remotes/unusual' 'fbr strips only the actual reference namespace from display' || return 1
  assert_contains "${row_by_ref[refs/heads/origin/topic]}" '[WT] origin/topic' 'fbr maps ambiguous full local refs to worktree badges' || return 1
  if (( $+commands[fzf] )); then
    selected=$(print -r -- "$rows" | command fzf --filter=refs/heads/origin/topic --delimiter=$'\t' --nth=5 --accept-nth=5)
    assert_equals "$selected" refs/heads/origin/topic 'fbr selection retains exact local identity despite namespace/tag collisions' || return 1
    _fbr_activate "$selected" "${worktree_paths[$selected]}" || return 1
    assert_equals "$PWD" "$worktree_dir" 'fbr enters the exact ambiguous branch worktree' || return 1
    builtin cd -- "$fixture_repo" || return 1
    selected=$(print -r -- "$rows" | command fzf --filter=refs/heads/tagged --delimiter=$'\t' --nth=5 --accept-nth=5)
    _fbr_activate "$selected" '' >/dev/null 2>&1 || return 1
    assert_equals "$(command git symbolic-ref HEAD)" refs/heads/tagged 'fbr activates a branch whose name also names a tag' || return 1
    assert_equals "$(command git rev-parse HEAD)" "$local_oid" 'fbr activates the branch commit rather than the colliding tag' || return 1
    selected=$(print -r -- "$rows" | command fzf --filter=refs/remotes/origin/topic --delimiter=$'\t' --nth=5 --accept-nth=5)
    assert_equals "$selected" refs/remotes/origin/topic 'fbr selection retains exact remote identity despite namespace collisions' || return 1
    assert_equals "$(command git rev-parse "$selected")" "$remote_oid" 'fbr preview payload resolves the exact selected remote commit' || return 1
    _fbr_activate "$selected" '' >/dev/null 2>&1 || return 1
    assert_equals "$(command git symbolic-ref HEAD)" refs/heads/topic 'fbr creates a tracking branch even with a colliding tag' || return 1
    assert_equals "$(command git rev-parse HEAD)" "$remote_oid" 'fbr tracks the selected remote rather than similarly named refs' || return 1
    assert_equals "$(command git for-each-ref --format='%(upstream)' refs/heads/topic)" refs/remotes/origin/topic 'fbr stores the canonical selected upstream' || return 1
    command git switch -- "$base_branch" >/dev/null 2>&1 || return 1
    _fbr_activate "$selected" '' >/dev/null 2>&1 || return 1
    assert_equals "$(command git symbolic-ref HEAD)" refs/heads/topic 'fbr reuses the correctly tracked local branch despite abbreviated-ref ambiguity' || return 1
  fi
)

# Frozen pre-optimization width, truncation and padding helpers. Both
# truncators keep their distinct narrow-width rules and REPLY side effects.
test_truncate_measures_text_once() {
  local output

  # Each truncation entry point measures the full text once, whether it fits
  # or is cut; cuts reuse that measurement instead of rescanning the text.
  output=$(LC_ALL=C.UTF-8 zsh -fc '
    source "$1/25-theme.zsh" || exit 90
    source "$1/55-ui-helpers.zsh" || exit 91
    functions[_measure_original]=$functions[_ui_display_width]
    integer full_scans
    probe=''
    _ui_display_width() {
      [[ $* == "$probe" ]] && (( full_scans++ ))
      _measure_original "$@"
    }
    check() {
      local label=$1 entry=$2
      shift 2
      probe="$*"
      full_scans=0
      if [[ $entry == marker ]]; then
        _ui_truncate_marker_reply "..." 10 "$@"
      else
        _ui_truncate_reply 10 "$@"
      fi
      print -r -- "$entry $label scans=$full_scans result=$REPLY"
    }
    for entry in wrapper marker; do
      check fit-ascii $entry abcdef
      check cut-ascii $entry abcdefghijklmnopqrstuvwxyz
      check cut-mixed $entry "雪abcdefghijklmnopqrstuvwxyz"
      check cut-cjk $entry 雪雪雪雪雪雪雪雪雪雪雪雪
      check cut-combining $entry "éééééééééééé"
      check cut-joined $entry abc defghij klmnopqrstuvwxyz
    done
  ' measure "$repo_dir")
  assert_equals "${#${(@M)${(f)output}:#* scans=1 *}}" 12 'truncation measures fitting and cut text once per entry point' || {
    print -u2 -r -- "$output"
    return 1
  }
}

test_width_truncation_oracle() {
  local width_matrix width_reference
  integer live_status frozen_status live_pid frozen_pid

  IFS= read -r -d '' width_matrix <<'EOF_WIDTH_MATRIX'
# Width/truncation characterization matrix; prints a transcript.
# Usage: zsh -f width-matrix.zsh repo [reference-file] [exhaustive] [scratch]
emulate -L zsh
setopt NO_UNSET
repo=$1 scratch=${4:-${TMPDIR:-/tmp}}
source "$repo/55-ui-helpers.zsh"
source "$repo/lib/functions-common.zsh"
[[ -n ${2-} ]] && source "$2"
integer exhaustive=0
[[ ${3-} == exhaustive ]] && exhaustive=1
integer w l
typeset text mode out locale fn
typeset -a widths lengths
ascii_base='abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 ~!@#$%^&*()_+-=[]{};:,./<>?|`'"'"'"'
while (( ${#ascii_base} < 80 )); do ascii_base+=$ascii_base; done
probe() {
  # probe label fn args...: records stdout, status, REPLY and reply after one call
  local label=$1 fn=$2 rc out=''
  shift 2
  REPLY=sentinel; reply=(one two)
  $fn "$@" >| "$scratch/out"; rc=$?
  IFS= read -r -d '' out < "$scratch/out"
  print -r -- "$label ${(qqqq)out} rc=$rc scratch=${(qqqq)REPLY}:${(j:,:)reply}"
}
run_set() {
  local text=$1 both_pads=${2:-1} w
  for w in "${widths[@]}"; do
    probe "trunc w=$w ${(qqqq)text}" _ui_truncate_reply "$w" "$text"
    probe "safe w=$w ${(qqqq)text}" _ui_safe_truncate "$w" "$text"
    probe "padl w=$w ${(qqqq)text}" _ui_pad_reply left "$w" "$text"
    (( both_pads )) && probe "padr w=$w ${(qqqq)text}" _ui_pad_reply right "$w" "$text"
  done
  probe "width ${(qqqq)text}" _ui_display_width "$text"
}
typeset empty=""
unicode_fixtures=(
  '' 'a' $'é' $'́abc' $'abć' $'abcdefghij́klmnop' '雪' '雪国の物語を読む' $'ab雪cd' $'ab雪́cd'
  '😀' $'\U0001F468‍\U0001F469‍\U0001F467 family' $' branch' $'\U000F0001 nerd glyph text' $'x️⃣y'
  $'क्ष हिन्दी' 'café crème brûlée' $'　wide space　' 'ｆｕｌｌｗｉｄｔｈ ｔｅｘｔ'
  'a\nb\tc\e[0m' 'trailing\' '\x1b\x7f\x9f mixed' '\\double\\' '\xZZ not hex' 'ab\x1' $'tab\there' $'\x01\x02ctl'
  'path/with\\backslash/name' 'abc雪\n雪def'
  $'\xff' $'ab\xffcd' $'\xc3' $'abc\xc3' $'\x7f' $'a\x01b\x1bc' $'\u0085next' $'雪\xff雪' $'\xe9\x9b' $'tail\xe9\x9b'
  "Package 雪 description ${(l:60::x:)empty}" "${(l:30::雪:)empty}" $'abc\u0301\u0301def雪ghi\u200bjkl' $'\ufeffbom text'
)
for mode in ascii unicode; do
  if [[ $mode == ascii ]]; then _ui_ascii_mode() { return 0; }; else _ui_ascii_mode() { return 1; }; fi
  for locale in C.UTF-8 C; do
    # The real predicate always selects ASCII markers outside UTF-8 locales.
    [[ $locale == C && $mode == unicode ]] && (( ! exhaustive )) && continue
    LC_ALL=$locale
    print -r -- "### mode=$mode locale=$locale"
    if (( exhaustive )); then
      lengths=( {0..80} ); widths=( {0..40} )
    elif [[ $locale == C ]]; then
      lengths=( 0 1 5 24 80 ); widths=( 0 1 3 4 5 24 )
    else
      lengths=( {0..7} 23 24 25 41 80 ); widths=( {0..7} 9 23 24 25 41 )
    fi
    for l in "${lengths[@]}"; do run_set "${ascii_base[1,l]}"; done
    (( exhaustive )) && widths=( {0..12} 17 24 40 ) || widths=( 0 1 2 3 5 9 17 )
    for text in "${unicode_fixtures[@]}"; do run_set "$text" "$exhaustive"; done
  done
done
LC_ALL=C.UTF-8
# Real marker-mode predicate (non-TTY plain mode) and fallback configurations.
unfunction _ui_ascii_mode
source "$repo/55-ui-helpers.zsh"
[[ -n ${2-} ]] && source "$2"
widths=( 0 1 2 3 4 5 9 24 )
print -r -- "### real ascii-mode predicate"
for text in "${ascii_base[1,30]}" $'ab雪́cd' 'a\nb\tc' $'́abc'; do run_set "$text"; done
saved_width=$functions[_ui_display_width]
saved_strip=$functions[_ui_strip_leading_marks_reply]
for config in no-width no-strip neither; do
  functions[_ui_display_width]=$saved_width
  functions[_ui_strip_leading_marks_reply]=$saved_strip
  case $config in
    no-width) unfunction _ui_display_width ;;
    no-strip) unfunction _ui_strip_leading_marks_reply ;;
    neither) unfunction _ui_display_width _ui_strip_leading_marks_reply ;;
  esac
  print -r -- "### fallback $config"
  for text in "${ascii_base[1,30]}" $'ab雪́cd' 'a\nb\tc' $'́abc' 'path/with\\backslash/name'; do
    for w in 0 1 2 3 4 5 9 24; do probe "safe w=$w ${(qqqq)text}" _ui_safe_truncate "$w" "$text"; done
  done
done
functions[_ui_display_width]=$saved_width
functions[_ui_strip_leading_marks_reply]=$saved_strip
# Unset and outer-local scratch for representative calls.
print -r -- "### scratch states"
for call in '_ui_truncate_reply 9 abcdefghijklmnop' '_ui_safe_truncate 9 abcdefghijklmnop' '_ui_safe_truncate 1 abcdef' \
    '_ui_safe_truncate 4 abcdef' '_ui_pad_reply left 9 abcdefghijklmnop' '_ui_display_width abc' '_ui_safe_truncate 40 short'; do
  unset REPLY reply
  ${=call} >/dev/null; print -r -- "unset $call -> ${+REPLY}:${REPLY-}:${+reply}"
  () { local REPLY=outer; local -a reply=(o1 o2); ${=call} >/dev/null; print -r -- "local $call -> $REPLY:${(j:,:)reply}"; }
done
print -r -- "width-data-loaded=${_ZSH_UI_WIDTH_DATA_LOADED:-0}"
EOF_WIDTH_MATRIX
  IFS= read -r -d '' width_reference <<'EOF_WIDTH_REFERENCE'
_ui_char_width() {
  emulate -L zsh
  integer code=$1 low high middle
  if (( code < 128 )); then
    REPLY=1
    return 0
  fi
  if (( ! ${_ZSH_UI_WIDTH_DATA_LOADED:-0} )); then
    setopt localoptions no_aliases
    source "$_ZSH_UI_HELPERS_DIR/lib/ui-width-data.zsh" || return 1
  fi
  low=1
  high=${#_ZSH_UI_ZERO_START}
  while (( low <= high )); do
    middle=$(( (low + high) / 2 ))
    if (( code < _ZSH_UI_ZERO_START[middle] )); then
      high=$(( middle - 1 ))
    elif (( code > _ZSH_UI_ZERO_END[middle] )); then
      low=$(( middle + 1 ))
    else
      REPLY=0
      return 0
    fi
  done
  low=1
  high=${#_ZSH_UI_WIDE_START}
  while (( low <= high )); do
    middle=$(( (low + high) / 2 ))
    if (( code < _ZSH_UI_WIDE_START[middle] )); then
      high=$(( middle - 1 ))
    elif (( code > _ZSH_UI_WIDE_END[middle] )); then
      low=$(( middle + 1 ))
    else
      REPLY=2
      return 0
    fi
  done
  REPLY=1
}

_ui_display_width() {
  emulate -L zsh
  setopt MULTIBYTE

  local text=$1 char
  local non_ascii_pattern='*[^ -~]*'
  integer index code width=0

  if [[ $text != ${~non_ascii_pattern} ]]; then
    REPLY=${#text}
    return 0
  fi

  for (( index = 1; index <= ${#text}; index++ )); do
    char=${text[$index]}
    printf -v code '%d' "'$char"
    _ui_char_width $code
    (( width += REPLY ))
  done
  REPLY=$width
}

_ui_strip_leading_marks_reply() {
  emulate -L zsh
  setopt MULTIBYTE
  local text=$1 char
  integer code
  while [[ -n $text ]]; do
    char=$text[1]
    printf -v code '%d' "'$char"
    _ui_char_width $code
    (( REPLY == 0 )) || break
    text=${text[2,-1]}
  done
  REPLY=$text
}

_ui_truncate_reply() {
  emulate -L zsh
  setopt MULTIBYTE

  local width=$1
  shift

  local text="$*"
  local marker='…'
  local char prefix='' suffix=''
  integer index code char_width text_width marker_width left right prefix_width suffix_width

  (( width > 0 )) || {
    REPLY=''
    return 0
  }

  if _ui_ascii_mode; then
    marker='...'
  fi

  _ui_display_width "$text"
  text_width=$REPLY
  if (( text_width <= width )); then
    REPLY=$text
    return 0
  fi

  _ui_display_width "$marker"
  marker_width=$REPLY
  if (( width <= marker_width + 1 )); then
    prefix=''
    prefix_width=0
    for (( index = 1; index <= ${#text}; index++ )); do
      char=${text[$index]}
      printf -v code '%d' "'$char"
      _ui_char_width $code
      char_width=$REPLY
      (( prefix_width + char_width > width )) && break
      prefix+=$char
      (( prefix_width += char_width ))
    done
    REPLY=$prefix
    return 0
  fi

  left=$(( (width - marker_width) / 2 ))
  right=$(( width - marker_width - left ))

  prefix=''
  prefix_width=0
  for (( index = 1; index <= ${#text}; index++ )); do
    char=${text[$index]}
    printf -v code '%d' "'$char"
    _ui_char_width $code
    char_width=$REPLY
    (( prefix_width + char_width > left )) && break
    prefix+=$char
    (( prefix_width += char_width ))
  done

  suffix=''
  suffix_width=0
  for (( index = ${#text}; index >= 1; index-- )); do
    char=${text[$index]}
    printf -v code '%d' "'$char"
    _ui_char_width $code
    char_width=$REPLY
    (( suffix_width + char_width > right )) && break
    suffix="${char}${suffix}"
    (( suffix_width += char_width ))
  done

  # A suffix must not attach a discarded base character's combining marks
  # to the ellipsis. Keep complete base-plus-mark sequences at the cut.
  _ui_strip_leading_marks_reply "$suffix"
  REPLY="${prefix}${marker}${REPLY}"
}

_ui_truncate() {
  _ui_truncate_reply "$@"
  print -r -- "$REPLY"
}

_ui_pad_reply() {
  emulate -L zsh

  # 'right' = right-align text (leading spaces); 'left' = left-align (trailing spaces)
  local align=$1
  local width=$2
  shift 2

  _ui_truncate_reply "$width" "$*"
  local text=$REPLY
  local text_width
  integer padding_width

  _ui_display_width "$text"
  text_width=$REPLY
  padding_width=$(( width - text_width ))

  (( padding_width < 0 )) && padding_width=0

  if [[ $align == right ]]; then
    printf -v REPLY '%*s%s' "$padding_width" '' "$text"
  else
    printf -v REPLY '%s%*s' "$text" "$padding_width" ''
  fi
}

_ui_pad() {
  _ui_pad_reply "$@"
  print -nr -- "$REPLY"
}

_ui_safe_truncate() {
  emulate -L zsh

  local width=$1
  shift

  local text="$*"
  local marker='…'
  local token pair quad prefix='' suffix=''
  local -a tokens
  integer index left right token_width prefix_width suffix_width text_width marker_width
  integer have_display_width=$(( $+functions[_ui_display_width] ))

  (( width > 0 )) || {
    print -r -- ''
    return 0
  }

  if _ui_ascii_mode; then
    marker='...'
  fi

  if (( have_display_width )); then
    _ui_display_width "$text"
    text_width=$REPLY
    _ui_display_width "$marker"
    marker_width=$REPLY
  else
    text_width=${#text}
    marker_width=${#marker}
  fi

  if (( text_width <= width )); then
    print -r -- "$text"
    return 0
  fi

  if (( width <= marker_width )); then
    print -r -- "${marker[1,width]}"
    return 0
  fi

  for (( index = 1; index <= ${#text}; index++ )); do
    token=${text[$index]}

    if [[ $token == $'\\' ]]; then
      pair=${text[$index,$(( index + 1 ))]}
      quad=${text[$index,$(( index + 3 ))]}

      if [[ $quad == \\x[0-9a-fA-F][0-9a-fA-F] ]]; then
        token=$quad
        (( index += 3 ))
      else
        case $pair in
          '\n'|'\r'|'\t'|'\e'|'\a'|'\b'|'\f'|'\v')
            token=$pair
            (( index++ ))
            ;;
        esac
      fi
    fi

    tokens+=("$token")
  done

  left=$(( (width - marker_width) / 2 ))
  right=$(( width - marker_width - left ))

  prefix_width=0
  for token in "${tokens[@]}"; do
    if (( have_display_width )); then
      _ui_display_width "$token"
      token_width=$REPLY
    else
      token_width=${#token}
    fi
    (( prefix_width + token_width <= left )) || break
    prefix+=$token
    (( prefix_width += token_width ))
  done

  suffix_width=0
  for (( index = ${#tokens[@]}; index >= 1; index-- )); do
    token=${tokens[$index]}
    if (( have_display_width )); then
      _ui_display_width "$token"
      token_width=$REPLY
    else
      token_width=${#token}
    fi
    (( suffix_width + token_width <= right )) || break
    suffix="${token}${suffix}"
    (( suffix_width += token_width ))
  done

  if (( $+functions[_ui_strip_leading_marks_reply] )); then
    _ui_strip_leading_marks_reply "$suffix"
    suffix=$REPLY
  fi
  print -r -- "${prefix}${marker}${suffix}"
}
EOF_WIDTH_REFERENCE

  print -r -- "$width_matrix" >| "$tmp_dir/width-matrix.zsh"
  print -r -- "$width_reference" >| "$tmp_dir/width-reference.zsh"
  command mkdir -p -- "$tmp_dir/width-live" "$tmp_dir/width-frozen"
  zsh -f "$tmp_dir/width-matrix.zsh" "$repo_dir" '' '' "$tmp_dir/width-live" >| "$tmp_dir/width-live.txt" 2>&1 &
  live_pid=$!
  zsh -f "$tmp_dir/width-matrix.zsh" "$repo_dir" "$tmp_dir/width-reference.zsh" '' "$tmp_dir/width-frozen" >| "$tmp_dir/width-frozen.txt" 2>&1 &
  frozen_pid=$!
  wait $live_pid; live_status=$?
  wait $frozen_pid; frozen_status=$?
  assert_status "$live_status:$frozen_status" 0:0 'width oracle matrix runs with live and frozen helpers' || return 1
  if [[ "$(<"$tmp_dir/width-live.txt")" != "$(<"$tmp_dir/width-frozen.txt")" ]]; then
    print -u2 -- 'not ok: width, truncation and padding match frozen helpers'
    command diff -- "$tmp_dir/width-frozen.txt" "$tmp_dir/width-live.txt" | command head -40 >&2
    return 1
  fi
  print -- 'ok: width, truncation and padding match frozen helpers across ASCII, Unicode, escapes and locales'

  local loaded
  loaded=$(LC_ALL=C.UTF-8 zsh -fc '
    source "$1/55-ui-helpers.zsh"
    source "$1/lib/functions-common.zsh"
    _ui_display_width "plain ascii label"
    _ui_truncate_reply 9 "plain ascii label"
    _ui_pad_reply left 9 "plain ascii label"
    _ui_safe_truncate 9 "plain ascii label" >/dev/null
    print -r -- "${_ZSH_UI_WIDTH_DATA_LOADED:-0}"' width "$repo_dir")
  assert_equals "$loaded" 0 'ASCII width and truncation leave Unicode width tables unloaded' || return 1
}

# Frozen pre-chunking collector: exact records, scan state, scratch and
# dusage/bigfiles output across tab, KiB, control, Unicode and tail cases,
# on both the sysread path and the read fallback.
test_scan_record_oracle() {
  local scan_matrix scan_reference live frozen fallback
  integer rc

  IFS= read -r -d '' scan_matrix <<'EOF_SCAN_MATRIX'
# Usage: zsh -f scan-matrix.zsh repo scratch [reference] [fallback]
emulate -L zsh
setopt NO_UNSET
repo=$1 scratch=$2
source "$repo/55-ui-helpers.zsh"
source "$repo/60-functions.zsh"
_zsh_functions_load files || exit 90
[[ -n ${3-} ]] && source "$3"
if [[ ${4-} == fallback ]]; then
  # Simulate a build without zsh/system to exercise the read fallback.
  zmodload() { [[ $* == *zsh/system* ]] && return 1; builtin zmodload "$@"; }
fi
functions[_ui_plain_mode]='return 0'
command mkdir -p -- "$scratch/bin" "$scratch/target/entry" "$scratch/tree"
print -r -- 'x' >| "$scratch/tree/file"
print -r -- '#!/bin/sh
cat -- "$SCAN_FIXTURE"
exit "${SCAN_DU_STATUS:-0}"' >| "$scratch/bin/du"
print -r -- '#!/bin/sh
printf "%s\0" "$SCAN_FIND_PATH"
exit "${SCAN_FIND_STATUS:-0}"' >| "$scratch/bin/find"
command chmod +x -- "$scratch/bin/du" "$scratch/bin/find"
path=("$scratch/bin" $path)
export SCAN_FIXTURE=$scratch/fixture SCAN_FIND_PATH=$scratch/tree/file
export TMPDIR=$scratch
typeset -A fixtures
fixtures=(
  empty ''
  simple $'1\ta\0'
  malformed $'x1\ta\0-1\tb\0001.5\tc\0 1\td\0001 \te\0\0\0\0002\tok\0'
  tabs $'\t\t3\tlead\0004\t\tdouble\0005\ttrail\t\t\0006\tin\tner\0007\0008\t\0\t\0009\ta\t\tb\t\0'
  controls $'10\tline1\nline2\00011\t\r\e\x01\x7f\00012\t\\back\\slash\0'
  unicode $'13\t雪.txt\00014\tcaf\xc3\xa9\xff\00015\t\xe9\x9b\0'
  unterminated $'16\tok\00017\ttail-unterminated'
  ties $'5\tfile10\0005\tfile9\0005\tfile100\00050\t2\0005\t10\0005\tfile9\0'
)
typeset big=''
integer i
for (( i = 1; i <= 9000; i++ )); do
  if (( i % 997 == 0 )); then big+=$'\t'"$i"$'\t\tpath/'"$i"$'\t\0'; else big+="$((i % 300))"$'\t'"/synthetic/dir-$((i % 17))/file $i"$'\0'; fi
done
fixtures[big]=$big
# Normalize the per-run scratch path so live and frozen runs compare exactly.
norm() {
  local text
  IFS= read -r -d '' text < "$1"
  print -rn -- "${text//$scratch/SCRATCH}"
}
report() {
  print -r -- "records=${#records} sha=$(print -rn -- "${(j:|:)${(@qqqq)records}}" | command cksum)"
  (( ${#records} <= 40 )) && print -r -- "${(j:|:)${(@qqqq)records}}"
  print -r -- "result=${(j:,:)${(@kv)scan_result}} signal=$signal_status"
}
for name in ${(ko)fixtures}; do
  print -rn -- "${fixtures[$name]}" >| "$scratch/fixture"
  for du_status in 0 1; do
    export SCAN_DU_STATUS=$du_status
    print -r -- "== $name du=$du_status"
    () {
      local -a records
      local -A scan_result
      integer signal_status=0 rc
      REPLY=sentinel; reply=(one two)
      _zsh_scan_collect dusage "$scratch/target" "$scratch/target/entry"; rc=$?
      print -r -- "collect rc=$rc scratch=$REPLY:${(j:,:)reply}"
      report
      _zsh_scan_collect bigfiles "$scratch/tree"; rc=$?
      print -r -- "collect-bigfiles rc=$rc"
      report
    }
    dusage "$scratch/target" 30 >| "$scratch/out" 2>| "$scratch/err"; rc=$?
    print -r -- "dusage rc=$rc out=$(norm "$scratch/out" | command cksum) err=${(qqqq)$(norm "$scratch/err")}"
    (( ${#fixtures[$name]} < 400 )) && norm "$scratch/out"
    bigfiles "$scratch/tree" 7 >| "$scratch/out" 2>| "$scratch/err"; rc=$?
    print -r -- "bigfiles rc=$rc out=$(norm "$scratch/out" | command cksum) err=${(qqqq)$(norm "$scratch/err")}"
    (( ${#fixtures[$name]} < 400 )) && norm "$scratch/out"
  done
done
unset SCAN_DU_STATUS
# Partial find with a successful du.
export SCAN_FIND_STATUS=1
print -rn -- $'3\tfound\0' >| "$scratch/fixture"
bigfiles "$scratch/tree" 5 >| "$scratch/out" 2>| "$scratch/err"; rc=$?
print -r -- "partial-find rc=$rc out=${(qqqq)$(norm "$scratch/out")} err=${(qqqq)$(norm "$scratch/err")}"
leftovers=( "$scratch"/(dusage|bigfiles).*(N) )
print -r -- "leftovers=${#leftovers}"
EOF_SCAN_MATRIX
  IFS= read -r -d '' scan_reference <<'EOF_SCAN_REFERENCE'
_zsh_scan_collect() {
  emulate -L zsh
  setopt localtraps
  local mode=$1 target=$2 entry_path kib path_list_file='' raw_output_file=''
  integer du_status=0 find_status=0 result_status=0
  shift 2
  trap 'signal_status=130; return 130' INT
  trap 'signal_status=143; return 143' TERM
  trap 'signal_status=129; return 129' HUP
  records=()
  scan_result=( state complete status 0 du_status 0 find_status 0 diagnostic '' )
  {
    path_list_file=$(command mktemp "${TMPDIR:-/tmp}/${mode}.paths.XXXXXX") || return 1
    raw_output_file=$(command mktemp "${TMPDIR:-/tmp}/${mode}.raw.XXXXXX") || return 1
    if [[ $mode == dusage ]]; then
      for entry_path in "$@"; do
        print -rn -- "$entry_path"$'\0'
      done >"$path_list_file"
      command du -sk --null --files0-from="$path_list_file" 2>/dev/null >"$raw_output_file"
      du_status=$?
    else
      command find "$target" -type f -print0 2>/dev/null >"$path_list_file"
      find_status=$?
      if [[ -s $path_list_file ]]; then
        command du -k --null --files0-from="$path_list_file" 2>/dev/null >"$raw_output_file"
        du_status=$?
      fi
    fi
    while IFS=$'\t' read -r -d '' kib entry_path; do
      [[ $kib == <-> ]] || continue
      records+=("${kib}"$'\t'"${entry_path}")
    done <"$raw_output_file"
  } always {
    command rm -f -- "$path_list_file" "$raw_output_file"
  }
  scan_result[du_status]=$du_status
  scan_result[find_status]=$find_status
  if (( find_status )); then
    result_status=$find_status
    scan_result[diagnostic]="find exit $find_status"
  fi
  if (( du_status )); then
    result_status=$du_status
    [[ -n ${scan_result[diagnostic]} ]] && scan_result[diagnostic]+=', '
    scan_result[diagnostic]+="du exit $du_status"
  fi
  scan_result[status]=$result_status
  (( result_status )) && scan_result[state]=partial
  return 0
}
EOF_SCAN_REFERENCE

  print -r -- "$scan_matrix" >| "$tmp_dir/scan-matrix.zsh"
  print -r -- "$scan_reference" >| "$tmp_dir/scan-reference.zsh"
  command mkdir -p -- "$tmp_dir/scan-live" "$tmp_dir/scan-frozen" "$tmp_dir/scan-fallback"
  live=$(LC_ALL=C.UTF-8 zsh -f "$tmp_dir/scan-matrix.zsh" "$repo_dir" "$tmp_dir/scan-live" '' '' 2>&1)
  rc=$?
  assert_status "$rc" 0 'scan record oracle runs with the live collector' || return 1
  frozen=$(LC_ALL=C.UTF-8 zsh -f "$tmp_dir/scan-matrix.zsh" "$repo_dir" "$tmp_dir/scan-frozen" "$tmp_dir/scan-reference.zsh" '' 2>&1)
  fallback=$(LC_ALL=C.UTF-8 zsh -f "$tmp_dir/scan-matrix.zsh" "$repo_dir" "$tmp_dir/scan-fallback" '' fallback 2>&1)
  if [[ $live != "$frozen" || $fallback != "$frozen" ]]; then
    print -u2 -- 'not ok: scan records match the frozen collector'
    command diff <(print -r -- "$frozen") <(print -r -- "$live") | command head -30 >&2
    command diff <(print -r -- "$frozen") <(print -r -- "$fallback") | command head -30 >&2
    return 1
  fi
  assert_contains "$live" 'leftovers=0' 'scan record oracle leaves no temporary files' || return 1
  print -- 'ok: chunked and fallback scan records match the frozen collector'
}

# A signal that arrives while records are being ingested is recorded for the
# caller in signal_status, leaves a partial record prefix and removes both
# temporary files (matching the pre-chunking read loop).
test_scan_ingestion_signal() {
  emulate -L zsh

  local fakebin="$tmp_dir/scan-signal-bin" fixture_dir="$tmp_dir/scan-signal"
  local raw="$tmp_dir/scan-signal-raw" content=$'123\t/synthetic/path/abcdefghijkl/x\0' signal_name output
  local watcher="$tmp_dir/scan-signal-watch.zsh" marker="$tmp_dir/scan-signal-marker" outcome=''
  integer expected index status_value record_count attempt
  local -a leftovers

  # A timed signal could land before ingestion starts or after it ends. Instead
  # a watcher follows the collector's read offset in du's output through
  # /proc/<pid>/fdinfo and signals inside the ingestion window.
  if [[ ! -r /proc/$$/fdinfo/0 ]]; then
    print -r -- 'skip: scan ingestion signal checks need /proc/<pid>/fdinfo'
    return 0
  fi

  command mkdir -p -- "$fakebin" "$fixture_dir/entry"
  # 262,144 fixed records (9 MiB); no adaptive growth.
  for (( index = 0; index < 18; index++ )); do content+=$content; done
  print -rn -- "$content" >| "$raw"
  print -r -- '#!/bin/sh
raw=$(readlink "/proc/$$/fd/1")
cat -- "$SCAN_SIGNAL_RAW"
"$SCAN_SIGNAL_ZSH" -f "$SCAN_SIGNAL_WATCHER" "$PPID" "$raw" "$SCAN_SIGNAL_NAME" "$SCAN_SIGNAL_MARKER" </dev/null >/dev/null 2>&1 &
exit 0' >| "$fakebin/du"
  command chmod +x -- "$fakebin/du"
  # Signal only after two 64 KiB reads (the first chunk's records are stored)
  # and before half the file, leaving ingestion still running. Polls every
  # 10 ms, stops after 20 s or when the collector exits, and reports the outcome.
  print -r -- 'emulate -L zsh
zmodload -F zsh/stat b:zstat || exit 1
zmodload zsh/zselect || exit 1
local parent=$1 raw=$2 signal_name=$3 marker=$4 fd line
local -a target size
integer polls pos=-1 low=131072 high
zstat -A size +size -- "$raw" || exit 1
high=$(( size[1] / 2 ))
for (( polls = 0; polls < 2000; polls++ )); do
  [[ -d /proc/$parent ]] || break
  for fd in /proc/$parent/fd/<->(N); do
    zstat -L -A target +link -- "$fd" 2>/dev/null || continue
    [[ ${target[1]} == "$raw" ]] || continue
    while IFS= read -r line; do
      if [[ $line == pos:* ]]; then
        pos=${line##*[[:space:]]}
        break
      fi
    done <"/proc/$parent/fdinfo/${fd:t}" 2>/dev/null
    if (( pos > low && pos <= high )); then
      print -r -- "fired $pos ${size[1]}" >| "$marker"
      kill -s "$signal_name" "$parent"
      exit 0
    fi
  done
  zselect -t 1
done
print -r -- "missed $pos ${size[1]}" >| "$marker"' >| "$watcher"
  for signal_name expected in INT 130 TERM 143; do
    # Only a missed window is retried, at most three times; a fired signal is final.
    for (( attempt = 1; attempt <= 3; attempt++ )); do
      command rm -f -- "$marker"
      output=$(PATH="$fakebin:$PATH" TMPDIR=$tmp_dir SCAN_SIGNAL_RAW=$raw SCAN_SIGNAL_NAME=$signal_name \
        SCAN_SIGNAL_ZSH=${commands[zsh]} SCAN_SIGNAL_WATCHER=$watcher SCAN_SIGNAL_MARKER=$marker \
        zsh -fc 'source "$1/55-ui-helpers.zsh"; source "$1/60-functions.zsh"; _zsh_functions_load files || exit 90
          typeset -a records; typeset -A scan_result; integer signal_status=0
          _zsh_scan_collect dusage "$2" "$2/entry"
          print -r -- "$signal_status ${#records}"' \
        scan-signal "$repo_dir" "$fixture_dir")
      for (( index = 0; index < 250; index++ )); do
        [[ -s $marker ]] && break
        command sleep 0.1
      done
      outcome=''
      [[ -s $marker ]] && outcome=$(<"$marker")
      [[ $outcome == fired* ]] && break
    done
    [[ $outcome == fired* ]] || {
      print -u2 -- "not ok: $signal_name watcher never observed the ingestion window (${outcome:-no outcome})"
      return 1
    }
    status_value=${output%% *}
    record_count=${output##* }
    assert_equals "$status_value" "$expected" "scan collection records $signal_name during record ingestion" || return 1
    (( record_count > 0 && record_count < 262144 )) || {
      print -u2 -- "not ok: $signal_name during ingestion keeps a partial record prefix ($output; $outcome)"
      return 1
    }
    leftovers=( "$tmp_dir"/dusage.*(N) )
    assert_equals "${#leftovers[@]}" 0 "scan collection removes temporary files after $signal_name during ingestion" || return 1
  done
}

main() {
  source "$repo_dir/55-ui-helpers.zsh"
  source "$repo_dir/60-functions.zsh"
  _zsh_functions_load || return 1

  functions[_ui_plain_mode]='return 0'

  test_missing_arguments || return 1
  test_local_emulation_and_leading_dash_operands || return 1
  test_usage_temp_cleanup || return 1
  test_usage_partial_scan || return 1
  test_usage_signal_cleanup || return 1
  test_scan_record_oracle || return 1
  test_scan_ingestion_signal || return 1
  test_dusage_oversized_operand_set || return 1
  test_path_empty_entries || return 1
  test_control_character_paths || return 1
  test_sanitizer_ascii_fast_path || return 1
  test_display_width || return 1
  test_width_truncation_oracle || return 1
  test_truncate_measures_text_once || return 1
  test_human_bytes || return 1
  test_alias_probes_are_quiet || return 1
  test_small_helper_success_paths || return 1
  test_fkill_signals || return 1
  test_fkill_scope_and_review || return 1
  test_fbr_worktree_navigation || return 1
  test_fbr_remote_collision || return 1
  test_fbr_canonical_refs || return 1
}

main "$@"
