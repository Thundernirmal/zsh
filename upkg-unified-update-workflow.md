# `upkg` Unified Update Workflow

## Summary

Add a new shell function, `upkg`, that provides one consistent entrypoint for checking outdated packages and running upgrades across the package managers available on a given machine.

Execution prep once mutation is allowed:

- Create branch from `master`: `feature/upkg-unified-updates`
- Save this plan to repo root: `UPKG-PLAN.md`

Target manager coverage:

- Ubuntu: `apt`
- Fedora: `dnf`
- Arch / CachyOS: `paru` when present, otherwise `pacman`
- Cross-distro extras: `flatpak`, `nix` via existing `npkg`, and global `npm`

Default behavior:

- `upkg` with no arguments shows outdated packages
- upgrades require an explicit subcommand
- no implicit `sudo`
- multi-manager runs continue on failure and summarize results at the end

## Public Interface

### New command

Define `upkg` in `60-functions.zsh`.

### Commands

```zsh
upkg
upkg outdated
upkg check
upkg list
upkg upgrade [--sudo]
upkg up [--sudo]
upkg update [--sudo]
upkg managers
upkg help
```

Command alias semantics:

- `outdated`, `check`, and `list` are synonyms for the read-only outdated workflow
- `upgrade`, `up`, and `update` are synonyms for the upgrade workflow
- `managers` prints detected backends in execution order and labels alternates that are available only via `--only`

### Flags

```zsh
--only <list>
--skip <list>
--sudo
```

### Flag behavior

- `--only <list>`: comma-separated manager IDs to include
- `--skip <list>`: comma-separated manager IDs to exclude
- `--sudo`: explicitly allow upgrade commands that need system privilege

Privilege handling by backend:

- `apt`, `dnf`, and `pacman`: prefix the native upgrade command with `sudo` only when `--sudo` is passed
- `paru`: require explicit `--sudo` opt-in for the system-upgrade path, but still run `paru` unprefixed so it can handle privilege escalation itself
- `npm`: never use or suggest `sudo`; keep it user-space only

Supported manager IDs:

- `apt`
- `dnf`
- `pacman`
- `paru`
- `flatpak`
- `nix`
- `npm`

## Manager Detection And Selection

### Detection order

1. distro package manager
2. `flatpak`
3. `nix`
4. `npm`

### Distro precedence

- if `paru` exists, use it as the Arch-family backend by default
- if `paru` does not exist but `pacman` does, use `pacman`
- do not run both `paru` and `pacman` by default
- explicit `--only pacman` must still work on systems that also have `paru`

## Backend Commands

### Outdated checks

Use read-only native commands:

- `apt`: `apt list --upgradable`
- `dnf`: `dnf check-update`
- `pacman`: `pacman -Qu`
- `paru`: `paru -Qua`
- `flatpak`: `flatpak remote-ls --updates`
- `nix`: `npkg outdated`
- `npm`: `npm outdated -g --depth=0`

### Upgrades

Use native full-upgrade commands:

- `apt`: `apt update && apt full-upgrade`
- `dnf`: `dnf upgrade --refresh`
- `pacman`: `pacman -Syu`
- `paru`: `paru -Syu`
- `flatpak`: `flatpak update`
- `nix`: `npkg upgrade`
- `npm`: `npm update -g`

## Privilege Policy

No automatic `sudo`.

Upgrade behavior for privileged backends:

- if the shell is not root and `--sudo` is not passed, do not run that backend
- print a clear rerun hint
- continue with non-root backends
- mark the backend as `blocked` in the summary

Root-managed backends:

- `apt`
- `dnf`
- `pacman`

Explicit opt-in backend:

- `paru`

Non-root backends by default:

- `flatpak`
- `nix`
- `npm`

`npm` policy:

- `upkg` should treat global npm upgrades as user-space only
- if the configured global prefix is not writable by the current user, do not suggest `sudo`
- mark npm as `blocked` and print a setup hint telling the user to move the global prefix under their home directory

Example rerun hint:

```zsh
apt upgrade requires root; rerun with: upkg upgrade --sudo --only apt
```

## Output And Exit Behavior

### Output format

For v1, do not build a unified parsed package table across all managers.

Instead:

- print a section header per manager
- print the manager’s native output beneath it
- print a final summary section

Summary states:

- `updates available`
- `up to date`
- `upgraded`
- `blocked`
- `skipped`
- `failed`

State meanings:

- `blocked`: the backend could not run because explicit privilege or required local setup was missing
- `skipped`: the backend was intentionally omitted by selection rules such as `--skip`

### Exit status

- return `0` if all selected managers succeed or have nothing to do
- return `1` if any selected manager fails or is `blocked`
- still continue other managers before returning

## Implementation Details

### Changes in `60-functions.zsh`

Add a new helper cluster near the existing `npkg` block:

- `_upkg_usage`
- `_upkg_parse_manager_list`
- `_upkg_detect_managers`
- `_upkg_apply_filters`
- `_upkg_needs_root`
- `_upkg_run_outdated_<manager>`
- `_upkg_run_upgrade_<manager>`
- `_upkg_print_summary`
- `upkg`

Placement rule:

- define `upkg` and its general helpers outside the nix-only `npkg` guard
- only the Nix bridge should depend on `npkg` being available in the current shell

Implementation style must follow existing repo patterns:

- use `emulate -L zsh`
- use `local` arrays
- guard calls with `command -v ... >/dev/null 2>&1`
- keep portable fallbacks explicit
- avoid introducing new shared dependencies
- parse `--only` and `--skip` lists with native Zsh comma-splitting such as `${(s:,:)list}`

### Nix integration

Reuse the existing `npkg` command rather than duplicating Nix logic.

- outdated: `npkg outdated`
- upgrade: `npkg upgrade`

Special case:

- if `nix` exists but `jq` does not, mark Nix outdated-check as unavailable with a clear reason
- Nix upgrade should still work, because `npkg upgrade` does not require `jq`
- if `npkg` is not defined in the current shell, treat the Nix backend as unavailable instead of assuming it can be called

### Exit-code normalization

Handle manager-specific semantics correctly:

- `dnf check-update`: exit `100` means updates available, not failure
- `npm outdated -g`: outdated results should not be treated as a hard failure; reserve `failed` for real invocation errors
- `pacman -Qu` / `paru -Qua`: empty output means up to date
- `apt list --upgradable`: ignore header-only output, and suppress unstable-CLI warning noise from stderr

### Metadata freshness policy

For v1, `upkg outdated` does not auto-refresh metadata.

Reasoning:

- keeps the default action read-only
- avoids implicit privileged behavior
- avoids unsafe or incomplete refresh flows on Arch-family systems

Documentation must state:

- distro outdated results depend on current local metadata
- the authoritative full system update path is `upkg upgrade --sudo` for root-managed distros
- `npm` upgrades are supported only as a user-space workflow; `upkg` will not recommend `sudo npm`

### Detection source of truth

Runtime detection is the source of truth.

V1 must not require a first-run bootstrap script or a persisted `.zshrc` variable before `upkg` can run.

Reasoning:

- `command -v` detection is cheap and always reflects the current machine state
- a persisted manager variable can go stale after package managers are installed or removed
- `upkg` should fail based on actual backend availability, not on missing setup metadata

Optional future extension:

- a helper script may later print recommended host-specific overrides or setup hints
- optional overrides such as `UPKG_DEFAULT_MANAGERS` can be considered later
- any future helper must stay advisory and must not gate `upkg` execution

## Documentation Changes

### `80-tips.zsh`

Add conditional tips such as:

- `Run upkg to list outdated packages across detected managers`
- `Run upkg upgrade --sudo to upgrade system packages explicitly`
- `Use upkg --only flatpak,npm to limit the run to selected managers`
- `Run upkg managers to see which package backends are active on this machine`

Only show `upkg` tips when at least one supported backend exists.

### `README.md`

Document:

- `upkg` as a new shell function
- supported managers
- default behavior
- explicit `--sudo` policy
- Arch precedence of `paru` over `pacman`
- runtime detection as the source of truth
- npm user-space-only upgrade policy
- no new required shared dependency

### `GUIDE.md`

Add a dedicated `upkg` section with:

- command table
- backend list
- examples
- metadata freshness notes
- `--sudo` behavior
- npm local-prefix setup note
- `managers` output semantics for active vs available-on-request backends
- mixed-manager examples for systems like CachyOS

## `scripts/check-deps.sh`

No changes in v1.

Reason:

- `upkg` is opportunistic
- it uses managers that are already installed on the host
- it does not introduce a new baseline dependency for the shared config itself

## Test Cases And Scenarios

### Required repo verification

Run after implementation:

1. `zsh -n *.zsh`
2. `sh -n scripts/check-deps.sh`
3. `zsh -fc 'source "$HOME/.config/zsh/init.zsh"'`

### Functional smoke tests

Run read-only checks where relevant:

1. `zsh -fc 'source "$HOME/.config/zsh/init.zsh"; upkg help'`
2. `zsh -fc 'source "$HOME/.config/zsh/init.zsh"; upkg managers'`
3. `zsh -fc 'source "$HOME/.config/zsh/init.zsh"; upkg --only nix'`
4. `zsh -fc 'source "$HOME/.config/zsh/init.zsh"; upkg --only flatpak'`
5. `zsh -fc 'source "$HOME/.config/zsh/init.zsh"; upkg --only npm'`

### Behavior scenarios

- no supported managers installed:
  - `upkg` prints a clean “no supported package managers detected” message and exits nonzero
- Fedora with `dnf`, `flatpak`, `nix`, `npm`:
  - `upkg` runs them in that order
- Ubuntu with `apt`, `flatpak`, `npm`:
  - `upkg upgrade` without `--sudo` skips `apt` with a rerun hint and still runs `flatpak` and `npm`
- Arch / CachyOS with `paru`, `pacman`, `flatpak`, `nix`, `npm`:
  - default set is `paru`, `flatpak`, `nix`, `npm`
  - `pacman` runs only if explicitly requested
- Arch / CachyOS with both `paru` and `pacman`:
  - `upkg managers` shows `paru` as active and `pacman` as available via `--only pacman`
- Arch / CachyOS with `paru`:
  - `upkg upgrade --sudo --only paru` runs `paru -Syu` without prefixing the command itself with `sudo`
- `nix` present but `jq` absent:
  - outdated check is unavailable with explanation
  - upgrade still works
- npm global prefix owned by root or otherwise not writable:
  - `upkg upgrade --only npm` marks npm as `blocked`
  - output explains how to move the npm global prefix under the user home directory
  - output does not recommend `sudo npm`
- one backend fails:
  - remaining backends still run
  - overall exit code is nonzero
- invalid `--only` / `--skip` identifiers:
  - print a clear usage error and exit nonzero
- clean shell with no persisted `upkg` variables:
  - `upkg managers` still works after sourcing `init.zsh`

## Acceptance Criteria

The work is complete when:

- `upkg` exists as one entrypoint for outdated checks and upgrades
- it supports `apt`, `dnf`, `paru`/`pacman`, `flatpak`, `nix`, and global `npm`
- `upkg` with no args shows outdated packages
- `upkg upgrade --sudo` performs the native full-upgrade path for root-managed distros
- it never injects `sudo` automatically
- it never recommends or runs `sudo npm`
- it does not require a prewritten `.zshrc` manager variable or bootstrap gate to run
- multi-manager runs continue after failures and summarize the result
- `80-tips.zsh`, `README.md`, and `GUIDE.md` are updated in the same change
- repo verification commands pass

## Assumptions And Defaults Chosen

- branch to create later: `feature/upkg-unified-updates`
- plan file to create later: `UPKG-PLAN.md`
- command name: `upkg`
- default action: `outdated`
- explicit privilege escalation only via `--sudo`
- `outdated`, `check`, and `list` are synonyms
- `upgrade`, `up`, and `update` are synonyms
- continue-on-failure with final summary
- `paru` takes precedence over `pacman`
- `paru` still runs unprefixed even when `--sudo` is used
- runtime detection is the source of truth
- no mandatory bootstrap script or persisted `.zshrc` variable in v1
- npm stays user-space only and should direct users toward a home-directory global prefix
- no unified parsed package table in v1
- no `scripts/check-deps.sh` changes in v1
- out of scope for v1:
  - `snap`
  - `brew`
  - `pipx`
  - `cargo`
  - mandatory first-run setup gates
  - background timers
  - scheduled updates
  - GUI wrappers
