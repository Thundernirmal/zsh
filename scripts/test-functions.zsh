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
  assert_missing_arg_usage extract 'Usage: extract <file>' || return 1
  assert_missing_arg_usage mkcd 'Usage: mkcd <directory>' || return 1
  assert_missing_arg_usage ff 'Usage: ff <pattern> [path]' || return 1
  assert_missing_arg_usage ft 'Usage: ft <pattern> [path]' || return 1
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
    extract "$archive_name" || {
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
  assert_contains "${functions[dusage]}" '--files0-from' 'dusage avoids unbounded argv expansion' || return 1

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
  functions[_ui_term_width]='print -r -- 120'
  functions[_ui_term_height]='print -r -- 30'
  dusage "$fixture_dir" 5 >"$stdout_file" 2>"$stderr_file"; rc=$?
  output=$(<"$stdout_file"); stderr_part=$(<"$stderr_file")
  functions[_ui_plain_mode]='return 0'
  unset 'functions[_ui_term_width]' 'functions[_ui_term_height]'
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
    functions[_ui_term_width]='print -r -- 60'
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
    functions[_ui_term_width]='print -r -- 60'
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
    functions[_ui_term_width]='print -r -- 60'
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

  curl() {
    [[ $1 == -sSIL && $2 == -- && $3 == 'https://example.invalid/path' ]] || return 9
    print -r -- 'HTTP/1.1 204 No Content'
  }
  output=$(headers 'https://example.invalid/path') || return 1
  unfunction curl
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
[ "$*" = "--http1.1 -fsSL https://wttr.in" ] || exit 8
printf "%s\n" "Clear 20 C"' >"$fakebin/curl"
  command chmod +x -- "$fakebin/curl"
  output=$(PATH="$fakebin:$old_path" "$commands[zsh]" -fc "source ${(q)repo_dir}/20-aliases.zsh; eval weather") || return 1
  assert_equals "$output" 'Clear 20 C' 'weather alias reaches its HTTPS forecast endpoint' || return 1

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

  assert_contains "${functions[fkill]}" 'local signal=${1:-15}' 'fkill defaults to SIGTERM' || return 1
  assert_contains "${functions[fkill]}" '--accept-nth=1' 'fkill asks fzf to return PIDs directly' || return 1
  assert_contains "${functions[fkill]}" '_fzf_picker_multi_args kill' 'fkill uses the shared live multi-selection footer' || return 1
  assert_not_contains "${functions[fkill]}" '_fzf_pointer' 'fkill no longer duplicates pointer presentation' || return 1
  assert_not_contains "${functions[fkill]}" 'SIG${signal}' 'fkill never renders a duplicated SIG prefix' || return 1
}

test_fbr_worktree_navigation() {
  local fixture_repo="$tmp_dir/fbr-repo"
  local remote_repo="$tmp_dir/fbr-remote.git"
  local worktree_dir="$tmp_dir/fbr worktree"
  local original_dir=$PWD branch current_branch first_row formatter_body projected second_row worktree_path
  integer private_fpath_count=0
  local -A worktree_paths

  assert_equals "${(V)functions[_fbr_format_entry]}" 'builtin autoload -XU' 'fbr formatter starts as a deferred repo-local autoload' || return 1
  _fbr_format_entry short '5 days ago' 'A subject' '' '' '' 16 12
  first_row=$REPLY
  assert_equals "$first_row" $'short           \t5 days ago  \tA subject\t\tshort' 'fbr pads branch and relative-date display columns' || return 1
  formatter_body=${functions[_fbr_format_entry]}
  assert_not_contains "${(V)formatter_body}" 'builtin autoload -XU' 'first fbr formatting call loads the deferred implementation' || return 1

  _fbr_format_entry short '5 days ago' 'A subject' '' '' '' 16 12
  second_row=$REPLY
  assert_equals "$second_row" "$first_row" 'repeated fbr formatting stays deterministic' || return 1

  source "$repo_dir/60-functions.zsh"
  assert_equals "${functions[_fbr_format_entry]}" "$formatter_body" 're-sourcing preserves the loaded fbr formatter' || return 1
  for worktree_path in "${fpath[@]}"; do
    [[ $worktree_path == "$repo_dir/functions" ]] && (( private_fpath_count++ ))
  done
  assert_equals "$private_fpath_count" 1 're-sourcing keeps one trusted functions path' || return 1

  _fbr_format_entry worktree-test '21 hours ago' $'Tabbed\tsubject' '/tmp/work tree' '' '' 16 12
  assert_equals "$REPLY" $'[WT] w...ee-test\t21 hours ago\tTabbed\\tsubject\t/tmp/work tree\tworktree-test' 'fbr aligns and sanitizes worktree rows while preserving the raw branch' || return 1

  _fbr_format_entry 'unicode-λ-雪' 'now' $'control-\e[31m' '' '' '' 18 8
  assert_equals "$REPLY" $'unicode-λ-雪       \tnow     \tcontrol-\\e[31m\t\tunicode-λ-雪' 'fbr preserves Unicode and sanitizes controls byte-for-byte' || return 1
  _fbr_format_entry '1234567890' '1234567890' subject '' '' '' 5 4
  assert_equals "$REPLY" $'1...0\t1234\tsubject\t\t1234567890' 'fbr preserves width-boundary truncation byte-for-byte' || return 1

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

  assert_equals "${worktree_paths[worktree-test]-}" "$worktree_dir" 'fbr maps a checked-out branch to its worktree path' || {
    builtin cd -- "$original_dir"
    return 1
  }

  current_branch=$(command git symbolic-ref --short HEAD) || return 1
  worktree_paths=()
  while IFS= read -r -d '' branch && IFS= read -r -d '' worktree_path; do
    worktree_paths[$branch]=$worktree_path
  done < <(_fbr_worktree_entries "$fixture_repo")
  assert_equals "${worktree_paths[$current_branch]-}" '' 'fbr does not mark the branch in the current checkout as another worktree' || {
    builtin cd -- "$original_dir"
    return 1
  }
  assert_equals "${worktree_paths[worktree-test]-}" "$worktree_dir" 'fbr still maps branches in other worktrees' || {
    builtin cd -- "$original_dir"
    return 1
  }

  command git update-ref refs/heads/-leading HEAD || return 1
  _fbr_activate -leading '' || return 1
  assert_equals "$(command git symbolic-ref --short HEAD)" '-leading' 'fbr safely activates a leading-dash local branch' || return 1
  command git switch -- "$current_branch" >/dev/null || return 1

  _fbr_activate origin/remote-safe '' || return 1
  assert_equals "$(command git symbolic-ref --short HEAD)" 'remote-safe' 'fbr safely activates and tracks a remote branch' || return 1
  command git switch -- "$current_branch" >/dev/null || return 1

  _fbr_activate worktree-test "${worktree_paths[worktree-test]}"
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

  output=$(_fbr_activate origin/topic '' 2>&1); rc=$?
  assert_status "$rc" 1 'fbr refuses an unrelated same-name remote selection' || { builtin cd -- "$original_dir"; return 1; }
  after_ref=$(command git rev-parse HEAD) || { builtin cd -- "$original_dir"; return 1; }
  assert_equals "$after_ref" "$before_ref" 'fbr keeps the current checkout after refusing a collision' || { builtin cd -- "$original_dir"; return 1; }
  assert_contains "$output" 'does not track local' 'fbr explains the upstream mismatch' || { builtin cd -- "$original_dir"; return 1; }
  assert_contains "$output" "git switch -- 'topic'" 'fbr offers entering the local branch' || { builtin cd -- "$original_dir"; return 1; }
  assert_contains "$output" "git switch --track -b <new-name> -- 'origin/topic'" 'fbr offers a differently named tracking branch' || { builtin cd -- "$original_dir"; return 1; }
  assert_contains "$output" "git switch --detach -- 'origin/topic'" 'fbr offers detached inspection' || { builtin cd -- "$original_dir"; return 1; }

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

  output=$(_fbr_activate upstream/topic '' 2>&1); rc=$?
  assert_status "$rc" 1 'fbr refuses when the local branch tracks a different remote' || { builtin cd -- "$original_dir"; return 1; }
  assert_contains "$output" "upstream: 'origin/topic'" 'fbr names the actual upstream on mismatch' || { builtin cd -- "$original_dir"; return 1; }
  assert_equals "$(command git symbolic-ref --short HEAD)" "$base_branch" 'fbr stays put on a different-upstream collision' || { builtin cd -- "$original_dir"; return 1; }

  _fbr_activate origin/topic '' >/dev/null 2>&1 || { builtin cd -- "$original_dir"; return 1; }
  assert_equals "$(command git symbolic-ref --short HEAD)" 'topic' 'fbr enters the local branch when it tracks the selected remote' || { builtin cd -- "$original_dir"; return 1; }
  command git switch -- "$base_branch" >/dev/null || { builtin cd -- "$original_dir"; return 1; }

  assert_contains "${functions[fbr]}" "upstream" 'fbr guards remote-to-worktree mapping by upstream' || { builtin cd -- "$original_dir"; return 1; }
  assert_contains "${functions[fbr]}" 'Enter worktree/checkout' 'fbr labels worktree and checkout actions distinctly' || { builtin cd -- "$original_dir"; return 1; }

  builtin cd -- "$original_dir"
}

main() {
  source "$repo_dir/55-ui-helpers.zsh"
  source "$repo_dir/60-functions.zsh"

  functions[_ui_plain_mode]='return 0'

  test_missing_arguments || return 1
  test_local_emulation_and_leading_dash_operands || return 1
  test_usage_temp_cleanup || return 1
  test_usage_partial_scan || return 1
  test_usage_signal_cleanup || return 1
  test_dusage_oversized_operand_set || return 1
  test_path_empty_entries || return 1
  test_control_character_paths || return 1
  test_alias_probes_are_quiet || return 1
  test_small_helper_success_paths || return 1
  test_fkill_signals || return 1
  test_fbr_worktree_navigation || return 1
  test_fbr_remote_collision || return 1
}

main "$@"
