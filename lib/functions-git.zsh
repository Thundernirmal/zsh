# Trusted lazy git implementations; loaded by functions-catalogue.zsh.

# Jump to the root of the current git repository
croot() {
  emulate -L zsh

  case ${1:-} in
    -h|--help)
      print 'Usage: croot'
      print 'Change to the root directory of the current Git repository.'
      return 0
      ;;
  esac
  if (( $# > 0 )); then
    print -u2 -r -- 'Usage: croot'
    return 1
  fi

  local root

  root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    print -u2 -r -- 'Not in a git repo'
    return 1
  }

  builtin cd -- "$root" || return
}

# Show contributor counts for the current repo history
function gitcount() {
  emulate -L zsh

  case ${1:-} in
    -h|--help)
      print 'Usage: gitcount'
      print 'Count non-merge commits by contributor in the current Git repository.'
      return 0
      ;;
  esac
  if (( $# > 0 )); then
    print -u2 -r -- 'Usage: gitcount'
    return 1
  fi

  git rev-parse --git-dir >/dev/null 2>&1 || {
    print -u2 -r -- 'Not in a git repo'
    return 1
  }

  git rev-parse --verify HEAD >/dev/null 2>&1 || {
    echo "No commits yet"
    return 0
  }

  git shortlog -sn --no-merges HEAD
}

# Emit NUL-delimited branch/path pairs for registered Git worktrees.
_fbr_worktree_entries() {
  emulate -L zsh

  local excluded_path=${1-} field worktree_path

  [[ -n $excluded_path ]] && excluded_path=${excluded_path:A}

  while IFS= read -r -d '' field; do
    case $field in
      'worktree '*)
        worktree_path=${field#worktree }
        ;;
      'branch refs/heads/'*)
        if [[ -n $excluded_path && ${worktree_path:A} == $excluded_path ]]; then
          continue
        fi
        print -rn -- "${field#branch }"$'\0'"$worktree_path"$'\0'
        ;;
    esac
  done < <(command git worktree list --porcelain -z)
}

# Enter a branch's worktree, or check out the branch when it has none.
_fbr_activate() {
  emulate -L zsh

  local branch=$1 worktree_path=${2-} local_branch upstream

  if [[ -n $worktree_path ]]; then
    builtin cd -- "$worktree_path"
    return
  fi

  if [[ $branch == refs/heads/* ]] && command git show-ref --verify --quiet "$branch"; then
    local_branch=${branch#refs/heads/}
    command git switch -- "$local_branch"
    return
  fi

  if [[ $branch == refs/remotes/* ]] && command git show-ref --verify --quiet "$branch"; then
    local_branch=${branch#refs/remotes/}
    local_branch=${local_branch#*/}
    if ! command git show-ref --verify --quiet "refs/heads/$local_branch"; then
      command git switch --track -- "$branch"
      return
    fi
    upstream=$(command git for-each-ref --format='%(upstream)' "refs/heads/$local_branch" 2>/dev/null) || upstream=''
    if [[ $upstream == "$branch" ]]; then
      command git switch -- "$local_branch"
      return
    fi
    if [[ -n $upstream ]]; then
      print -u2 -r -- "Remote '$branch' does not track local '$local_branch' (upstream: '$upstream'). Refusing to switch."
    else
      print -u2 -r -- "Remote '$branch' does not track local '$local_branch' (no upstream). Refusing to switch."
    fi
    print -u2 -r -- "To enter the local branch: git switch -- ${(q)local_branch}"
    print -u2 -r -- "To track the remote under a new name: git switch --track -b NEW_BRANCH -- ${(q)branch}"
    print -u2 -r -- "To inspect the remote without changing branches: git switch --detach -- ${(q)branch}"
    return 1
  fi

  print -u2 -r -- "Branch '$branch' was not found"
  return 1
}

# Display labels are separate from canonical refs used by selection/preview.
_fbr_ref_rows() {
  emulate -L zsh

  local badge_color=$1 badge_reset=$2
  shift 2
  local -A worktree_paths=( "$@" )
  local ref_line ref details symbolic relative subject display_branch worktree_path
  while IFS= read -r ref_line; do
    ref=${ref_line%%$'\t'*}
    details=${ref_line#*$'\t'}
    symbolic=${details%%$'\t'*}
    # Exclude remote symbolic aliases, without hiding branches named */HEAD.
    [[ $ref == refs/remotes/* && -n $symbolic ]] && continue
    details=${details#*$'\t'}
    relative=${details%%$'\t'*}
    subject=${details#*$'\t'}
    case $ref in
      refs/heads/*) display_branch=${ref#refs/heads/} ;;
      refs/remotes/*) display_branch=${ref#refs/remotes/} ;;
      *) continue ;;
    esac
    worktree_path=${worktree_paths[$ref]-}
    _fbr_format_entry "$display_branch" "$relative" "$subject" "$worktree_path" \
      "$badge_color" "$badge_reset" 32 14 "$ref"
    print -r -- "$REPLY"
  done < <(
    command git for-each-ref --sort=-committerdate \
      --format=$'%(refname)\t%(symref)\t%(committerdate:relative)\t%(subject)' \
      refs/heads refs/remotes
  )
}

# Fuzzy-pick a Git branch, entering its worktree or checking it out.
fbr() {
  emulate -L zsh

  case ${1:-} in
    -h|--help)
      print 'Usage: fbr'
      print 'Pick a local or remote branch and enter its worktree or check it out.'
      return 0
      ;;
  esac

  if (( $# > 0 )); then
    print -u2 -r -- 'Usage: fbr'
    return 1
  fi

  _zsh_require_fzf || return 1

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    print -u2 -r -- 'fbr requires an interactive terminal'
    return 1
  fi

  command git rev-parse --git-dir >/dev/null 2>&1 || {
    print -u2 -r -- 'Not in a git repo'
    return 1
  }

  local selection branch current_worktree worktree_branch worktree_path
  local worktree_badge_color='' worktree_badge_reset='' preview_command short_name upstream
  local -A worktree_paths
  local -a fzf_args context_args preview_args
  if ! _ui_plain_mode; then
    if _zsh_theme_sgr success fg ui; then
      worktree_badge_color=$REPLY
      worktree_badge_reset=$'\e[0m'
    fi
  fi

  if [[ -n ${NO_COLOR:-} ]]; then
    # fzf quotes field placeholders before invoking the preview shell.
    preview_command='git log --oneline --decorate --color=never -20 {5}'
  else
    preview_command='git log --oneline --decorate --color=always -20 {5}'
  fi
  _fzf_picker_context_args Branches 'Type to filter branches' 'Enter worktree/checkout  Ctrl-P preview  Ctrl-/ wrap  Esc close'
  context_args=( "${reply[@]}" )
  _fzf_picker_preview_args Log
  preview_args=( "${reply[@]}" )
  fzf_args=(
    "${context_args[@]}"
    "${preview_args[@]}"
    --ansi
    --delimiter=$'\t'
    --with-nth=1,2,3
    --nth=1,2,3
    --accept-nth=5
    --freeze-left=1
    --no-multi
    "--preview=$preview_command"
  )

  current_worktree=$(command git rev-parse --show-toplevel 2>/dev/null) || current_worktree=''
  while IFS= read -r -d '' worktree_branch && IFS= read -r -d '' worktree_path; do
    worktree_paths[$worktree_branch]=$worktree_path
  done < <(_fbr_worktree_entries "$current_worktree")

  selection=$(
    _fbr_ref_rows "$worktree_badge_color" "$worktree_badge_reset" "${(@kv)worktree_paths}" |
      command fzf "${fzf_args[@]}"
  ) || return 0

  branch=$selection

  worktree_path=${worktree_paths[$branch]-}
  if [[ -z $worktree_path && $branch == refs/remotes/* ]] && command git show-ref --verify --quiet "$branch"; then
    short_name=${branch#refs/remotes/}
    short_name="refs/heads/${short_name#*/}"
    if [[ -n ${worktree_paths[$short_name]-} ]]; then
      upstream=$(command git for-each-ref --format='%(upstream)' "$short_name" 2>/dev/null) || upstream=''
      if [[ $upstream == "$branch" ]]; then
        worktree_path=${worktree_paths[$short_name]}
      fi
    fi
  fi

  _fbr_activate "$branch" "$worktree_path"
}

