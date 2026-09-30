# Fixed private-session entrypoint; only trusted callbacks may run here.
emulate -L zsh
setopt NO_MONITOR
zmodload zsh/system || exit 1
zmodload zsh/zselect || exit 1
zmodload zsh/stat || exit 1
local control_dir=$1 owner_pid=$2 owner_identity=$3 root_pid=$4 root_identity=$5
integer cleanup_count=$6 callback_status=1 signal_status=0 root_alive=1
shift 6
local -a cleanup_dirs=( "$control_dir" ) root_dirs fields
while (( cleanup_count-- > 0 )); do root_dirs+=( "$1" ); shift; done
local callback=$1 child_pid='' child_identity='' stat_text dir pid identity supervisor_pid=$sysparams[pid]
local -A directory_identities info
shift
trap '(( signal_status )) || signal_status=130' INT
trap '(( signal_status )) || signal_status=143' TERM
trap '(( signal_status )) || signal_status=129' HUP
_supervisor_process_alive() {
  local pid=$1 identity=$2 stat_text
  local -a fields
  [[ $pid == <-> && -r /proc/$pid/stat ]] || return 1
  stat_text=$(</proc/$pid/stat); fields=( ${=${stat_text##*\) }} )
  [[ ${fields[1]-} != Z && ${fields[20]-} == "$identity" ]]
}
# Record only private directories created by the trusted calling workflows.
for dir in "$control_dir" "${root_dirs[@]}"; do
  [[ -n $dir && -d $dir && ! -L $dir ]] || continue
  zstat -H info -- "$dir" 2>/dev/null || continue
  (( info[uid] == EUID && (info[mode] & 8#77) == 0 )) || continue
  directory_identities[$dir]="$info[device]:$info[inode]"
done
_supervisor_cleanup() {
  local dir
  local -A info
  for dir in "${cleanup_dirs[@]}"; do
    [[ -d $dir && ! -L $dir && -n ${directory_identities[$dir]-} ]] || continue
    zstat -H info -- "$dir" 2>/dev/null || continue
    [[ "$info[device]:$info[inode]" == "${directory_identities[$dir]}" ]] || continue
    command rm -rf -- "$dir"
  done
}
_supervisor_shutdown() {
  # Keep the anchor alive while TERM handlers can still fork group members.
  builtin kill -TERM -- "-$supervisor_pid" 2>/dev/null
  zselect -t 10
  # The root can disappear while a worker is already shutting down.
  _supervisor_process_alive "$root_pid" "$root_identity" || root_alive=0
  (( root_alive )) || cleanup_dirs+=( "${root_dirs[@]}" )
  _supervisor_cleanup
  builtin kill -KILL -- "-$supervisor_pid" 2>/dev/null
  exit 1
}
_supervisor_check_owner() {
  root_alive=1
  _supervisor_process_alive "$root_pid" "$root_identity" || root_alive=0
  if (( ! root_alive )) || ! _supervisor_process_alive "$owner_pid" "$owner_identity"; then
    _supervisor_shutdown
  fi
}
stat_text=$(</proc/$supervisor_pid/stat); fields=( ${=${stat_text##*\) }} )
[[ ${fields[3]-} == "$supervisor_pid" && ${fields[4]-} == "$supervisor_pid" ]] || exit 1
_supervisor_check_owner
print -r -- "$supervisor_pid ${fields[20]}" > "$control_dir/identity" || _supervisor_shutdown
case $callback in
  command) command "$@" & ;;
  _npkg_nix|_npkg_eval_installable_record)
    source "${0:A:h}/functions-nix.zsh"
    "$callback" "$@" & ;;
  *) exit 1 ;;
esac
child_pid=$!
if [[ -r /proc/$child_pid/stat ]]; then
  stat_text=$(</proc/$child_pid/stat); fields=( ${=${stat_text##*\) }} )
  [[ ${fields[2]-} != "$supervisor_pid" ]] || child_identity=${fields[20]-}
fi
# Poll rather than blocking in wait: owner death must interrupt active queries.
while true; do
  _supervisor_check_owner
  [[ -r /proc/$child_pid/stat ]] || break
  stat_text=$(</proc/$child_pid/stat); fields=( ${=${stat_text##*\) }} )
  [[ ${fields[1]-} != Z && ${fields[2]-} == "$supervisor_pid" ]] || break
  [[ -z $child_identity || ${fields[20]-} == "$child_identity" ]] || break
  zselect -t 1
done
wait "$child_pid" 2>/dev/null
callback_status=$?
(( ! signal_status )) || callback_status=$signal_status
print -r -- "$callback_status" > "$control_dir/status" || _supervisor_shutdown
# Pin the group identity until normal shutdown, but never outlive a dead owner.
while true; do _supervisor_check_owner; zselect -t 10; done
