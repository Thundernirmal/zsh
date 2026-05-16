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
  local fake_home archive source_root output cmd_status backup_count

  fake_home="$tmp_dir/home"
  source_root="$tmp_dir/zsh-vtest"
  archive="$tmp_dir/zsh-vtest.tar.gz"

  command mkdir -p "$fake_home" "$source_root/scripts" || return 1
  print -- '# test init' > "$source_root/init.zsh"
  print -- '# test deps' > "$source_root/scripts/check-deps.sh"
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
}

main "$@"
