# `upkg clean` feature specification

Status: Implemented

## Summary

Add an explicit, mutating `upkg clean` command that removes packages and cached data which the selected package managers classify as unused, stale, or unreachable.

The command covers every manager that `upkg` already supports: `apt`, `dnf`, `pacman`, `paru`, `brew`, `flatpak`, `nix`, and `npm`. It reuses the existing runtime detection, manager order, `--only`/`--skip` filters, privilege policy, themed output, and final summary.

The default cleanup policy is intentionally conservative. It uses package-manager cleanup commands instead of deleting cache directories directly, keeps package data retained for rollback or reuse when the manager's normal cleanup preserves it, and never deletes application data or user configuration.

## User goals

- Reclaim disk space through one command across all detected package managers.
- Remove dependencies, runtimes, and store objects that the owning manager says are no longer needed.
- Remove stale package caches, including the npm/npx execution cache and Homebrew's normal cleanup candidates.
- Preserve the safeguards and filtering behavior users already know from `upkg upgrade`.
- Allow a non-mutating preview before cleanup.

## Non-goals

- Do not update package metadata or upgrade packages before cleaning.
- Do not add support for package managers that `upkg` does not already detect.
- Do not delete project-local artifacts such as `node_modules`, lockfiles, virtual environments, or build output.
- Do not delete application data, including Flatpak data under `~/.var/app`.
- Do not purge user-edited package configuration.
- Do not delete Nix profile generations or remove Nix rollback capability.
- Do not force-delete every recreatable cache entry. Aggressive operations such as `apt clean`, `pacman -Scc`, `brew cleanup --prune=all`, and `npm cache clean --force` are outside this feature.
- Do not add an automatic confirmation flag. Native package-manager prompts remain authoritative.
- Do not report an exact reclaimed-byte total; backend output is preserved, but byte reporting is not portable across the supported managers.

## Command-line interface

```text
upkg clean [--only <list>] [--skip <list>] [--sudo] [--dry-run]
```

Examples:

```zsh
upkg clean
upkg clean --dry-run
upkg clean --only brew,npm
upkg clean --skip nix
upkg clean --sudo --only apt
```

Behavior of existing commands does not change. In particular, bare `upkg` remains a read-only outdated-package check.

### Flag behavior

| Flag | Cleanup behavior |
|---|---|
| `--only <list>` / `--only=<list>` | Clean only the named, available managers, in the order given. |
| `--skip <list>` / `--skip=<list>` | Exclude the named managers. |
| `--sudo` | Authorize cleanup for root-managed distro backends. It never auto-confirms a native prompt. |
| `--dry-run` | Perform a read-only preview. No cleanup command may mutate packages, caches, profiles, or manager state. |

`clean` has no alias in the first release. The word `clean` remains a valid search query after `upkg search`, matching the parser's existing treatment of other command words.

## Cleanup policy

Cleanup is manager-owned: `upkg` invokes documented manager operations and does not directly remove files from manager cache directories.

Within a manager, unused packages are removed before caches are cleaned. This allows artifacts associated with newly removed packages to become cleanup candidates in the same run. When a manager has multiple independent cleanup steps, a failed step does not prevent later steps from being attempted; the manager is reported as `partial` or `failed` as described below.

No backend receives an automatic yes flag (`-y`, `--assumeyes`, `--noconfirm`, or equivalent). A user can review and decline any prompt provided by the native manager.

### Backend matrix

| Manager | Unused-package step | Cache/store step | Required behavior |
|---|---|---|---|
| `apt` | `apt autoremove` | `apt autoclean` | Run both as root or through `sudo`. Use `autoclean`, not `clean`, so downloadable archives intentionally retained by APT are preserved. |
| `dnf` | `dnf autoremove` | `dnf clean all` | Run both as root or through `sudo`. `clean all` is DNF's documented cleanup of temporary repository files and cached packages/metadata. |
| `pacman` | Query `pacman -Qtdq`; when non-empty, pass the resulting array to `pacman -Rs --` | `pacman -Sc` | Run mutating steps as root or through `sudo`. Treat an empty orphan query, including pacman's empty exit-1 form, as success. Do not use `-Rn`, which could discard user-edited backup configuration, or `-Scc`, which deletes the complete package cache. |
| `paru` | `paru -c` | `paru -Sc` | Require explicit `--sudo` authorization, but run Paru unprefixed so it retains control of its configured privilege helper. This covers repository/AUR dependency cleanup plus Paru's AUR cache extension. Do not also run a separate pacman handler during the default Paru route. |
| `brew` | `brew autoremove` | `brew cleanup` | Run unprefixed in Homebrew user space. Default cleanup removes stale locks, outdated downloads, old installed formula versions, and downloads beyond Homebrew's configured age. Do not use `--prune=all` or `--scrub`. |
| `flatpak` | `flatpak uninstall --unused --user`, then `flatpak uninstall --unused --system` | Included in uninstall: Flatpak prunes unneeded OSTree objects | Address user and system installations explicitly so duplicate refs cannot make selection ambiguous. Do not pass `--delete-data`, `--force-remove`, or `--assumeyes`. System cleanup may invoke Flatpak's normal polkit authentication. |
| `nix` | None | `nix-collect-garbage` | Delete unreachable store objects only. Never pass `-d`, `--delete-old`, or `--delete-older-than`, because those remove profile generations and rollback history. Do not delete the wrapper-owned `npkg` attribute cache. |
| `npm` | None | `npm cache npx rm`, then `npm cache verify` | Remove all npm-managed npx execution-cache entries, then verify the content-addressable npm cache and let npm garbage-collect unneeded data. Run in user space without checking the global install prefix and never suggest `sudo npm`. Do not fall back to raw directory deletion or `npm cache clean --force`. |

No new shared dependency is introduced. In particular, `paccache` is not required; pacman cleanup uses pacman's own `-Sc` operation.

### Compatibility behavior

- The Nix handler must check that `nix-collect-garbage` is available before invoking it. If it is unexpectedly absent from a detected Nix installation, report the Nix backend as failed with an actionable message; do not substitute direct store deletion.
- `npm cache npx rm` is available in current npm releases but not all older installations. If npm rejects the npx cache subcommand, continue with `npm cache verify`, report npm as `partial`, return nonzero for the overall command, and recommend upgrading npm. Do not delete npm's `_npx` directory directly.
- Existing manager detection remains authoritative. On an Arch-family machine with both Paru and pacman, the default route runs only Paru; `--only pacman` continues to select pacman explicitly.

## Privilege and safety model

`apt`, `dnf`, and `pacman` are blocked when the shell is not root and `--sudo` was not passed. The message must name the selected backend and provide a copyable retry, for example:

```text
apt cleanup requires root; rerun with: upkg clean --sudo --only apt
```

When authorized from a non-root shell, those backends use `sudo` for each mutating native command. If `sudo` is missing, reuse the existing blocked-state behavior and root-shell hint.

Paru follows the existing upgrade policy: `--sudo` is an explicit authorization gate, but `upkg` invokes `paru` directly and allows Paru to call its configured privilege helper.

Homebrew, Nix, and npm are never prefixed with `sudo`. Flatpak keeps its native user/system and polkit model. `upkg` never caches credentials, keeps a sudo loop alive, or adds non-interactive confirmation options.

## Dry-run behavior

`upkg clean --dry-run` must return a useful preview without requiring `--sudo` and without invoking a mutating form of any backend command.

The preview is best-effort because not every manager exposes a complete cleanup simulation:

- Use native read-only simulation/listing when reliable, such as APT simulation, pacman's orphan query, `brew autoremove --dry-run`, `brew cleanup --dry-run`, `nix-collect-garbage --dry-run`, `npm cache npx ls`, and DNF's unneeded-package query.
- For a step without a native dry-run, print the exact command that an actual cleanup would execute and label it `would run`; do not execute it.
- A preview must not claim that a listed command has candidates when the backend cannot provide that information safely.
- Root-managed commands shown in a preview include the required privilege context, but the preview must not call `sudo` or prompt for credentials.
- A successful manager preview records `planned`. A preview probe failure records `failed`, does not stop other managers, and contributes to a nonzero final status.

`--dry-run` remains valid for the existing default/outdated, plan, and upgrade flows. It becomes additionally valid for `clean`; it remains invalid for `search`, `managers`, and `help`.

## Output and status

Rich terminals use a `Package Cleanup` dashboard title, existing manager icons, manager sections, and the shared summary treatment. Plain contexts keep deterministic headings and summary lines.

Native command output and prompts pass through unchanged beneath the manager section. Each multi-step handler also prints a short phase label such as `Unused packages`, `Package cache`, or `npx cache` so users can tell which operation produced the output.

Cleanup adds these summary states:

| State | Meaning | Overall exit status |
|---|---|---|
| `cleaned` | Every cleanup step for the manager exited successfully. This does not guarantee that bytes were reclaimed. | Does not cause failure. |
| `planned` | Every dry-run preview step completed successfully. | Does not cause failure. |
| `partial` | At least one cleanup step succeeded and at least one failed or was unsupported. | Causes exit `1`. |
| `failed` | No required cleanup work completed successfully, or a handler/probe failed. | Causes exit `1`. |
| `blocked` | Required privilege or local capability was not authorized/available. | Causes exit `1`. |
| `skipped` | Existing filters intentionally omitted the manager. | Does not cause failure. |

Multi-manager execution always continues after `partial`, `failed`, or `blocked`, then returns `1` if any selected manager ended in one of those states. Otherwise it returns `0`.

Example plain summary:

```text
Summary:
  apt: blocked - rerun with --sudo --only apt
  brew: cleaned
  npm: partial - npx cache cleanup is unsupported; npm cache verified
```

## Parser, completion, help, and documentation changes

Implementation must update all user-facing surfaces in the same change:

- `60-functions.zsh`: usage panels/text, parser routing, dry-run validation, cleanup handlers, dispatch, and summary states.
- `66-compdefs.zsh`: add `clean:Remove unused packages and stale caches` to `upkg` command completion. Existing flags and manager completion remain available.
- `65-help.zsh`: broaden the `upkg` description from check/search/upgrade to include cleanup, without changing its availability guard.
- `80-tips.zsh`: add a concise cleanup tip and a privileged-cleanup tip where the existing detection guards apply.
- `README.md` and `GUIDE.md`: document the mutating nature of `clean`, the safety boundary, flags, backend matrix, examples, and npm/npx behavior.
- `scripts/test-upkg.zsh`, `scripts/test-completions.zsh`, and `scripts/test-help.zsh`: cover the behavior below.

Because this changes user-facing workflow, the documentation and tips updates are required by the repository rules. `scripts/check-deps.sh` does not change because the feature introduces no shared dependency.

## Required automated coverage

### Routing and validation

- `upkg clean` is recognized and bare `upkg` still routes to `outdated`.
- `upkg search clean --only npm` passes `clean` to npm as the search query.
- `--only` order and `--skip` behavior are unchanged for cleanup.
- `upkg clean --dry-run` is accepted; `--dry-run` remains rejected for unsupported commands.
- Help and completion expose `clean` and describe `--sudo` as authorizing privileged backends, not only upgrades.

### Safety and privilege

- Non-root APT, DNF, and pacman cleanup is blocked without `--sudo`; no mutating fake backend is invoked.
- Authorized distro cleanup uses `sudo` for both package and cache phases.
- Paru requires the authorization flag but is invoked without an outer `sudo`.
- Homebrew, Nix, and npm never receive `sudo`.
- No handler sends an automatic-confirmation or aggressive cleanup flag.
- Nix cleanup never receives generation-deletion flags.
- Flatpak cleanup never receives `--delete-data` or `--force-remove`.
- Dry-run tests log every fake invocation and prove that no mutating form was called.

### Manager behavior

- APT runs autoremove before autoclean.
- DNF runs autoremove before clean-all.
- Pacman removes a non-empty orphan array before `-Sc`; an empty `pacman -Qtdq` exit `1` is normal and still reaches cache cleanup.
- Paru runs `-c` before `-Sc` and does not duplicate the pacman route.
- Homebrew runs autoremove before cleanup and uses both native dry-run forms during preview.
- Flatpak cleans user then system unused refs and reports partial success if only one installation succeeds.
- Nix runs garbage collection without deleting profile generations.
- npm removes the npx cache before verifying the npm cache; an unsupported npx subcommand plus successful verification produces `partial` and exit `1`.
- A failed first phase still allows the second independent phase to run.

### Output and exit status

- Plain and forced-rich cleanup paths use the correct title/sections and include a final summary.
- `cleaned`, `planned`, `partial`, `failed`, `blocked`, and `skipped` render with the intended summary roles.
- A fully successful run exits `0`; any partial, failed, or blocked selected manager makes the final exit status `1` after all selected managers run.

## Acceptance criteria

The feature is complete when:

1. `upkg clean` safely covers all eight existing manager IDs according to the backend matrix.
2. The npm path removes the npx cache through npm and verifies/garbage-collects the normal npm cache.
3. The Homebrew path removes unused formula dependencies and performs standard Homebrew cleanup.
4. Root-managed distro cleanup cannot run accidentally without root or explicit `--sudo` authorization.
5. `upkg clean --dry-run` invokes no mutating backend command.
6. One backend or phase failing does not prevent independent cleanup work for later phases/managers.
7. Help, completion, tips, README, GUIDE, and regression tests agree with the implemented behavior.
8. All repository verification commands in `AGENTS.md` pass in order.

## Upstream command references

- [APT `autoremove`, `autoclean`, and `clean`](https://manpages.debian.org/bookworm/apt/apt-get.8.en.html)
- [DNF `autoremove` and `clean`](https://dnf.readthedocs.io/en/stable/command_ref.html)
- [pacman orphan and cache-cleaning options](https://man.archlinux.org/man/pacman.8.en)
- [Paru's extended `-Sc` and no-operation `-c`](https://github.com/Morganamilo/paru/blob/master/man/paru.8)
- [Homebrew `autoremove` and `cleanup`](https://docs.brew.sh/Manpage)
- [Flatpak `uninstall --unused`](https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-uninstall)
- [Nix garbage collection and generation-deletion risks](https://nix.dev/manual/nix/2.34/command-ref/nix-collect-garbage)
- [npm and npx cache commands](https://docs.npmjs.com/cli/cache/)
