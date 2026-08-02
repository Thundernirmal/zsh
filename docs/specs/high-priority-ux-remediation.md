# High-Priority UX and Safety Remediation Specification

| Field | Value |
| --- | --- |
| Status | Proposed |
| Audit date | 2026-08-02 |
| Target | Next stable release |
| Working branch | `spec/high-critical-ux-fixes` |
| Scope | Four High-priority release blockers; the audit identified no separate Critical-severity finding |

## Summary

The next stable release must not ship until all four findings in this specification are resolved. They affect destructive-command safety, the trustworthiness of package-update reporting, compatibility with supported `fzf` installations, and safe rendering of filesystem-controlled text.

This document defines the required user-visible behavior and acceptance criteria. It deliberately avoids prescribing every implementation detail, but it does choose the safety and compatibility policy where ambiguity would otherwise lead to inconsistent fixes.

## Goals

- Restore conventional, safe glob behavior so an unqualified `*` does not silently include hidden files.
- Make `npkg outdated` report package drift without guessing versions or hiding evaluation failures.
- Keep fuzzy-finder features usable on common distribution packages, while degrading quietly when Zsh integration is unavailable.
- Prevent filenames and other path data from injecting terminal control sequences into rich or plain output.
- Preserve clean, fast startup and the existing guarded-integration conventions.

## Non-goals

- Fix Medium- or Low-priority audit findings in the same implementation change.
- Implement semantic version ordering for arbitrary Nix package versions.
- Redesign the package-manager commands, fuzzy-finder theme, or terminal dashboard system.
- Change the intentionally interactive aliases for `cp`, `mv`, or `rm`, except where tests must verify their interaction with glob expansion.
- Modify user-owned `~/.zshrc`, Oh My Zsh, Starship, or machine-local completion wiring.

## Cross-cutting requirements

The implementation must meet all of these constraints:

1. Startup-time command guards continue to use `(( $+commands[tool] ))`; they must not use top-level `command -v` checks.
2. `zsh -i -c ...` and non-interactive sourcing remain free of ZLE warnings, prompts, and unexpected output.
3. External integrations fail closed: an unsupported or broken optional capability is skipped without partially evaluating generated shell code.
4. Plain output remains suitable for pipes and logs. Rich output may contain only control sequences intentionally emitted by the UI layer, never sequences originating in data.
5. User-facing behavior changes are reflected together in `80-tips.zsh`, `README.md`, and `GUIDE.md`.
6. New behavior is covered by deterministic tests using temporary directories and stubbed commands; tests must not depend on the host's installed Nix or `fzf` version.

## HC-01: Hidden files are included in ordinary globs

### Problem

`init.zsh` enables `GLOB_DOTS` globally. As a result, an ordinary `*` includes entries such as `.git`, `.env`, and other hidden state. This violates normal shell expectations and expands the impact of destructive commands. For example, the configured interactive `rm` alias cannot guarantee a prompt when the caller later supplies `-f`, so `rm -rf *` can remove hidden entries as well as visible ones.

### Required behavior

- `init.zsh` must explicitly run `unsetopt GLOB_DOTS`. Explicitly unsetting the option is required because an earlier framework or user layer may have enabled it before sourcing this repository.
- An unqualified `*` and `**/*` must exclude leading-dot entries.
- Users must opt in to hidden matches with explicit Zsh syntax such as `*(D)` or `**/*(D)`, or with a command whose contract includes hidden files, such as `ls -A`.
- Features that intentionally search hidden files, including an `fd --hidden`-backed picker, may retain that behavior when it is explicit in the function rather than inherited from the global shell option.
- The docs and tips must stop claiming that `*` includes dotfiles and must show the explicit `(D)` qualifier instead.

### Acceptance criteria

- In a temporary directory containing `visible`, `.hidden`, and `.git/`, `print -rl -- *` reports only `visible` after sourcing `init.zsh`.
- `print -rl -- *(D)` reports both visible and hidden entries.
- The result is the same when the calling shell has enabled `GLOB_DOTS` before sourcing `init.zsh`.
- A regression test verifies the expansion passed to a stubbed destructive command; it must not execute a real removal.
- Startup remains silent in the existing init smoke-test cases.

### Migration note

Anyone relying on this shared config to make `*` include hidden files must change those commands to use an explicit dotfile pattern or the `(D)` glob qualifier. This is an intentional safety break.

## HC-02: `npkg outdated` can report false upgrades or false success

### Problem

The current implementation derives an installed version from a Nix store-path basename and treats any unequal version strings as an upgrade. Hyphenated or date-like versions can be parsed incorrectly, and an installed version that is newer than the evaluated version is still labeled an upgrade. When evaluation fails, the result becomes `??`, is excluded from the change count, and can still produce `Everything is up to date.` with a successful exit status.

### Decision

Package status must be based on Nix output identity, not semantic interpretation of display strings. A changed output is a **change available**, not necessarily an upgrade: it may be an upgrade, downgrade, rebuild, input change, or packaging change.

### Data model

For every active profile element whose source is nixpkgs, collect structural fields from `nix profile list --json`:

- the complete installed `storePaths` set;
- `attrPath`;
- `originalUrl`, which is the upgrade source requested by the user;
- the locked `uri`, when present;
- a stable display name.

Both object-shaped and array-shaped `elements` schemas must be supported. Missing required fields make that element `unknown`; they must not cause the element to disappear from the report.

Evaluate the current source and attribute as one machine-readable record containing the output path set that the same profile installable would place in the profile, plus an optional display version. This must respect Nix's output selection for multi-output derivations rather than blindly comparing every derivation output. If a locked source is available, its version may be evaluated for the installed-version display. Version strings are presentation only and must never determine status. Store-path basenames must not be parsed as authoritative package versions.

### Status rules

Each profile element has exactly one status:

| Status | Rule | User label |
| --- | --- | --- |
| Current | Evaluated output path set equals the installed `storePaths` set | `current` |
| Changed | Evaluation succeeds and the output path sets differ | `change available` |
| Unknown | Profile data is incomplete, evaluation fails, or usable output paths are absent | `unknown` |

Installed and available versions may be shown when obtained structurally. Missing versions are displayed as `?`; this does not by itself make a result unknown when output identity is available.

### Summary and exit behavior

- `Everything is up to date.` may appear only when every checked element is `current`.
- A successful report with changed elements states the exact number of changes and uses `change(s) available`, not `upgrade(s) available`.
- Any unknown element produces a clearly labeled partial-result summary with separate changed and unknown counts.
- An unknown or incomplete report returns nonzero. A complete current or changed report returns zero.
- A total profile-read or JSON-parse failure returns nonzero and must not print a success summary.
- A profile with no active nixpkgs elements is a complete, zero-count result, not an evaluation failure. Its internal state is `current`, while its user-facing message remains `No nixpkgs packages found in the current profile.`
- Temporary files are removed on normal return and on handled signals.

### `upkg` integration contract

`upkg` must not infer Nix state by matching human-readable phrases. `_npkg_outdated` must expose stable internal state and counts—`current`, `changed`, or `partial`—to `_upkg_run_outdated_nix`. The caller must invoke it in a way that preserves that state rather than hiding it in a command-substitution subshell. Human-readable output may then change without breaking orchestration.

`upkg outdated` and `upkg plan` must:

- mark a complete changed report as `updates available`;
- mark a complete current report as `up to date`;
- mark an incomplete report as `failed` or `blocked`, preserve the diagnostic output, and return nonzero for the overall operation under the existing aggregate-status rules.

### Acceptance criteria

Automated fixtures must cover at least:

1. matching installed and evaluated output paths;
2. different output paths with equal display versions;
3. a hyphenated/date version such as `unstable-2026-08-01`;
4. an installed display version that appears newer than the available one;
5. a failed `nix eval` for one of several elements;
6. missing `attrPath`, source, or output-path data;
7. both object and array profile-manifest schemas;
8. a derivation with multiple outputs;
9. more rows than the rich dashboard can display, proving hidden rows still affect totals;
10. propagation of `current`, `changed`, and `partial` states through `upkg`.

No failure fixture may emit `Everything is up to date.` or return success.

## HC-03: Common `fzf` packages are incompatible with startup configuration

### Problem

The global options use `selected-bg`, introduced in `fzf` 0.52, and startup invokes `fzf --zsh`, introduced in 0.48. The dependency checker currently validates only command presence and recommends distribution packages that may be older. A user can follow the documented install command and receive broken fuzzy-finder commands or noisy shell startup.

### Compatibility policy

The shared config must support two integration tiers:

| Tier | Capability | Required behavior |
| --- | --- | --- |
| Embedded | `fzf --zsh` is supported | Evaluate generated Zsh integration only after the command succeeds |
| Legacy | The installed package provides readable Zsh completion and/or key-binding scripts | Source the available scripts directly |

An installed binary with neither capability is usable only as a standalone command and is **degraded** for this repository. Shell startup must remain clean; `scripts/check-deps.sh` must explain the missing integration and give an actionable upgrade or installation hint.

### Required behavior

- Remove `selected-bg` from the shared `FZF_DEFAULT_OPTS` baseline. The baseline must be accepted by the oldest supported legacy tier; enhanced colors must not be required for correct operation.
- During a normal interactive prompt startup, detect the embedded capability and use `fzf --zsh` when supported.
- If embedded integration is unavailable, look for packaged Zsh integration scripts in deterministic, documented locations. The implementation must cover the common `/usr/share/doc/fzf/examples/` and `/usr/share/fzf/shell/` layouts and may also honor an existing `FZF_BASE` shell directory.
- Source only readable regular files. Completion and key-binding scripts are independent capabilities: use whichever are present and do not source a path twice.
- Capture expected probe errors. Never pass empty, partial, or failed command output to `eval`.
- Keep the existing `[[ -o interactive ]]` and `[[ -z "$ZSH_EXECUTION_STRING" ]]` protections so command-mode interactive shells do not initialize ZLE bindings.
- A missing or degraded integration must not print a warning during shell startup. Diagnostics belong in `scripts/check-deps.sh` and documentation.
- The dependency checker must report the detected `fzf` version and one of `embedded integration`, `legacy integration`, or `degraded: no Zsh integration`. A degraded required dependency makes the checker fail.
- `apt` hints on distributions whose repository version lacks embedded integration must mention that the packaged legacy scripts are used. If those scripts are absent, the hint must direct the user to a current upstream installation instead of implying that command presence is sufficient.

### Acceptance criteria

Tests use a stubbed `fzf` and temporary integration scripts to cover:

- 0.38 and 0.44-style installations with legacy scripts;
- 0.48 through 0.51 with embedded integration and no `selected-bg` option;
- 0.52 or newer with embedded integration;
- a binary whose `--zsh` probe exits nonzero;
- a present binary with no usable Zsh integration;
- a missing binary;
- `zsh -i -c ...` and non-interactive sourcing.

Every supported case starts without stderr output. Invoking a fuzzy picker with the stubbed pre-0.52 binary must not fail because of an unsupported color option. The degraded case is silent at startup but is reported as a failure by `scripts/check-deps.sh`.

## HC-04: Filesystem text can inject terminal control sequences

### Problem

`_ui_single_line_path` escapes newline, carriage return, and tab only. Other control characters—including ESC, BEL, backspace, DEL, and C1 controls—can pass from a filename or path into `dusage` and `bigfiles`. In a terminal, this can alter rendering, ring the bell, hide or overwrite text, create misleading output, or inject arbitrary terminal escape sequences.

### Safe-text contract

Replace the narrow helper with a reusable data-sanitization helper and apply it before any width calculation, truncation, coloring, or rendering.

The sanitizer must:

- preserve printable Unicode text;
- convert LF, CR, tab, ESC, BEL, backspace, form feed, and vertical tab to visible escapes such as `\n`, `\r`, `\t`, `\e`, `\a`, `\b`, `\f`, and `\v`;
- encode every other C0 control, DEL, and C1 control as a visible hexadecimal escape such as `\x01` or `\x7f`;
- produce exactly one logical line for one input value;
- avoid using locale-dependent character classes as the sole protection;
- treat the resulting escape text as ordinary data so rich-output styling cannot reactivate it.

NUL cannot occur in a shell argument or filesystem pathname and is outside the input domain.

### Required coverage

Sanitization applies to every filesystem- or environment-controlled label rendered by:

- `dusage`, including the requested target, entry labels, and full paths;
- `bigfiles`, including the requested target, file labels, and full paths;
- `path`, for user-controlled `PATH` entries;
- any shared helper introduced for these commands.

If the implementation discovers another dashboard that renders raw path data through the same helper, it must migrate that caller as part of this fix.

### Acceptance criteria

- Tests create filenames containing ESC, BEL, backspace, DEL, newline, carriage return, and tab, plus representative UTF-8 characters.
- Equivalent tests cover a target-directory name and a `PATH` entry, not only child filenames.
- Plain output contains no raw data-derived C0, DEL, or C1 control. Newline may appear only as an output record delimiter.
- Rich output contains only the UI layer's expected terminal sequences; after those sequences are removed, the same byte-level guarantee as plain output holds.
- Each hostile filename occupies one logical output row and has a readable visible escape.
- Truncation and alignment are calculated from the escaped display value and do not split an escape token.
- Existing ordinary ASCII and printable Unicode paths remain unchanged.

## Documentation requirements

The implementation change must update all three user-facing documentation surfaces:

- `80-tips.zsh`: replace the `GLOB_DOTS` tip, describe explicit `(D)` usage, and describe Nix results as changes rather than guaranteed upgrades.
- `README.md`: document the `fzf` embedded/legacy fallback, dependency-checker diagnostics, safe path rendering, and conservative Nix status semantics.
- `GUIDE.md`: update the shell-options section, `npkg outdated` workflow, `fzf` setup guidance, and terminal-output safety guarantee with concrete examples.

Documentation must not promise that `npkg outdated` determines version ordering. It must explain that `unknown` makes the check incomplete and unsuccessful.

## Implementation and verification order

1. Add failing regression fixtures for all four findings.
2. Disable implicit dotfile globbing and update its user guidance.
3. Introduce the safe-text contract and migrate path-rendering callers.
4. Replace Nix version-string comparison with output-identity comparison and add the stable `upkg` state contract.
5. Add `fzf` capability tiers and dependency diagnostics.
6. Synchronize `80-tips.zsh`, `README.md`, and `GUIDE.md`.
7. Run the complete automated verification sequence.
8. Perform interactive QA for prompt startup, fuzzy bindings, hostile filenames, and Nix partial results.

The required automated verification sequence is:

```sh
zsh -n *.zsh
sh -n scripts/check-deps.sh
zsh scripts/test-init.zsh
zsh scripts/test-functions.zsh
zsh scripts/test-upkg.zsh
zsh scripts/test-completions.zsh
zsh scripts/test-help.zsh
zsh -fc 'source "$HOME/.config/zsh/init.zsh"'
```

Because this is a stable-release QA pass, create a local-only `qa-features.csv` using the repository's required columns and add it to `.gitignore`. The manual checklist must include the new glob behavior, embedded and legacy `fzf` startup, degraded `fzf` diagnostics, rich and plain hostile-path rendering, and all three Nix result states.

## Release gates

The remediation is complete only when:

- every acceptance criterion in HC-01 through HC-04 has an automated test or an explicitly identified manual QA row;
- all repository verification commands pass;
- interactive startup is clean with modern, legacy, missing, and broken `fzf` fixtures;
- no `npkg` failure path can print an all-current summary;
- byte-level hostile-path tests pass in rich and plain modes;
- documentation and tips describe the shipped behavior accurately;
- the working tree contains no generated QA artifact other than the intentionally ignored local checklist.

## Rollback boundaries

Each remediation should remain independently revertible. If a compatibility problem is discovered:

- keep `GLOB_DOTS` disabled; do not restore implicit hidden-file expansion as a rollback;
- keep control-character sanitization active and simplify presentation instead of emitting raw data;
- make Nix results `unknown` rather than restoring version guessing;
- disable only the failing `fzf` integration tier while preserving silent startup and dependency diagnostics.

These boundaries preserve the safety guarantees even during a partial rollback.

## References

- [`init.zsh`](../../init.zsh) and [`40-fzf.zsh`](../../40-fzf.zsh)
- [`60-functions.zsh`](../../60-functions.zsh)
- [`scripts/check-deps.sh`](../../scripts/check-deps.sh)
- [`README.md`](../../README.md), [`GUIDE.md`](../../GUIDE.md), and [`80-tips.zsh`](../../80-tips.zsh)
- [Nix profile manifest schema](https://releases.nixos.org/nix/nix-2.22.4/manual/command-ref/files/manifest.json.html)
- [Nix profile command reference](https://releases.nixos.org/nix/nix-2.13.6/manual/command-ref/new-cli/nix3-profile.html)
- [`fzf` changelog](https://github.com/junegunn/fzf/blob/master/CHANGELOG.md)
- [Ubuntu 24.04 `fzf` package](https://packages.ubuntu.com/noble/fzf)
- [Debian 12 `fzf` package](https://packages.debian.org/bookworm/fzf)
