#!/usr/bin/env zsh

emulate -L zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

typeset -r repo_dir=${0:A:h:h}
typeset smoke_home=''

cleanup() {
  [[ -n $smoke_home ]] && command rm -rf -- "$smoke_home"
  return 0
}

handle_signal() {
  local signal_name=$1
  local fallback_status=$2

  cleanup
  trap - EXIT "$signal_name"
  kill -s "$signal_name" "$$"
  exit $fallback_status
}

trap cleanup EXIT
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM
trap 'handle_signal HUP 129' HUP

builtin cd -- "$repo_dir"

zsh -n ./*.zsh ./lib/*.zsh ./functions/ztheme ./functions/_fbr_format_entry
zsh -n ./scripts/benchmark-startup.zsh ./scripts/test-theme.zsh
sh -n ./scripts/check-deps.sh
zsh ./scripts/test-init.zsh
zsh ./scripts/test-theme.zsh
zsh ./scripts/test-functions.zsh
zsh ./scripts/test-cgm.zsh
zsh ./scripts/test-upkg.zsh
zsh ./scripts/test-completions.zsh
zsh ./scripts/test-help.zsh

if [[ $repo_dir == ${HOME:-}/.config/zsh ]]; then
  zsh -fc 'source "$HOME/.config/zsh/init.zsh"'
else
  smoke_home=$(command mktemp -d "${TMPDIR:-/tmp}/zsh-config-smoke.XXXXXX")
  [[ -n $smoke_home ]] || {
    print -u2 -r -- 'fatal: mktemp returned an empty smoke-test home'
    exit 1
  }
  command mkdir -p -- "$smoke_home/.config"
  command ln -s -- "$repo_dir" "$smoke_home/.config/zsh"
  HOME=$smoke_home zsh -fc 'source "$HOME/.config/zsh/init.zsh"'
fi
