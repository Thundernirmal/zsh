#!/usr/bin/env zsh

set -u

repo_dir=${0:A:h:h}
tmp_dir=$(mktemp -d) || { print -u2 -- 'fatal: mktemp failed'; exit 1; }
[ -n "$tmp_dir" ] || { print -u2 -- 'fatal: mktemp returned empty path'; exit 1; }

cleanup() {
  command rm -rf "$tmp_dir"
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

assert_file_contains() {
  local file=$1
  local needle=$2
  local label=$3

  if ! command grep -F -- "$needle" "$file" >/dev/null 2>&1; then
    print -u2 -- "not ok: $label"
    print -u2 -- "missing: $needle"
    [ -f "$file" ] && command cat "$file" >&2
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

assert_file_not_contains() {
  local file=$1
  local needle=$2
  local label=$3

  if command grep -F -- "$needle" "$file" >/dev/null 2>&1; then
    print -u2 -- "not ok: $label"
    print -u2 -- "unexpected: $needle"
    command cat "$file" >&2
    return 1
  fi

  print -- "ok: $label"
}

assert_path_exists() {
  local path=$1
  local label=$2

  if [ ! -e "$path" ]; then
    print -u2 -- "not ok: $label"
    print -u2 -- "missing path: $path"
    return 1
  fi

  print -- "ok: $label"
}

main() {
  local fake_home archive source_root output cmd_status backup_count loaded_dir
  local comment_home manual_home broken_home misordered_home rollback_home slash_home no_zshrc_home

  fake_home="$tmp_dir/home"
  source_root="$tmp_dir/zsh-vtest"
  archive="$tmp_dir/zsh-vtest.tar.gz"

  command mkdir -p "$fake_home" "$source_root/scripts" || return 1
  command cp "$repo_dir/init.zsh" "$source_root/init.zsh" || return 1
  print -- '# test deps' > "$source_root/scripts/check-deps.sh"
  print -- 'typeset -g TEST_INSTALL_LOADED_FROM=${${(%):-%x}:A:h}' > "$source_root/80-tips.zsh"
  command tar -czf "$archive" -C "$tmp_dir" zsh-vtest || return 1

  output=$(
    HOME="$fake_home" sh "$repo_dir/scripts/install.sh" \
      --repo example/zsh \
      --tag vtest \
      --archive-url "file://$archive" \
      --dir "$fake_home/.config/zsh" \
      --zshrc "$fake_home/.zshrc"
  )
  cmd_status=$?
  assert_status "$cmd_status" 0 'installer succeeds with a local release archive' || {
    print -u2 -- "$output"
    return 1
  }
  assert_path_exists "$fake_home/.config/zsh/init.zsh" 'installer writes init.zsh to target dir' || return 1
  assert_path_exists "$fake_home/.config/zsh/scripts/check-deps.sh" 'installer writes scripts directory' || return 1
  assert_file_contains "$fake_home/.zshrc" '# >>> shared zsh config >>>' 'installer appends source block marker' || return 1
  assert_file_contains "$fake_home/.zshrc" "$fake_home/.config/zsh/init.zsh" 'installer points zshrc at installed init' || return 1

  output=$(
    HOME="$fake_home" sh "$repo_dir/scripts/install.sh" \
      --repo example/zsh \
      --tag vtest \
      --archive-url "file://$archive" \
      --dir "$fake_home/.config/zsh" \
      --zshrc "$fake_home/.zshrc"
  )
  cmd_status=$?
  assert_status "$cmd_status" 0 'installer rerun succeeds and backs up existing config' || {
    print -u2 -- "$output"
    return 1
  }

  backup_count=$(command find "$fake_home/.config" -maxdepth 1 -type d -name 'zsh.backup.*' | command wc -l | tr -d ' ')
  assert_status "$backup_count" 1 'installer creates one backup on rerun' || return 1
  assert_path_exists "$fake_home/.config/zsh/init.zsh" 'installer restores target after rerun' || return 1

  if [[ $(command grep -F -c -- '# >>> shared zsh config >>>' "$fake_home/.zshrc") != 1 ]]; then
    print -u2 -- 'not ok: installer keeps zshrc block idempotent'
    command cat "$fake_home/.zshrc" >&2
    return 1
  fi
  print -- 'ok: installer keeps zshrc block idempotent'

  output=$(
    HOME="$fake_home" sh "$repo_dir/scripts/install.sh" \
      --repo example/zsh \
      --tag vtest \
      --archive-url "file://$archive" \
      --dir "$fake_home/.config/zsh-alt" \
      --zshrc "$fake_home/.zshrc"
  )
  cmd_status=$?
  assert_status "$cmd_status" 0 'installer rerun with custom dir succeeds' || {
    print -u2 -- "$output"
    return 1
  }
  assert_path_exists "$fake_home/.config/zsh-alt/init.zsh" 'installer writes custom target dir' || return 1
  assert_file_contains "$fake_home/.zshrc" "$fake_home/.config/zsh-alt/init.zsh" 'installer updates managed block for custom dir' || return 1
  assert_file_not_contains "$fake_home/.zshrc" "$fake_home/.config/zsh/init.zsh" 'installer removes stale managed source path' || return 1

  if [[ $(command grep -F -c -- '# >>> shared zsh config >>>' "$fake_home/.zshrc") != 1 ]]; then
    print -u2 -- 'not ok: installer keeps one managed zshrc block after custom dir update'
    command cat "$fake_home/.zshrc" >&2
    return 1
  fi
  print -- 'ok: installer keeps one managed zshrc block after custom dir update'

  loaded_dir=$(HOME="$fake_home" zsh -fc 'source "$HOME/.zshrc"; print -r -- "${TEST_INSTALL_LOADED_FROM:-missing}"')
  assert_status "$loaded_dir" "$fake_home/.config/zsh-alt" 'custom-dir zshrc loads modules from custom install dir' || return 1

  comment_home="$tmp_dir/comment-home"
  command mkdir -p "$comment_home" || return 1
  print -- "# previous note: source $comment_home/.config/zsh/init.zsh later" > "$comment_home/.zshrc"
  output=$(
    HOME="$comment_home" sh "$repo_dir/scripts/install.sh" \
      --repo example/zsh \
      --tag vtest \
      --archive-url "file://$archive" \
      --dir "$comment_home/.config/zsh" \
      --zshrc "$comment_home/.zshrc"
  )
  cmd_status=$?
  assert_status "$cmd_status" 0 'installer ignores commented source path' || {
    print -u2 -- "$output"
    return 1
  }
  assert_file_contains "$comment_home/.zshrc" '# >>> shared zsh config >>>' 'installer appends block when path was only in a comment' || return 1

  manual_home="$tmp_dir/manual-home"
  command mkdir -p "$manual_home" "$manual_home/.config/zsh" || return 1
  {
    print -- 'if [ -r "$HOME/.config/zsh/init.zsh" ]; then'
    print -- '  source "$HOME/.config/zsh/init.zsh"'
    print -- 'fi'
  } > "$manual_home/.zshrc"
  output=$(
    HOME="$manual_home" sh "$repo_dir/scripts/install.sh" \
      --repo example/zsh \
      --tag vtest \
      --archive-url "file://$archive" \
      --dir "$manual_home/.config/zsh" \
      --zshrc "$manual_home/.zshrc"
  )
  cmd_status=$?
  assert_status "$cmd_status" 0 'installer accepts existing manual source line' || {
    print -u2 -- "$output"
    return 1
  }
  assert_not_contains "$output" 'Updated zshrc' 'manual source line skips managed block rewrite' || return 1
  assert_file_not_contains "$manual_home/.zshrc" '# >>> shared zsh config >>>' 'manual source line does not get duplicate managed block' || return 1

  broken_home="$tmp_dir/broken-home"
  command mkdir -p "$broken_home" || return 1
  {
    print -- '# >>> shared zsh config >>>'
    print -- 'export KEEP_ME=1'
  } > "$broken_home/.zshrc"
  output=$(
    HOME="$broken_home" sh "$repo_dir/scripts/install.sh" \
      --repo example/zsh \
      --tag vtest \
      --archive-url "file://$archive" \
      --dir "$broken_home/.config/zsh" \
      --zshrc "$broken_home/.zshrc" 2>&1
  )
  cmd_status=$?
  assert_status "$cmd_status" 1 'installer rejects incomplete managed block' || {
    print -u2 -- "$output"
    return 1
  }
  assert_contains "$output" 'found an incomplete managed block' 'incomplete marker error is explicit' || return 1
  assert_file_contains "$broken_home/.zshrc" 'export KEEP_ME=1' 'incomplete marker path preserves user zshrc content' || return 1

  misordered_home="$tmp_dir/misordered-home"
  command mkdir -p "$misordered_home" || return 1
  {
    print -- '# <<< shared zsh config <<<'
    print -- 'export KEEP_TOP=1'
    print -- '# >>> shared zsh config >>>'
    print -- 'export KEEP_BOTTOM=1'
  } > "$misordered_home/.zshrc"
  output=$(
    HOME="$misordered_home" sh "$repo_dir/scripts/install.sh" \
      --repo example/zsh \
      --tag vtest \
      --archive-url "file://$archive" \
      --dir "$misordered_home/.config/zsh" \
      --zshrc "$misordered_home/.zshrc" 2>&1
  )
  cmd_status=$?
  assert_status "$cmd_status" 1 'installer rejects misordered managed markers' || {
    print -u2 -- "$output"
    return 1
  }
  assert_contains "$output" 'found an incomplete managed block' 'misordered marker error is explicit' || return 1
  assert_file_contains "$misordered_home/.zshrc" 'export KEEP_TOP=1' 'misordered marker path preserves pre-marker user content' || return 1
  assert_file_contains "$misordered_home/.zshrc" 'export KEEP_BOTTOM=1' 'misordered marker path preserves post-marker user content' || return 1

  rollback_home="$tmp_dir/rollback-home"
  command mkdir -p "$rollback_home/.config/zsh" || return 1
  print -- 'export BEFORE_ROLLBACK=1' > "$rollback_home/.config/zsh/init.zsh"
  {
    print -- '# >>> shared zsh config >>>'
    print -- 'export INCOMPLETE=1'
  } > "$rollback_home/.zshrc"
  output=$(
    HOME="$rollback_home" sh "$repo_dir/scripts/install.sh" \
      --repo example/zsh \
      --tag vtest \
      --archive-url "file://$archive" \
      --dir "$rollback_home/.config/zsh" \
      --zshrc "$rollback_home/.zshrc" 2>&1
  )
  cmd_status=$?
  assert_status "$cmd_status" 1 'installer rolls back target when zshrc update fails' || {
    print -u2 -- "$output"
    return 1
  }
  assert_file_contains "$rollback_home/.config/zsh/init.zsh" 'export BEFORE_ROLLBACK=1' 'rollback keeps previous target after zshrc failure' || return 1

  slash_home="$tmp_dir/slash-home"
  command mkdir -p "$slash_home" || return 1
  output=$(
    HOME="$slash_home" sh "$repo_dir/scripts/install.sh" \
      --repo example/zsh \
      --tag vtest \
      --archive-url "file://$archive" \
      --dir "$slash_home/.config/zsh/" \
      --zshrc "$slash_home/.zshrc"
  )
  cmd_status=$?
  assert_status "$cmd_status" 0 'installer accepts trailing slash install dir' || {
    print -u2 -- "$output"
    return 1
  }
  assert_path_exists "$slash_home/.config/zsh/init.zsh" 'trailing slash install writes normalized target' || return 1
  assert_file_contains "$slash_home/.zshrc" "$slash_home/.config/zsh/init.zsh" 'trailing slash install writes normalized zshrc path' || return 1

  no_zshrc_home="$tmp_dir/no-zshrc-home"
  command mkdir -p "$no_zshrc_home" || return 1
  output=$(
    HOME="$no_zshrc_home" sh "$repo_dir/scripts/install.sh" \
      --repo example/zsh \
      --tag vtest \
      --archive-url "file://$archive" \
      --dir "$no_zshrc_home/.config/zsh" \
      --zshrc "$no_zshrc_home/.zshrc" \
      --no-zshrc
  )
  cmd_status=$?
  assert_status "$cmd_status" 0 'installer supports no-zshrc mode' || {
    print -u2 -- "$output"
    return 1
  }
  assert_not_contains "$output" 'Next shell startup will source' 'no-zshrc output does not claim automatic startup loading' || return 1
  assert_contains "$output" 'To load it manually' 'no-zshrc output gives manual source instruction' || return 1
  if [ -e "$no_zshrc_home/.zshrc" ]; then
    print -u2 -- 'not ok: no-zshrc mode leaves zshrc untouched'
    command cat "$no_zshrc_home/.zshrc" >&2
    return 1
  fi
  print -- 'ok: no-zshrc mode leaves zshrc untouched'
}

main "$@"
