#!/usr/bin/env zsh
# Synthetic ownership failures; never invoke a live package manager.
emulate -L zsh
setopt NO_UNSET NO_MONITOR
repo_dir=${0:A:h:h}
source "$repo_dir/60-functions.zsh"
upkg help >/dev/null || exit 1
_zsh_functions_load_domain nix || exit 1
zmodload zsh/system || exit 1
zmodload zsh/zselect || exit 1
scratch=$(command mktemp -d) || exit 1
zsh_bin=$(whence -p zsh)
setsid_bin=$(whence -p setsid)
original_path=$PATH
# Ambient private variable names must never register arbitrary cleanup paths.
command mkdir "$scratch/unrelated-storage"
command chmod 700 "$scratch/unrelated-storage"
print sentinel > "$scratch/unrelated-storage/sentinel"
_ZSH_QUERY_ROOT_PID=1
_ZSH_QUERY_ROOT_IDENTITY=invalid
_ZSH_QUERY_ROOT_CLEANUP_DIRS=( "$scratch/unrelated-storage" )
local owner='' unrelated='' case_dir mode phase group identity pid text
local -a groups pids fields leftovers
local -A group_identities
cleanup() {
  if [[ -n $owner ]]; then builtin kill -KILL "$owner" 2>/dev/null; builtin wait "$owner" 2>/dev/null; owner=''; fi
  for group in "${groups[@]}"; do _zsh_stop_owned_group "$group" "${group_identities[$group]}" 1; done
  if [[ -n $unrelated ]]; then builtin kill -TERM "$unrelated" 2>/dev/null; builtin wait "$unrelated" 2>/dev/null; unrelated=''; fi
  command rm -rf -- "$scratch"
}
trap cleanup EXIT
fail() { print -u2 -r -- "not ok: $*"; exit 1; }
alive() {
  local pid=$1 text
  local -a fields
  [[ -r /proc/$pid/stat ]] || return 1
  text=$(</proc/$pid/stat); fields=( ${=${text##*\) }} )
  [[ ${fields[1]-} != Z ]]
}
record_groups() {
  local file group identity
  for file in "$case_dir"/tmp/zsh-query-owner.*/identity(N); do
    local -a row=( ${=$(<"$file")} )
    group=$row[1]; identity=$row[2]
    groups+=( "$group" ); group_identities[$group]=$identity
  done
}
check_gone() {
  local pid
  integer ticks=0 remaining=1
  while (( remaining && ticks++ < 200 )); do
    remaining=0
    for pid in "$@"; do alive "$pid" && remaining=1; done
    (( ! remaining )) || zselect -t 1
  done
  (( ! remaining )) || fail 'abandoned process remained alive'
  leftovers=( "$case_dir"/tmp/*(ND) )
  (( ${#leftovers} == 0 )) || fail "abandoned storage remains: $leftovers"
  builtin kill -0 "$unrelated" 2>/dev/null || fail 'unrelated job was stopped'
  [[ $(<"$scratch/unrelated-storage/sentinel") == sentinel ]] || fail 'ambient cleanup path was used'
}
command sleep 30 &
unrelated=$!
command mkdir "$scratch/bin"
command cat > "$scratch/backend" <<'BACKEND'
#!/bin/sh
sleep 30 &
child=$!
printf '%s %s\n' "$$" "$child" >> "$OWNERSHIP_PIDS"
trap ': > "$OWNERSHIP_TERM"; sleep 30 & late=$!; printf "%s\n" "$late" >> "$OWNERSHIP_PIDS"; wait "$child"; exit 143' TERM
wait "$child"
BACKEND
command cat > "$scratch/bin/nix" <<'NIX'
#!/bin/sh
shift 2
if [ "$OWNERSHIP_MODE" = profile ] || [ "$1" = eval ]; then
  exec sh "$OWNERSHIP_BACKEND"
fi
if [ "$OWNERSHIP_MODE" = worker-root-race ]; then
  printf '%s\n' '{"elements":{"one":{"originalUrl":"nixpkgs","attrPath":"legacyPackages.test.one","storePaths":["/nix/store/one"]}}}'
  exit 0
fi
printf '%s\n' '{"elements":{"one":{"originalUrl":"nixpkgs","attrPath":"legacyPackages.test.one","storePaths":["/nix/store/one"]},"two":{"originalUrl":"nixpkgs","attrPath":"legacyPackages.test.two","storePaths":["/nix/store/two"]}}}'
NIX
command chmod +x "$scratch/backend" "$scratch/bin/nix"
for mode in query completed profile evaluation worker worker-root-race; do
  [[ $mode != profile && $mode != evaluation && $mode != worker && $mode != worker-root-race ]] || command -v jq >/dev/null 2>&1 || continue
  case_dir="$scratch/$mode"
  command mkdir -p "$case_dir/tmp"
  export OWNERSHIP_PIDS="$case_dir/pids" OWNERSHIP_BACKEND="$scratch/backend" OWNERSHIP_MODE=$mode OWNERSHIP_TERM="$case_dir/term"
  (
    trap - EXIT
    export TMPDIR="$case_dir/tmp" PATH="$scratch/bin:$original_path"
    case $mode in
      query) _upkg_capture_query sh "$scratch/backend" ;;
      completed)
        _zsh_stop_owned_group() { : > "$case_dir/ready"; while true; do zselect -t 1; done; }
        _upkg_capture_query true ;;
      *) _upkg_run_outdated_nix ;;
    esac
  ) > "$case_dir/stdout" 2> "$case_dir/stderr" &
  owner=$!
  integer ticks=0 expected=1
  [[ $mode != evaluation && $mode != worker ]] || expected=2
  while (( ticks++ < 300 )); do
    if [[ $mode == completed ]]; then
      [[ -e $case_dir/ready ]] && break
    elif [[ -s $OWNERSHIP_PIDS ]]; then
      pids=( ${=$(<"$OWNERSHIP_PIDS")} )
      (( ${#pids} >= expected * 2 )) && break
    fi
    zselect -t 1
  done
  (( ticks <= 300 )) || fail "$mode fixture did not start"
  record_groups
  if [[ $mode == worker || $mode == worker-root-race ]]; then
    # Loss of one worker must not delete root-owned sibling capture storage.
    local worker_group=${groups[-1]} worker_pid=''
    text=$(</proc/$worker_group/stat); fields=( ${=${text##*\) }} ); worker_pid=$fields[2]
    # Hold the root in place so the grace-period race is deterministic.
    [[ $mode != worker-root-race ]] || builtin kill -STOP "$owner" || fail 'could not stop root for race fixture'
    builtin kill -KILL "$worker_pid" || fail 'could not kill recorded worker'
    if [[ $mode == worker-root-race ]]; then
      # Kill the root during the worker's TERM grace, not before or after it.
      ticks=0
      while [[ ! -e $OWNERSHIP_TERM ]] && (( ticks++ < 100 )); do zselect -t 1; done
      [[ -e $OWNERSHIP_TERM ]] || fail 'worker shutdown did not enter its TERM grace'
    else
      ticks=0
      while alive "$worker_group" && (( ticks++ < 200 )); do zselect -t 1; done
      alive "$worker_group" && fail 'worker-owned session remained alive'
      leftovers=( "$case_dir"/tmp/npkg-outdated.*(N) )
      (( ${#leftovers} == 1 )) || fail 'worker loss removed shared batch storage'
      alive "$owner" || fail 'worker loss stopped root owner'
    fi
  fi
  builtin kill -KILL "$owner" || fail 'could not kill query owner'
  builtin wait "$owner" 2>/dev/null
  owner=''
  if [[ -s $OWNERSHIP_PIDS ]]; then pids=( ${=$(<"$OWNERSHIP_PIDS")} ); else pids=(); fi
  check_gone "${groups[@]}" "${pids[@]}"
  print -r -- "ok: $mode owner loss stops private sessions and removes owned storage"
done

# Failed completion publication must not leave an owner waiting forever.
case_dir="$scratch/status-error"
command mkdir -p "$case_dir/tmp"
export OWNERSHIP_GROUP="$case_dir/group"
command cat > "$case_dir/backend" <<'STATUS_FAILURE'
#!/bin/sh
for control in "$TMPDIR"/zsh-query-owner.*; do
  cat "$control/identity" > "$OWNERSHIP_GROUP"
  mkdir "$control/status"
done
printf '%s\n' 'captured bytes'
STATUS_FAILURE
(
  trap - EXIT
  export TMPDIR="$case_dir/tmp"
  _upkg_capture_query sh "$case_dir/backend"
  local rc=$?
  print -r -- "$rc:$_UPKG_QUERY_STDOUT" > "$case_dir/result"
) > "$case_dir/stdout" 2> "$case_dir/stderr" &
owner=$!
ticks=0
while [[ ! -s $OWNERSHIP_GROUP ]] && (( ticks++ < 100 )); do zselect -t 1; done
[[ -s $OWNERSHIP_GROUP ]] || fail 'completion publication fixture did not start'
fields=( ${=$(<"$OWNERSHIP_GROUP")} )
groups+=( "$fields[1]" ); group_identities[$fields[1]]=$fields[2]
ticks=0
while [[ ! -s $case_dir/result ]] && (( ticks++ < 200 )); do zselect -t 1; done
[[ -s $case_dir/result ]] || fail 'failed completion publication caused an unbounded wait'
builtin wait "$owner" || fail 'completion publication harness failed'
owner=''
[[ $(<"$case_dir/result") == '1:captured bytes' ]] || fail 'failed completion publication lost status or captured data'
check_gone "${groups[@]}"
print 'ok: failed completion publication terminates and retains captured data'

# A faithful startup failure: session leader ignores TERM and never publishes identity.
command mkdir -p "$scratch/slow/lib" "$scratch/fork-bin"
command cat > "$scratch/slow/lib/query-supervisor.zsh" <<'SLOW'
emulate -L zsh
zmodload zsh/system
zmodload zsh/zselect
trap '' TERM
local pid=$sysparams[pid] text
local -a fields
text=$(</proc/$pid/stat); fields=( ${=${text##*\) }} )
print -r -- "$pid ${fields[20]}" > "$OWNERSHIP_GROUP"
command sleep 30 &
print -r -- "$pid $!" > "$OWNERSHIP_PIDS"
while true; do zselect -t 1; done
SLOW
print -r -- '#!/bin/sh' > "$scratch/fork-bin/setsid"
printf 'exec %q --fork "$@"\n' "$setsid_bin" >> "$scratch/fork-bin/setsid"
command chmod +x "$scratch/fork-bin/setsid"
for mode in direct fork; do
  case_dir="$scratch/slow-$mode"
  command mkdir -p "$case_dir/tmp"
  export OWNERSHIP_PIDS="$case_dir/pids" OWNERSHIP_GROUP="$case_dir/group"
  (
    trap - EXIT
    export TMPDIR="$case_dir/tmp"
    [[ $mode != fork ]] || export PATH="$scratch/fork-bin:$original_path"
    _ZSH_FUNCTIONS_MODULE_DIR="$scratch/slow"
    _upkg_capture_query true
    local rc=$?
    print -u2 -r -- "$_UPKG_QUERY_STDERR"
    print -r -- "$rc" > "$case_dir/result"
  ) > "$case_dir/stdout" 2> "$case_dir/stderr" &
  owner=$!
  ticks=0
  while [[ ! -s $OWNERSHIP_GROUP ]] && (( ticks++ < 100 )); do zselect -t 1; done
  [[ -s $OWNERSHIP_GROUP ]] || fail 'delayed supervisor did not start'
  fields=( ${=$(<"$OWNERSHIP_GROUP")} )
  groups+=( "$fields[1]" ); group_identities[$fields[1]]=$fields[2]
  ticks=0
  while [[ ! -s $case_dir/result ]] && (( ticks++ < 500 )); do zselect -t 1; done
  [[ -s $case_dir/result ]] || fail 'missing identity caused an unbounded wait'
  builtin wait "$owner" || fail 'startup harness failed'
  owner=''
  [[ $(<"$case_dir/result") == 1 ]] || fail 'startup failure did not return status1'
  [[ $(<"$case_dir/stderr") == *'did not establish its identity'* ]] || fail "startup failure lacks diagnostic: $(<"$case_dir/stderr")"
  pids=( ${=$(<"$OWNERSHIP_PIDS")} )
  check_gone "${groups[@]}" "${pids[@]}"
  print -r -- "ok: $mode missing identity shuts down within its startup budget"
done
