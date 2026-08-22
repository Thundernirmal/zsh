#!/usr/bin/env zsh

# Repeatable warm-start benchmark for the shared configuration. This measures
# both ordinary command-mode sourcing and a normal interactive prompt path.

emulate -L zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL
zmodload zsh/datetime

typeset -r benchmark_root=${0:A:h:h}
integer iterations=${1:-30}
integer warmups=${ZSH_BENCHMARK_WARMUPS:-3}

if (( iterations < 5 )); then
  print -u2 -r -- 'usage: scripts/benchmark-startup.zsh [iterations>=5]'
  exit 2
fi

if [[ $benchmark_root != ${HOME}/.config/zsh ]]; then
  print -u2 -r -- "benchmark requires the repository at ${HOME}/.config/zsh"
  exit 2
fi

typeset zsh_binary=${commands[zsh]:-}
if [[ -z $zsh_binary ]]; then
  print -u2 -r -- 'benchmark requires zsh on PATH'
  exit 2
fi

typeset benchmark_input
benchmark_input=$(command mktemp "${TMPDIR:-/tmp}/zsh-startup-benchmark.XXXXXX")
trap 'command rm -f -- "$benchmark_input"' EXIT INT TERM
print -r -- "source ${(q)benchmark_root}/init.zsh" >| "$benchmark_input"
print -r -- 'exit' >> "$benchmark_input"

export TERM=${TERM:-xterm-256color}
export COLORTERM=${COLORTERM:-truecolor}
export COLUMNS=${COLUMNS:-120}
export LINES=${LINES:-40}

benchmark_mode() {
  emulate -L zsh

  typeset mode=$1
  typeset -a samples
  typeset started
  integer elapsed_us index run

  for (( run = 1; run <= warmups; run++ )); do
    if [[ $mode == interactive ]]; then
      command "$zsh_binary" -dfi < "$benchmark_input" >/dev/null 2>&1
    else
      command "$zsh_binary" -df < "$benchmark_input" >/dev/null 2>&1
    fi
  done

  for (( run = 1; run <= iterations; run++ )); do
    started=$EPOCHREALTIME
    if [[ $mode == interactive ]]; then
      command "$zsh_binary" -dfi < "$benchmark_input" >/dev/null 2>&1
    else
      command "$zsh_binary" -df < "$benchmark_input" >/dev/null 2>&1
    fi
    elapsed_us=$(( (EPOCHREALTIME - started) * 1000000 ))
    samples+=( $elapsed_us )
  done

  samples=( ${(on)samples} )
  index=$(( (iterations + 1) / 2 ))
  integer median_us=${samples[$index]}
  index=$(( (iterations * 95 + 99) / 100 ))
  (( index > iterations )) && index=$iterations
  integer p95_us=${samples[$index]}

  printf '%-11s median=%7.3f ms  p95=%7.3f ms  min=%7.3f ms  max=%7.3f ms  n=%d\n' \
    "$mode" \
    "$(( median_us / 1000.0 ))" \
    "$(( p95_us / 1000.0 ))" \
    "$(( samples[1] / 1000.0 ))" \
    "$(( samples[-1] / 1000.0 ))" \
    "$iterations"
}

benchmark_mode command
benchmark_mode interactive
