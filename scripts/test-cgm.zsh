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

assert_exists() {
  local path=$1 label=$2

  if [[ ! -e $path ]]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "missing path: $path"
    return 1
  fi

  print -- "ok: $label"
}

assert_not_exists() {
  local path=$1 label=$2

  if [[ -e $path || -L $path ]]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "unexpected path: $path"
    return 1
  fi

  print -- "ok: $label"
}

file_contents() {
  local file=$1

  [[ -f $file ]] && print -r -- "$(<"$file")"
}

make_fake_secret_tool() {
  local fakebin=$1

  command mkdir -p -- "$fakebin"
  print -r -- '#!/bin/sh
set -u

action=${1-}
[ "$#" -gt 0 ] && shift

{
  printf "%s" "$action"
  for argument in "$@"; do
    printf "\t%s" "$argument"
  done
  printf "\n"
} >> "$CGM_TEST_LOG"

credential_name=
for argument in "$@"; do
  credential_name=$argument
done

case $action in
  store)
    [ "${CGM_TEST_FAIL_STORE_NAME:-}" != "$credential_name" ] || exit 9
    printf "%s" "${CGM_TEST_STORE_VALUE-}" > "$CGM_TEST_BACKEND_DIR/$credential_name"
    ;;
  lookup)
    [ "${CGM_TEST_FAIL_LOOKUP_NAME:-}" != "$credential_name" ] || exit 7
    [ -f "$CGM_TEST_BACKEND_DIR/$credential_name" ] || exit 1
    cat "$CGM_TEST_BACKEND_DIR/$credential_name"
    ;;
  clear)
    [ "${CGM_TEST_FAIL_CLEAR_NAME:-}" != "$credential_name" ] || exit 8
    rm -f -- "$CGM_TEST_BACKEND_DIR/$credential_name"
    ;;
  *)
    exit 2
    ;;
esac' > "$fakebin/secret-tool"
  command chmod +x "$fakebin/secret-tool"
}

start_case() {
  local case_name=$1

  XDG_DATA_HOME="$tmp_dir/$case_name/data"
  CGM_TEST_BACKEND_DIR="$tmp_dir/$case_name/backend"
  CGM_TEST_LOG="$tmp_dir/$case_name/secret-tool.log"
  command mkdir -p -- "$CGM_TEST_BACKEND_DIR"
  : > "$CGM_TEST_LOG"
  export XDG_DATA_HOME CGM_TEST_BACKEND_DIR CGM_TEST_LOG
  unset CGM_TEST_FAIL_STORE_NAME CGM_TEST_FAIL_LOOKUP_NAME CGM_TEST_FAIL_CLEAR_NAME CGM_TEST_STORE_VALUE
}

test_startup_gate() {
  local gate_home="$tmp_dir/gate-home"
  local missing_bin="$tmp_dir/gate-missing-bin"
  local present_bin="$tmp_dir/gate-present-bin"
  local invocation_log="$tmp_dir/gate-secret-tool.log"
  local output stderr_file rc

  command mkdir -p -- "$gate_home/.config" "$missing_bin" "$present_bin"
  command ln -s -- "$repo_dir" "$gate_home/.config/zsh"

  output=$(HOME="$gate_home" PATH="$missing_bin" "$zsh_bin" -dfc '
    source "$HOME/.config/zsh/init.zsh"
    print -r -- "${+functions[cgm]}:${+functions[_cgm_usage]}"
  ')
  rc=$?
  assert_status "$rc" 0 'init succeeds without secret-tool' || return 1
  assert_equals "$output" '0:0' 'init skips the entire CGM module without secret-tool' || return 1

  print -r -- '#!/bin/sh
printf "%s\n" invoked >> "$CGM_GATE_LOG"
exit 99' > "$present_bin/secret-tool"
  command chmod +x "$present_bin/secret-tool"
  : > "$invocation_log"
  stderr_file="$tmp_dir/gate.stderr"

  output=$(HOME="$gate_home" PATH="$present_bin" CGM_GATE_LOG="$invocation_log" \
    "$zsh_bin" -dfc '
      source "$HOME/.config/zsh/init.zsh"
      print -r -- "${+functions[cgm]}:${+functions[_cgm_usage]}"
    ' 2>"$stderr_file")
  rc=$?
  assert_status "$rc" 0 'init succeeds with secret-tool present' || return 1
  assert_equals "$output" '1:1' 'init loads the complete CGM module when secret-tool is present' || return 1
  assert_equals "$(file_contents "$invocation_log")" '' 'CGM startup never invokes secret-tool' || return 1
  assert_equals "$(file_contents "$stderr_file")" '' 'CGM startup stays quiet' || return 1
}

test_set_and_catalogue() {
  local secret='set-secret-value'
  local output_file="$tmp_dir/set.stdout"
  local error_file="$tmp_dir/set.stderr"
  local marker root output log rc

  start_case set
  CGM_TEST_STORE_VALUE=$secret
  export CGM_TEST_STORE_VALUE
  cgm set OPENAI_KEY >"$output_file" 2>"$error_file"
  rc=$?

  marker="$XDG_DATA_HOME/cgm/entries/OPENAI_KEY"
  root="$XDG_DATA_HOME/cgm"
  output=$(file_contents "$output_file")
  log=$(file_contents "$CGM_TEST_LOG")
  assert_status "$rc" 0 'set stores a valid credential' || {
    command cat -- "$error_file" >&2
    return 1
  }
  assert_contains "$output" 'Saved OPENAI_KEY.' 'set confirms only the credential name' || return 1
  assert_not_contains "$output" "$secret" 'set stdout never contains the credential value' || return 1
  assert_not_contains "$(file_contents "$error_file")" "$secret" 'set stderr never contains the credential value' || return 1
  assert_not_contains "$log" "$secret" 'set never passes the credential value as a command argument' || return 1
  assert_contains "$log" $'store\t--label=cgm: OPENAI_KEY\tapplication\tcgm\tvariable\tOPENAI_KEY' 'set uses the isolated CGM Secret Service attributes' || return 1
  assert_equals "$(file_contents "$CGM_TEST_BACKEND_DIR/OPENAI_KEY")" "$secret" 'the fake backend receives the credential through its secure input channel' || return 1
  assert_exists "$marker" 'set creates a name-only catalogue marker' || return 1
  assert_equals "$(command stat -c '%a' "$root")" 700 'catalogue root is private' || return 1
  assert_equals "$(command stat -c '%a' "$XDG_DATA_HOME/cgm/entries")" 700 'catalogue entries directory is private' || return 1
  assert_equals "$(command stat -c '%a' "$marker")" 600 'catalogue marker is private' || return 1
  assert_equals "$(file_contents "$marker")" '' 'catalogue marker stores no secret data' || return 1

  : > "$CGM_TEST_LOG"
  cgm list >"$output_file" 2>"$error_file"
  assert_status "$?" 0 'list succeeds with saved credentials' || return 1
  assert_equals "$(file_contents "$output_file")" 'OPENAI_KEY' 'plain list prints names only' || return 1
  assert_equals "$(file_contents "$CGM_TEST_LOG")" '' 'list never invokes secret-tool' || return 1
  assert_not_contains "$(file_contents "$output_file")" "$secret" 'list never prints the credential value' || return 1
}

test_set_validation_and_rollback() {
  local output_file="$tmp_dir/set-validation.stdout"
  local error_file="$tmp_dir/set-validation.stderr"
  local old_path=$PATH rc

  start_case set-validation

  cgm set BAD-NAME >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 1 'set rejects invalid environment names' || return 1
  assert_contains "$(file_contents "$error_file")" 'names must match [A-Z_][A-Z0-9_]*' 'invalid names get an actionable diagnostic' || return 1
  assert_equals "$(file_contents "$CGM_TEST_LOG")" '' 'invalid names never reach secret-tool' || return 1

  cgm set PATH >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 1 'set rejects special Zsh parameters' || return 1
  assert_equals "$PATH" "$old_path" 'special-parameter rejection leaves PATH unchanged' || return 1
  assert_equals "$(file_contents "$CGM_TEST_LOG")" '' 'special Zsh parameters never reach secret-tool' || return 1

  typeset -ga ARRAY_TOKEN=(keep both)
  cgm set ARRAY_TOKEN >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 1 'set rejects existing non-scalar parameters' || return 1
  assert_equals "${(j: :)ARRAY_TOKEN}" 'keep both' 'non-scalar rejection preserves the existing array' || return 1
  unset ARRAY_TOKEN

  cgm set lower_case >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 1 'set enforces conventional uppercase credential names' || return 1
  assert_equals "$(file_contents "$CGM_TEST_LOG")" '' 'lowercase names never reach secret-tool' || return 1

  CGM_TEST_FAIL_STORE_NAME=ROLLBACK_TOKEN
  CGM_TEST_STORE_VALUE='not-saved'
  export CGM_TEST_FAIL_STORE_NAME CGM_TEST_STORE_VALUE
  cgm set ROLLBACK_TOKEN >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 9 'set preserves the backend failure status' || return 1
  assert_not_exists "$XDG_DATA_HOME/cgm/entries/ROLLBACK_TOKEN" 'failed set rolls back a newly-created catalogue marker' || return 1

  unset CGM_TEST_FAIL_STORE_NAME
  CGM_TEST_STORE_VALUE=original
  export CGM_TEST_STORE_VALUE
  cgm set REPLACE_TOKEN >"$output_file" 2>"$error_file" || return 1
  functions[_cgm_confirm]='return 1'
  CGM_TEST_STORE_VALUE=replacement
  export CGM_TEST_STORE_VALUE
  cgm set REPLACE_TOKEN >"$output_file" 2>"$error_file"
  rc=$?
  functions[_cgm_confirm]='return 0'
  assert_status "$rc" 1 'declining replacement cancels set' || return 1
  assert_equals "$(file_contents "$CGM_TEST_BACKEND_DIR/REPLACE_TOKEN")" original 'cancelled replacement preserves the existing value' || return 1
}

test_env_literal_and_catalogue_repair() {
  local injection_marker="$tmp_dir/should-not-exist"
  local secret='token $(touch '"$tmp_dir"'/should-not-exist); * [x] = spaced'
  local output_file="$tmp_dir/env.stdout"
  local error_file="$tmp_dir/env.stderr"
  local output rc

  start_case env
  CGM_TEST_STORE_VALUE=$secret
  export CGM_TEST_STORE_VALUE
  cgm set SAFE_TOKEN >/dev/null 2>"$error_file" || return 1
  : > "$CGM_TEST_LOG"

  cgm env SAFE_TOKEN >"$output_file" 2>"$error_file"
  rc=$?
  output=$(file_contents "$output_file")
  assert_status "$rc" 0 'env loads a selected credential' || return 1
  assert_equals "$SAFE_TOKEN" "$secret" 'env preserves shell metacharacters as literal value data' || return 1
  assert_contains "${parameters[SAFE_TOKEN]}" export 'env marks the loaded parameter for child processes' || return 1
  assert_not_exists "$injection_marker" 'env never evaluates credential contents as shell code' || return 1
  assert_not_contains "$output" "$secret" 'env stdout never contains the credential value' || return 1
  assert_not_contains "$(file_contents "$error_file")" "$secret" 'env stderr never contains the credential value' || return 1
  assert_not_contains "$(file_contents "$CGM_TEST_LOG")" "$secret" 'env never passes the credential value as a command argument' || return 1

  print -nr -- orphan-secret > "$CGM_TEST_BACKEND_DIR/ORPHAN_TOKEN"
  assert_not_exists "$XDG_DATA_HOME/cgm/entries/ORPHAN_TOKEN" 'orphan fixture starts outside the name catalogue' || return 1
  cgm env ORPHAN_TOKEN >"$output_file" 2>"$error_file"
  assert_status "$?" 0 'exact-name env can recover a backend-only credential' || return 1
  assert_equals "$ORPHAN_TOKEN" orphan-secret 'exact-name env loads a backend-only credential' || return 1
  assert_exists "$XDG_DATA_HOME/cgm/entries/ORPHAN_TOKEN" 'exact-name env repairs the missing catalogue marker' || return 1

  cgm unset SAFE_TOKEN ORPHAN_TOKEN >"$output_file" 2>"$error_file"
  assert_status "$?" 0 'unset removes selected credentials from the current shell' || return 1
  (( ! ${+parameters[SAFE_TOKEN]} && ! ${+parameters[ORPHAN_TOKEN]} )) || {
    print -u2 -- 'not ok: unset removes both exported parameters'
    return 1
  }
  print -- 'ok: unset removes both exported parameters'
  assert_exists "$CGM_TEST_BACKEND_DIR/SAFE_TOKEN" 'unset leaves the stored credential intact' || return 1
}

test_env_suppresses_shell_tracing() {
  local secret=trace-secret-value
  local output_file="$tmp_dir/env-trace.stdout"
  local trace_file="$tmp_dir/env-trace.stderr"
  local trace_restored=off

  start_case env-trace
  print -nr -- "$secret" > "$CGM_TEST_BACKEND_DIR/TRACE_TOKEN"
  _cgm_catalog_add TRACE_TOKEN || return 1

  {
    setopt xtrace
    cgm env TRACE_TOKEN >"$output_file"
    trace_restored=$options[xtrace]
    unsetopt xtrace
  } 2>"$trace_file"

  assert_equals "$TRACE_TOKEN" "$secret" 'env still loads a credential when caller tracing is enabled' || return 1
  assert_not_contains "$(file_contents "$trace_file")" "$secret" 'env suppresses credential values from Zsh trace output' || return 1
  assert_equals "$trace_restored" on 'env restores the caller trace option after returning' || return 1
  unset TRACE_TOKEN
}

test_env_all_is_atomic() {
  local output_file="$tmp_dir/env-all.stdout"
  local error_file="$tmp_dir/env-all.stderr"
  local rc

  start_case env-all
  print -nr -- new-alpha > "$CGM_TEST_BACKEND_DIR/ATOMIC_ALPHA"
  print -nr -- new-beta > "$CGM_TEST_BACKEND_DIR/ATOMIC_BETA"
  _cgm_catalog_add ATOMIC_ALPHA || return 1
  _cgm_catalog_add ATOMIC_BETA || return 1
  typeset -gx ATOMIC_ALPHA=old-alpha
  typeset -gx ATOMIC_BETA=old-beta
  CGM_TEST_FAIL_LOOKUP_NAME=ATOMIC_BETA
  export CGM_TEST_FAIL_LOOKUP_NAME

  cgm env --all >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 7 'env --all preserves a failed lookup status' || return 1
  assert_equals "$ATOMIC_ALPHA" old-alpha 'env --all leaves earlier variables unchanged after a later lookup failure' || return 1
  assert_equals "$ATOMIC_BETA" old-beta 'env --all leaves the failing variable unchanged' || return 1
  assert_not_contains "$(file_contents "$output_file")" new-alpha 'failed env --all never leaks a retrieved value to stdout' || return 1

  unset CGM_TEST_FAIL_LOOKUP_NAME
  cgm env --all >"$output_file" 2>"$error_file"
  assert_status "$?" 0 'env --all loads every credential after all lookups succeed' || return 1
  assert_equals "$ATOMIC_ALPHA" new-alpha 'successful env --all exports the first credential' || return 1
  assert_equals "$ATOMIC_BETA" new-beta 'successful env --all exports the second credential' || return 1
}

test_env_rejects_unsafe_context_and_values() {
  local output_file="$tmp_dir/env-unsafe.stdout"
  local error_file="$tmp_dir/env-unsafe.stderr"
  local rc

  start_case env-unsafe
  print -r -- $'first\nsecond' > "$CGM_TEST_BACKEND_DIR/MULTILINE_TOKEN"
  _cgm_catalog_add MULTILINE_TOKEN || return 1
  typeset -gx MULTILINE_TOKEN=previous

  cgm env MULTILINE_TOKEN >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 1 'env rejects multiline credentials' || return 1
  assert_equals "$MULTILINE_TOKEN" previous 'multiline rejection leaves the existing environment unchanged' || return 1
  assert_contains "$(file_contents "$error_file")" 'not a single-line value' 'multiline rejection explains the supported value shape' || return 1

  print -nr -- $'trailing-newline\n' > "$CGM_TEST_BACKEND_DIR/TRAILING_TOKEN"
  _cgm_catalog_add TRAILING_TOKEN || return 1
  typeset -gx TRAILING_TOKEN=previous
  cgm env TRAILING_TOKEN >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 1 'env preserves and rejects a trailing newline' || return 1
  assert_equals "$TRAILING_TOKEN" previous 'trailing-newline rejection leaves the environment unchanged' || return 1

  print -nr -- subshell-secret > "$CGM_TEST_BACKEND_DIR/SUBSHELL_TOKEN"
  _cgm_catalog_add SUBSHELL_TOKEN || return 1
  : > "$CGM_TEST_LOG"
  ( cgm env SUBSHELL_TOKEN ) >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 1 'env rejects a subshell invocation' || return 1
  assert_contains "$(file_contents "$error_file")" "run 'cgm env ...' directly" 'subshell rejection explains how to load persistently' || return 1
  assert_equals "$(file_contents "$CGM_TEST_LOG")" '' 'subshell rejection happens before a keyring lookup' || return 1

  typeset -gx SUBSHELL_TOKEN=subshell-secret
  ( cgm unset SUBSHELL_TOKEN ) >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 1 'unset rejects a subshell invocation' || return 1
  assert_equals "$SUBSHELL_TOKEN" subshell-secret 'subshell unset leaves the parent shell value intact' || return 1
  assert_contains "$(file_contents "$error_file")" "run 'cgm unset ...' directly" 'subshell unset explains the direct invocation requirement' || return 1

  : > "$CGM_TEST_LOG"
  ( cgm delete SUBSHELL_TOKEN ) >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 1 'delete rejects a subshell invocation' || return 1
  assert_exists "$CGM_TEST_BACKEND_DIR/SUBSHELL_TOKEN" 'subshell delete leaves storage unchanged' || return 1
  assert_equals "$(file_contents "$CGM_TEST_LOG")" '' 'subshell delete stops before contacting Secret Service' || return 1
  unset SUBSHELL_TOKEN
}

test_env_all_validates_every_name_first() {
  local output_file="$tmp_dir/env-all-validation.stdout"
  local error_file="$tmp_dir/env-all-validation.stderr"
  local rc

  start_case env-all-validation
  print -nr -- safe > "$CGM_TEST_BACKEND_DIR/VALID_TOKEN"
  print -nr -- forbidden > "$CGM_TEST_BACKEND_DIR/PATH"
  _cgm_catalog_add VALID_TOKEN || return 1
  _cgm_catalog_add PATH || return 1
  : > "$CGM_TEST_LOG"

  cgm env --all >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 1 'env --all rejects an unsafe catalogued parameter' || return 1
  assert_equals "$(file_contents "$CGM_TEST_LOG")" '' 'env --all validates every name before any keyring lookup' || return 1
  (( ! ${+parameters[VALID_TOKEN]} )) || {
    print -u2 -- 'not ok: unsafe env --all exports no earlier credential'
    return 1
  }
  print -- 'ok: unsafe env --all exports no earlier credential'
}

test_delete() {
  local secret=delete-secret
  local output_file="$tmp_dir/delete.stdout"
  local error_file="$tmp_dir/delete.stderr"
  local unsafe_target="$tmp_dir/delete-unsafe-target"
  local rc

  start_case delete
  CGM_TEST_STORE_VALUE=$secret
  export CGM_TEST_STORE_VALUE
  cgm set DELETE_TOKEN >/dev/null 2>"$error_file" || return 1
  cgm env DELETE_TOKEN >/dev/null 2>"$error_file" || return 1
  : > "$CGM_TEST_LOG"

  cgm delete DELETE_TOKEN >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 0 'delete removes a saved credential' || return 1
  assert_not_exists "$CGM_TEST_BACKEND_DIR/DELETE_TOKEN" 'delete clears the Secret Service item' || return 1
  assert_not_exists "$XDG_DATA_HOME/cgm/entries/DELETE_TOKEN" 'delete removes the name-only catalogue marker' || return 1
  (( ! ${+parameters[DELETE_TOKEN]} )) || {
    print -u2 -- 'not ok: delete unsets the value from the current shell'
    return 1
  }
  print -- 'ok: delete unsets the value from the current shell'
  assert_not_contains "$(file_contents "$output_file")" "$secret" 'delete output never contains the credential value' || return 1
  assert_contains "$(file_contents "$CGM_TEST_LOG")" $'clear\tapplication\tcgm\tvariable\tDELETE_TOKEN' 'delete clears only the exact CGM credential attributes' || return 1

  print -nr -- protected > "$CGM_TEST_BACKEND_DIR/PROTECTED_TOKEN"
  command ln -s -- "$unsafe_target" "$XDG_DATA_HOME/cgm/entries/PROTECTED_TOKEN"
  : > "$CGM_TEST_LOG"
  cgm delete PROTECTED_TOKEN >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 1 'delete rejects an unsafe catalogue marker' || return 1
  assert_exists "$CGM_TEST_BACKEND_DIR/PROTECTED_TOKEN" 'unsafe catalogue rejection happens before keyring deletion' || return 1
  assert_equals "$(file_contents "$CGM_TEST_LOG")" '' 'unsafe catalogue rejection never contacts Secret Service' || return 1
}

test_runtime_backend_guard() {
  local old_path=$PATH
  local no_backend="$tmp_dir/no-backend"
  local output_file="$tmp_dir/no-backend.stdout"
  local error_file="$tmp_dir/no-backend.stderr"
  local rc

  start_case no-backend
  command mkdir -p -- "$no_backend"
  PATH=$no_backend
  cgm env MISSING_TOKEN >"$output_file" 2>"$error_file"
  rc=$?
  PATH=$old_path

  assert_status "$rc" 1 'runtime guard catches secret-tool disappearing from PATH' || return 1
  assert_contains "$(file_contents "$error_file")" 'secret-tool is unavailable' 'runtime backend failure is actionable' || return 1
}

test_help_and_rich_ui() {
  local output_file="$tmp_dir/help-ui.stdout"
  local error_file="$tmp_dir/help-ui.stderr"
  local output rc

  start_case help-ui
  cgm help >"$output_file" 2>"$error_file"
  assert_status "$?" 0 'plain help succeeds' || return 1
  output=$(file_contents "$output_file")
  assert_contains "$output" 'env --all' 'help documents all-credential loading' || return 1
  assert_contains "$output" 'values stay hidden' 'help states the non-disclosure contract' || return 1

  cgm unknown >"$output_file" 2>"$error_file"
  rc=$?
  assert_status "$rc" 1 'unknown commands fail' || return 1
  assert_contains "$(file_contents "$error_file")" 'unknown command: unknown' 'unknown commands get a concise diagnostic' || return 1

  _cgm_catalog_add UI_TOKEN || return 1
  : > "$CGM_TEST_LOG"
  (
    functions[_ui_plain_mode]='return 1'
    cgm list
  ) >"$output_file" 2>"$error_file"
  assert_status "$?" 0 'rich credential list renders successfully' || return 1
  output=$(file_contents "$output_file")
  assert_contains "$output" 'Credentials' 'rich list uses the shared dashboard title' || return 1
  assert_contains "$output" 'UI_TOKEN' 'rich list renders saved names' || return 1
  assert_contains "$output" 'Values: hidden' 'rich list makes the hidden-value contract visible' || return 1
  assert_equals "$(file_contents "$CGM_TEST_LOG")" '' 'rich list does not contact Secret Service' || return 1
}

main() {
  local fakebin="$tmp_dir/fakebin"

  make_fake_secret_tool "$fakebin" || return 1
  PATH="$fakebin:$PATH"
  export PATH

  source "$repo_dir/55-ui-helpers.zsh"
  source "$repo_dir/60-functions.zsh"
  source "$repo_dir/62-cgm.zsh"
  functions[_ui_plain_mode]='return 0'
  functions[_cgm_input_is_terminal]='return 0'
  functions[_cgm_confirm]='return 0'

  test_startup_gate || return 1
  test_set_and_catalogue || return 1
  test_set_validation_and_rollback || return 1
  test_env_literal_and_catalogue_repair || return 1
  test_env_suppresses_shell_tracing || return 1
  test_env_all_is_atomic || return 1
  test_env_rejects_unsafe_context_and_values || return 1
  test_env_all_validates_every_name_first || return 1
  test_delete || return 1
  test_runtime_backend_guard || return 1
  test_help_and_rich_ui || return 1
}

main "$@"
