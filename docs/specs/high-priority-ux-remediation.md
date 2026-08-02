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
- Preserve the complete fuzzy-finder feature set and require a version that supports it without compatibility downgrades.
- Prevent filenames and other path data from injecting terminal control sequences into rich or plain output.
- Preserve clean, fast startup and the existing guarded-integration conventions.
- Preserve every existing user-facing function, alias, picker, keybinding, preview, and workflow while correcting the audited behavior.

## Non-goals

- Fix Medium- or Low-priority audit findings in the same implementation change.
- Implement semantic version ordering for arbitrary Nix package versions.
- Redesign the package-manager commands, fuzzy-finder theme, or terminal dashboard system.
- Remove or reduce a feature to accommodate an outdated external dependency.
- Change the intentionally interactive aliases for `cp`, `mv`, or `rm`, except where tests must verify their interaction with glob expansion.
- Modify user-owned `~/.zshrc`, Oh My Zsh, Starship, or machine-local completion wiring.

## Cross-cutting requirements

The implementation must meet all of these constraints:

1. Startup-time command guards continue to use `(( $+commands[tool] ))`; they must not use top-level `command -v` checks.
2. `zsh -i -c ...` and non-interactive sourcing remain free of ZLE warnings, prompts, and unexpected output.
3. External integrations fail closed: generated shell code is evaluated only after all required capability checks succeed. An unsupported required `fzf` version is hard-blocked as defined in HC-03.
4. Plain output remains suitable for pipes and logs. Rich output may contain only control sequences intentionally emitted by the UI layer, never sequences originating in data.
5. User-facing behavior changes are reflected together in `80-tips.zsh`, `README.md`, and `GUIDE.md`.
6. New behavior is covered by deterministic tests using temporary directories and stubbed commands; tests must not depend on the host's installed Nix or `fzf` version.
7. No existing user-facing function, alias, picker, keybinding, preview, theme option, or workflow may be deleted as a compatibility fix. Unsupported dependencies are rejected with an actionable diagnostic instead.

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

## HC-03: `fzf` must meet the complete feature set's minimum version

### Problem

The global options use `selected-bg`, introduced in `fzf` 0.52, and startup invokes `fzf --zsh`, introduced in 0.48. The dependency checker currently validates only command presence and recommends distribution packages that may be older. A user can follow the documented install command and receive broken fuzzy-finder commands or noisy shell startup.

### Decision

The minimum supported version is **`fzf` 0.52.0**. This is the first release line that supports both the current `fzf --zsh` integration and the current `selected-bg` theme option.

The implementation must retain the complete current theme, previews, bindings, generated Zsh integration, and every user-facing function that depends on `fzf`. It must not remove `selected-bg`, source legacy integration scripts, or offer a reduced-function compatibility mode for older versions.

Consequently, distribution packages below 0.52.0 are intentionally unsupported even when the `fzf` command exists. The dependency checker must reject them rather than modifying the configuration to fit them.

The preservation baseline includes Ctrl+R, Ctrl+T, and Alt+C; `fkill`; `fbr`; the `zhelp` palette and its existing plain mode; zoxide's `zi` workflow; all interactive `npkg` add, find, and remove paths; the `npkg fzf` command alias; and all current previews and theme options.

### Hard-block semantics

The hard block applies to the `fzf` subsystem, not to unrelated shell configuration. The rest of the modules must continue loading so the user retains a usable shell.

When `fzf` is missing, reports an unparseable version, is older than 0.52.0, or fails to generate valid Zsh integration:

- do not evaluate output from `fzf --zsh`;
- do not initialize any `fzf` keybindings or partially configure a reduced feature set;
- retain all repository-defined functions and aliases;
- make every code path that would invoke `fzf` consult the shared version guard first;
- make an `fzf`-required command return nonzero before attempting its picker and print a concise upgrade diagnostic;
- preserve existing explicitly or automatically selected non-`fzf` modes, including `zhelp --plain` and `zhelp`'s documented plain table when fuzzy interaction is unavailable, while ensuring they never invoke the blocked binary;
- cache the blocked state for the session so each command does not repeat external version probes;
- during a normal interactive prompt startup, print one actionable diagnostic to stderr; do not repeat it for every module or binding;
- keep non-interactive sourcing and `zsh -i -c ...` silent and free of ZLE initialization.

The required diagnostic format is:

```text
zsh config: fzf 0.52.0 or newer is required (found: <version-or-reason>). Upgrade fzf and restart the shell.
```

An invocation of an `fzf`-required function may reuse this message when the subsystem is blocked. It must not introduce a new compatibility fallback; an already-supported non-`fzf` mode remains part of the function's existing contract.

### Required behavior

- Keep the complete existing `FZF_DEFAULT_OPTS`, including `selected-bg`, and preserve `FZF_CTRL_T_OPTS`, `FZF_ALT_C_OPTS`, and `FZF_CTRL_R_OPTS` behavior.
- Use `(( $+commands[fzf] ))` for the startup-time presence guard. Version inspection may invoke the resolved command only inside the normal interactive-startup path or an explicit `fzf`-dependent command.
- Parse the leading stable numeric version from `fzf --version` and compare integer major, minor, and patch components. Do not use lexicographic string comparison. An omitted patch component is zero; unparseable and prerelease versions are blocked.
- Treat 0.52.0 as the inclusive boundary: 0.51.x is blocked and 0.52.0 or newer is accepted.
- Invoke `fzf --zsh` only after the version check succeeds. Capture stdout and stderr separately, require a zero status and non-empty generated code, and call `eval` only on that validated stdout.
- Export the repository's `FZF_*` configuration only after validation succeeds. A blocked setup must not inject options that the installed binary cannot parse.
- Record a session-level ready or blocked state that all repository-defined `fzf` entry points can query through one shared guard.
- Inside function bodies, resolve `fzf` with `command -v` and key the cached version result by the resolved executable path. If `PATH` selects a different binary mid-session, validate the new binary before use.
- Keep the existing `[[ -o interactive ]]` and `[[ -z "$ZSH_EXECUTION_STRING" ]]` protections so command-mode interactive shells do not initialize ZLE bindings.
- `scripts/check-deps.sh` must remain POSIX `sh` and report the installed and minimum versions. Missing, unparseable, prerelease, and older versions are required-dependency failures and make the script exit nonzero.
- Installation hints must not claim an older distribution package is sufficient. If the detected package source cannot provide 0.52.0 or newer, direct the user to a current supported package or the official upstream installation instructions.

### Acceptance criteria

Tests use a stubbed `fzf` to cover:

- missing `fzf`;
- version-command failure and malformed output;
- a prerelease version;
- 0.51.1 as an explicit below-boundary failure;
- 0.52.0 as an explicit boundary success;
- representative newer minor and major versions;
- a supported version whose `--zsh` call exits nonzero or returns empty output;
- normal interactive startup, `zsh -i -c ...`, and non-interactive sourcing.

The tests must also prove that:

- every blocked case prevents `eval` and returns nonzero from an `fzf`-required function;
- existing non-`fzf` modes, including explicit and automatically selected `zhelp` plain output, still work without invoking the blocked binary;
- a normal interactive shell prints exactly one actionable block diagnostic, while command-mode and non-interactive startup remain silent;
- version detection is cached and not repeated by every picker;
- all existing repository-defined functions and aliases remain defined in both ready and blocked states;
- supported versions retain `selected-bg`, all three specialized option variables, previews, generated completion, and keybindings;
- `scripts/check-deps.sh` returns nonzero for every blocked version case and zero at the 0.52.0 boundary.

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
- `README.md`: document the `fzf` 0.52.0 minimum, hard-block behavior, dependency-checker diagnostics, safe path rendering, and conservative Nix status semantics.
- `GUIDE.md`: update the shell-options section, `npkg outdated` workflow, `fzf` setup guidance, and terminal-output safety guarantee with concrete examples.

Documentation must not promise that `npkg outdated` determines version ordering. It must explain that `unknown` makes the check incomplete and unsuccessful.

## Implementation and verification order

1. Add failing regression fixtures for all four findings.
2. Disable implicit dotfile globbing and update its user guidance.
3. Introduce the safe-text contract and migrate path-rendering callers.
4. Replace Nix version-string comparison with output-identity comparison and add the stable `upkg` state contract.
5. Add the `fzf` 0.52.0 version gate, shared runtime guard, hard-block diagnostic, and dependency-checker enforcement without removing any feature.
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

Because this is a stable-release QA pass, create a local-only `qa-features.csv` using the repository's required columns and add it to `.gitignore`. The manual checklist must include the new glob behavior, supported-boundary `fzf` startup, below-minimum `fzf` hard blocking, preservation of every fuzzy feature on a supported version, rich and plain hostile-path rendering, and all three Nix result states.

## Release gates

The remediation is complete only when:

- every acceptance criterion in HC-01 through HC-04 has an automated test or an explicitly identified manual QA row;
- all repository verification commands pass;
- supported `fzf` startup retains every existing fuzzy feature, and missing, below-minimum, malformed, and broken versions are hard-blocked with the specified mode-appropriate diagnostic;
- no user-facing function, alias, picker, keybinding, preview, theme option, or workflow is removed by the remediation;
- no `npkg` failure path can print an all-current summary;
- byte-level hostile-path tests pass in rich and plain modes;
- documentation and tips describe the shipped behavior accurately;
- the working tree contains no generated QA artifact other than the intentionally ignored local checklist.

## Rollback boundaries

Each remediation should remain independently revertible. If a compatibility problem is discovered:

- keep `GLOB_DOTS` disabled; do not restore implicit hidden-file expansion as a rollback;
- keep control-character sanitization active and simplify presentation instead of emitting raw data;
- make Nix results `unknown` rather than restoring version guessing;
- keep the `fzf` minimum at 0.52.0 and hard-block the subsystem rather than deleting features or adding a reduced compatibility path.

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
