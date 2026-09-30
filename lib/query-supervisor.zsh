# Fixed private-session entrypoint; only trusted callbacks may run here.
emulate -L zsh
setopt NO_MONITOR
zmodload zsh/system || exit 1
zmodload zsh/zselect || exit 1
local control_dir=$1 callback=$2 callback_status=1 signal_status=0 child_pid stat_text
local -a fields
shift 2
trap '(( signal_status )) || signal_status=130' INT
trap '(( signal_status )) || signal_status=143' TERM
trap '(( signal_status )) || signal_status=129' HUP
stat_text=$(</proc/$sysparams[pid]/stat); fields=( ${=${stat_text##*\) }} )
[[ ${fields[3]-} == "$sysparams[pid]" && ${fields[4]-} == "$sysparams[pid]" ]] || exit 1
print -r -- "$sysparams[pid] ${fields[20]}" > "$control_dir/identity"
case $callback in
  command) command "$@" & ;;
  _npkg_nix|_npkg_eval_installable_record)
    source "${0:A:h}/functions-nix.zsh"
    "$callback" "$@" & ;;
  *) exit 1 ;;
esac
child_pid=$!
wait "$child_pid" 2>/dev/null
callback_status=$?
(( ! signal_status )) || callback_status=$signal_status
print -r -- "$callback_status" > "$control_dir/status"
# Remain an anchor until the owner finishes group shutdown, even after TERM.
while true; do zselect -t 10; done
