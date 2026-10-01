#!/usr/bin/env zsh
# Fault-injected failed-startup cleanup; synthetic processes only.
emulate -L zsh
setopt NO_UNSET NO_MONITOR
repo_dir=${0:A:h:h}
source "$repo_dir/60-functions.zsh"
upkg help >/dev/null || exit 1
zmodload zsh/system || exit 1
zmodload zsh/zselect || exit 1
scratch=$(command mktemp -d) || exit 1
trap 'command rm -rf -- "$scratch"' EXIT
export FIXTURE_ZSH=$(whence -p zsh) FIXTURE_DIR=$scratch
command cat > "$scratch/fixture_launcher.zsh" <<'LAUNCHER'
"$FIXTURE_ZSH" -df "$FIXTURE_DIR/fixture_child.zsh" &
print -r -- $! > "$FIXTURE_CASE/fixture_child"
wait
LAUNCHER
command cat > "$scratch/fixture_child.zsh" <<'CHILD'
zmodload zsh/zselect
trap '' TERM
if [[ $FIXTURE_MODE == transition ]]; then
  trap 'exec setsid --wait "$FIXTURE_ZSH" -df "$FIXTURE_DIR/group.zsh"' TERM
fi
: > "$FIXTURE_CASE/ready"
while true; do zselect -t 1; done
CHILD
command cat > "$scratch/group.zsh" <<'GROUP'
zmodload zsh/system
zmodload zsh/zselect
trap '' TERM
command sleep 30 &
print -r -- "$sysparams[pid] $!" > "$FIXTURE_CASE/group"
while true; do zselect -t 1; done
GROUP
for mode in reparent child-unreadable launcher-gone launcher-unreadable transition; do
  (
    trap - EXIT
    export FIXTURE_MODE=$mode FIXTURE_CASE="$scratch/$mode"
    command mkdir "$FIXTURE_CASE"
    local fixture_launcher fixture_child fixture_launch_identity fixture_child_identity blocked=0 reads=0
    local -a reply row
    functions[_fixture_record]=$functions[_zsh_query_process_record]
    functions[_zsh_stop_unidentified_launcher]=${functions[_zsh_stop_unidentified_launcher]//builtin kill/_fixture_kill}
    _fixture_kill() {
      print -r -- "$*" >> "$FIXTURE_CASE/signals"
      builtin kill "$@"
    }
    _zsh_query_task_children() {
      if [[ $mode == launcher-gone ]]; then
        builtin kill -KILL "$fixture_launcher"
        builtin wait "$fixture_launcher" 2>/dev/null
      fi
      blocked=1
      reply=( "$fixture_child" )
    }
    sysopen() {
      if [[ $mode == launcher-unreadable && $blocked == 1 && ${@[-1]} == /proc/$fixture_launcher/stat ]]; then
        return 1
      fi
      builtin sysopen "$@"
    }
    _zsh_query_process_record() {
      if [[ $1 == "$fixture_child" ]]; then
        (( reads++ ))
        [[ $mode != child-unreadable || $reads != 2 ]] || return 1
      fi
      _fixture_record "$@" || return 1
      if [[ $mode == reparent && $1 == "$fixture_child" && $reads == 1 ]]; then
        builtin kill -KILL "$fixture_launcher"
        builtin wait "$fixture_launcher" 2>/dev/null
      fi
      return 0
    }
    wait_dead() {
      local target=$1
      integer ticks=0
      while _fixture_record "$target" && [[ $reply[1] != Z ]] && (( ticks++ < 100 )); do zselect -t 1; done
      ! _fixture_record "$target" || [[ $reply[1] == Z ]]
    }
    "$FIXTURE_ZSH" -df "$scratch/fixture_launcher.zsh" &
    fixture_launcher=$!
    run_fixture() {
    {
      integer ticks=0
      while [[ ! -e $FIXTURE_CASE/ready || ! -s $FIXTURE_CASE/fixture_child ]] && (( ticks++ < 200 )); do zselect -t 1; done
      [[ -e $FIXTURE_CASE/ready ]] || return 1
      fixture_child=$(<"$FIXTURE_CASE/fixture_child")
      _fixture_record "$fixture_launcher" || return 1
      fixture_launch_identity=$reply[20]
      _fixture_record "$fixture_child" || return 1
      fixture_child_identity=$reply[20]
      _zsh_stop_unidentified_launcher "$fixture_launcher" "$fixture_launch_identity" "$sysparams[pid]"
      if [[ $mode == reparent || $mode == transition ]]; then
        wait_dead "$fixture_child" || return 1
      fi
      if _fixture_record "$fixture_child"; then
        [[ $reply[1] != T && $reply[1] != t ]] || return 1
        if [[ $mode == reparent || $mode == transition ]]; then
          [[ $reply[1] == Z ]] || return 1
        fi
      fi
      [[ $(<"$FIXTURE_CASE/signals") != *"-STOP $fixture_child"* ]] || return 1
      if [[ $mode == launcher-gone ]]; then
        [[ $(<"$FIXTURE_CASE/signals") != *"-KILL $fixture_launcher"* ]] || return 1
      fi
      if [[ $mode == transition ]]; then
        [[ -s $FIXTURE_CASE/group ]] || return 1
        row=( ${=$(<"$FIXTURE_CASE/group")} )
        wait_dead "$row[2]" || return 1
      fi
      wait_dead "$fixture_launcher" || return 1
      print -r -- "ok: $mode cleanup never strands a stopped task or kills an unverified launcher"
    } always {
      # Preserve ownership checks even in failing fixtures.
      if [[ -n ${fixture_child:-} && -n ${fixture_child_identity:-} ]] && _fixture_record "$fixture_child" && [[ $reply[20] == "$fixture_child_identity" ]]; then
        if [[ $reply[3] == "$fixture_child" && $reply[4] == "$fixture_child" ]]; then
          _zsh_stop_owned_group "$fixture_child" "$fixture_child_identity" 1
        else
          builtin kill -KILL "$fixture_child" 2>/dev/null
        fi
      fi
      if [[ -n ${fixture_launch_identity:-} ]] && _fixture_record "$fixture_launcher" && [[ $reply[20] == "$fixture_launch_identity" && $reply[2] == "$sysparams[pid]" ]]; then
        builtin kill -KILL "$fixture_launcher" 2>/dev/null
      fi
      builtin wait "$fixture_launcher" 2>/dev/null
    }
    }
    run_fixture
  ) || { print -u2 -r -- "not ok: $mode launcher fault fixture"; exit 1; }
done
