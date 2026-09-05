#!/usr/bin/env zsh

set -u

repo_dir=${0:A:h:h}
original_path=$PATH
fakebin=$(mktemp -d) || { print -u2 -- 'fatal: mktemp failed for fakebin'; exit 1; }
[ -n "$fakebin" ] || { print -u2 -- 'fatal: mktemp returned empty fakebin'; exit 1; }
tmp_prefix=$(mktemp -d) || { print -u2 -- 'fatal: mktemp failed for tmp_prefix'; exit 1; }
[ -n "$tmp_prefix" ] || { print -u2 -- 'fatal: mktemp returned empty tmp_prefix'; exit 1; }
inspect_tmp=''

cleanup() {
  local PATH=$original_path

  if [ -n "${inspect_tmp:-}" ] && [ -d "$inspect_tmp" ]; then
    command chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree" 2>/dev/null || true
    command rm -rf "$inspect_tmp"
  fi
  command rm -rf "$fakebin" "$tmp_prefix"
}

trap cleanup EXIT INT TERM

write_fake() {
  local name=$1
  shift

  {
    print '#!/bin/sh'
    print "$@"
  } >"$fakebin/$name"
  command chmod +x "$fakebin/$name"
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

assert_matching_lines() {
  local haystack=$1
  local needle=$2
  local expected=$3
  local label=$4
  local actual

  actual=$(printf '%s\n' "$haystack" | command grep -F -c -- "$needle")

  if [[ $actual != "$expected" ]]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "expected occurrences: $expected"
    print -u2 -- "actual occurrences: $actual"
    print -u2 -- "needle: $needle"
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

assert_equals() {
  local actual=$1
  local expected=$2
  local label=$3

  if [[ $actual != "$expected" ]]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "expected: $expected"
    print -u2 -- "actual: $actual"
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

run_upkg_rich() {
  (
    functions[_ui_plain_mode]='return 1'
    functions[_ui_term_width]='print -r -- 120'
    functions[_ui_color]=':'
    functions[_ui_reset]=':'
    functions[_ui_bold]=':'
    functions[_ui_icon]='print -nr -- "$2"'
    upkg "$@"
  )
}

run_upkg_rich_without_managers() {
  (
    functions[_upkg_detect_managers]='
      typeset -g -a _UPKG_ACTIVE_MANAGERS _UPKG_ALTERNATE_MANAGERS
      _UPKG_ACTIVE_MANAGERS=()
      _UPKG_ALTERNATE_MANAGERS=()
    '
    run_upkg_rich "$@"
  )
}

run_upkg_with_managers() {
  local manager_spec=$1
  shift

  (
    functions[_upkg_detect_managers]="
      typeset -g -a _UPKG_ACTIVE_MANAGERS _UPKG_ALTERNATE_MANAGERS
      _UPKG_ACTIVE_MANAGERS=($manager_spec)
      _UPKG_ALTERNATE_MANAGERS=()
    "
    upkg "$@"
  )
}

run_upkg_as_root_with_managers() {
  local manager_spec=$1
  shift

  (
    functions[_upkg_is_root]='return 0'
    functions[_upkg_detect_managers]="
      typeset -g -a _UPKG_ACTIVE_MANAGERS _UPKG_ALTERNATE_MANAGERS
      _UPKG_ACTIVE_MANAGERS=($manager_spec)
      _UPKG_ALTERNATE_MANAGERS=()
    "
    upkg "$@"
  )
}

run_upkg_rich_with_managers() {
  local manager_spec=$1
  shift

  (
    functions[_upkg_detect_managers]="
      typeset -g -a _UPKG_ACTIVE_MANAGERS _UPKG_ALTERNATE_MANAGERS
      _UPKG_ACTIVE_MANAGERS=($manager_spec)
      _UPKG_ALTERNATE_MANAGERS=()
    "
    run_upkg_rich "$@"
  )
}

set_npkg_fixture() {
  print -r -- "$1" >"$NPKG_TEST_PROFILE_FILE"
  print -r -- "$2" >"$NPKG_TEST_EVAL_FILE"
  : >"$NPKG_TEST_EVAL_LOG"
}

run_npkg_outdated_capture() {
  local output_file rc

  output_file=$(mktemp "${TMPDIR:-/tmp}/test-npkg-outdated.XXXXXX") || return 1
  npkg outdated >"$output_file" 2>&1
  rc=$?
  typeset -g NPKG_TEST_OUTPUT="$(<"$output_file")"
  command rm -f -- "$output_file"
  return $rc
}

run_npkg_interrupt_capture() {
  local npkg_tmp_dir=$1
  local worker_started="$tmp_prefix/npkg-interrupt-started"
  local unrelated_stop="$tmp_prefix/npkg-interrupt-stop"
  local output_file="$tmp_prefix/npkg-interrupt-output"
  local harness_pid signaler_pid rc

  typeset -gi NPKG_INTERRUPT_SKIPPED=0
  command rm -f -- "$worker_started" "$unrelated_stop" "$output_file"
  if ! zmodload zsh/zselect 2>/dev/null; then
    NPKG_INTERRUPT_SKIPPED=1
    return 0
  fi

  (
    emulate -L zsh
    setopt localtraps NO_UNSET

    local unrelated_pid=''
    integer npkg_status unrelated_alive=0
    local -a leftover_tmp

    export TMPDIR=$npkg_tmp_dir
    functions[_ui_is_rich_terminal]='return 1'
    functions[_ui_plain_mode]='return 0'

    _npkg_nix() {
      if [[ "$*" == 'profile list --json' ]]; then
        print -r -- '{"elements":{"interrupt":{"active":true,"originalUrl":"nixpkgs","uri":"github:NixOS/nixpkgs/locked-interrupt","attrPath":"packages.test.interrupt","storePaths":["/nix/store/interrupt-installed"],"outputs":null}}}'
        return 0
      fi
      return 2
    }

    _npkg_eval_installable_record() {
      integer worker_ticks=0

      : >"$worker_started"
      while (( worker_ticks < 600 )); do
        zselect -t 1
        (( worker_ticks++ ))
      done
      return 1
    }

    _npkg_interrupt_harness_cleanup() {
      [[ -n $unrelated_pid ]] || return 0
      : >"$unrelated_stop"
      wait "$unrelated_pid" 2>/dev/null
    }
    trap _npkg_interrupt_harness_cleanup EXIT

    (
      integer unrelated_ticks=0

      while [[ ! -e $unrelated_stop ]] && (( unrelated_ticks < 500 )); do
        zselect -t 1
        (( unrelated_ticks++ ))
      done
    ) &
    unrelated_pid=$!

    npkg outdated >/dev/null 2>&1
    npkg_status=$?

    kill -0 "$unrelated_pid" 2>/dev/null && unrelated_alive=1
    leftover_tmp=( "$npkg_tmp_dir"/npkg-outdated.*(N) )

    print -r -- "status=$npkg_status"
    print -r -- "unrelated_alive=$unrelated_alive"
    print -r -- "leftovers=${#leftover_tmp[@]}"

    : >"$unrelated_stop"
    wait "$unrelated_pid" 2>/dev/null
    unrelated_pid=''
  ) >"$output_file" 2>&1 &
  harness_pid=$!

  (
    integer signal_ticks=0

    while [[ ! -e $worker_started ]] && (( signal_ticks < 100 )); do
      zselect -t 1
      (( signal_ticks++ ))
    done
    [[ -e $worker_started ]] && kill -INT "$harness_pid" 2>/dev/null
  ) &
  signaler_pid=$!

  wait "$harness_pid" 2>/dev/null
  rc=$?
  wait "$signaler_pid" 2>/dev/null
  typeset -g NPKG_INTERRUPT_OUTPUT="$(<"$output_file")"
  command rm -f -- "$worker_started" "$unrelated_stop" "$output_file"
  return $rc
}

test_npkg_cache_safety() {
  emulate -L zsh

  local cache_root="$tmp_prefix/npkg-cache-safety"
  local fallback_home="$tmp_prefix/npkg-cache-home"
  local first_output="$tmp_prefix/npkg-refresh-first"
  local second_output="$tmp_prefix/npkg-refresh-second"
  local error_output="$tmp_prefix/npkg-refresh-error"
  local old_cache_home=${XDG_CACHE_HOME-} old_home=${HOME-}
  local saved_current_system=${functions[_npkg_current_system]}
  local saved_nix=${functions[_npkg_nix]}
  local real_mktemp real_mv
  local output
  integer had_cache_home=${+XDG_CACHE_HOME} had_home=${+HOME}
  integer first_pid second_pid first_status second_status failure_status
  local -a leftovers

  command mkdir -p -- "$cache_root" "$fallback_home"
  real_mktemp=$(PATH=$original_path command -v mktemp) || return 1
  real_mv=$(PATH=$original_path command -v mv) || return 1
  functions[_npkg_current_system]='print -r -- test-system'
  functions[_npkg_nix]='print -r -- '\''["zoxide","ripgrep"]'\'''

  XDG_CACHE_HOME=relative
  HOME=$fallback_home
  output=$(_npkg_attr_cache_file) || return 1
  assert_equals "$output" "$fallback_home/.cache/npkg/nixpkgs-attrs-test-system.txt" 'npkg ignores a relative XDG cache home' || return 1

  XDG_CACHE_HOME=$cache_root
  (_npkg_refresh_index >"$first_output") &
  first_pid=$!
  (_npkg_refresh_index >"$second_output") &
  second_pid=$!
  wait "$first_pid"
  first_status=$?
  wait "$second_pid"
  second_status=$?
  assert_status "$first_status" 0 'first concurrent npkg refresh succeeds' || return 1
  assert_status "$second_status" 0 'second concurrent npkg refresh succeeds' || return 1
  leftovers=( "$cache_root"/npkg/*.tmp.*(N) "$cache_root"/npkg/*.err.*(N) )
  assert_equals "${#leftovers[@]}" 0 'concurrent npkg refreshes leave no intermediate files' || return 1
  assert_equals "$(<"$cache_root/npkg/nixpkgs-attrs-test-system.txt")" $'zoxide\nripgrep' 'concurrent npkg refreshes atomically publish a complete cache' || return 1

  functions[_npkg_nix]='print -u2 -r -- simulated-refresh-failure; return 9'
  _npkg_refresh_index >"$first_output" 2>"$error_output"
  failure_status=$?
  assert_status "$failure_status" 1 'failed npkg refresh returns nonzero' || return 1
  assert_contains "$(<"$error_output")" 'simulated-refresh-failure' 'failed npkg refresh preserves its diagnostic on stderr' || return 1
  leftovers=( "$cache_root"/npkg/*.tmp.*(N) "$cache_root"/npkg/*.err.*(N) )
  assert_equals "${#leftovers[@]}" 0 'failed npkg refresh removes every intermediate file' || return 1

  write_fake mktemp '
case "$1" in
  *.err.XXXXXX) exit 8 ;;
  *) exec '"$real_mktemp"' "$@" ;;
esac'
  rehash
  _npkg_refresh_index >"$first_output" 2>"$error_output"
  failure_status=$?
  assert_status "$failure_status" 1 'npkg refresh fails when its second temporary file cannot be created' || return 1
  leftovers=( "$cache_root"/npkg/*.tmp.*(N) "$cache_root"/npkg/*.err.*(N) )
  assert_equals "${#leftovers[@]}" 0 'second-temp failure removes the first temporary file' || return 1

  write_fake mktemp "exec $real_mktemp \"\$@\""
  write_fake mv 'exit 9'
  rehash
  functions[_npkg_nix]='print -r -- '\''["zoxide","ripgrep"]'\'''
  _npkg_refresh_index >"$first_output" 2>"$error_output"
  failure_status=$?
  assert_status "$failure_status" 1 'npkg refresh preserves a failed atomic activation' || return 1
  leftovers=( "$cache_root"/npkg/*.tmp.*(N) "$cache_root"/npkg/*.err.*(N) )
  assert_equals "${#leftovers[@]}" 0 'failed atomic activation removes every intermediate file' || return 1

  write_fake mv "exec $real_mv \"\$@\""
  rehash
  functions[_npkg_nix]='kill -HUP $$; print -r -- '\''["zoxide","ripgrep"]'\'''
  _npkg_refresh_index >"$first_output" 2>"$error_output"
  failure_status=$?
  assert_status "$failure_status" 129 'npkg refresh returns SIGHUP status from its function body' || return 1
  leftovers=( "$cache_root"/npkg/*.tmp.*(N) "$cache_root"/npkg/*.err.*(N) )
  assert_equals "${#leftovers[@]}" 0 'npkg refresh removes every intermediate file after SIGHUP' || return 1

  functions[_npkg_current_system]=$saved_current_system
  functions[_npkg_nix]=$saved_nix
  if (( had_cache_home )); then
    XDG_CACHE_HOME=$old_cache_home
  else
    unset XDG_CACHE_HOME
  fi
  if (( had_home )); then
    HOME=$old_home
  else
    unset HOME
  fi
}

main() {
  local output cmd_status route state_role npm_stdout npm_stderr stderr_output
  local parser_stdout="$tmp_prefix/upkg-parser.stdout"
  local parser_stderr="$tmp_prefix/upkg-parser.stderr"
  local npkg_profile_file="$tmp_prefix/npkg-profile.json"
  local npkg_eval_file="$tmp_prefix/npkg-evaluations.json"
  local npkg_eval_log="$tmp_prefix/npkg-evaluations.log"

  local default_brew_script='
case "$*" in
  "outdated") printf "%s\n" "wget (1.24.5) < 1.25.0" ; printf "%s\n" "ghostty (1.2.3) < 1.2.4" ;;
  "search --formula -- ripgrep") printf "%s\n" "ripgrep" ;;
  "search --cask -- ripgrep") printf "%s\n" "ripgrep-app" ;;
  "search --formula -- broad")
    i=1
    while [ "$i" -le 55 ]; do
      printf "pkg%s\n" "$i"
      i=$((i + 1))
    done
    ;;
  "search --cask -- broad") printf "%s\n" "No casks found for \"broad\"" >&2 ; exit 1 ;;
  "search --formula -- overlap") printf "%s\n" "overlap" ;;
  "search --cask -- overlap") printf "%s\n" "overlap" ;;
  "search --formula -- nomatch") printf "%s\n" "No formulae found for \"nomatch\"" >&2 ; exit 1 ;;
  "search --cask -- nomatch") printf "%s\n" "No casks found for \"nomatch\"" >&2 ; exit 1 ;;
  "info --formula ripgrep")
    printf "%s\n" "==> ripgrep: stable 14.1.1 (bottled), HEAD"
    ;;
  "info --formula pkg"*)
    [ "$#" -eq 52 ] || { printf "expected capped formula info args, got %s\n" "$#" >&2; exit 3; }
    shift 2
    for candidate in "$@"; do
      printf "==> %s: stable 1.0.0\n" "$candidate"
    done
    ;;
  "info --cask ripgrep-app")
    printf "%s\n" "==> ripgrep-app (Ripgrep App): 1.2.3"
    ;;
  "info --formula overlap") printf "%s\n" "==> overlap: stable 1.0.0" ;;
  "info --cask overlap") printf "%s\n" "==> overlap: 2.0.0" ;;
  "upgrade") printf "%s\n" "brew upgrade" ;;
  *) exit 2 ;;
esac
'

  write_fake pacman '
case "$*" in
  "-Qu") printf "%s\n" "coreutils 9.5-1 -> 9.6-1" ;;
  "-Ss -- ripgrep") printf "%s\n" "extra/ripgrep 14.1.1-1" ; printf "%s\n" "    recursively search directories" ; printf "%s\n" "    for a regex pattern" ;;
  "-Syu") printf "%s\n" "pacman upgrade" ;;
  *) exit 2 ;;
esac
'

  write_fake paru '
case "$*" in
  "-Qua") printf "%s\n" "yay-bin 12.4.2-1 -> 12.5.0-1" ;;
  "-Ss -- ripgrep") printf "%s\n" "aur/ripgrep-all 0.9.1-2 [installed]" ; printf "%s\n" "    search multiple ripgrep backends" ; printf "%s\n" "    together" ;;
  "-Syu") printf "%s\n" "paru upgrade" ;;
  *) exit 2 ;;
esac
'

  write_fake brew "$default_brew_script"

  write_fake flatpak '
case "$*" in
  "remote-ls --updates") printf "%s\n" "org.example.App stable" ;;
  "search --columns=application,version,name,description -- ripgrep") printf "org.example.Ripgrep\t14.1.1\tRipgrep Viewer\tRemote ripgrep browser\n" ;;
  "update") printf "%s\n" "flatpak upgrade" ;;
  *) exit 2 ;;
esac
'

write_fake npm '
case "$*" in
  "config get prefix") printf "%s\n" "$UPKG_TEST_NPM_PREFIX" ;;
  "outdated -g --depth=0") printf "%s\n" "Package Current Wanted Latest Location"; printf "%s\n" "eslint 8.0.0 8.1.0 9.0.0 global"; exit 1 ;;
  "search --parseable -- help") printf "helpful-lib\tLibrary named after help\tnpm-user\t2024-01-01\t2.0.0\thelper\n" ;;
  "search --parseable -- managers") printf "managers-kit\tLibrary named after managers\tnpm-user\t2024-01-01\t4.5.6\tmanager\n" ;;
  "search --parseable -- ripgrep") printf "ripgrep-js\tJavaScript wrapper around ripgrep\tnpm-user\t2024-01-01\t3.4.5\tripgrep\n" ;;
  "search --parseable -- ripgrep viewer")
    [ "$#" -eq 5 ] || exit 3
    printf "ripgrep-viewer\tMulti-term search result\tnpm-user\t2024-01-01\t5.6.7\tripgrep viewer\n"
    ;;
  "search --parseable -- upgrade") printf "upgrade-helper\tSearches packages named after commands\tnpm-user\t2024-01-01\t1.2.3\tupgrade\n" ;;
  "search --parseable -- -leading") printf "leading-safe\tLeading-dash query\tnpm-user\t2024-01-01\t1.0.0\tleading\n" ;;
  "update -g") printf "%s\n" "npm upgrade" ;;
  *) exit 2 ;;
esac
'

write_fake mktemp "exec $(command -v mktemp) \"\$@\""

write_fake rm "exec $(command -v rm) \"\$@\""

write_fake ss '
cat <<'"'"'EOF'"'"'
Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
tcp LISTEN 0 128 0.0.0.0:3000 0.0.0.0:* users:(("node",pid=111,fd=20),("node",pid=112,fd=21),("node",pid=113,fd=22))
EOF
'

  export NPKG_TEST_PROFILE_FILE=$npkg_profile_file
  export NPKG_TEST_EVAL_FILE=$npkg_eval_file
  export NPKG_TEST_EVAL_LOG=$npkg_eval_log
  set_npkg_fixture \
    '{"elements":{"default":{"active":true,"originalUrl":"nixpkgs","url":"github:NixOS/nixpkgs/default","attrPath":"packages.test.default","storePaths":["/nix/store/default-current"],"outputs":null}}}' \
    '{"nixpkgs#packages.test.default":{"paths":["/nix/store/default-current"],"version":"1.0"},"github:NixOS/nixpkgs/default#packages.test.default":{"paths":["/nix/store/default-current"],"version":"1.0"}}'

write_fake nix '
while [ "$1" = "--extra-experimental-features" ]; do
  shift 2
done

  if [ "$*" = "profile list --json" ]; then
    if [ "$(sed -n "1p" "$NPKG_TEST_PROFILE_FILE")" = "__FAIL__" ]; then
      printf "%s\n" "simulated profile read failure" >&2
      exit 1
    fi
    cat "$NPKG_TEST_PROFILE_FILE"
    exit $?
  fi

  if [ "$1" = "eval" ] && [ "$2" = "--json" ]; then
    installable=$3
    printf "%s|%s\n" "$installable" "$5" >> "$NPKG_TEST_EVAL_LOG"
    record=$(jq -c --arg installable "$installable" '"'"'.[$installable] // empty'"'"' "$NPKG_TEST_EVAL_FILE") || exit 2
    [ -n "$record" ] || {
      printf "missing evaluation fixture for %s\n" "$installable" >&2
      exit 2
    }
    error=$(printf "%s\n" "$record" | jq -r ".error // empty") || exit 2
    if [ -n "$error" ]; then
      printf "%s\n" "$error" >&2
      exit 1
    fi
    printf "%s\n" "$record"
    exit 0
  fi

  case "$*" in
    "search nixpkgs ripgrep")
      printf "%s\n" "* legacyPackages.x86_64-linux.ripgrep (14.1.1)"
      printf "%s\n" "  recursively search directories"
      printf "%s\n" "  with wrapped descriptions"
      ;;
    "search nixpkgs nomatch") printf "%s\n" "error: no results for the given search term(s)!" >&2; exit 1 ;;
    *) exit 2 ;;
  esac
 '

  export PATH=$fakebin:$original_path
  rehash
  export UPKG_TEST_NPM_PREFIX=$tmp_prefix

  local fallback_file rich_check_file
  fallback_file="$tmp_prefix/fallback-load.zsh"
  rich_check_file="$tmp_prefix/rich-check.zsh"

  {
    print -- 'unset -f _ui_plain_mode _ui_ascii_mode _ui_repeat _ui_color _ui_reset _ui_bold _ui_icon _ui_title_line _ui_section_break _ui_panel_prefix _ui_panel_kv _ui_badge _ui_human_kib _ui_usage_entry_icon _ui_truncate _ui_pad _ui_bar _ui_visible_count _ui_term_width 2>/dev/null || true'
    print -- "source '$repo_dir/60-functions.zsh'"
    print -- '_zsh_functions_load || exit 1'
    print -- '_ui_truncate 10 "My File.txt"'
    print -- '_ui_pad left 20 "My File.txt"'
  } > "$fallback_file"
  output=$(ZDOTDIR=$tmp_prefix TERM=xterm zsh -f "$fallback_file")
  cmd_status=$?
  assert_status "$cmd_status" 0 '60-functions fallback helpers load without ui module' || return 1
  assert_contains "$output" 'My File.txt' 'fallback helpers preserve spaced text' || return 1

  {
    print -- "source '$repo_dir/55-ui-helpers.zsh'"
    print -- 'if _ui_is_rich_terminal; then print -- rich; else print -- plain; fi'
  } > "$rich_check_file"
  output=$(ZDOTDIR=$tmp_prefix TERM=xterm LANG=en_US.UTF-8 zsh -f "$rich_check_file")
  cmd_status=$?
  assert_status "$cmd_status" 0 'ui helper TERM check script runs' || return 1
  assert_contains "$output" 'plain' 'non-TTY output keeps rich mode disabled' || return 1

  source "$repo_dir/55-ui-helpers.zsh"
  source "$repo_dir/60-functions.zsh"
  _zsh_functions_load || return 1

  assert_contains "${functions[_npkg_pick_installables]}" '_fzf_picker_multi_args add' 'Nix install picker uses the shared live multi-selection footer' || return 1
  assert_contains "${functions[_npkg_remove_picker]}" '--accept-nth=4' 'Nix remove picker asks fzf to return targets directly' || return 1
  assert_contains "${functions[_npkg_remove_picker]}" '_fzf_picker_preview_args Package' 'Nix remove picker uses shared responsive previews' || return 1
  assert_not_contains "${functions[_npkg_pick_installables]}" '245;224;220' 'Nix install preview no longer embeds the fixed RGB palette' || return 1
  assert_not_contains "${functions[_npkg_remove_picker]}" '137;180;250' 'Nix remove preview no longer embeds the fixed RGB palette' || return 1

  COLUMNS=120
  output=$(_npkg_fzf_preview_window 45)
  assert_contains "$output" 'right,50%,border-left,wrap-word' 'npkg picker uses the shared compact side preview on wide terminals' || return 1

  COLUMNS=80
  output=$(_npkg_fzf_preview_window 60)
  assert_contains "$output" 'down,40%,border-top,wrap-word' 'npkg picker uses the shared compact lower preview on narrow terminals' || return 1

  output=$(_ui_status_icon 'matches found')
  assert_contains "$output" '?' 'matches found status uses a dedicated fallback icon' || return 1
  output=$(_ui_status_icon 'no matches')
  assert_contains "$output" '0' 'no matches status uses a dedicated fallback icon' || return 1

  output=$(
    (
      functions[_ui_plain_mode]='return 1'
      functions[_ui_color]=':'
      functions[_ui_reset]=':'
      functions[_ui_icon]='print -nr -- "*"'
      _UPKG_THEME_MODE=1
      _upkg_search_progress npm ''
      print ''
      _upkg_search_progress brew formulae
    )
  )
  assert_contains "$output" 'Searching * npm...' 'search progress names the active manager with manager icon' || return 1
  assert_contains "$output" 'Searching * Homebrew (formulae)...' 'search progress includes backend phase detail' || return 1

  output=$(
    (
      functions[_ui_plain_mode]='return 1'
      functions[_ui_color]=':'
      functions[_ui_reset]=':'
      functions[_ui_icon]='print -nr -- "*"'
      functions[_ui_badge]='print -nr -- "[$1]"'
      functions[_ui_section_break]=':'
      _UPKG_THEME_MODE=1
      typeset -ga _UPKG_SEARCH_ROWS
      typeset -ga _UPKG_SUMMARY_ORDER
      typeset -gA _UPKG_SUMMARY_STATE _UPKG_SUMMARY_DETAIL
      _UPKG_SEARCH_ROWS=($'npm\tripgrep-js\t3.4.5\tJavaScript wrapper around ripgrep')
      _UPKG_SUMMARY_ORDER=(npm brew)
      _UPKG_SUMMARY_STATE=( npm 'matches found' brew failed )
      _UPKG_SUMMARY_DETAIL=( npm '1 result(s)' brew 'brew search failed' )
      _upkg_print_search_summary
    )
  )
  assert_contains "$output" 'Failed managers: brew' 'rich search summary names failed managers' || return 1

  output=$(
    (
      functions[_ui_plain_mode]='return 1'
      functions[_ui_color]=':'
      functions[_ui_reset]=':'
      functions[_ui_icon]='print -nr -- "*"'
      functions[_ui_badge]='print -nr -- "[$1:$2]"'
      functions[_ui_section_break]=':'
      _UPKG_THEME_MODE=1
      _UPKG_OPERATION=clean
      typeset -ga _UPKG_SUMMARY_ORDER
      typeset -gA _UPKG_SUMMARY_STATE _UPKG_SUMMARY_DETAIL
      _UPKG_SUMMARY_ORDER=(apt brew npm nix flatpak pacman)
      _UPKG_SUMMARY_STATE=(apt blocked brew cleaned npm partial nix failed flatpak planned pacman skipped)
      _UPKG_SUMMARY_DETAIL=()
      _upkg_print_summary
    )
  )
  for state_role in blocked:warning cleaned:success partial:danger failed:danger planned:info skipped:muted; do
    assert_contains "$output" "[$state_role]" "rich cleanup summary renders $state_role" || return 1
  done

  output=$'npm error code EUSAGE\nnpm error Please use --force to remove entire npx cache\nnpm error Usage:\nnpm error npm cache npx ls\nnpm error npm cache npx rm [<key>...]'
  _upkg_npm_npx_cache_unsupported "$output"
  cmd_status=$?
  assert_status "$cmd_status" 1 'force-required whole-cache usage still indicates npx subcommands are supported' || return 1

  output=$(upkg managers)
  assert_contains "$output" 'paru' 'detects paru' || return 1
  assert_contains "$output" 'brew' 'detects brew' || return 1
  assert_not_contains "$output" 'paru (active)' 'active managers keep plain output stable' || return 1
  assert_not_contains "$output" 'title=' 'manager listing stays free of debug leaks' || return 1
  assert_order "$output" '  - paru' '  - brew' 'manager listing keeps brew after distro backend' || return 1
  assert_order "$output" '  - brew' '  - flatpak' 'manager listing keeps brew ahead of flatpak' || return 1
  assert_order "$output" '  - flatpak' '  - nix' 'manager listing keeps flatpak ahead of nix' || return 1
  assert_order "$output" '  - nix' '  - npm' 'manager listing keeps nix ahead of npm' || return 1
  assert_contains "$output" 'pacman (available via --only pacman)' 'labels pacman alternate' || return 1

  output=$(upkg --only=brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'brew outdated succeeds' || return 1
  assert_contains "$output" '==> Homebrew' 'brew section title is rendered' || return 1
  assert_contains "$output" 'wget (1.24.5) < 1.25.0' 'brew outdated preserves Homebrew formula format' || return 1
  assert_contains "$output" 'ghostty (1.2.3) < 1.2.4' 'brew outdated preserves multiple Homebrew rows' || return 1

  output=$(upkg --only=npm,flatpak)
  assert_contains "$output" '==> npm' 'equals --only keeps first selected manager first' || return 1
  assert_contains "$output" '==> Flatpak' 'equals --only includes second selected manager' || return 1
  assert_order "$output" '==> npm' '==> Flatpak' 'selected manager order' || return 1

  output=$(upkg managers --only=npm,flatpak)
  assert_contains "$output" '  - npm (selected)' 'manager listing marks npm selected' || return 1
  assert_contains "$output" '  - flatpak (selected)' 'manager listing marks flatpak selected' || return 1
  assert_order "$output" '  - npm (selected)' '  - flatpak (selected)' 'manager listing follows selected order' || return 1

  output=$(upkg --only=apt 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'unavailable selected manager returns nonzero' || return 1
  assert_contains "$output" 'Selected managers are not available: apt' 'unavailable manager is named' || return 1
  assert_contains "$output" 'Detected managers: paru, brew, flatpak, nix, npm, pacman' 'unavailable manager error lists detected managers' || return 1
  assert_contains "$output" 'Run: upkg managers' 'unavailable manager error suggests managers view' || return 1

  output=$(upkg --skip='paru, brew, flatpak, nix, npm' 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'empty filtered selection returns nonzero' || return 1
  assert_contains "$output" 'No package managers selected after applying filters.' 'empty selection explains filter result' || return 1
  assert_contains "$output" 'Skip filter: paru, brew, flatpak, nix, npm' 'empty selection includes skip filter' || return 1
  assert_contains "$output" 'Run: upkg managers --skip paru,brew,flatpak,nix,npm' 'empty selection suggests filtered managers view' || return 1

  output=$(upkg search ripgrep)
  cmd_status=$?
  assert_status "$cmd_status" 0 'default search succeeds across detected managers' || return 1
  assert_contains "$output" 'Manager' 'search shows manager column' || return 1
  assert_matching_lines "$output" 'Manager' 1 'search prints a single table header' || return 1
  assert_not_contains "$output" '==> Paru' 'search suppresses paru section title' || return 1
  assert_not_contains "$output" '==> Homebrew' 'search suppresses brew section title' || return 1
  assert_contains "$output" 'ripgrep-all' 'search shows paru package name' || return 1
  assert_contains "$output" '0.9.1-2' 'search shows paru available version' || return 1
  assert_contains "$output" 'search multiple ripgrep backends together' 'search preserves spaces in wrapped paru descriptions' || return 1
  assert_contains "$output" 'ripgrep-app' 'search shows brew cask name' || return 1
  assert_contains "$output" '1.2.3' 'search shows brew version' || return 1
  assert_contains "$output" 'flatpak' 'search shows flatpak manager label' || return 1
  assert_contains "$output" 'legacyPackages.x86_64-linux.ripgrep' 'search shows nix attribute path' || return 1
  assert_contains "$output" '14.1.1' 'search shows nix available version' || return 1
  assert_contains "$output" 'recursively search directories with wrapped descriptions' 'search preserves spaces in wrapped nix descriptions' || return 1
  assert_contains "$output" 'ripgrep-js' 'search shows npm package name' || return 1
  assert_contains "$output" '3.4.5' 'search shows npm version' || return 1
  assert_contains "$output" 'Search summary: 6 result(s) across 5 manager(s).' 'search prints compact summary' || return 1

  output=$(upkg search ripgrep --only=npm,flatpak)
  cmd_status=$?
  assert_status "$cmd_status" 0 'search respects only filters after query args' || return 1
  assert_contains "$output" 'npm' 'filtered search includes npm' || return 1
  assert_contains "$output" 'flatpak' 'filtered search includes flatpak' || return 1
  assert_order "$output" 'npm      ripgrep-js' 'flatpak  org.example.Ripgrep' 'filtered search keeps selected order' || return 1
  assert_not_contains "$output" 'brew' 'filtered search omits unselected managers' || return 1

  output=$(upkg search ripgrep --only=pacman)
  cmd_status=$?
  assert_status "$cmd_status" 0 'search supports pacman alternate via only' || return 1
  assert_contains "$output" 'pacman' 'alternate search includes pacman manager label' || return 1
  assert_contains "$output" 'ripgrep' 'search shows pacman package name' || return 1
  assert_contains "$output" '14.1.1-1' 'search shows pacman version' || return 1
  assert_contains "$output" 'recursively search directories for a regex pattern' 'search preserves spaces in wrapped pacman descriptions' || return 1

  output=$(upkg search nomatch --only=brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'search treats brew no matches as success' || return 1
  assert_contains "$output" 'No matches found across selected managers.' 'search reports no matches cleanly' || return 1
  assert_contains "$output" 'Search summary: 0 result(s) across 1 manager(s).' 'no-match search prints compact summary' || return 1
  assert_matching_lines "$output" 'No matches found' 1 'no-match search prints one no-match message' || return 1

  output=$(upkg search nomatch --only=nix)
  cmd_status=$?
  assert_status "$cmd_status" 0 'nix lowercase no-result search succeeds' || return 1
  assert_contains "$output" 'No matches found across selected managers.' 'nix lowercase no-result search reports no matches' || return 1

  output=$(upkg search broad --only=brew 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 0 'broad brew search succeeds with capped info lookup' || return 1
  assert_contains "$output" 'Homebrew formula search returned 55 matches; showing first 50.' 'broad brew search reports capped formula results' || return 1
  assert_contains "$output" 'brew     pkg50' 'broad brew search includes the last capped formula' || return 1
  assert_not_contains "$output" 'brew     pkg51' 'broad brew search omits uncapped formula results' || return 1

  output=$(upkg search overlap --only=brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'brew search keeps formula and cask name collisions' || return 1
  assert_contains "$output" 'brew     overlap                              1.0.0              formula' 'brew search includes formula collision row' || return 1
  assert_contains "$output" 'brew     overlap                              2.0.0              cask' 'brew search includes cask collision row' || return 1

  write_fake brew '
case "$*" in
  "search --formula -- ripgrep") printf "%s\n" "Error: simulated brew search failure" >&2; exit 1 ;;
  "search --cask -- ripgrep") printf "%s\n" "ripgrep-app" ;;
  "info --cask ripgrep-app") printf "%s\n" "==> ripgrep-app (Ripgrep App): 1.2.3" ;;
  *) exit 2 ;;
esac
'

  output=$(upkg search ripgrep --only=brew,npm 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'search returns nonzero when one backend fails' || return 1
  assert_contains "$output" 'Error: simulated brew search failure' 'partial search keeps backend error text' || return 1
  assert_contains "$output" 'npm      ripgrep-js' 'partial search still prints successful rows' || return 1
  assert_contains "$output" 'Search summary: 1 result(s) across 1 manager(s), 1 failed (brew).' 'partial search summary names failed managers' || return 1

  output=$(upkg search ripgrep --only=brew 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'all-failed search returns nonzero' || return 1
  assert_contains "$output" 'Search results unavailable; failed manager(s): brew.' 'all-failed search names failed managers' || return 1
  assert_not_contains "$output" 'No matches found across selected managers.' 'all-failed search does not report no matches' || return 1
  assert_contains "$output" 'Search summary: 0 result(s) across 0 manager(s), 1 failed (brew).' 'all-failed search summary names failed managers' || return 1

  write_fake brew "$default_brew_script"

  output=$(upkg search 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'search requires a query' || return 1
  assert_contains "$output" 'Usage: upkg search <query>' 'search missing query shows usage' || return 1
  assert_not_contains "$output" 'Commands:' 'search missing query avoids full help dump' || return 1

  upkg --only >"$parser_stdout" 2>"$parser_stderr"
  cmd_status=$?
  assert_status "$cmd_status" 1 'missing upkg option values fail' || return 1
  assert_equals "$(<"$parser_stdout")" '' 'upkg parser failures keep stdout clean' || return 1
  assert_contains "$(<"$parser_stderr")" 'Usage: upkg [command]' 'upkg parser failures keep actionable usage on stderr' || return 1

  upkg help >"$parser_stdout" 2>"$parser_stderr"
  cmd_status=$?
  assert_status "$cmd_status" 0 'upkg help remains successful' || return 1
  assert_contains "$(<"$parser_stdout")" 'Usage: upkg [command]' 'upkg help remains on stdout' || return 1
  assert_equals "$(<"$parser_stderr")" '' 'upkg help keeps stderr clean' || return 1

  output=$(upkg managers --dry-run 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'dry-run rejects managers command' || return 1
  assert_contains "$output" '--dry-run is only valid with the default outdated check, plan, upgrade, or clean' 'dry-run error explains valid commands' || return 1

  output=$(upkg search upgrade --only=npm)
  cmd_status=$?
  assert_status "$cmd_status" 0 'search accepts query terms that match command keywords' || return 1
  assert_contains "$output" 'upgrade-helper' 'command-keyword searches still reach npm backend' || return 1

  output=$(upkg search help --only=npm)
  cmd_status=$?
  assert_status "$cmd_status" 0 'search accepts help as a literal query' || return 1
  assert_contains "$output" 'helpful-lib' 'help keyword searches still reach npm backend' || return 1

  output=$(upkg search managers --only=npm)
  cmd_status=$?
  assert_status "$cmd_status" 0 'search accepts managers as a literal query' || return 1
  assert_contains "$output" 'managers-kit' 'manager keyword searches still reach npm backend' || return 1

  output=$(upkg search --help)
  cmd_status=$?
  assert_status "$cmd_status" 0 'search help flag shows usage' || return 1
  assert_contains "$output" 'Usage: upkg [command]' 'search help flag reaches upkg usage' || return 1

  output=$(upkg --only=npm search -- upgrade)
  cmd_status=$?
  assert_status "$cmd_status" 0 'search supports double-dash to stop option parsing' || return 1
  assert_contains "$output" 'upgrade-helper' 'double-dash search passes literal query terms through' || return 1

  output=$(upkg --only=npm search -- -leading)
  cmd_status=$?
  assert_status "$cmd_status" 0 'search accepts a leading-dash query' || return 1
  assert_contains "$output" 'leading-safe' 'backend option terminators protect leading-dash queries' || return 1

  output=$(upkg search ripgrep viewer --only=npm)
  cmd_status=$?
  assert_status "$cmd_status" 0 'search preserves multi-word query args for backends' || return 1
  assert_contains "$output" 'ripgrep-viewer' 'multi-word search reaches npm as separate argv entries' || return 1

  for route in outdated check list; do
    output=$(run_upkg_rich "$route" --only=brew)
    cmd_status=$?
    assert_status "$cmd_status" 0 "$route succeeds in forced rich mode" || return 1
    assert_contains "$output" 'Package Dashboard  outdated' "$route reaches the rich outdated dashboard" || return 1
  done

  output=$(run_upkg_rich --only=brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'default command succeeds in forced rich mode' || return 1
  assert_contains "$output" 'Package Dashboard  outdated' 'default command reaches the rich outdated dashboard' || return 1

  output=$(run_upkg_rich search ripgrep --only=brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'search succeeds in forced rich mode' || return 1
  assert_contains "$output" 'Package Search  ripgrep' 'search reaches the rich search dashboard' || return 1

  output=$(run_upkg_rich plan --only=brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'plan succeeds in forced rich mode' || return 1
  assert_contains "$output" 'Package Dashboard  plan' 'plan reaches the rich plan dashboard' || return 1

  output=$(run_upkg_rich upgrade --dry-run --only=brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'upgrade dry-run succeeds in forced rich mode' || return 1
  assert_contains "$output" 'Package Dashboard  plan' 'upgrade dry-run reaches the rich plan dashboard' || return 1

  output=$(run_upkg_rich --dry-run --only=brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'default dry-run succeeds in forced rich mode' || return 1
  assert_contains "$output" 'Package Dashboard  plan' 'default dry-run reaches the rich plan dashboard' || return 1

  output=$(run_upkg_rich managers --only=brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'managers succeeds in forced rich mode' || return 1
  assert_contains "$output" 'Detected Managers  upkg managers' 'managers reaches the rich manager dashboard' || return 1

  for route in help -h --help; do
    output=$(run_upkg_rich "$route")
    cmd_status=$?
    assert_status "$cmd_status" 0 "$route succeeds in forced rich mode" || return 1
    assert_contains "$output" 'Unified Package Updates  upkg help' "$route reaches the rich help dashboard" || return 1
  done

  output=$(run_upkg_rich search --help)
  cmd_status=$?
  assert_status "$cmd_status" 0 'search help succeeds in forced rich mode' || return 1
  assert_contains "$output" 'Unified Package Updates  upkg help' 'search help reaches the rich help dashboard' || return 1

  output=$(run_upkg_rich --only=unsupported 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'invalid filter fails in forced rich mode' || return 1
  assert_contains "$output" 'Package Dashboard  outdated' 'invalid filter retains the rich command header' || return 1
  assert_contains "$output" 'Unsupported manager id: unsupported' 'invalid filter retains its error detail' || return 1

  output=$(run_upkg_rich unknown 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'unknown command fails in forced rich mode' || return 1
  assert_contains "$output" 'Unified Package Updates  upkg help' 'unknown command reaches the rich usage dashboard' || return 1
  assert_contains "$output" 'Unknown argument: unknown' 'unknown command retains its error detail' || return 1

  output=$(run_upkg_rich search 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'missing search query fails in forced rich mode' || return 1
  assert_contains "$output" 'Package Search  usage' 'missing search query reaches the rich search usage panel' || return 1

  output=$(run_upkg_rich_without_managers 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'missing managers fails in forced rich mode' || return 1
  assert_contains "$output" 'Package Dashboard  outdated' 'missing managers retains the rich command header' || return 1
  assert_contains "$output" 'No supported package managers detected.' 'missing managers retains its error detail' || return 1

  output=$(upkg plan --only=paru)
  cmd_status=$?
  assert_status "$cmd_status" 0 'paru plan succeeds when repo and AUR checks succeed' || return 1
  assert_contains "$output" 'Repo updates:' 'paru plan includes repo updates' || return 1
  assert_contains "$output" 'AUR updates:' 'paru plan includes AUR updates' || return 1

  output=$(upkg upgrade --dry-run --only=npm)
  assert_contains "$output" 'eslint 8.0.0 8.1.0 9.0.0 global' 'dry-run previews npm instead of upgrading' || return 1

  output=$(upkg upgrade --only=brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'brew upgrade runs without sudo gating' || return 1
  assert_contains "$output" 'brew upgrade' 'brew upgrade invokes brew directly' || return 1
  assert_contains "$output" 'brew: upgraded' 'brew upgrade summary marks backend upgraded' || return 1

  output=$(run_upkg_rich upgrade --only=brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'brew upgrade succeeds in forced rich mode' || return 1
  assert_contains "$output" 'Package Dashboard' 'upgrade path renders the rich dashboard title' || return 1
  assert_contains "$output" 'Package Dashboard  upgrade' 'upgrade path shows the active command in the rich title' || return 1
  assert_contains "$output" 'Homebrew' 'upgrade path renders the rich manager section' || return 1
  assert_not_contains "$output" '==> Homebrew' 'upgrade path avoids the plain manager heading in rich mode' || return 1
  assert_not_contains "$output" 'Summary:' 'upgrade path avoids the plain summary heading in rich mode' || return 1

  for route in up update; do
    output=$(run_upkg_rich "$route" --only=brew)
    cmd_status=$?
    assert_status "$cmd_status" 0 "$route succeeds in forced rich mode" || return 1
    assert_contains "$output" 'Package Dashboard  upgrade' "$route reaches the rich upgrade dashboard" || return 1
  done

  write_fake brew '
case "$*" in
  "outdated") printf "%s\n" "Error: simulated brew outdated failure" >&2; exit 1 ;;
  "upgrade") printf "%s\n" "brew upgrade" ;;
  *) exit 2 ;;
esac
'

  output=$(upkg --only=brew 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'brew outdated failure returns nonzero' || return 1
  assert_contains "$output" 'Error: simulated brew outdated failure' 'brew outdated forwards backend failure output' || return 1
  assert_contains "$output" 'brew: failed - brew outdated failed' 'brew outdated summary marks backend failed' || return 1

  write_fake brew '
case "$*" in
  "outdated") printf "%s\n" "wget (1.24.5) < 1.25.0" ;;
  "upgrade") printf "%s\n" "Error: simulated brew upgrade failure" >&2; exit 1 ;;
  *) exit 2 ;;
esac
'

  output=$(upkg upgrade --only=brew 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'brew upgrade failure returns nonzero' || return 1
  assert_contains "$output" 'Error: simulated brew upgrade failure' 'brew upgrade forwards backend failure output' || return 1
  assert_contains "$output" 'brew: failed - brew upgrade failed' 'brew upgrade summary marks backend failed' || return 1

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

  local clean_log="$tmp_prefix/upkg-clean-invocations"
  export UPKG_TEST_CLEAN_LOG=$clean_log

  # Exercise the non-root cleanup contract regardless of the test runner's UID.
  functions[_upkg_is_root]='return 1'

  write_fake sudo '
printf "%s\n" "sudo $*" >> "$UPKG_TEST_CLEAN_LOG"
exec "$@"
'

  write_fake apt '
printf "%s\n" "apt $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "list --upgradable") printf "%s\n" "Listing..." ;;
  "--simulate autoremove") printf "%s\n" "APT autoremove simulation" ;;
  "--simulate autoclean") printf "%s\n" "APT autoclean simulation" ;;
  "autoremove") printf "%s\n" "MUTATING apt autoremove" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "APT autoremove" ;;
  "autoclean") printf "%s\n" "MUTATING apt autoclean" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "APT autoclean" ;;
  *) exit 2 ;;
esac
'

  write_fake dnf '
printf "%s\n" "dnf $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "--cacheonly repoquery --unneeded") printf "%s\n" "unused-dependency" ;;
  "autoremove") printf "%s\n" "MUTATING dnf autoremove" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "DNF autoremove" ;;
  "clean all") printf "%s\n" "MUTATING dnf clean all" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "DNF clean all" ;;
  *) exit 2 ;;
esac
'

  write_fake pacman '
printf "%s\n" "pacman $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "-Qtdq") printf "%s\n" "orphan-one" "orphan-two" ;;
  "-Rs -- orphan-one orphan-two") printf "%s\n" "MUTATING pacman orphan removal" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "Pacman orphan removal" ;;
  "-Sc") printf "%s\n" "MUTATING pacman cache" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "Pacman cache cleanup" ;;
  *) exit 2 ;;
esac
'

  write_fake paru '
printf "%s\n" "paru $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "-c") printf "%s\n" "MUTATING paru dependencies" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "Paru dependency cleanup" ;;
  "-Sc") printf "%s\n" "MUTATING paru cache" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "Paru cache cleanup" ;;
  *) exit 2 ;;
esac
'

  write_fake brew '
printf "%s\n" "brew $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "outdated") printf "%s\n" "wget (1.24.5) < 1.25.0" ;;
  "autoremove --dry-run") printf "%s\n" "Homebrew autoremove preview" ;;
  "cleanup --dry-run") printf "%s\n" "Homebrew cleanup preview" ;;
  "autoremove") printf "%s\n" "MUTATING brew autoremove" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "Homebrew autoremove" ;;
  "cleanup") printf "%s\n" "MUTATING brew cleanup" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "Homebrew cleanup" ;;
  *) exit 2 ;;
esac
'

  write_fake flatpak '
printf "%s\n" "flatpak $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "uninstall --unused --user") printf "%s\n" "MUTATING flatpak user" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "Flatpak user cleanup" ;;
  "uninstall --unused --system") printf "%s\n" "MUTATING flatpak system" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "Flatpak system cleanup" ;;
  *) exit 2 ;;
esac
'

  write_fake nix-collect-garbage '
printf "%s\n" "nix-collect-garbage $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "--dry-run") printf "%s\n" "Nix garbage collection preview" ;;
  "") printf "%s\n" "MUTATING nix garbage collection" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "Nix garbage collection" ;;
  *) exit 2 ;;
esac
'
  rehash

  write_fake npm '
printf "%s\n" "npm $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "search --parseable -- clean") printf "clean-package\tCleanup helper\tnpm-user\t2024-01-01\t1.0.0\tclean\n" ;;
  "cache npx ls") printf "%s\n" "npx-cache-key-one: test-package" "npx-cache-key-two: another-package" ;;
  "cache npx rm npx-cache-key-one npx-cache-key-two") printf "%s\n" "MUTATING npm npx cache" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "npm npx cache removed" ;;
  "cache verify") printf "%s\n" "MUTATING npm cache verify" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "npm cache verified" ;;
  *) exit 2 ;;
esac
'

  : > "$clean_log"
  output=$(run_upkg_with_managers 'brew' --only=brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'bare upkg still routes to outdated after adding clean' || return 1
  assert_contains "$output" 'wget (1.24.5) < 1.25.0' 'bare upkg keeps the outdated backend path' || return 1

  : > "$clean_log"
  output=$(run_upkg_with_managers 'npm' search clean --only=npm)
  cmd_status=$?
  assert_status "$cmd_status" 0 'search accepts clean as a literal query' || return 1
  assert_contains "$output" 'clean-package' 'clean keyword searches still reach npm' || return 1
  assert_contains "$(<"$clean_log")" 'npm search --parseable -- clean' 'search passes clean to the npm backend' || return 1

  : > "$clean_log"
  output=$(run_upkg_with_managers 'apt dnf pacman paru brew flatpak nix npm' clean --dry-run --only=apt,dnf,pacman,paru,brew,flatpak,nix,npm)
  cmd_status=$?
  assert_status "$cmd_status" 0 'cleanup dry-run succeeds across every backend' || return 1
  for manager in apt dnf pacman paru brew flatpak nix npm; do
    assert_contains "$output" "$manager: planned" "$manager dry-run summary is planned" || return 1
  done
  assert_contains "$output" 'would run: sudo apt autoclean' 'APT preview prints cache cleanup without reading its privileged cache' || return 1
  assert_contains "$output" 'would run: sudo pacman -Rs -- orphan-one orphan-two' 'pacman preview includes orphan removal privilege context' || return 1
  assert_contains "$output" 'would run: flatpak uninstall --unused --system' 'flatpak preview prints the exact system cleanup command' || return 1
  assert_contains "$output" 'would run: npm cache verify' 'npm preview does not execute cache verification' || return 1
  output=$(<"$clean_log")
  assert_not_contains "$output" 'MUTATING' 'cleanup dry-run invokes no mutating fake command form' || return 1
  assert_not_contains "$output" 'sudo ' 'cleanup dry-run never invokes sudo' || return 1
  assert_not_contains "$output" 'apt --simulate autoclean' 'cleanup dry-run avoids APT cache reads that can require root' || return 1
  assert_contains "$output" 'dnf --cacheonly repoquery --unneeded' 'DNF preview cannot refresh package metadata' || return 1
  assert_order "$output" 'brew autoremove --dry-run' 'brew cleanup --dry-run' 'brew preview runs both native dry-run forms in order' || return 1
  assert_contains "$output" 'nix-collect-garbage --dry-run' 'nix preview uses garbage collector dry-run' || return 1
  assert_contains "$output" 'npm cache npx ls' 'npm preview lists the npx cache' || return 1

  : > "$clean_log"
  output=$(run_upkg_as_root_with_managers 'apt dnf pacman' clean --dry-run --only=apt,dnf,pacman)
  cmd_status=$?
  assert_status "$cmd_status" 0 'cleanup dry-run succeeds in simulated root mode' || return 1
  assert_contains "$output" 'would run: apt autoclean' 'root APT preview omits sudo' || return 1
  assert_contains "$output" 'would run: dnf clean all' 'root DNF preview omits sudo' || return 1
  assert_contains "$output" 'would run: pacman -Rs -- orphan-one orphan-two' 'root Pacman preview omits sudo' || return 1
  assert_not_contains "$output" 'would run: sudo ' 'root cleanup previews never display sudo' || return 1
  assert_not_contains "$(<"$clean_log")" 'sudo ' 'root cleanup dry-run never invokes sudo' || return 1

  output=$(run_upkg_with_managers 'brew npm' clean --dry-run --only=npm,brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'cleanup honors explicit only order' || return 1
  assert_order "$output" '==> npm' '==> Homebrew' 'cleanup sections follow only order' || return 1

  output=$(run_upkg_rich_with_managers 'brew' clean --dry-run --only=brew)
  cmd_status=$?
  assert_status "$cmd_status" 0 'cleanup preview succeeds in forced rich mode' || return 1
  assert_contains "$output" 'Package Cleanup  dry-run' 'cleanup preview uses the rich cleanup dashboard title' || return 1
  assert_contains "$output" '[planned]' 'rich cleanup summary renders the planned state' || return 1

  : > "$clean_log"
  output=$(run_upkg_with_managers 'paru pacman' clean --dry-run --skip=pacman)
  cmd_status=$?
  assert_status "$cmd_status" 0 'cleanup skip filter succeeds' || return 1
  assert_contains "$output" 'pacman: skipped' 'cleanup summary records skipped managers' || return 1
  assert_not_contains "$(<"$clean_log")" 'pacman -Qtdq' 'skipped cleanup does not invoke the backend' || return 1

  for manager in apt dnf pacman; do
    : > "$clean_log"
    output=$(run_upkg_with_managers "$manager" clean --only="$manager" 2>&1)
    cmd_status=$?
    assert_status "$cmd_status" 1 "$manager cleanup is blocked without --sudo" || return 1
    assert_contains "$output" "$manager cleanup requires root; rerun with: upkg clean --sudo --only $manager" "$manager cleanup prints a copyable privilege retry" || return 1
    assert_not_contains "$(<"$clean_log")" 'MUTATING' "$manager blocked cleanup invokes no mutating command" || return 1
  done

  : > "$clean_log"
  output=$(run_upkg_with_managers 'apt dnf pacman' clean --sudo --only=apt,dnf,pacman)
  cmd_status=$?
  assert_status "$cmd_status" 0 'authorized distro cleanup succeeds' || return 1
  assert_contains "$output" 'apt: cleaned' 'authorized apt cleanup is cleaned' || return 1
  assert_contains "$output" 'dnf: cleaned' 'authorized dnf cleanup is cleaned' || return 1
  assert_contains "$output" 'pacman: cleaned' 'authorized pacman cleanup is cleaned' || return 1
  output=$(<"$clean_log")
  assert_order "$output" 'sudo apt autoremove' 'sudo apt autoclean' 'apt cleans unused packages before its cache through sudo' || return 1
  assert_order "$output" 'sudo dnf autoremove' 'sudo dnf clean all' 'dnf cleans unused packages before its cache through sudo' || return 1
  assert_order "$output" 'pacman -Qtdq' 'sudo pacman -Rs -- orphan-one orphan-two' 'pacman queries and removes its orphan array' || return 1
  assert_order "$output" 'sudo pacman -Rs -- orphan-one orphan-two' 'sudo pacman -Sc' 'pacman removes orphans before cleaning its cache' || return 1
  assert_not_contains "$output" ' -y' 'distro cleanup sends no automatic confirmation flag' || return 1
  assert_not_contains "$output" '-Scc' 'pacman cleanup avoids aggressive cache deletion' || return 1
  assert_not_contains "$output" '-Rn' 'pacman cleanup preserves backup configuration' || return 1

  : > "$clean_log"
  output=$(run_upkg_as_root_with_managers 'apt dnf pacman' clean --only=apt,dnf,pacman)
  cmd_status=$?
  assert_status "$cmd_status" 0 'distro cleanup succeeds in simulated root mode without --sudo' || return 1
  output=$(<"$clean_log")
  assert_order "$output" 'apt autoremove' 'apt autoclean' 'root APT cleanup runs directly in phase order' || return 1
  assert_order "$output" 'dnf autoremove' 'dnf clean all' 'root DNF cleanup runs directly in phase order' || return 1
  assert_order "$output" 'pacman -Qtdq' 'pacman -Rs -- orphan-one orphan-two' 'root Pacman cleanup removes its orphan array directly' || return 1
  assert_order "$output" 'pacman -Rs -- orphan-one orphan-two' 'pacman -Sc' 'root Pacman cleanup runs directly in phase order' || return 1
  assert_not_contains "$output" 'sudo ' 'root distro cleanup never invokes sudo' || return 1

  write_fake pacman '
printf "%s\n" "pacman $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "-Qtdq")
    printf "%s\n" "warning: optional package database is unavailable" >&2
    printf "%s\n" "orphan-one" "orphan-two"
    ;;
  "-Rs -- orphan-one orphan-two") printf "%s\n" "MUTATING pacman orphan removal" >> "$UPKG_TEST_CLEAN_LOG" ;;
  "-Sc") printf "%s\n" "MUTATING pacman cache" >> "$UPKG_TEST_CLEAN_LOG" ;;
  *) exit 2 ;;
esac
'
  : > "$clean_log"
  output=$(run_upkg_with_managers 'pacman' clean --sudo --only=pacman 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 0 'pacman warnings do not contaminate the orphan array' || return 1
  assert_contains "$output" 'warning: optional package database is unavailable' 'pacman orphan-query stderr passes through' || return 1
  assert_contains "$(<"$clean_log")" 'sudo pacman -Rs -- orphan-one orphan-two' 'pacman removes only package names from query stdout' || return 1
  assert_not_contains "$(<"$clean_log")" 'sudo pacman -Rs -- warning:' 'pacman never treats query stderr as a package name' || return 1

  : > "$clean_log"
  output=$(run_upkg_with_managers 'paru' clean --only=paru 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'paru cleanup requires explicit authorization' || return 1
  assert_contains "$output" 'rerun with: upkg clean --sudo --only paru' 'paru cleanup prints its authorization retry' || return 1
  assert_not_contains "$(<"$clean_log")" 'MUTATING' 'blocked paru cleanup invokes nothing' || return 1

  : > "$clean_log"
  output=$(run_upkg_with_managers 'paru pacman' clean --sudo --only=paru)
  cmd_status=$?
  assert_status "$cmd_status" 0 'authorized paru cleanup succeeds' || return 1
  output=$(<"$clean_log")
  assert_order "$output" 'paru -c' 'paru -Sc' 'paru removes unused dependencies before its cache' || return 1
  assert_not_contains "$output" 'sudo paru' 'paru retains control of its privilege helper' || return 1
  assert_not_contains "$output" 'pacman ' 'explicit paru cleanup does not duplicate the pacman route' || return 1

  : > "$clean_log"
  output=$(upkg clean --sudo --skip=brew,flatpak,nix,npm)
  cmd_status=$?
  assert_status "$cmd_status" 0 'default Arch cleanup route succeeds through Paru' || return 1
  assert_contains "$output" 'paru: cleaned' 'default Arch cleanup summarizes Paru' || return 1
  assert_not_contains "$(<"$clean_log")" 'pacman ' 'default Paru cleanup route does not duplicate Pacman' || return 1

  : > "$clean_log"
  output=$(run_upkg_with_managers 'brew flatpak nix npm' clean --only=brew,flatpak,nix,npm)
  cmd_status=$?
  assert_status "$cmd_status" 0 'user-space cleanup backends succeed' || return 1
  for manager in brew flatpak nix npm; do
    assert_contains "$output" "$manager: cleaned" "$manager cleanup summary is cleaned" || return 1
  done
  output=$(<"$clean_log")
  assert_not_contains "$output" 'sudo ' 'brew, flatpak, nix, and npm are never prefixed with sudo' || return 1
  assert_order "$output" 'brew autoremove' 'brew cleanup' 'Homebrew removes dependencies before standard cleanup' || return 1
  assert_order "$output" 'flatpak uninstall --unused --user' 'flatpak uninstall --unused --system' 'Flatpak cleans user refs before system refs' || return 1
  assert_order "$output" 'npm cache npx rm' 'npm cache verify' 'npm removes the npx cache before verifying its content cache' || return 1
  assert_contains "$output" 'npm cache npx rm npx-cache-key-one npx-cache-key-two' 'npm removes the explicit keys returned by its npx cache listing' || return 1
  assert_not_contains "$output" 'npm cache npx rm --force' 'npm avoids whole-cache force removal for npx entries' || return 1
  assert_not_contains "$output" '--delete-data' 'Flatpak cleanup preserves application data' || return 1
  assert_not_contains "$output" '--force-remove' 'Flatpak cleanup avoids force removal' || return 1
  assert_not_contains "$output" '--prune=all' 'Homebrew cleanup uses its conservative defaults' || return 1
  assert_not_contains "$output" '--delete-old' 'Nix cleanup preserves profile generations' || return 1
  assert_not_contains "$output" ' -d' 'Nix cleanup preserves rollback history' || return 1
  assert_not_contains "$output" 'cache clean --force' 'npm cleanup avoids aggressive cache deletion' || return 1

  write_fake npm '
printf "%s\n" "npm $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "cache npx ls") : ;;
  "cache verify") printf "%s\n" "MUTATING npm cache verify" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "npm cache verified" ;;
  *) exit 2 ;;
esac
'
  : > "$clean_log"
  output=$(run_upkg_with_managers 'npm' clean --only=npm)
  cmd_status=$?
  assert_status "$cmd_status" 0 'npm cleanup succeeds when the npx cache listing is empty' || return 1
  assert_contains "$output" 'No npx cache entries found.' 'empty npm npx cache is explained' || return 1
  assert_contains "$output" 'npm: cleaned' 'empty npx cache plus successful verification is cleaned' || return 1
  assert_not_contains "$(<"$clean_log")" 'npm cache npx rm' 'empty npm npx cache invokes no removal' || return 1
  assert_contains "$(<"$clean_log")" 'npm cache verify' 'empty npm npx cache still gets verified' || return 1

  write_fake npm '
printf "%s\n" "npm $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "cache npx ls") printf "%s\n" "--force: unsafe-option-shaped-key" ;;
  "cache verify") printf "%s\n" "MUTATING npm cache verify" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "npm cache verified" ;;
  *) exit 2 ;;
esac
'
  : > "$clean_log"
  output=$(run_upkg_with_managers 'npm' clean --only=npm 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'untrusted npm npx cache keys fail cleanup safely' || return 1
  assert_contains "$output" 'Could not safely parse npm npx cache keys' 'unsafe npm npx cache key is explained' || return 1
  assert_contains "$output" 'npm: partial - npx cache listing could not be parsed' 'unsafe npm npx cache key plus successful verification is partial' || return 1
  assert_not_contains "$(<"$clean_log")" 'npm cache npx rm' 'unsafe npm npx cache key invokes no removal' || return 1
  assert_contains "$(<"$clean_log")" 'npm cache verify' 'unsafe npm npx cache key does not suppress verification' || return 1

  write_fake pacman '
printf "%s\n" "pacman $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "-Qtdq") printf "%s\n" "warning: no optional sync database" >&2 ; exit 1 ;;
  "-Sc") printf "%s\n" "MUTATING pacman cache" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "Pacman cache cleanup" ;;
  *) exit 2 ;;
esac
'
  : > "$clean_log"
  output=$(run_upkg_with_managers 'pacman' clean --sudo --only=pacman 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 0 'empty pacman orphan query exit 1 is normal' || return 1
  assert_contains "$output" 'warning: no optional sync database' 'empty pacman query preserves stderr without treating it as output' || return 1
  assert_contains "$output" 'No orphaned packages found.' 'empty pacman orphan query is explained' || return 1
  assert_contains "$(<"$clean_log")" 'sudo pacman -Sc' 'pacman still cleans its cache after an empty orphan query' || return 1

  write_fake brew '
printf "%s\n" "brew $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "autoremove") printf "%s\n" "simulated Homebrew autoremove failure" >&2 ; exit 1 ;;
  "cleanup") printf "%s\n" "MUTATING brew cleanup" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "Homebrew cleanup" ;;
  *) exit 2 ;;
esac
'
  write_fake npm '
printf "%s\n" "npm $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "cache npx ls") printf "%s\n" "npm cache usage: unsupported npx subcommand" >&2 ; exit 1 ;;
  "cache verify") printf "%s\n" "MUTATING npm cache verify" >> "$UPKG_TEST_CLEAN_LOG" ; printf "%s\n" "npm cache verified" ;;
  *) exit 2 ;;
esac
'
  : > "$clean_log"
  output=$(run_upkg_with_managers 'brew npm' clean --only=brew,npm 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'partial cleanup makes the overall command fail after later managers run' || return 1
  assert_contains "$output" 'brew: partial - brew autoremove failed' 'failed first phase plus successful cache cleanup is partial' || return 1
  assert_contains "$output" 'npm: partial - npx cache cleanup is unsupported; npm cache verified' 'unsupported npx cleanup plus verified npm cache is partial' || return 1
  assert_contains "$output" 'upgrade npm to enable npx cache cleanup' 'unsupported npx cleanup recommends upgrading npm' || return 1
  assert_order "$(<"$clean_log")" 'brew autoremove' 'brew cleanup' 'failed Homebrew first phase does not suppress cache cleanup' || return 1
  assert_order "$(<"$clean_log")" 'brew cleanup' 'npm cache npx ls' 'partial Homebrew cleanup does not stop the next manager' || return 1
  assert_not_contains "$(<"$clean_log")" 'npm cache npx rm' 'unsupported npx listing never attempts a removal' || return 1

  npm_stdout="$tmp_prefix/npm-clean.stdout"
  npm_stderr="$tmp_prefix/npm-clean.stderr"
  run_upkg_with_managers 'npm' clean --only=npm >"$npm_stdout" 2>"$npm_stderr"
  cmd_status=$?
  assert_status "$cmd_status" 1 'unsupported npx cleanup remains partial with split output streams' || return 1
  assert_contains "$(<"$npm_stderr")" 'npm cache usage: unsupported npx subcommand' 'npm npx stderr passes through on stderr' || return 1
  assert_not_contains "$(<"$npm_stdout")" 'npm cache usage: unsupported npx subcommand' 'npm npx stderr is not replayed on stdout' || return 1
  assert_contains "$(<"$npm_stdout")" 'npm cache verified' 'npm cache verification stdout passes through on stdout' || return 1

  : > "$clean_log"
  output=$(run_upkg_with_managers 'npm' clean --dry-run --only=npm 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'failed cleanup preview probe returns nonzero' || return 1
  assert_contains "$output" 'npm: failed - npx cache preview failed' 'failed cleanup preview probe is summarized as failed' || return 1
  assert_not_contains "$(<"$clean_log")" 'MUTATING' 'failed cleanup preview still invokes no mutating form' || return 1

  write_fake flatpak '
printf "%s\n" "flatpak $*" >> "$UPKG_TEST_CLEAN_LOG"
case "$*" in
  "uninstall --unused --user") printf "%s\n" "MUTATING flatpak user" >> "$UPKG_TEST_CLEAN_LOG" ;;
  "uninstall --unused --system") printf "%s\n" "simulated Flatpak system failure" >&2 ; exit 1 ;;
  *) exit 2 ;;
esac
'
  output=$(run_upkg_with_managers 'flatpak' clean --only=flatpak 2>&1)
  cmd_status=$?
  assert_status "$cmd_status" 1 'one successful Flatpak installation cleanup is partial' || return 1
  assert_contains "$output" 'flatpak: partial - flatpak system cleanup failed' 'Flatpak partial summary identifies the failed installation' || return 1

  command rm -f "$fakebin/nix-collect-garbage"
  local path_with_nix_gc=$PATH
  PATH=$fakebin
  output=$(run_upkg_with_managers 'nix' clean --only=nix 2>&1)
  cmd_status=$?
  PATH=$path_with_nix_gc
  assert_status "$cmd_status" 1 'missing nix-collect-garbage fails Nix cleanup' || return 1
  assert_contains "$output" 'nix-collect-garbage is required for Nix cleanup' 'missing Nix garbage collector prints an actionable message' || return 1
  assert_contains "$output" 'nix: failed - nix-collect-garbage is not available' 'missing Nix garbage collector is summarized as failed' || return 1

  inspect_tmp=$(mktemp -d) || {
    print -u2 -- 'not ok: mktemp creates inspect tmpdir'
    return 1
  }
  if [ -z "$inspect_tmp" ]; then
    print -u2 -- 'not ok: mktemp returned empty inspect tmpdir'
    return 1
  fi
  command mkdir -p "$inspect_tmp/readable-dir" "$inspect_tmp/blocked-dir/inner" "$inspect_tmp/readable-tree" "$inspect_tmp/blocked-tree/inner"
  print -r -- 'ok' >"$inspect_tmp/readable-dir/file.txt"
  print -r -- 'ok' >"$inspect_tmp/blocked-dir/inner/file.txt"
  print -r -- 'ok' >"$inspect_tmp/readable-tree/visible.txt"
  print -r -- 'ok' >"$inspect_tmp/blocked-tree/inner/hidden.txt"
  command chmod 000 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"

  output=$(dusage "$inspect_tmp" 5 2>"$inspect_tmp/dusage.stderr")
  cmd_status=$?
  stderr_output=$(<"$inspect_tmp/dusage.stderr")
  assert_status "$cmd_status" 1 'dusage reports incomplete scans instead of silent success' || {
    command chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"
    command rm -rf "$inspect_tmp"
    return 1
  }
  assert_contains "$output" 'readable-dir' 'dusage still reports readable entries' || {
    command chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"
    command rm -rf "$inspect_tmp"
    return 1
  }
  assert_contains "$stderr_output" 'Incomplete scan' 'dusage explains partial results on stderr' || {
    command chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"
    command rm -rf "$inspect_tmp"
    return 1
  }

  output=$(bigfiles "$inspect_tmp" 5 2>"$inspect_tmp/bigfiles.stderr")
  cmd_status=$?
  stderr_output=$(<"$inspect_tmp/bigfiles.stderr")
  assert_status "$cmd_status" 1 'bigfiles reports incomplete scans instead of silent success' || {
    command chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"
    command rm -rf "$inspect_tmp"
    return 1
  }
  assert_contains "$output" 'visible.txt' 'bigfiles still reports readable files' || {
    command chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"
    command rm -rf "$inspect_tmp"
    return 1
  }
  assert_contains "$stderr_output" 'Incomplete scan' 'bigfiles explains partial results on stderr' || {
    command chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"
    command rm -rf "$inspect_tmp"
    return 1
  }

  functions[_ui_is_rich_terminal]='return 0'
  functions[_ui_plain_mode]='return 1'
  functions[_ui_term_width]='print -r -- 120'
  functions[_ui_term_height]='print -r -- 12'
  functions[_ui_color]=':'
  functions[_ui_reset]=':'
  functions[_ui_bold]=':'

  output=$(ports)
  cmd_status=$?
  assert_status "$cmd_status" 0 'ports rich parser succeeds for multi-owner sockets' || return 1
  assert_contains "$output" 'node, node, node' 'ports preserves all socket owners' || return 1
  assert_contains "$output" 'pid=111,112,113' 'ports preserves all socket pids' || return 1

  if command -v jq >/dev/null 2>&1; then
    local profile_fixture eval_fixture old_tmpdir=${TMPDIR-}
    local npkg_tmp_dir="$tmp_prefix/npkg-tmp"
    integer had_tmpdir=${+TMPDIR}
    local -a leftover_tmp

    command mkdir -p -- "$npkg_tmp_dir"
    test_npkg_cache_safety || return 1
    TMPDIR=$npkg_tmp_dir
    functions[_ui_is_rich_terminal]='return 1'
    functions[_ui_plain_mode]='return 0'

    set_npkg_fixture \
      '{"elements":{"multi":{"active":true,"originalUrl":"nixpkgs","url":"github:NixOS/nixpkgs/locked-multi","attrPath":"packages.test.multi","storePaths":["/nix/store/multi-man","/nix/store/multi-out"],"outputs":["out","man"]}}}' \
      '{"nixpkgs#packages.test.multi":{"paths":["/nix/store/multi-out","/nix/store/multi-man"],"version":"unstable-2026-08-01"},"github:NixOS/nixpkgs/locked-multi#packages.test.multi":{"paths":["/nix/store/multi-man","/nix/store/multi-out"],"version":"unstable-2026-08-01"}}'
    run_npkg_outdated_capture
    cmd_status=$?
    output=$NPKG_TEST_OUTPUT
    assert_status "$cmd_status" 0 'matching multi-output identity is a complete npkg report' || return 1
    assert_equals "$_NPKG_OUTDATED_STATE" current 'matching output sets expose current state' || return 1
    assert_equals "$_NPKG_OUTDATED_TOTAL" 1 'object-shaped profile contributes one checked element' || return 1
    assert_equals "$_NPKG_OUTDATED_CHANGED" 0 'matching output sets have no changes' || return 1
    assert_equals "$_NPKG_OUTDATED_UNKNOWN" 0 'matching output sets have no unknown rows' || return 1
    assert_contains "$output" 'unstable-2026-08-01' 'hyphenated date versions remain intact for display' || return 1
    assert_contains "$output" 'current' 'matching multi-output package is labeled current' || return 1
    assert_contains "$output" 'Everything is up to date.' 'all-current complete report prints the success summary' || return 1
    output=$(<"$NPKG_TEST_EVAL_LOG")
    assert_contains "$output" 'selectedOutputs = [ "out" "man" ];' 'multi-output evaluation preserves the manifest output selection' || return 1

    output=$(run_upkg_with_managers 'nix' outdated --only=nix)
    cmd_status=$?
    assert_status "$cmd_status" 0 'upkg accepts a complete current Nix report' || return 1
    assert_contains "$output" 'nix: up to date' 'upkg maps current Nix state without matching prose' || return 1

    set_npkg_fixture \
      '{"elements":[{"active":true,"originalUrl":"nixpkgs","uri":"github:NixOS/nixpkgs/locked-equal","attrPath":"packages.test.equal","storePaths":["/nix/store/equal-old"],"outputs":null},{"active":true,"originalUrl":"nixpkgs","uri":"github:NixOS/nixpkgs/locked-newer","attrPath":"packages.test.newer","storePaths":["/nix/store/newer-installed"],"outputs":null}]}' \
      '{"nixpkgs#packages.test.equal":{"paths":["/nix/store/equal-new"],"version":"1.0"},"github:NixOS/nixpkgs/locked-equal#packages.test.equal":{"paths":["/nix/store/equal-old"],"version":"1.0"},"nixpkgs#packages.test.newer":{"paths":["/nix/store/newer-available"],"version":"2.0"},"github:NixOS/nixpkgs/locked-newer#packages.test.newer":{"paths":["/nix/store/newer-installed"],"version":"9.0"}}'
    run_npkg_outdated_capture
    cmd_status=$?
    output=$NPKG_TEST_OUTPUT
    assert_status "$cmd_status" 0 'changed array-shaped profile is a complete npkg report' || return 1
    assert_equals "$_NPKG_OUTDATED_STATE" changed 'different output sets expose changed state' || return 1
    assert_equals "$_NPKG_OUTDATED_TOTAL" 2 'array-shaped profile contributes every active nixpkgs element' || return 1
    assert_equals "$_NPKG_OUTDATED_CHANGED" 2 'different output paths count as changes despite display versions' || return 1
    assert_contains "$output" '1.0' 'equal installed and available versions remain display-only data' || return 1
    assert_contains "$output" '9.0' 'installed version that appears newer remains intact' || return 1
    assert_contains "$output" '2.0' 'available version that appears older remains intact' || return 1
    assert_contains "$output" 'change available' 'changed rows use the conservative user label' || return 1
    assert_contains "$output" '2 change(s) available.' 'complete changed report uses conservative change wording' || return 1
    assert_not_contains "$output" 'upgrade(s) available' 'npkg never infers version ordering from display strings' || return 1
    assert_contains "$(<"$NPKG_TEST_EVAL_LOG")" 'outputsToInstall' 'default output evaluation consults Nix output-selection metadata' || return 1

    output=$(run_upkg_with_managers 'nix' outdated --only=nix)
    cmd_status=$?
    assert_status "$cmd_status" 0 'upkg accepts a complete changed Nix report' || return 1
    assert_contains "$output" 'nix: updates available' 'upkg maps changed Nix state to updates available' || return 1
    output=$(run_upkg_with_managers 'nix' plan --only=nix)
    cmd_status=$?
    assert_status "$cmd_status" 0 'upkg plan accepts a complete changed Nix report' || return 1
    assert_contains "$output" 'nix: updates available' 'upkg plan preserves changed Nix state' || return 1

    set_npkg_fixture \
      '{"elements":{"current":{"active":true,"originalUrl":"nixpkgs","url":"github:NixOS/nixpkgs/locked-current","attrPath":"packages.test.current","storePaths":["/nix/store/current"],"outputs":null},"changed":{"active":true,"originalUrl":"nixpkgs","url":"github:NixOS/nixpkgs/locked-changed","attrPath":"packages.test.changed","storePaths":["/nix/store/changed-old"],"outputs":null},"broken":{"active":true,"originalUrl":"nixpkgs","url":"github:NixOS/nixpkgs/locked-broken","attrPath":"packages.test.broken","storePaths":["/nix/store/broken"],"outputs":null}}}' \
      '{"nixpkgs#packages.test.current":{"paths":["/nix/store/current"],"version":"1.0"},"github:NixOS/nixpkgs/locked-current#packages.test.current":{"paths":["/nix/store/current"],"version":"1.0"},"nixpkgs#packages.test.changed":{"paths":["/nix/store/changed-new"],"version":"1.0"},"github:NixOS/nixpkgs/locked-changed#packages.test.changed":{"paths":["/nix/store/changed-old"],"version":"1.0"},"nixpkgs#packages.test.broken":{"error":"simulated nix eval failure"},"github:NixOS/nixpkgs/locked-broken#packages.test.broken":{"paths":["/nix/store/broken"],"version":"1.0"}}'
    run_npkg_outdated_capture
    cmd_status=$?
    output=$NPKG_TEST_OUTPUT
    assert_status "$cmd_status" 1 'one failed evaluation makes the npkg report incomplete' || return 1
    assert_equals "$_NPKG_OUTDATED_STATE" partial 'failed evaluation exposes partial state' || return 1
    assert_equals "$_NPKG_OUTDATED_CHANGED" 1 'partial report keeps its known change count' || return 1
    assert_equals "$_NPKG_OUTDATED_UNKNOWN" 1 'partial report counts the failed evaluation as unknown' || return 1
    assert_contains "$output" 'Partial result: 1 change(s) available; 1 unknown.' 'partial summary keeps separate change and unknown counts' || return 1
    assert_contains "$output" 'simulated nix eval failure' 'partial report preserves the evaluation diagnostic' || return 1
    assert_not_contains "$output" 'Everything is up to date.' 'partial report never prints an all-current summary' || return 1

    output=$(run_upkg_with_managers 'nix' outdated --only=nix 2>&1)
    cmd_status=$?
    assert_status "$cmd_status" 1 'upkg outdated fails for partial Nix state' || return 1
    assert_contains "$output" 'simulated nix eval failure' 'upkg outdated preserves partial Nix diagnostics' || return 1
    assert_contains "$output" 'nix: failed' 'upkg outdated maps partial Nix state to failed' || return 1
    output=$(run_upkg_with_managers 'nix' plan --only=nix 2>&1)
    cmd_status=$?
    assert_status "$cmd_status" 1 'upkg plan fails for partial Nix state' || return 1
    assert_contains "$output" 'nix: failed' 'upkg plan maps partial Nix state to failed' || return 1

    set_npkg_fixture \
      '{"elements":[{"active":true,"originalUrl":"nixpkgs","uri":"github:NixOS/nixpkgs/missing-attr","storePaths":["/nix/store/missing-attr"],"outputs":null},{"active":true,"uri":"github:NixOS/nixpkgs/missing-source","attrPath":"packages.test.missingSource","storePaths":["/nix/store/missing-source"],"outputs":null},{"active":true,"originalUrl":"nixpkgs","uri":"github:NixOS/nixpkgs/missing-paths","attrPath":"packages.test.missingPaths","outputs":null},{"active":true,"originalUrl":"nixpkgs","uri":"github:NixOS/nixpkgs/no-eval-paths","attrPath":"packages.test.noEvalPaths","storePaths":["/nix/store/no-eval-paths"],"outputs":null}]}' \
      '{"nixpkgs#packages.test.noEvalPaths":{"paths":[],"version":"1.0"},"github:NixOS/nixpkgs/no-eval-paths#packages.test.noEvalPaths":{"paths":["/nix/store/no-eval-paths"],"version":"1.0"}}'
    run_npkg_outdated_capture
    cmd_status=$?
    output=$NPKG_TEST_OUTPUT
    assert_status "$cmd_status" 1 'missing structural or evaluated output data makes npkg incomplete' || return 1
    assert_equals "$_NPKG_OUTDATED_TOTAL" 4 'incomplete nixpkgs elements remain visible in the report' || return 1
    assert_equals "$_NPKG_OUTDATED_UNKNOWN" 4 'missing attr source and path data are all unknown' || return 1
    assert_matching_lines "$output" 'unknown' 5 'four unknown rows plus the partial summary are visible' || return 1
    assert_contains "$output" 'incomplete profile data' 'structural unknown rows explain their cause' || return 1
    assert_contains "$output" 'evaluation returned unusable output-path data' 'empty evaluated output set is unknown' || return 1
    assert_not_contains "$output" 'Everything is up to date.' 'missing-data report never prints success' || return 1

    set_npkg_fixture \
      '{"elements":[{"active":true,"originalUrl":"github:example/tools","uri":"github:example/tools/locked","attrPath":"packages.test.tool","storePaths":["/nix/store/tool"]}]}' \
      '{}'
    run_npkg_outdated_capture
    cmd_status=$?
    output=$NPKG_TEST_OUTPUT
    assert_status "$cmd_status" 0 'profile without active nixpkgs elements is complete' || return 1
    assert_equals "$_NPKG_OUTDATED_STATE" current 'zero-count nixpkgs profile exposes current state' || return 1
    assert_equals "$_NPKG_OUTDATED_TOTAL" 0 'zero-count nixpkgs profile checks no elements' || return 1
    assert_contains "$output" 'No nixpkgs packages found in the current profile.' 'zero-count profile keeps its dedicated message' || return 1
    assert_equals "$(<"$NPKG_TEST_EVAL_LOG")" '' 'zero-count profile performs no evaluation' || return 1

    set_npkg_fixture '__FAIL__' '{}'
    local profile_stdout="$tmp_prefix/npkg-profile-failure.stdout"
    local profile_stderr="$tmp_prefix/npkg-profile-failure.stderr"
    npkg outdated >"$profile_stdout" 2>"$profile_stderr"
    cmd_status=$?
    output=$(<"$profile_stderr")
    assert_status "$cmd_status" 1 'total profile read failure returns nonzero' || return 1
    assert_equals "$_NPKG_OUTDATED_STATE" partial 'profile read failure exposes partial state' || return 1
    assert_contains "$output" 'simulated profile read failure' 'profile read failure preserves its diagnostic' || return 1
    assert_equals "$(<"$profile_stdout")" '' 'profile read failure keeps stdout empty' || return 1
    assert_not_contains "$output" 'Everything is up to date.' 'profile read failure never prints success' || return 1

    set_npkg_fixture '{"elements":' '{}'
    run_npkg_outdated_capture
    cmd_status=$?
    output=$NPKG_TEST_OUTPUT
    assert_status "$cmd_status" 1 'profile JSON parse failure returns nonzero' || return 1
    assert_contains "$output" 'Failed to parse Nix profile JSON.' 'profile JSON parse failure is explicit' || return 1
    assert_not_contains "$output" 'Everything is up to date.' 'profile JSON parse failure never prints success' || return 1

    profile_fixture=$(command jq -nc '
      {
        elements: [
          range(1; 13) as $index
          | {
              active: true,
              originalUrl: "nixpkgs",
              uri: ("github:NixOS/nixpkgs/locked-" + ($index | tostring)),
              attrPath: ("packages.test.pkg" + ($index | tostring)),
              storePaths: [("/nix/store/pkg" + ($index | tostring) + "-installed")],
              outputs: null
            }
        ]
      }
    ')
    eval_fixture=$(command jq -nc '
      reduce range(1; 13) as $index ({};
        .[("nixpkgs#packages.test.pkg" + ($index | tostring))] = {
          paths: [(
            if $index == 12
            then "/nix/store/pkg12-changed"
            else ("/nix/store/pkg" + ($index | tostring) + "-installed")
            end
          )],
          version: "1.0"
        }
        | .[("github:NixOS/nixpkgs/locked-" + ($index | tostring) + "#packages.test.pkg" + ($index | tostring))] = {
            paths: [("/nix/store/pkg" + ($index | tostring) + "-installed")],
            version: "1.0"
          }
      )
    ')
    set_npkg_fixture "$profile_fixture" "$eval_fixture"
    functions[_ui_is_rich_terminal]='return 0'
    functions[_ui_plain_mode]='return 1'
    functions[_ui_term_height]='print -r -- 12'
    run_npkg_outdated_capture
    cmd_status=$?
    output=$NPKG_TEST_OUTPUT
    assert_status "$cmd_status" 0 'rich report with hidden rows remains complete' || return 1
    assert_equals "$_NPKG_OUTDATED_STATE" changed 'hidden changed row still exposes changed state' || return 1
    assert_equals "$_NPKG_OUTDATED_CHANGED" 1 'hidden changed row contributes to the change total' || return 1
    assert_contains "$output" '+9 not shown' 'rich dashboard reports rows hidden by terminal height' || return 1
    assert_contains "$output" '1 change(s) available. Run npkg upgrade to apply.' 'rich summary counts a hidden changed row' || return 1

    run_npkg_interrupt_capture "$npkg_tmp_dir"
    cmd_status=$?
    assert_status "$cmd_status" 0 'npkg interrupt regression harness completes' || return 1
    if (( NPKG_INTERRUPT_SKIPPED )); then
      print -- 'skip: zsh/zselect unavailable; npkg interrupt regression not run'
    else
      output=$NPKG_INTERRUPT_OUTPUT
      assert_contains "$output" 'status=130' 'npkg outdated returns 130 from its main function after Ctrl+C' || return 1
      assert_contains "$output" 'unrelated_alive=1' 'npkg outdated does not wait for or terminate unrelated background jobs' || return 1
      assert_contains "$output" 'leftovers=0' 'npkg outdated removes temporary files after Ctrl+C' || return 1
    fi

    leftover_tmp=( "$npkg_tmp_dir"/*(N) )
    assert_equals "${#leftover_tmp[@]}" 0 'npkg outdated removes temporary files after every normal result' || return 1

    if (( had_tmpdir )); then
      TMPDIR=$old_tmpdir
    else
      unset TMPDIR
    fi
  fi

  command chmod 700 "$inspect_tmp/blocked-dir" "$inspect_tmp/blocked-tree"
  command rm -rf "$inspect_tmp"

  write_fake curl '
case "$*" in
  "-fsSL https://ifconfig.me/ip") printf "%s" "203.0.113.42" ;;
  *) exit 2 ;;
esac
'

  functions[_ui_is_rich_terminal]='return 1'
  functions[_ui_plain_mode]='return 0'
  output=$(myip)
  cmd_status=$?
  assert_status "$cmd_status" 0 'myip plain mode exits 0 with stubbed curl' || return 1
  assert_contains "$output" '203.0.113.42' 'myip plain mode prints the IP address' || return 1

  functions[_ui_is_rich_terminal]='return 0'
  functions[_ui_plain_mode]='return 1'
  functions[_ui_term_width]='print -r -- 120'
  functions[_ui_term_height]='print -r -- 12'
  functions[_ui_color]=':'
  functions[_ui_reset]=':'
  functions[_ui_bold]=':'
  functions[_ui_title_line]=':'
  functions[_ui_panel_kv]=':'
  functions[_ui_section_break]=':'
  output=$(myip)
  cmd_status=$?
  assert_status "$cmd_status" 0 'myip rich mode exits 0 with stubbed curl' || return 1
  assert_contains "$output" '203.0.113.42' 'myip rich mode includes the IP address' || return 1

  command rm -f "$fakebin/paru" "$fakebin/pacman"
  write_fake apt '
case "$*" in
  "list --upgradable")
    printf "%s\n" "Listing..."
    printf "%s\n" "ripgrep/stable 14.1.1-2 amd64 [upgradable from: 14.1.1-1]"
    ;;
  "search --names-only -- ripgrep")
    printf "%s\n" "Sorting..."
    printf "%s\n" "Full Text Search..."
    printf "%s\n" "ripgrep/stable 14.1.1-1 amd64"
    printf "%s\n" "  recursively search directories"
    ;;
  *) exit 2 ;;
esac
'

  output=$(_upkg_run_outdated_apt)
  cmd_status=$?
  assert_status "$cmd_status" 0 'apt outdated backend succeeds with fake apt data' || return 1
  assert_contains "$output" 'ripgrep/stable 14.1.1-2' 'apt outdated shows upgradable packages' || return 1
  assert_not_contains "$output" 'Listing...' 'apt outdated removes the apt listing banner' || return 1

  _UPKG_SEARCH_ROWS=()
  _upkg_run_search_apt ripgrep >/dev/null
  cmd_status=$?
  assert_status "$cmd_status" 0 'apt search backend succeeds with fake apt data' || return 1
  output="${(F)_UPKG_SEARCH_ROWS}"
  assert_contains "$output" 'apt' 'apt search records apt manager label' || return 1
  assert_contains "$output" 'ripgrep' 'apt search shows package name' || return 1
  assert_contains "$output" '14.1.1-1' 'apt search shows available version' || return 1

  command rm -f "$fakebin/apt"
  write_fake dnf '
case "$*" in
  "list --available *ripgrep*")
    printf "%s\n" "Available Packages"
    printf "%s\n" "ripgrep.x86_64 14.1.1-1.fc40 updates"
    ;;
  *) exit 2 ;;
esac
'

  _UPKG_SEARCH_ROWS=()
  _upkg_run_search_dnf ripgrep >/dev/null
  cmd_status=$?
  assert_status "$cmd_status" 0 'dnf search backend succeeds with fake dnf data' || return 1
  output="${(F)_UPKG_SEARCH_ROWS}"
  assert_contains "$output" 'dnf' 'dnf search records dnf manager label' || return 1
  assert_contains "$output" 'ripgrep.x86_64' 'dnf search shows package name with arch' || return 1
  assert_contains "$output" '14.1.1-1.fc40' 'dnf search shows available version' || return 1
}

main "$@"
