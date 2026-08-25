#!/usr/bin/env zsh

set -u

repo_dir=${0:A:h:h}
zsh_bin=${commands[zsh]:-$(command -v zsh)}
[[ -n $zsh_bin ]] || { print -u2 -- 'fatal: zsh is unavailable'; exit 1; }
tmp_home=$(mktemp -d) || { print -u2 -- 'fatal: mktemp failed for tmp_home'; exit 1; }
[ -n "$tmp_home" ] || { print -u2 -- 'fatal: mktemp returned empty tmp_home'; exit 1; }

cleanup() {
  command rm -rf "$tmp_home"
}

trap cleanup EXIT INT TERM

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

assert_no_output() {
  local file=$1
  local label=$2

  if [[ -s $file ]]; then
    print -u2 -- "not ok: $label"
    command cat "$file" >&2
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

  actual=$(print -r -- "$haystack" | command grep -F -c -- "$needle")
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

file_contents() {
  local file=$1
  [[ -f $file ]] && print -r -- "$(<"$file")"
}

run_init_case() {
  local label=$1
  local setup=${2-}
  local command_text cmd_status stdout_file stderr_file

  stdout_file=$(mktemp) || { print -u2 -- 'fatal: mktemp failed for stdout_file'; return 1; }
  stderr_file=$(mktemp) || { print -u2 -- 'fatal: mktemp failed for stderr_file'; command rm -f "$stdout_file"; return 1; }

  command_text=$setup
  if [[ -n $command_text ]]; then
    command_text+=$'\n'
  fi
  command_text+='source "$HOME/.config/zsh/init.zsh"'

  HOME="$tmp_home" zsh -fc "$command_text" >"$stdout_file" 2>"$stderr_file"
  cmd_status=$?

  assert_status "$cmd_status" 0 "$label exits cleanly" || {
    command cat "$stderr_file" >&2
    command rm -f "$stdout_file" "$stderr_file"
    return 1
  }
  assert_no_output "$stdout_file" "$label keeps stdout clean" || {
    command rm -f "$stdout_file" "$stderr_file"
    return 1
  }
  assert_no_output "$stderr_file" "$label keeps stderr clean" || {
    command rm -f "$stdout_file" "$stderr_file"
    return 1
  }

  command rm -f "$stdout_file" "$stderr_file"
}

prepare_fzf_fakebin() {
  local fakebin=$1
  local version=${2:-0.68.0}
  local version_status=${3:-0}
  local integration_mode=${4:-ok}
  local include_fzf=${5:-1}
  local tool

  command mkdir -p -- "$fakebin" || return 1
  for tool in zsh chmod mkdir mktemp mv rm ls grep diff; do
    local tool_path=${commands[$tool]:-}
    [[ -n $tool_path ]] || tool_path=$(command -v "$tool")
    [[ -n $tool_path ]] || {
      print -u2 -r -- "fatal: test fixture requires $tool"
      return 1
    }
    command ln -s -- "$tool_path" "$fakebin/$tool" || return 1
  done

  print -r -- '#!/bin/sh
if [ "$*" = "init zsh" ]; then
  printf "%s\n" \
    "__zoxide_zi() { typeset -g ZOXIDE_PICKER_CALLED=1; }" \
    "z() { :; }" \
    "zi() { __zoxide_zi \"\$@\"; }"
  exit 0
fi
exit 0' > "$fakebin/zoxide"
  command chmod +x "$fakebin/zoxide"

  print -r -- '#!/bin/sh
exit 0' > "$fakebin/nix"
  command chmod +x "$fakebin/nix"
  print -r -- '#!/bin/sh
exit 0' > "$fakebin/jq"
  command chmod +x "$fakebin/jq"

  (( include_fzf )) || return 0

  print -r -- "$version" > "$fakebin/fzf.version"
  print -r -- "$version_status" > "$fakebin/fzf.version-status"
  print -r -- "$integration_mode" > "$fakebin/fzf.integration-mode"
  print -r -- '#!/bin/sh
printf "%s:%s\n" "$0" "$1" >> "${FZF_TEST_LOG:-/dev/null}"

case "$1" in
  --version)
    IFS= read -r version < "$0.version"
    IFS= read -r version_status < "$0.version-status"
    [ "$version_status" -eq 0 ] || exit "$version_status"
    printf "%s\n" "$version"
    ;;
  --zsh)
    IFS= read -r integration_mode < "$0.integration-mode"
    case "$integration_mode" in
      fail)
        printf "%s\n" "simulated fzf --zsh failure" >&2
        exit 7
        ;;
      empty)
        exit 0
        ;;
      invalid)
        printf "%s\n" "if ("
        exit 0
        ;;
      runtime-fail)
        printf "%s\n" "false"
        exit 0
        ;;
      *)
        printf "%s\n" \
          "typeset -g FZF_TEST_EVALUATED=1" \
          "fzf-file-widget() { print -r -- file-widget >> \"\$FZF_TEST_WIDGET_LOG\"; }" \
          "fzf-cd-widget() { print -r -- cd-widget >> \"\$FZF_TEST_WIDGET_LOG\"; }" \
          "fzf-history-widget() { print -r -- history-widget >> \"\$FZF_TEST_WIDGET_LOG\"; }" \
          "__fzf_comprun() { print -r -- completion >> \"\$FZF_TEST_WIDGET_LOG\"; command fzf \"\$@\"; }" \
          "_fzf_complete() { :; }"
        ;;
    esac
    ;;
  *)
    printf "%s:%s\n" "$0" "picker:$*" >> "${FZF_TEST_LOG:-/dev/null}"
    exit 91
    ;;
esac' > "$fakebin/fzf"
  command chmod +x "$fakebin/fzf"
}

run_fzf_startup_case() {
  local version=$1
  local version_status=$2
  local integration_mode=$3
  local include_fzf=$4
  local case_dir script_file stdout_file stderr_file log_file widget_log

  case_dir=$(mktemp -d "$tmp_home/fzf-startup.XXXXXX") || return 1
  script_file="$case_dir/startup.zsh"
  stdout_file="$case_dir/stdout"
  stderr_file="$case_dir/stderr"
  log_file="$case_dir/fzf.log"
  widget_log="$case_dir/widget.log"
  : > "$log_file"
  : > "$widget_log"

  prepare_fzf_fakebin "$case_dir/bin" "$version" "$version_status" "$integration_mode" "$include_fzf" || return 1
  print -r -- 'unset FZF_DEFAULT_OPTS FZF_CTRL_T_OPTS FZF_ALT_C_OPTS FZF_CTRL_R_OPTS FZF_COMPLETION_OPTS FZF_COMPLETION_PATH_OPTS FZF_COMPLETION_DIR_OPTS
source "$HOME/.config/zsh/init.zsh"
[[ ${FZF_DEFAULT_OPTS-} == *selected-bg* ]] && selected_bg=1 || selected_bg=0
print -r -- "state=${_FZF_STATE:-unset} found=${_FZF_FOUND:-unset} evaluated=${FZF_TEST_EVALUATED:-0}"
print -r -- "opts=${+FZF_DEFAULT_OPTS}${+FZF_CTRL_T_OPTS}${+FZF_ALT_C_OPTS}${+FZF_CTRL_R_OPTS}${+FZF_COMPLETION_OPTS}${+FZF_COMPLETION_PATH_OPTS}${+FZF_COMPLETION_DIR_OPTS} zoxide=${+_ZO_FZF_OPTS} selected-bg=$selected_bg"
print -r -- "generated=${+functions[fzf-file-widget]}${+functions[fzf-cd-widget]}${+functions[fzf-history-widget]}${+functions[__fzf_comprun]}${+functions[_fzf_complete]}"
print -r -- "defined=${+functions[fkill]}${+functions[fbr]}${+functions[zhelp]}${+functions[npkg]}${+functions[zi]}"' > "$script_file"

  HOME="$tmp_home" \
    XDG_CACHE_HOME="$case_dir/cache" \
    PATH="$case_dir/bin" \
    NO_COLOR= \
    TERM=xterm-256color \
    COLORTERM=truecolor \
    FZF_TEST_LOG="$log_file" \
    FZF_TEST_WIDGET_LOG="$widget_log" \
    "$zsh_bin" -dfi "$script_file" >"$stdout_file" 2>"$stderr_file"
  typeset -g FZF_CASE_STATUS=$?
  typeset -g FZF_CASE_STDOUT="$(file_contents "$stdout_file")"
  typeset -g FZF_CASE_STDERR="$(file_contents "$stderr_file")"
  typeset -g FZF_CASE_LOG="$(file_contents "$log_file")"
  typeset -g FZF_CASE_DIR=$case_dir
}

test_glob_policy() {
  local fixture_dir="$tmp_home/glob-fixture"
  local fakebin="$tmp_home/glob-fakebin"
  local glob_log="$tmp_home/glob-stub.log"
  local ordinary_file="$tmp_home/glob-ordinary.out"
  local recursive_file="$tmp_home/glob-recursive.out"
  local explicit_file="$tmp_home/glob-explicit.out"
  local stdout_file="$tmp_home/glob.stdout"
  local stderr_file="$tmp_home/glob.stderr"
  local cmd_status output

  command mkdir -p -- "$fixture_dir/.git" "$fixture_dir/tree" "$fakebin" || return 1
  : > "$fixture_dir/visible"
  : > "$fixture_dir/.hidden"
  : > "$fixture_dir/.git/config"
  : > "$fixture_dir/tree/child"

  print -r -- '#!/bin/sh
printf "%s\n" "$@" > "$GLOB_STUB_LOG"' > "$fakebin/rm"
  command chmod +x "$fakebin/rm"

  HOME="$tmp_home" \
    PATH="$fakebin:$PATH" \
    GLOB_FIXTURE_DIR="$fixture_dir" \
    GLOB_ORDINARY_FILE="$ordinary_file" \
    GLOB_RECURSIVE_FILE="$recursive_file" \
    GLOB_EXPLICIT_FILE="$explicit_file" \
    GLOB_STUB_LOG="$glob_log" \
    zsh -fc '
      setopt GLOB_DOTS
      source "$HOME/.config/zsh/init.zsh"
      cd "$GLOB_FIXTURE_DIR" || exit 1
      print -rl -- * > "$GLOB_ORDINARY_FILE"
      print -rl -- **/* > "$GLOB_RECURSIVE_FILE"
      print -rl -- *(D) > "$GLOB_EXPLICIT_FILE"
      eval "rm -rf *"
    ' >"$stdout_file" 2>"$stderr_file"
  cmd_status=$?

  assert_status "$cmd_status" 0 'glob policy fixture exits cleanly' || {
    command cat "$stderr_file" >&2
    return 1
  }
  assert_no_output "$stdout_file" 'glob policy fixture keeps stdout clean' || return 1
  assert_no_output "$stderr_file" 'glob policy fixture keeps stderr clean' || return 1

  output=$(<"$ordinary_file")
  assert_equals "$output" $'tree\nvisible' 'ordinary glob excludes hidden entries after an inherited GLOB_DOTS setting' || return 1

  output=$(<"$recursive_file")
  assert_equals "$output" $'tree\ntree/child\nvisible' 'recursive ordinary glob excludes hidden entries' || return 1

  output=$(<"$explicit_file")
  assert_equals "$output" $'.git\n.hidden\ntree\nvisible' 'explicit (D) glob includes hidden entries' || return 1

  output=$(<"$glob_log")
  assert_equals "$output" $'-iv\n-rf\ntree\nvisible' 'stubbed destructive command receives visible matches only' || return 1

  [[ -e "$fixture_dir/visible" && -e "$fixture_dir/.hidden" && -d "$fixture_dir/.git" ]] || {
    print -u2 -- 'not ok: destructive-command fixture never removes real files'
    return 1
  }
  print -- 'ok: destructive-command fixture never removes real files'
}

test_fzf_startup_gate() {
  local expected case_spec version version_status integration_mode found label
  local -a fields blocked_cases integration_cases supported_cases

  run_fzf_startup_case 'unused' 0 ok 0 || return 1
  expected='zsh config: fzf 0.68.0 or newer is required (found: missing). Upgrade fzf and restart the shell.'
  assert_status "$FZF_CASE_STATUS" 0 'missing fzf leaves normal interactive startup usable' || return 1
  assert_contains "$FZF_CASE_STDOUT" 'state=blocked found=missing evaluated=0' 'missing fzf records a blocked session state' || return 1
  assert_contains "$FZF_CASE_STDOUT" 'opts=0000000 zoxide=1 selected-bg=0' 'missing fzf exports no fzf integration options' || return 1
  assert_contains "$FZF_CASE_STDOUT" 'generated=00000' 'missing fzf evaluates no generated integration' || return 1
  assert_contains "$FZF_CASE_STDOUT" 'defined=11111' 'missing fzf preserves repository picker functions' || return 1
  assert_equals "$FZF_CASE_STDERR" "$expected" 'missing fzf prints exactly one normal-startup diagnostic' || return 1
  assert_equals "$FZF_CASE_LOG" '' 'missing fzf invokes no binary' || return 1
  command rm -rf -- "$FZF_CASE_DIR"

  blocked_cases=(
    'version command failure|0.68.0|7|ok|version check failed'
    'malformed version|not-a-version|0|ok|unparseable version'
    'prerelease version|0.69.0-beta|0|ok|0.69.0-beta'
    'below-minimum version|0.67.9|0|ok|0.67.9'
  )

  for case_spec in "${blocked_cases[@]}"; do
    fields=( "${(@s:|:)case_spec}" )
    label=${fields[1]}
    version=${fields[2]}
    version_status=${fields[3]}
    integration_mode=${fields[4]}
    found=${fields[5]}
    run_fzf_startup_case "$version" "$version_status" "$integration_mode" 1 || return 1
    expected="zsh config: fzf 0.68.0 or newer is required (found: ${found}). Upgrade fzf and restart the shell."

    assert_status "$FZF_CASE_STATUS" 0 "$label leaves normal interactive startup usable" || return 1
    assert_contains "$FZF_CASE_STDOUT" "state=blocked found=${found} evaluated=0" "$label records the expected block reason" || return 1
    assert_contains "$FZF_CASE_STDOUT" 'opts=0000000 zoxide=1 selected-bg=0' "$label exports no fzf integration options" || return 1
    assert_contains "$FZF_CASE_STDOUT" 'generated=00000' "$label prevents generated integration evaluation" || return 1
    assert_contains "$FZF_CASE_STDOUT" 'defined=11111' "$label preserves repository picker functions" || return 1
    assert_equals "$FZF_CASE_STDERR" "$expected" "$label prints exactly one actionable diagnostic" || return 1
    assert_matching_lines "$FZF_CASE_LOG" ':--version' 1 "$label runs one version probe" || return 1
    assert_not_contains "$FZF_CASE_LOG" ':--zsh' "$label never requests generated integration" || return 1
    command rm -rf -- "$FZF_CASE_DIR"
  done

  integration_cases=(
    'failed integration|fail|integration generation failed'
    'empty integration|empty|empty integration output'
    'invalid integration|invalid|invalid integration output'
    'failing integration initialization|runtime-fail|integration initialization failed'
  )

  for case_spec in "${integration_cases[@]}"; do
    fields=( "${(@s:|:)case_spec}" )
    label=${fields[1]}
    integration_mode=${fields[2]}
    found=${fields[3]}
    run_fzf_startup_case 0.68.0 0 "$integration_mode" 1 || return 1
    expected="zsh config: fzf 0.68.0 or newer is required (found: ${found}). Upgrade fzf and restart the shell."

    assert_status "$FZF_CASE_STATUS" 0 "$label leaves unrelated shell config usable" || return 1
    assert_contains "$FZF_CASE_STDOUT" "state=blocked found=${found} evaluated=0" "$label hard-blocks the fuzzy subsystem" || return 1
    assert_contains "$FZF_CASE_STDOUT" 'opts=0000000 zoxide=1 selected-bg=0' "$label exports no fzf integration options" || return 1
    assert_contains "$FZF_CASE_STDOUT" 'generated=00000' "$label does not partially initialize generated features" || return 1
    assert_contains "$FZF_CASE_STDOUT" 'defined=11111' "$label preserves repository picker functions" || return 1
    assert_equals "$FZF_CASE_STDERR" "$expected" "$label prints exactly one actionable diagnostic" || return 1
    assert_matching_lines "$FZF_CASE_LOG" ':--version' 1 "$label runs one version probe" || return 1
    assert_matching_lines "$FZF_CASE_LOG" ':--zsh' 1 "$label captures one integration attempt" || return 1
    command rm -rf -- "$FZF_CASE_DIR"
  done

  supported_cases=(
    'inclusive boundary|0.68.0'
    'omitted patch boundary|0.68'
    'newer minor|0.80.2'
    'newer major|1.0.0'
  )

  for case_spec in "${supported_cases[@]}"; do
    fields=( "${(@s:|:)case_spec}" )
    label=${fields[1]}
    version=${fields[2]}
    run_fzf_startup_case "$version" 0 ok 1 || return 1

    assert_status "$FZF_CASE_STATUS" 0 "$label initializes successfully" || return 1
    assert_contains "$FZF_CASE_STDOUT" "state=ready found=${version} evaluated=1" "$label records a ready session and evaluates integration" || return 1
    assert_contains "$FZF_CASE_STDOUT" 'opts=1111111 zoxide=1 selected-bg=1' "$label retains global, widget, completion, and zoxide options" || return 1
    assert_contains "$FZF_CASE_STDOUT" 'generated=11111' "$label retains generated widgets and completion" || return 1
    assert_contains "$FZF_CASE_STDOUT" 'defined=11111' "$label retains every repository picker function" || return 1
    assert_equals "$FZF_CASE_STDERR" '' "$label startup stays quiet" || return 1
    assert_matching_lines "$FZF_CASE_LOG" ':--version' 1 "$label runs one version probe" || return 1
    assert_matching_lines "$FZF_CASE_LOG" ':--zsh' 1 "$label requests generated integration once" || return 1
    command rm -rf -- "$FZF_CASE_DIR"
  done
}

test_fzf_persistent_startup_cache() {
  local case_dir cache_root script_file stdout_file stderr_file log_file process_log
  local output cmd_status phase cache_file
  local -a cache_files

  case_dir=$(mktemp -d "$tmp_home/fzf-persistent-cache.XXXXXX") || return 1
  cache_root="$case_dir/cache"
  script_file="$case_dir/startup.zsh"
  stdout_file="$case_dir/stdout"
  stderr_file="$case_dir/stderr"
  log_file="$case_dir/fzf.log"
  process_log="$case_dir/process.log"
  : > "$log_file"
  : > "$process_log"

  prepare_fzf_fakebin "$case_dir/bin" 0.70.0 0 ok 1 || return 1
  command rm -f -- "$case_dir/bin/zsh"
  print -r -- '#!/bin/sh
printf "zsh:%s\n" "$*" >> "${FZF_TEST_PROCESS_LOG:-/dev/null}"
exec "$FZF_TEST_REAL_ZSH" "$@"' > "$case_dir/bin/zsh"
  command chmod +x "$case_dir/bin/zsh"

  print -r -- 'source "$HOME/.config/zsh/init.zsh"
print -r -- "state=$_FZF_STATE found=$_FZF_FOUND evaluated=${FZF_TEST_EVALUATED:-0} opts=${+FZF_DEFAULT_OPTS}"' > "$script_file"

  for phase in cold warm; do
    HOME="$tmp_home" \
      XDG_CACHE_HOME="$cache_root" \
      PATH="$case_dir/bin" \
      FZF_TEST_LOG="$log_file" \
      FZF_TEST_PROCESS_LOG="$process_log" \
      FZF_TEST_REAL_ZSH="$zsh_bin" \
      "$zsh_bin" -dfi "$script_file" >"$stdout_file" 2>"$stderr_file"
    cmd_status=$?
    output=$(file_contents "$stdout_file")

    assert_status "$cmd_status" 0 "$phase persistent-cache startup exits cleanly" || return 1
    assert_contains "$output" 'state=ready found=0.70.0 evaluated=1 opts=1' "$phase persistent-cache startup retains the full integration" || return 1
    assert_no_output "$stderr_file" "$phase persistent-cache startup stays quiet" || return 1
  done

  assert_matching_lines "$(file_contents "$log_file")" ':--version' 1 'warm startup reuses the cached version result' || return 1
  assert_matching_lines "$(file_contents "$log_file")" ':--zsh' 1 'warm startup does not regenerate fzf integration' || return 1
  assert_matching_lines "$(file_contents "$process_log")" 'zsh:-fn ' 1 'warm startup does not repeat syntax validation' || return 1

  cache_files=( "$cache_root"/zsh/fzf/integration-*.zsh(N) )
  assert_equals "${#cache_files[@]}" 1 'cold startup creates one persistent integration cache file' || return 1
  cache_file=${cache_files[1]}

  command chmod 666 -- "$cache_file"
  HOME="$tmp_home" \
    XDG_CACHE_HOME="$cache_root" \
    PATH="$case_dir/bin" \
    FZF_TEST_LOG="$log_file" \
    FZF_TEST_PROCESS_LOG="$process_log" \
    FZF_TEST_REAL_ZSH="$zsh_bin" \
    "$zsh_bin" -dfi "$script_file" >"$stdout_file" 2>"$stderr_file"
  cmd_status=$?
  output=$(file_contents "$stdout_file")
  assert_status "$cmd_status" 0 'unsafe persistent cache is replaced cleanly' || return 1
  assert_contains "$output" 'state=ready found=0.70.0 evaluated=1 opts=1' 'unsafe cache replacement retains the full integration' || return 1
  assert_no_output "$stderr_file" 'unsafe persistent cache replacement stays quiet' || return 1
  assert_matching_lines "$(file_contents "$log_file")" ':--version' 2 'group-writable cache forces version revalidation' || return 1
  assert_matching_lines "$(file_contents "$log_file")" ':--zsh' 2 'group-writable cache forces integration regeneration' || return 1

  print -r -- '# changed binary identity' >> "$case_dir/bin/fzf"
  HOME="$tmp_home" \
    XDG_CACHE_HOME="$cache_root" \
    PATH="$case_dir/bin" \
    FZF_TEST_LOG="$log_file" \
    FZF_TEST_PROCESS_LOG="$process_log" \
    FZF_TEST_REAL_ZSH="$zsh_bin" \
    "$zsh_bin" -dfi "$script_file" >"$stdout_file" 2>"$stderr_file"
  cmd_status=$?
  output=$(file_contents "$stdout_file")
  assert_status "$cmd_status" 0 'changed fzf binary rebuilds the persistent cache cleanly' || return 1
  assert_contains "$output" 'state=ready found=0.70.0 evaluated=1 opts=1' 'changed binary cache rebuild retains the full integration' || return 1
  assert_no_output "$stderr_file" 'changed fzf binary cache rebuild stays quiet' || return 1
  assert_matching_lines "$(file_contents "$log_file")" ':--version' 3 'changed fzf binary invalidates the cached version result' || return 1
  assert_matching_lines "$(file_contents "$log_file")" ':--zsh' 3 'changed fzf binary invalidates generated integration' || return 1
  assert_matching_lines "$(file_contents "$process_log")" 'zsh:-fn ' 3 'only cold and invalidated caches receive syntax validation' || return 1

  command rm -rf -- "$case_dir"
}

test_fzf_quiet_startup_modes() {
  local case_dir stdout_file stderr_file log_file cmd_status

  case_dir=$(mktemp -d "$tmp_home/fzf-quiet.XXXXXX") || return 1
  prepare_fzf_fakebin "$case_dir/bin" 0.67.9 0 ok 1 || return 1
  stdout_file="$case_dir/stdout"
  stderr_file="$case_dir/stderr"
  log_file="$case_dir/fzf.log"

  : > "$log_file"
  HOME="$tmp_home" PATH="$case_dir/bin" FZF_TEST_LOG="$log_file" \
    "$zsh_bin" -dfc 'source "$HOME/.config/zsh/init.zsh"' >"$stdout_file" 2>"$stderr_file"
  cmd_status=$?
  assert_status "$cmd_status" 0 'non-interactive fzf-blocked sourcing exits cleanly' || return 1
  assert_no_output "$stdout_file" 'non-interactive fzf-blocked sourcing keeps stdout clean' || return 1
  assert_no_output "$stderr_file" 'non-interactive fzf-blocked sourcing keeps stderr clean' || return 1
  assert_equals "$(file_contents "$log_file")" '' 'non-interactive sourcing does not inspect fzf' || return 1

  : > "$log_file"
  HOME="$tmp_home" PATH="$case_dir/bin" FZF_TEST_LOG="$log_file" \
    "$zsh_bin" -dfic 'source "$HOME/.config/zsh/init.zsh"' >"$stdout_file" 2>"$stderr_file"
  cmd_status=$?
  assert_status "$cmd_status" 0 'zsh -i -c fzf-blocked sourcing exits cleanly' || return 1
  assert_no_output "$stdout_file" 'zsh -i -c fzf-blocked sourcing keeps stdout clean' || return 1
  assert_no_output "$stderr_file" 'zsh -i -c fzf-blocked sourcing keeps stderr and ZLE warnings clean' || return 1
  assert_equals "$(file_contents "$log_file")" '' 'zsh -i -c does not inspect or initialize fzf' || return 1

  command rm -rf -- "$case_dir"
}

test_fzf_runtime_guards() {
  local case_dir script_file stdout_file stderr_file log_file widget_log
  local explicit_plain automatic_plain output diagnostics cmd_status

  case_dir=$(mktemp -d "$tmp_home/fzf-runtime.XXXXXX") || return 1
  prepare_fzf_fakebin "$case_dir/bin" 0.67.9 0 ok 1 || return 1
  script_file="$case_dir/runtime.zsh"
  stdout_file="$case_dir/stdout"
  stderr_file="$case_dir/stderr"
  log_file="$case_dir/fzf.log"
  widget_log="$case_dir/widget.log"
  explicit_plain="$case_dir/explicit-plain"
  automatic_plain="$case_dir/automatic-plain"
  : > "$log_file"
  : > "$widget_log"

  print -r -- 'unset FZF_DEFAULT_OPTS FZF_CTRL_T_OPTS FZF_ALT_C_OPTS FZF_CTRL_R_OPTS
source "$HOME/.config/zsh/init.zsh"
zhelp --plain --all > "$FZF_TEST_EXPLICIT_PLAIN"
explicit_rc=$?
TERM=dumb zhelp --all > "$FZF_TEST_AUTOMATIC_PLAIN"
automatic_rc=$?
print -r -- plain-finished >> "$FZF_TEST_LOG"
fkill >/dev/null
fkill_rc=$?
fbr >/dev/null
fbr_rc=$?
_npkg_require_picker install >/dev/null
npkg_rc=$?
_zsh_help_palette "" 1 >/dev/null
help_rc=$?
zi >/dev/null
zi_rc=$?
print -r -- "plain=$explicit_rc,$automatic_rc guarded=$fkill_rc,$fbr_rc,$npkg_rc,$help_rc,$zi_rc opts=${+FZF_DEFAULT_OPTS}"' > "$script_file"

  HOME="$tmp_home" \
    PATH="$case_dir/bin" \
    FZF_TEST_LOG="$log_file" \
    FZF_TEST_WIDGET_LOG="$widget_log" \
    FZF_TEST_EXPLICIT_PLAIN="$explicit_plain" \
    FZF_TEST_AUTOMATIC_PLAIN="$automatic_plain" \
    "$zsh_bin" -dfc 'source "$1"' zsh "$script_file" >"$stdout_file" 2>"$stderr_file"
  cmd_status=$?
  output=$(file_contents "$stdout_file")
  diagnostics=$(file_contents "$stderr_file")

  assert_status "$cmd_status" 0 'blocked runtime guard fixture completes' || return 1
  assert_contains "$output" 'plain=0,0 guarded=1,1,1,1,1 opts=0' 'plain modes work while every direct fuzzy entry point fails closed' || return 1
  assert_contains "$(file_contents "$explicit_plain")" 'Command        Category' 'zhelp --plain works without invoking blocked fzf' || return 1
  assert_contains "$(file_contents "$automatic_plain")" 'Command        Category' 'zhelp automatic plain mode works without invoking blocked fzf' || return 1
  assert_matching_lines "$diagnostics" 'zsh config: fzf 0.68.0 or newer is required (found: 0.67.9).' 5 'every blocked explicit picker reports the shared diagnostic' || return 1
  assert_equals "$(file_contents "$log_file")" $'plain-finished\n'"$case_dir/bin/fzf:--version" 'plain help never probes fzf and guarded pickers share one cached version probe' || return 1
  assert_equals "$(file_contents "$widget_log")" '' 'blocked direct entry points never reach a picker implementation' || return 1

  command rm -rf -- "$case_dir"
}

test_fzf_path_cache() {
  local case_dir ready_bin blocked_bin script_file stdout_file stderr_file log_file output diagnostics cmd_status

  case_dir=$(mktemp -d "$tmp_home/fzf-cache.XXXXXX") || return 1
  ready_bin="$case_dir/ready-bin"
  blocked_bin="$case_dir/blocked-bin"
  prepare_fzf_fakebin "$ready_bin" 0.68.0 0 ok 1 || return 1
  prepare_fzf_fakebin "$blocked_bin" 0.67.9 0 ok 1 || return 1
  script_file="$case_dir/cache.zsh"
  stdout_file="$case_dir/stdout"
  stderr_file="$case_dir/stderr"
  log_file="$case_dir/fzf.log"
  : > "$log_file"

  print -r -- 'source "$HOME/.config/zsh/init.zsh"
_fzf_require_ready; ready_one=$?
_fzf_require_ready; ready_two=$?
PATH="$FZF_TEST_BLOCKED_BIN"
_fzf_require_ready; blocked_one=$?
_fzf_require_ready; blocked_two=$?
PATH="$FZF_TEST_READY_BIN"
_fzf_require_ready; ready_again=$?
print -r -- "states=$ready_one,$ready_two,$blocked_one,$blocked_two,$ready_again final=$_FZF_STATE found=$_FZF_FOUND"' > "$script_file"

  HOME="$tmp_home" \
    XDG_CACHE_HOME="$case_dir/cache" \
    PATH="$ready_bin" \
    FZF_TEST_READY_BIN="$ready_bin" \
    FZF_TEST_BLOCKED_BIN="$blocked_bin" \
    FZF_TEST_LOG="$log_file" \
    "$zsh_bin" -dfc 'source "$1"' zsh "$script_file" >"$stdout_file" 2>"$stderr_file"
  cmd_status=$?
  output=$(file_contents "$stdout_file")
  diagnostics=$(file_contents "$stderr_file")

  assert_status "$cmd_status" 0 'path-keyed fzf cache fixture completes' || return 1
  assert_contains "$output" 'states=0,0,1,1,0 final=ready found=0.68.0' 'PATH changes validate a new binary and reuse each path result' || return 1
  assert_matching_lines "$(file_contents "$log_file")" ':--version' 2 'each resolved fzf path is version-probed exactly once' || return 1
  assert_matching_lines "$(file_contents "$log_file")" "$ready_bin/fzf:--version" 1 'supported path result is reused after switching back' || return 1
  assert_matching_lines "$(file_contents "$log_file")" "$blocked_bin/fzf:--version" 1 'blocked path result is cached after its first probe' || return 1
  assert_matching_lines "$diagnostics" 'found: 0.67.9' 2 'blocked calls can reuse the cached actionable diagnostic' || return 1

  command rm -rf -- "$case_dir"
}

test_fzf_generated_guards() {
  local case_dir ready_bin blocked_bin script_file stdout_file stderr_file log_file widget_log
  local output diagnostics cmd_status

  case_dir=$(mktemp -d "$tmp_home/fzf-generated.XXXXXX") || return 1
  ready_bin="$case_dir/ready-bin"
  blocked_bin="$case_dir/blocked-bin"
  prepare_fzf_fakebin "$ready_bin" 0.68.0 0 ok 1 || return 1
  prepare_fzf_fakebin "$blocked_bin" 0.67.9 0 ok 1 || return 1
  script_file="$case_dir/generated.zsh"
  stdout_file="$case_dir/stdout"
  stderr_file="$case_dir/stderr"
  log_file="$case_dir/fzf.log"
  widget_log="$case_dir/widget.log"
  : > "$log_file"
  : > "$widget_log"

  print -r -- 'source "$HOME/.config/zsh/init.zsh"
PATH="$FZF_TEST_BLOCKED_BIN"
fzf-file-widget; file_rc=$?
fzf-cd-widget; cd_rc=$?
fzf-history-widget; history_rc=$?
__fzf_comprun test; completion_rc=$?
print -r -- "generated-guards=$file_rc,$cd_rc,$history_rc,$completion_rc"' > "$script_file"

  HOME="$tmp_home" \
    XDG_CACHE_HOME="$case_dir/cache" \
    PATH="$ready_bin" \
    FZF_TEST_BLOCKED_BIN="$blocked_bin" \
    FZF_TEST_LOG="$log_file" \
    FZF_TEST_WIDGET_LOG="$widget_log" \
    "$zsh_bin" -dfi "$script_file" >"$stdout_file" 2>"$stderr_file"
  cmd_status=$?
  output=$(file_contents "$stdout_file")
  diagnostics=$(file_contents "$stderr_file")

  assert_status "$cmd_status" 0 'generated entry-point guard fixture completes' || return 1
  assert_contains "$output" 'generated-guards=1,1,1,1' 'generated keybinding and completion paths fail before a blocked picker' || return 1
  assert_equals "$(file_contents "$widget_log")" '' 'blocked generated paths never reach their generated implementations' || return 1
  assert_matching_lines "$(file_contents "$log_file")" "$ready_bin/fzf:--version" 1 'generated integration starts from one supported version check' || return 1
  assert_matching_lines "$(file_contents "$log_file")" "$ready_bin/fzf:--zsh" 1 'supported startup retains generated integration' || return 1
  assert_matching_lines "$(file_contents "$log_file")" "$blocked_bin/fzf:--version" 1 'generated entry points validate a replacement PATH binary once' || return 1
  assert_not_contains "$(file_contents "$log_file")" 'picker:' 'generated entry points never launch the blocked picker' || return 1
  assert_matching_lines "$diagnostics" 'found: 0.67.9' 4 'each generated blocked invocation returns the shared diagnostic' || return 1

  command rm -rf -- "$case_dir"
}

test_fzf_theme_option_refresh() {
  local case_dir script_file stdout_file stderr_file log_file widget_log
  local output diagnostics cmd_status

  case_dir=$(mktemp -d "$tmp_home/fzf-theme-options.XXXXXX") || return 1
  script_file="$case_dir/options.zsh"
  stdout_file="$case_dir/stdout"
  stderr_file="$case_dir/stderr"
  log_file="$case_dir/fzf.log"
  widget_log="$case_dir/widget.log"
  : > "$log_file"
  : > "$widget_log"
  prepare_fzf_fakebin "$case_dir/bin" 0.70.0 0 ok 1 || return 1

  print -r -- 'export FZF_DEFAULT_OPTS="--user-default"
export FZF_CTRL_T_OPTS="--user-files"
export FZF_CTRL_R_OPTS="--user-history"
export FZF_ALT_C_OPTS="--user-dirs"
export FZF_COMPLETION_OPTS="--user-completion"
export FZF_COMPLETION_PATH_OPTS="--user-paths"
export FZF_COMPLETION_DIR_OPTS="--user-dir-completion"
export _ZO_FZF_OPTS="--user-zoxide"
typeset -g ZSH_FZF_EXTRA_OPTS="--tabstop=4"
source "$HOME/.config/zsh/init.zsh"

structured=0
[[ $FZF_DEFAULT_OPTS == *--style=default* && $FZF_DEFAULT_OPTS == *--border=rounded* && $FZF_DEFAULT_OPTS == *--input-border=bottom* && $FZF_DEFAULT_OPTS == *--footer-border=top* && $FZF_DEFAULT_OPTS == *current-bg* && $FZF_DEFAULT_OPTS == *footer-border* ]] && structured=1
contexts=0
[[ $FZF_CTRL_T_OPTS == *Files* && $FZF_CTRL_R_OPTS == *History* && $FZF_ALT_C_OPTS == *Directories* ]] && contexts=1
completion=0
[[ $FZF_COMPLETION_OPTS == *Completions* && $FZF_COMPLETION_PATH_OPTS == *Paths* && $FZF_COMPLETION_DIR_OPTS == *Directories* ]] && completion=1
preserved=0
[[ $FZF_DEFAULT_OPTS == *--user-default* && $FZF_DEFAULT_OPTS == *--tabstop=4* && $FZF_CTRL_T_OPTS == *--user-files* && $FZF_COMPLETION_PATH_OPTS == *--user-paths* && $_ZO_FZF_OPTS == *--user-zoxide* ]] && preserved=1

first_default=$FZF_DEFAULT_OPTS
ZSH_UI_THEME=nord
ZSH_FZF_LAYOUT=roomy
_zsh_theme_resolve_settings
_fzf_require_ready
refreshed=0
[[ $FZF_DEFAULT_OPTS != "$first_default" && $FZF_DEFAULT_OPTS == *--style=default* && $FZF_DEFAULT_OPTS == *--padding=1,2* && $FZF_DEFAULT_OPTS == *b48ead* ]] && refreshed=1

typeset -gA ZSH_UI_CUSTOM_COLORS
for role in "${_ZSH_UI_THEME_ROLES[@]}"; do
  ZSH_UI_CUSTOM_COLORS[$role]=101010
done
ZSH_UI_CUSTOM_COLORS[accent]=abcdef
ZSH_UI_THEME=custom
ZSH_FZF_LAYOUT=compact
_zsh_theme_resolve_settings
_fzf_require_ready
first_custom=$FZF_DEFAULT_OPTS
ZSH_UI_CUSTOM_COLORS[accent]=112233
_zsh_theme_resolve_settings
_fzf_require_ready
custom_refreshed=0
[[ $FZF_DEFAULT_OPTS != "$first_custom" && $FZF_DEFAULT_OPTS == *112233* && $_ZO_FZF_OPTS == *112233* ]] && custom_refreshed=1

NO_COLOR=1
_fzf_require_ready
nocolor=0
[[ $FZF_DEFAULT_OPTS == *--no-color && $FZF_CTRL_T_OPTS == *--no-color && $FZF_CTRL_R_OPTS == *--no-color && $FZF_ALT_C_OPTS == *--no-color && $FZF_COMPLETION_OPTS == *--no-color && $FZF_COMPLETION_PATH_OPTS == *--no-color && $FZF_COMPLETION_DIR_OPTS == *--no-color && $_ZO_FZF_OPTS == *--no-color ]] && nocolor=1
preview_plain=0
[[ $FZF_CTRL_T_OPTS == *--color=never* && $FZF_CTRL_T_OPTS != *--color=always* ]] && preview_plain=1

source "$HOME/.config/zsh/40-fzf.zsh"
duplicates=0
[[ $FZF_DEFAULT_OPTS == *--user-default*--user-default* || $FZF_COMPLETION_PATH_OPTS == *--user-paths*--user-paths* || $_ZO_FZF_OPTS == *--user-zoxide*--user-zoxide* ]] && duplicates=1
print -r -- "structured=$structured contexts=$contexts completion=$completion preserved=$preserved refreshed=$refreshed custom_refreshed=$custom_refreshed nocolor=$nocolor preview_plain=$preview_plain duplicates=$duplicates"' > "$script_file"

  HOME="$tmp_home" \
    XDG_CACHE_HOME="$case_dir/cache" \
    PATH="$case_dir/bin" \
    NO_COLOR= \
    TERM=xterm-256color \
    COLORTERM=truecolor \
    FZF_TEST_LOG="$log_file" \
    FZF_TEST_WIDGET_LOG="$widget_log" \
    "$zsh_bin" -dfi "$script_file" >"$stdout_file" 2>"$stderr_file"
  cmd_status=$?
  output=$(file_contents "$stdout_file")
  diagnostics=$(file_contents "$stderr_file")

  assert_status "$cmd_status" 0 'theme-aware fzf option fixture completes' || return 1
  assert_equals "$output" 'structured=1 contexts=1 completion=1 preserved=1 refreshed=1 custom_refreshed=1 nocolor=1 preview_plain=1 duplicates=0' 'fzf options refresh by signature while preserving each user layer once' || return 1
  assert_equals "$diagnostics" '' 'theme-aware fzf option refresh stays quiet' || return 1
  assert_matching_lines "$(file_contents "$log_file")" ':--version' 1 'theme/layout/no-color refresh does not repeat version validation' || return 1
  assert_matching_lines "$(file_contents "$log_file")" ':--zsh' 1 'theme/layout/no-color refresh does not regenerate integration' || return 1

  command rm -rf -- "$case_dir"
}

prepare_dependency_fakebin() {
  local fakebin=$1
  local version=$2
  local version_status=$3
  local include_fzf=$4
  local tool

  prepare_fzf_fakebin "$fakebin" "$version" "$version_status" ok "$include_fzf" || return 1
  for tool in git curl ss lsd; do
    print -r -- '#!/bin/sh
exit 0' > "$fakebin/$tool"
    command chmod +x "$fakebin/$tool"
  done
}

run_dependency_case() {
  local version=$1
  local version_status=$2
  local include_fzf=$3
  local case_dir output_file

  case_dir=$(mktemp -d "$tmp_home/fzf-deps.XXXXXX") || return 1
  output_file="$case_dir/output"
  prepare_dependency_fakebin "$case_dir/bin" "$version" "$version_status" "$include_fzf" || return 1
  PATH="$case_dir/bin" /bin/sh "$repo_dir/scripts/check-deps.sh" > "$output_file" 2>&1
  typeset -g FZF_DEP_STATUS=$?
  typeset -g FZF_DEP_OUTPUT="$(file_contents "$output_file")"
  typeset -g FZF_DEP_DIR=$case_dir
}

test_fzf_dependency_checker() {
  local case_spec label version version_status include_fzf expected
  local -a fields blocked_cases supported_cases

  blocked_cases=(
    'missing|unused|0|0|missing required: fzf (minimum 0.68.0)'
    'version failure|0.68.0|7|1|unsupported required: fzf version check failed (minimum 0.68.0)'
    'malformed|not-a-version|0|1|unsupported required: fzf has an unparseable version (minimum 0.68.0)'
    'prerelease|0.69.0-beta|0|1|unsupported required: fzf 0.69.0-beta is a prerelease (minimum 0.68.0)'
    'below minimum|0.67.9|0|1|unsupported required: fzf 0.67.9 (minimum 0.68.0)'
  )

  for case_spec in "${blocked_cases[@]}"; do
    fields=( "${(@s:|:)case_spec}" )
    label=${fields[1]}
    version=${fields[2]}
    version_status=${fields[3]}
    include_fzf=${fields[4]}
    expected=${fields[5]}
    run_dependency_case "$version" "$version_status" "$include_fzf" || return 1
    assert_status "$FZF_DEP_STATUS" 1 "dependency checker rejects $label fzf" || return 1
    assert_contains "$FZF_DEP_OUTPUT" "$expected" "dependency checker reports $label with the minimum" || return 1
    assert_contains "$FZF_DEP_OUTPUT" 'https://github.com/junegunn/fzf#installation' "dependency checker gives $label an upstream-compatible hint" || return 1
    command rm -rf -- "$FZF_DEP_DIR"
  done

  supported_cases=(
    'inclusive boundary|0.68.0'
    'omitted patch boundary|0.68'
    'newer minor|0.80.2'
    'newer major|1.0.0'
  )

  for case_spec in "${supported_cases[@]}"; do
    fields=( "${(@s:|:)case_spec}" )
    label=${fields[1]}
    version=${fields[2]}
    run_dependency_case "$version" 0 1 || return 1
    assert_status "$FZF_DEP_STATUS" 0 "dependency checker accepts $label fzf" || return 1
    assert_contains "$FZF_DEP_OUTPUT" "ok: fzf ${version} (minimum 0.68.0)" "dependency checker reports installed and minimum versions for $label" || return 1
    assert_contains "$FZF_DEP_OUTPUT" 'missing optional: secret-tool' "dependency checker reports optional cgm support for $label" || return 1
    command rm -rf -- "$FZF_DEP_DIR"
  done
}

test_owned_module_settings() {
  HOME="$tmp_home" "$zsh_bin" -fc '
    source "$1/10-history.zsh"
    [[ $HISTSIZE == 100000 && $SAVEHIST == 100000 && $HISTFILE == "$HOME/.zsh_history" ]] || exit 11
    [[ -o appendhistory && -o sharehistory && -o histignorealldups && -o histfindnodups ]] || exit 12
    [[ -o histignorespace && -o histreduceblanks ]] || exit 13

    source "$1/50-completion.zsh"
    local -a values
    zstyle -a ":completion:*" matcher-list values || exit 14
    [[ "${(j: :)values}" == "m:{a-zA-Z}={A-Za-z}" ]] || exit 15
    zstyle -t ":completion:*" squeeze-slashes || exit 16
    zstyle -s ":completion:*:*:*:*:processes" command process_command || exit 17
    [[ $process_command == *"ps -u"* && $process_command == *"-o pid,user,comm,cmd"* ]] || exit 18

    source "$1/70-globals.zsh"
    [[ ${(v)galiases[G]} == "| grep" ]] || exit 19
    [[ ${(v)galiases[L]} == "| less" ]] || exit 20
    [[ ${(v)galiases[NUL]} == ">/dev/null 2>&1" ]] || exit 21
  ' zsh "$repo_dir"
  assert_status "$?" 0 'history, completion, and global-alias modules retain their owned settings' || return 1
}

test_zoxide_init_outcomes() {
  local fakebin="$tmp_home/zoxide-outcomes"
  local mode stdout_file="$tmp_home/zoxide.stdout" stderr_file="$tmp_home/zoxide.stderr" output

  command mkdir -p -- "$fakebin"
  print -r -- '#!/bin/sh
case "$ZOXIDE_TEST_MODE" in
  success) printf "%s\n" "z() { :; }" "__zoxide_zi() { :; }" "zi() { __zoxide_zi \"\$@\"; }" ;;
  fail) printf "%s\n" "generation failed" >&2; exit 7 ;;
  empty) exit 0 ;;
  malformed) printf "%s\n" "if (" ;;
  runtime) printf "%s\n" "z() { :; }" "chpwd_functions+=(half-installed)" "false" ;;
esac' >"$fakebin/zoxide"
  command chmod +x -- "$fakebin/zoxide"

  for mode in success fail empty malformed runtime; do
    ZOXIDE_TEST_MODE=$mode PATH="$fakebin" "$zsh_bin" -fc '
      source "$1/25-theme.zsh"
      unset _ZO_FZF_OPTS
      precmd_functions=(kept-precmd)
      chpwd_functions=(kept-chpwd)
      source "$1/30-zoxide.zsh"
      print -r -- "z=$+functions[z] zi=$+functions[zi] precmd=${(j:,:)precmd_functions} chpwd=${(j:,:)chpwd_functions} registry=$_ZSH_THEME_REGISTRY_LOADED zo=${+_ZO_FZF_OPTS}"
    ' zsh "$repo_dir" >"$stdout_file" 2>"$stderr_file"
    assert_status "$?" 0 "zoxide $mode fixture sources deterministically" || return 1
    output=$(<"$stdout_file")
    if [[ $mode == success ]]; then
      assert_equals "$output" 'z=1 zi=1 precmd=kept-precmd chpwd=kept-chpwd registry=0 zo=0' 'successful command-mode zoxide init defers finder chrome' || return 1
    else
      assert_equals "$output" 'z=0 zi=0 precmd=kept-precmd chpwd=kept-chpwd registry=0 zo=0' "zoxide $mode leaves no partial integration" || return 1
    fi
    assert_no_output "$stderr_file" "non-interactive zoxide $mode startup stays quiet" || return 1
  done
}

main() {
  local -a high_risk_aliases
  local high_risk_alias_setup

  command mkdir -p "$tmp_home/.config" || { print -u2 -- 'fatal: mkdir failed for temp HOME'; return 1; }
  ln -s "$repo_dir" "$tmp_home/.config/zsh" || { print -u2 -- 'fatal: failed to link repo into temp HOME'; return 1; }

  high_risk_aliases=(
    'alias gcount="git shortlog --summary --numbered"'
    'alias gitcount="git shortlog --summary --numbered"'
    'alias gst="git status"'
    'alias grt="cd repo-root"'
  )
  high_risk_alias_setup=$(printf '%s\n' "${high_risk_aliases[@]}")

  run_init_case 'clean init smoke test' || return 1
  run_init_case 'high-risk alias init smoke test' "$high_risk_alias_setup" || return 1
  test_owned_module_settings || return 1
  test_zoxide_init_outcomes || return 1
  test_glob_policy || return 1
  test_fzf_startup_gate || return 1
  test_fzf_persistent_startup_cache || return 1
  test_fzf_quiet_startup_modes || return 1
  test_fzf_runtime_guards || return 1
  test_fzf_path_cache || return 1
  test_fzf_generated_guards || return 1
  test_fzf_theme_option_refresh || return 1
  test_fzf_dependency_checker || return 1
}

main "$@"
