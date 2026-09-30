# ZSH-011: Git branch selection fails when short reference names are ambiguous

| Field | Value |
| --- | --- |
| Status | Open; not fixed by this documentation change |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `12e276a` |
| Affected surface | fbr; local and remote branch activation |
| Evidence | Reproduced during audit; independently checked by a review subagent |

## Summary

The branch picker uses Git's display-oriented short ref abbreviation as an activation identifier. When Git adds a namespace prefix to disambiguate refs, activation reconstructs the wrong full ref and refuses a valid selection.

## Affected code and documentation

- [lib/functions-git.zsh](../../lib/functions-git.zsh): `fbr`, `_fbr_activate`, and `_fbr_worktree_entries`.
- [functions/_fbr_format_entry](../../functions/_fbr_format_entry): display and selection payload.
- [scripts/test-functions.zsh](../../scripts/test-functions.zsh): Git picker and worktree fixtures.
- [GUIDE.md](../../GUIDE.md): branch activation and alternate worktrees.

## Trigger and reproduction

Run in a fresh Zsh shell from the repository root. The Git repository and commits are temporary.

```zsh
source "$PWD/60-functions.zsh"
_zsh_functions_load git
scratch=$(mktemp -d /tmp/zsh-issue-git.XXXXXX) || exit 1
trap 'command rm -rf -- "$scratch"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
command git -C "$scratch" init -q
command git -C "$scratch" -c user.name=Audit -c user.email=audit@example.invalid   commit --allow-empty -qm initial
command git -C "$scratch" branch origin/topic
command git -C "$scratch" update-ref refs/remotes/origin/topic HEAD
builtin cd -- "$scratch"
command git for-each-ref --format='%(refname:short)' refs/heads refs/remotes
_fbr_activate heads/origin/topic
print -r -- "activation-status=$?"
```

Audit result: the enumeration included `heads/origin/topic` and `remotes/origin/topic`; activation returned 1 with `Branch 'heads/origin/topic' was not found`. A picker stub returning that row reproduces the public `fbr` failure.

## Current behavior and impact

A branch shown in the picker cannot be activated. Worktree lookup uses another short-name representation, so a disambiguated selection can also fail to find its existing worktree. The refs are valid; the defect is loss of stable identity between enumeration, display, selection, and activation.

## Root cause

`%(refname:short)` produces a non-ambiguous abbreviation, not necessarily just the branch name. Activation assumes it can always prepend `refs/heads/` or `refs/remotes/`. Worktree and upstream comparisons make similar assumptions about short strings.

## Fix goal and expected behavior

Carry canonical full refs as hidden selection identities and keep display labels separate. Selecting a local branch must activate that exact ref or enter its registered worktree. Selecting a remote must preserve existing tracking/collision safeguards and use its exact remote identity. Ambiguity in a display label must not change behavior.

## Implementation constraints

- Update preview payloads, activation, upstream checks, and worktree mapping consistently.
- Preserve undecorated selection values and terminal-cell-aligned display.
- Do not silently switch an unrelated local branch for a remote selection.
- Preserve unusual valid branch names and safe argument quoting.
- Continue excluding symbolic remote HEAD entries without losing legitimate branches.

## Acceptance criteria

- [ ] Local `origin/topic` and remote `origin/topic` can each be selected and identified correctly.
- [ ] A tag colliding with a branch display name does not break branch activation.
- [ ] Worktree navigation uses canonical identity and reaches the correct directory.
- [ ] Remote tracking creation and existing-upstream checks retain their safeguards.
- [ ] Preview uses the selected canonical ref.
- [ ] Ordinary branches, cancellation, and display alignment remain unchanged.

## Validation plan

Extend temporary Git fixtures in `scripts/test-functions.zsh` with namespace collisions, tag collisions, and associated worktrees. Use a fake fzf to select full rows and assert resulting branch or directory. Run `zsh scripts/run-tests.zsh`; check picker rendering with the existing fzf terminal tests when payload columns change.

## References

- [Git for-each-ref: refname and short abbreviation](https://git-scm.com/docs/git-for-each-ref)
- [Git worktree manual](https://git-scm.com/docs/git-worktree)
