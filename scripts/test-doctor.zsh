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

make_fakebin() {
  local fakebin=$1 tool

  command mkdir -p -- "$fakebin"
  for tool in zsh git curl ss lsd zoxide bat tree jq secret-tool nix fd; do
    print -r -- '#!/bin/sh
exit 0' >"$fakebin/$tool"
    command chmod +x -- "$fakebin/$tool"
  done
  print -r -- '#!/bin/sh
if [ "$1" = "--version" ]; then
  printf "%s\n" "0.74.0"
  exit 0
fi
exit 0' >"$fakebin/fzf"
  command chmod +x -- "$fakebin/fzf"
  print -r -- '#!/bin/sh
printf "%s\n" "$*" >> "$ZDOCTOR_CURL_LOG"
exit ${ZDOCTOR_CURL_STATUS:-0}' >"$fakebin/curl"
  command chmod +x -- "$fakebin/curl"
}

test_usage() {
  local output rc

  output=$(zdoctor --help)
  assert_status "$?" 0 'zdoctor documents its explicit probe flags' || return 1
  assert_contains "$output" 'Usage: zdoctor [--network] [--secrets]' 'zdoctor usage names both probes' || return 1

  output=$(zdoctor --bogus 2>&1); rc=$?
  assert_status "$rc" 1 'zdoctor rejects unknown options' || return 1
  assert_contains "$output" 'Unknown zdoctor option' 'zdoctor names the rejected option' || return 1

  output=$(zdoctor surplus 2>&1); rc=$?
  assert_status "$rc" 1 'zdoctor rejects positional arguments' || return 1
}

test_healthy_fixture() {
  local fixture_home="$tmp_dir/doctor-home" fakebin="$tmp_dir/doctor-fakebin"
  local old_path=$PATH output rc

  command mkdir -p -- "$fixture_home/.config"
  command ln -s -- "$repo_dir" "$fixture_home/.config/zsh"
  make_fakebin "$fakebin"
  PATH="$fakebin:$old_path"
  rehash
  unfunction cgm npkg zi 2>/dev/null || true

  output=$(HOME="$fixture_home" zdoctor 2>&1); rc=$?
  assert_status "$rc" 0 'zdoctor passes a healthy fixture' || {
    print -u2 -- "$output"
    return 1
  }
  assert_contains "$output" 'ok: install location' 'zdoctor verifies the fixed install path' || return 1
  assert_contains "$output" 'ok: all expected modules are readable' 'zdoctor verifies module readability' || return 1
  assert_contains "$output" 'compinit has not run' 'zdoctor explains silent completion loss' || return 1
  assert_contains "$output" 'ok: required tool: fzf 0.74.0 (minimum 0.68.0)' 'zdoctor gates the fzf minimum version' || return 1
  assert_contains "$output" 'ok: optional tool: nix' 'zdoctor separates optional tools from required ones' || return 1
  assert_contains "$output" 'global aliases are disabled' 'zdoctor reports the global-alias state' || return 1
  assert_contains "$output" 'network endpoints not probed' 'zdoctor skips network probes by default' || return 1
  assert_contains "$output" 'Secret Service not contacted' 'zdoctor skips secret probes by default' || return 1
  assert_contains "$output" 'zdoctor: healthy' 'zdoctor summarizes a healthy setup' || return 1
  [[ ! -e $tmp_dir/doctor-curl.log ]] || {
    print -u2 -- 'not ok: default zdoctor never invokes curl'
    PATH=$old_path
    rehash
    return 1
  }
  print -- 'ok: default zdoctor never invokes curl'
  PATH=$old_path
  rehash
}

test_bad_install_location() {
  local fixture_home="$tmp_dir/doctor-nowhere" fakebin="$tmp_dir/doctor-fakebin"
  local old_path=$PATH output rc

  command mkdir -p -- "$fixture_home"
  make_fakebin "$fakebin"
  PATH="$fakebin:$old_path"
  rehash

  output=$(HOME="$fixture_home" zdoctor 2>&1); rc=$?
  assert_status "$rc" 1 'zdoctor fails a missing install location' || return 1
  assert_contains "$output" 'fail: install location' 'zdoctor names the install problem' || return 1
  assert_contains "$output" 'unreadable modules' 'zdoctor names silently skipped modules' || { PATH=$old_path; rehash; return 1; }
  PATH=$old_path
  rehash
}

test_explicit_probes() {
  local fixture_home="$tmp_dir/doctor-home" fakebin="$tmp_dir/doctor-fakebin"
  local old_path=$PATH output rc log="$tmp_dir/doctor-probe-curl.log"

  command mkdir -p -- "$fixture_home/.config"
  command ln -sfn -- "$repo_dir" "$fixture_home/.config/zsh"
  make_fakebin "$fakebin"
  PATH="$fakebin:$old_path"
  rehash
  unfunction cgm npkg zi 2>/dev/null || true

  output=$(HOME="$fixture_home" ZDOCTOR_CURL_LOG=$log ZDOCTOR_CURL_STATUS=0 zdoctor --network 2>&1); rc=$?
  assert_status "$rc" 0 'zdoctor passes when probed endpoints answer' || {
    print -u2 -- "$output"
    return 1
  }
  assert_contains "$output" 'myip endpoint is reachable' 'zdoctor probes the myip endpoint explicitly' || return 1
  assert_contains "$output" 'weather endpoint is reachable' 'zdoctor probes the weather endpoint explicitly' || return 1
  assert_contains "$(<"$log")" 'ifconfig.me' 'network probes request the documented endpoint' || return 1
  assert_contains "$(<"$log")" 'wttr.in' 'network probes cover the forecast endpoint' || return 1

  command rm -f -- "$log"
  output=$(HOME="$fixture_home" ZDOCTOR_CURL_LOG=$log ZDOCTOR_CURL_STATUS=1 zdoctor --network 2>&1); rc=$?
  assert_status "$rc" 1 'zdoctor fails unreachable endpoints' || return 1
  assert_contains "$output" 'myip endpoint is unreachable' 'zdoctor reports endpoint failures' || return 1

  output=$(HOME="$fixture_home" zdoctor --secrets 2>&1); rc=$?
  assert_status "$rc" 0 'zdoctor checks secrets without failing a healthy fixture' || return 1
  assert_contains "$output" 'never retrieves credential values' 'zdoctor never retrieves secret values' || { PATH=$old_path; rehash; return 1; }
  PATH=$old_path
  rehash
}

test_old_fzf_is_a_failure() {
  local fixture_home="$tmp_dir/doctor-home" fakebin="$tmp_dir/doctor-oldfzf"
  local old_path=$PATH output rc

  command mkdir -p -- "$fixture_home/.config" "$fakebin"
  command ln -sfn -- "$repo_dir" "$fixture_home/.config/zsh"
  print -r -- '#!/bin/sh
printf "%s\n" "0.60.0"
exit 0' >"$fakebin/fzf"
  command chmod +x -- "$fakebin/fzf"
  PATH="$fakebin:$old_path"
  rehash

  output=$(HOME="$fixture_home" zdoctor 2>&1); rc=$?
  assert_status "$rc" 1 'zdoctor fails an fzf older than the minimum' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$output" 'older than the 0.68.0 minimum' 'zdoctor names the outdated fzf' || { PATH=$old_path; rehash; return 1; }
  PATH=$old_path
  rehash
}

test_glyph_reporting() {
  local fixture_home="$tmp_dir/doctor-home" fakebin="$tmp_dir/doctor-fakebin"
  local old_path=$PATH output rc

  command mkdir -p -- "$fixture_home/.config"
  command ln -sfn -- "$repo_dir" "$fixture_home/.config/zsh"
  make_fakebin "$fakebin"
  PATH="$fakebin:$old_path"
  rehash
  unfunction cgm npkg zi 2>/dev/null || true
  source "$repo_dir/25-theme.zsh"

  output=$(HOME="$fixture_home" ZSH_UI_GLYPHS=nerd zdoctor 2>&1); rc=$?
  assert_status "$rc" 0 'zdoctor passes an explicit glyph tier' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$output" 'glyphs resolve to nerd' 'zdoctor reports the resolved glyph tier' || { PATH=$old_path; rehash; return 1; }

  output=$(HOME="$fixture_home" ZSH_UI_GLYPHS=bogus zdoctor 2>&1); rc=$?
  assert_status "$rc" 1 'zdoctor fails an invalid glyph setting' || { PATH=$old_path; rehash; return 1; }
  assert_contains "$output" 'is invalid (use auto, nerd, unicode, or ascii)' 'zdoctor explains valid glyph tiers' || { PATH=$old_path; rehash; return 1; }
  PATH=$old_path
  rehash
}

# Exercise the real initialization path in a fresh interactive command shell.
# Initialization is explicit because -i -c intentionally skips prompt startup.
test_fzf_integration_diagnostics() {
  local fixture_home="$tmp_dir/doctor-integration-home" fakebin="$tmp_dir/doctor-integration-bin"
  local real_zsh=$(command -v zsh) mode output rc expected reason
  command mkdir -p -- "$fixture_home/.config"
  command ln -s -- "$repo_dir" "$fixture_home/.config/zsh"
  make_fakebin "$fakebin"
  command rm -- "$fakebin/zsh"
  command ln -s -- "$real_zsh" "$fakebin/zsh"
  cat > "$fakebin/fzf" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$ZDOCTOR_FZF_LOG"
case "$1" in
  --version)
    case "$ZDOCTOR_FZF_MODE" in
      old) printf '%s\n' '0.60.0' ;;
      prerelease) printf '%s\n' '0.74.0-beta' ;;
      *) printf '%s\n' '0.74.0' ;;
    esac ;;
  --zsh)
    case "$ZDOCTOR_FZF_MODE" in
      generation) exit 42 ;;
      activation) printf '%s\n' 'return 1' ;;
      *) printf '%s\n' ':' ;;
    esac ;;
  *) exit 1 ;;
esac
SH
  command chmod +x -- "$fakebin/fzf"
  # Any Secret Service access is a test failure, even if the caller suppresses output.
  print -r -- '#!/bin/sh
printf "%s\n" "$*" >> "$ZDOCTOR_SECRET_LOG"
exit 1' > "$fakebin/secret-tool"

  for mode in generation activation ready unchecked old prerelease missing; do
    expected=1
    reason=''
    case $mode in
      generation) reason='integration generation failed' ;;
      activation) reason='integration initialization failed' ;;
      ready|unchecked) expected=0 ;;
    esac
    [[ $mode != missing ]] || command mv "$fakebin/fzf" "$fakebin/fzf.hidden"
    output=$(HOME="$fixture_home" XDG_CACHE_HOME="$tmp_dir/cache-$mode" \
      PATH="$fakebin:$PATH" ZDOCTOR_FZF_MODE=$mode \
      ZDOCTOR_FZF_LOG="$tmp_dir/fzf-$mode.log" \
      ZDOCTOR_CURL_LOG="$tmp_dir/curl-$mode.log" \
      ZDOCTOR_SECRET_LOG="$tmp_dir/secret-$mode.log" \
      "$real_zsh" -fic '
        source "$HOME/.config/zsh/init.zsh"
        functions[_ui_plain_mode]="return 0"
        if [[ $ZDOCTOR_FZF_MODE == missing ]]; then
          PATH=${PATH%%:*}
          rehash
        fi
        if [[ $ZDOCTOR_FZF_MODE != unchecked ]]; then
          _fzf_initialize_zsh || true
        fi
        before_state=$(typeset -p _FZF_STATE _FZF_FOUND _FZF_CHECKED_PATH
          typeset -p _FZF_INTEGRATION_STATE_BY_PATH _FZF_INTEGRATION_REASON_BY_PATH)
        before_widgets=$(builtin zle -la; builtin bindkey -lL; builtin bindkey -L)
        before_opts=$(typeset -p FZF_DEFAULT_OPTS FZF_CTRL_T_OPTS FZF_CTRL_R_OPTS FZF_ALT_C_OPTS FZF_COMPLETION_OPTS 2>/dev/null)
        before_cache=$(for cache_entry in "$XDG_CACHE_HOME"/**/*(DN); do
          print -r -- "$cache_entry"
          [[ ! -f $cache_entry ]] || print -r -- "$(<"$cache_entry")"
        done)
        : > "$ZDOCTOR_FZF_LOG"
        zdoctor
        doctor_rc=$?
        after_state=$(typeset -p _FZF_STATE _FZF_FOUND _FZF_CHECKED_PATH
          typeset -p _FZF_INTEGRATION_STATE_BY_PATH _FZF_INTEGRATION_REASON_BY_PATH)
        after_widgets=$(builtin zle -la; builtin bindkey -lL; builtin bindkey -L)
        after_opts=$(typeset -p FZF_DEFAULT_OPTS FZF_CTRL_T_OPTS FZF_CTRL_R_OPTS FZF_ALT_C_OPTS FZF_COMPLETION_OPTS 2>/dev/null)
        after_cache=$(for cache_entry in "$XDG_CACHE_HOME"/**/*(DN); do
          print -r -- "$cache_entry"
          [[ ! -f $cache_entry ]] || print -r -- "$(<"$cache_entry")"
        done)
        [[ $before_state == $after_state && $before_widgets == $after_widgets &&
           $before_opts == $after_opts && $before_cache == $after_cache ]] || {
          print -r -- "diagnosis mutated integration state"
          [[ $before_state == $after_state ]] || print -r -- "state changed"
          [[ $before_widgets == $after_widgets ]] || print -r -- "widgets changed"
          [[ $before_opts == $after_opts ]] || print -r -- "options changed"
          exit 99
        }
        print -r -- "retained-state=$_FZF_STATE reason=$_FZF_FOUND"
        exit $doctor_rc
      ' 2>&1); rc=$?
    # Restore the absent-binary fixture for later runs/cleanup.
    [[ ! -e $fakebin/fzf.hidden ]] || command mv "$fakebin/fzf.hidden" "$fakebin/fzf"
    assert_status "$rc" "$expected" "$mode fzf diagnosis returns the expected aggregate status without mutation" || { print -u2 -r -- "$output"; return 1; }
    if [[ $mode == unchecked ]]; then
      assert_contains "$output" 'note: fzf integration state: unchecked (not initialized in this shell' 'unchecked command mode is described without initialization' || return 1
      assert_contains "$output" 'retained-state=unchecked reason=not checked' 'unchecked state remains unchanged' || return 1
    elif [[ $mode == ready ]]; then
      assert_contains "$output" 'ok: fzf integration state: ready' 'ready integration stays successful' || return 1
      assert_contains "$output" 'zdoctor: healthy' 'ready integration remains healthy' || return 1
    else
      assert_contains "$output" 'fail: fzf integration state: blocked' "$mode produces a failed integration diagnostic" || return 1
      assert_not_contains "$output" 'ok: fzf integration state: blocked' "$mode has no contradictory success diagnostic" || return 1
      assert_not_contains "$output" 'zdoctor: healthy' "$mode is not summarized as healthy" || return 1
      [[ -z $reason ]] || assert_contains "$output" "retained-state=blocked reason=$reason" "$mode retains its original block reason" || return 1
    fi
    assert_not_contains "$(<"$tmp_dir/fzf-$mode.log")" '--zsh' "$mode diagnosis never regenerates integration" || return 1
    [[ ! -e $tmp_dir/curl-$mode.log && ! -e $tmp_dir/secret-$mode.log ]] || {
      print -u2 -- "not ok: $mode contacted network or Secret Service"; return 1
    }
    print -r -- "ok: $mode diagnosis never contacts network or Secret Service"
  done
}

main() {
  source "$repo_dir/55-ui-helpers.zsh"
  source "$repo_dir/60-functions.zsh"

  functions[_ui_plain_mode]='return 0'

  test_usage || return 1
  test_healthy_fixture || return 1
  test_bad_install_location || return 1
  test_explicit_probes || return 1
  test_old_fzf_is_a_failure || return 1
  test_glyph_reporting || return 1
  test_fzf_integration_diagnostics || return 1
}

main "$@"
