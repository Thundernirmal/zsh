# Zsh architecture and terminal UX audit

Reviewed 4 September 2026. Repository: Thundernirmal/zsh, branch `master`, commit `8233c85ad52bd1e17d82cb1e7e05f944a227f00d`.

**Remediation completed 5 September 2026.** All prioritized findings, workflow improvements, and maintenance recommendations below are implemented. The original audit evidence remains pinned to its reviewed commit; use [GUIDE.md](../../GUIDE.md) for current behavior. WSL crash investigation is outside this work at the maintainer’s request.

## Verdict

Keep the current modular Zsh approach. The project has strong foundations: deliberate startup boundaries, lazy loading, shared presentation primitives, guarded integrations, and substantial regression coverage. Its biggest remaining problems concern trustworthy selection, honest failure reporting, and discoverability. Another visual redesign should come after those fixes.

No critical vulnerability was confirmed in this audit. Two high-priority findings deserve attention: remote branch selection can activate a different local branch, and the process-killing picker hides essential identifying information. The latter is an interaction-design risk, not a demonstrated unintended kill.

This is an audit of the shell repository and its documentation. The repository contains no website application; the separately linked documentation website, machine-local `.zshrc`, Oh My Zsh configuration, and prompt appearance were not audited.

## Evidence and verification

- Retrieved the repository tree and source at the pinned commit through GitHub. Reviewed startup, integrations, aliases, command implementations, completions, theme/UI helpers, documentation, and test/CI structure.
- Ran `zsh scripts/run-tests.zsh`: exit 0, with 1,057 `ok:` assertions logged. This includes the existing integration fixtures and smoke test; it is not 1,057 independent end-to-end scenarios.
- Ran individual syntax checks for all 32 Zsh source/helper/test files: all passed. The individual checks compensate for the runner defect below.
- Reproduced remote-branch misselection using a disposable local Git repository.
- Reproduced incomplete disk scans returning success using a fake `du` that emits a valid record then exits 1.
- Reproduced the multiple-file syntax-check gap with a valid first file and malformed second file.
- Reproduced global alias argument rewriting using a constant command string.
- Real fzf was unavailable in this environment. Picker findings are based on source and the existing fixture tests, not a live rendered fzf session. Real Secret Service, package mutations, and the user's full desktop environment were not exercised.
- An initially suspected fzf extra-options cache defect was ruled out: `_zsh_theme_signature` already includes `ZSH_FZF_EXTRA_OPTS`.

## Architecture

| Layer | Ownership and behavior | Assessment |
|---|---|---|
| Host configuration | `.zshrc`, OMZ, prompt, PATH and `compinit` remain outside the repository | Sensible boundary; setup needs clearer standalone instructions |
| Bootstrap | `init.zsh` sets shell options and sources thirteen numbered modules from `~/.config/zsh` | Easy to trace, but fixed location and silent skipping complicate diagnosis |
| Everyday shell defaults | History, ordinary aliases and global aliases | Small, understandable modules; global aliases have unusually broad effects |
| Integrations | zoxide and fzf generated integration, validation, caches and wrappers | Careful cache ownership, permissions and syntax validation; maintainable only with continued regression coverage |
| Presentation | `25-theme.zsh`, `55-ui-helpers.zsh`, theme libraries | Strong shared semantic roles, glyph tiers, responsive previews and plain fallbacks |
| General commands | `60-functions.zsh` registers loaders; `lib/functions-catalogue.zsh` supplies implementations | Startup stays light, but first use loads an oversized mixed-domain catalogue |
| Credentials | Optional `62-cgm.zsh`; Secret Service stores values; local marker files track names | Good secret/value separation; operational recovery and status could improve |
| Discovery | Lazy help/tips catalogues and `66-compdefs.zsh` | Good safe example queueing; subcommands and unavailable features need better discovery |
| Package workflows | `upkg` orchestrates backends; `npkg` manages Nix profiles | Useful privilege, planning and partial-result policies; excessive concentration in one file |
| Assurance | GitHub Actions invokes the repository regression runner | Extensive fixture tests, but limited real-tool/terminal coverage and broken multi-file syntax invocation |

Load order is history → aliases → theme → zoxide → fzf → completion styles → UI helpers → general loaders → optional CGM → help → completion definitions → global aliases → tips. This explains two important dependencies: `compinit` must precede this layer, and the general catalogue depends on module-owned paths and shared helpers.

Persistent state is distributed intentionally: history in `~/.zsh_history`, executable-fingerprinted integration caches under the cache root, a Nix attribute cache, and credential-name markers under the data root. Secrets stay in Secret Service. Theme switching changes the session; `ztheme export` prints settings rather than editing `.zshrc`.

### Recommended architecture changes

1. Split the 4,749-line general catalogue by domain: files/search, system diagnostics, Git, package orchestration, backend adapters, and Nix. Preserve fixed repository-relative loaders and avoid introducing runtime discovery. A call to `mkcd` should not need to parse package management implementations.
2. Grow the existing command metadata into a shared registry for canonical name, aliases, summary, usage, examples, dependency check and mutation category. Generate help/completion declarations where practical; retain human-written workflow documentation.
3. Separate result collection from rendering. A command should finish with explicit state, records, diagnostics and status; rich and plain renderers must preserve the same outcome. The disk-scan defect demonstrates why this matters.
4. Add an on-demand `zdoctor`. Check install location, missing modules, completion readiness, tool versions, glyph configuration and optional integration status. Keep network and Secret Service probes explicit; add no prompt-time work.

## Prioritized findings

### H1 — Remote selection can silently activate the wrong local branch

**Type:** confirmed functional/UX defect. **Priority:** high.

`_fbr_activate` strips the remote prefix, then switches to any existing local branch with that name. It does not check that the local branch tracks the selected remote. The surrounding picker also maps a remote selection to the local branch's worktree by name alone.

**Reproduction:** create local `topic` at commit A and `upstream/topic` at commit B. Calling `_fbr_activate upstream/topic` switches to local `topic` at A, returning success. This is especially confusing with multiple remotes or unrelated local work. Divergence itself is normal; the defect is treating a name match as proof of the selected branch's identity.

**Fix:** inspect the local branch's upstream before reusing it. For an unrelated local collision, present explicit choices: enter the local branch, create a differently named tracking branch, or inspect the selected remote detached. Do not reset existing branches automatically. Label worktree actions as “Enter worktree” rather than the current universal “Enter checkout.”

**Status (2026-09-05): fixed.** `_fbr_activate` now reads `%(upstream:short)` via `for-each-ref` and only reuses the local branch when it tracks the selected remote; otherwise it returns 1 with the three explicit `git switch` alternatives. The `fbr` picker only maps a remote to a worktree when the upstream matches, and the footer reads `Enter worktree/checkout`. Covered by `test_fbr_remote_collision` (unrelated, different-upstream, and tracking cases).

[Evidence: branch activation and picker](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/lib/functions-catalogue.zsh#L1153-L1263).

### H2 — `fkill` hides process identity before an immediate destructive action

**Type:** source-confirmed interaction risk. **Priority:** high.

The process list removes owner, PID, parent PID and timing fields from the display. PID is retained as a hidden selection field; `--with-nth=2..` shows only command text. Enter immediately sends the requested signal to every selected PID. Similar workers can be indistinguishable, and processes belonging to other users appear without ownership context.

**Fix:** show PID, owner, elapsed time and command; add full command/cwd details in a preview. Make the current user's processes the default, with an explicit all-users mode. Keep ordinary SIGTERM efficient, but add a review step for SIGKILL and bulk selections. Report per-target outcomes. Never invoke privilege escalation implicitly.

**Status (2026-09-05): fixed.** `fkill [--all] [signal]` lists PID, owner, elapsed time, and command with a `ps` + `/proc/cwd` preview; the default scope is the current user via `id -un`, with `--all`/`-a` for every process. Single SIGTERM sends immediately, while SIGKILL or multi-selections confirm naming targets and signal. Kills run per-PID with individual success/failure reports and no sudo/su. Covered by extended `test_fkill_signals` source assertions plus `test_fkill_scope_and_review` (flag parsing, terminal gate, row formatting).

[Evidence: fkill](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/lib/functions-catalogue.zsh#L141-L194).

### M1 — Incomplete disk scans look successful

**Type:** reproduced defect. **Priority:** medium.

`dusage` and `bigfiles` capture scan statuses but discard them once records exist. Both suppress tool stderr. A failed `du` that emitted one record produced normal output and exit 0 in both commands. Partial `find` results have a related path in `bigfiles`.

**Impact:** permission failures, vanished files or filesystem errors can make an incomplete ranking look authoritative.

**Fix:** preserve available results, add “Incomplete scan” with a concise diagnostic on stderr, and return nonzero. Rich output should carry the same partial state. Match the already stronger package-result policy.

**Status (2026-09-05): fixed.** `dusage` keeps partial rows, prints `Incomplete scan in '<target>' (du exit <code>); results are partial` on stderr, adds a rich `Warning` row plus `(incomplete scan)` footer, and returns the `du` status. `bigfiles` tracks both `find` and `du`, reports the failed tool(s), and returns the failing status while preserving partial rows. Empty-result failures also carry the diagnostic. Covered by `test_usage_partial_scan` and updated unreadable-fixture expectations in `test-upkg.zsh`.

[Evidence: dusage](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/lib/functions-catalogue.zsh#L569-L720), [bigfiles](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/lib/functions-catalogue.zsh#L723-L876).

### M2 — CI syntax checks only the first filename in each Zsh invocation

**Type:** reproduced verification defect. **Priority:** medium.

`zsh -n file1 file2 ...` checks `file1`; the remaining filenames become script arguments. A valid first fixture and malformed second fixture returned 0 together, while checking the second alone returned 1. The regression suites still provide meaningful coverage; this does not mean CI checks nothing.

**Fix:** loop over source files and invoke `zsh -n "$file"` separately, including lazy helpers and test scripts. All current files passed the corrected individual check during this audit.

**Status (2026-09-05): fixed.** `scripts/run-tests.zsh` now loops `for _zsh_syntax_file in ./*.zsh ./lib/*.zsh ./functions/ztheme ./functions/_fbr_format_entry ./scripts/*.zsh` with one `zsh -n` per file (plus `sh -n` for `check-deps.sh`). Covered by `test_runner_syntax_loop`, which also documents that multi-file `zsh -n` only checks the first file.

[Evidence: runner](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/scripts/run-tests.zsh#L31-L40).

### M3 — Global aliases rewrite ordinary arguments

**Type:** reproduced, intentional behavior with UX cost. **Priority:** medium.

Unquoted tokens such as `H`, `T`, `G` and `L` expand anywhere in a command. For example, after loading the aliases, an interactively parsed `echo H` behaves as `echo | head`. A filename or search term can become shell syntax.

**Fix:** make global aliases opt-in for a shared configuration. Existing personal users can preserve them with one setting. Include a clear quoting example and show their enabled state in `zdoctor`. This is a design change, not a claim that Zsh expansion is malfunctioning.

**Status (2026-09-05): fixed.** `70-globals.zsh` defines `G/L/W/H/T/NE/NUL` only when `ZSH_GLOBAL_ALIASES=1` is exported before startup; quoting (`echo 'H'`) keeps tokens literal and is documented in the module header, GUIDE, and tips. Disabled aliases disappear from default `zhelp` via the existing unavailable-category path, the globals tips only load when enabled, and `zdoctor` reports the enabled state.

[Evidence: global aliases](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/70-globals.zsh).

### M4 — Onboarding fails quietly and assumes too much

**Type:** architecture/UX recommendation. **Priority:** medium.

The README gives the source snippet but omits a concrete clone/setup step. The entrypoint only loads modules at the fixed install path and silently skips unreadable ones. Missing `compinit` silently disables custom completions. The dependency checker cannot explain those configuration failures.

**Fix:** document installation into an empty target directory, a standalone `compinit` setup, the OMZ setup, and verification. Resolve the module root from the entrypoint if portability is desired; otherwise make the fixed path a prominent setup check. Use `zdoctor` for diagnosis without adding startup noise. Distinguish optional features from the checker's “required for intended setup” tools.

**Status (2026-09-05): fixed.** README and GUIDE now document cloning into an empty `~/.config/zsh`, the fixed-path requirement, standalone `compinit -i` setup, OMZ ordering, and verification via `check-deps.sh` plus `zdoctor`. Startup stays silent; the new on-demand `zdoctor` (lazy-loaded, with shell completion and help entry) reports install location, unreadable modules, `compinit` readiness, required/optional tool availability and the fzf version minimum, glyph resolution, and fzf/zoxide/cgm/npkg/global-alias state, exiting nonzero while a failure is present. Network and Secret Service stay untouched unless `--network`/`--secrets` are passed explicitly. Covered by `scripts/test-doctor.zsh`.

[Evidence: README](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/README.md), [bootstrap](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/init.zsh), [completion guard](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/66-compdefs.zsh#L1-L9).

### M5 — Glyph defaults confuse UTF-8 with font support

**Type:** source-confirmed compatibility risk. **Priority:** medium.

`auto` selects Nerd Font glyphs whenever the locale is UTF-8 unless `NO_NERD_FONT` is set. UTF-8 support does not establish that private-use icons exist in the font. Existing Unicode and ASCII overrides are good escape hatches, but a fresh installation may show missing-glyph boxes.

**Fix:** default auto to ordinary Unicode; make Nerd Font icons an explicit preference. Keep a compact preview in setup/help so the user can verify their choice.

**Status (2026-09-05): fixed.** `auto` now resolves to Unicode in UTF-8 locales (ASCII outside them); Nerd Font icons require `ZSH_UI_GLYPHS=nerd`, while `NO_NERD_FONT=1` downgrades even an explicit `nerd` tier. `ztheme current` prints the resolved tier with a compact pointer/marker/gutter sample. Covered by `test_glyph_tier_selection` plus updated default/signature/fallback/idempotence expectations.

[Evidence: glyph resolver](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/25-theme.zsh#L105-L132).

### M6 — Display width uses character count instead of terminal cells

**Type:** source-confirmed layout limitation; no live visual reproduction. **Priority:** medium for multilingual filenames.

Padding and truncation use `${#text}`. Wide CJK characters and combining sequences do not occupy one terminal cell per character, so columns can misalign or wrap despite the numeric width calculation.

**Fix:** introduce one display-width primitive and use it consistently after control-character sanitization. Verify narrow, wide-character and combining-character fixtures. Do not add per-row external processes just to calculate width.

**Status (2026-09-05): fixed.** Committed Unicode 16.0 intervals now cover nonspacing/format marks and assigned wide code points, load on first non-ASCII measurement, and use binary search without external processes. Truncation drops orphaned combining marks at suffix cuts. `_ui_char_width`/`_ui_display_width` in `55-ui-helpers.zsh` measure terminal cells purely in Zsh (wide CJK as two, combining marks as zero) and drive `_ui_truncate_reply`, `_ui_pad_reply`, and `_ui_safe_truncate` (with a character-count fallback when the helper is unavailable). Covered by `test_display_width` (narrow, CJK, combining, escape fixtures plus aligned pad/truncate rows) and a cell-based `fbr` CJK fixture.

[Evidence: truncation and padding](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/55-ui-helpers.zsh#L216-L288).

## UX improvements beyond defects

| Area | Current friction | Recommended behavior |
|---|---|---|
| Help discovery | `zhelp` has one entry per top-level command; package and credential actions hide beneath it | Add searchable action entries such as “preview upgrades”, “remove Nix package” and “load credentials” |
| Search consistency | CLI help query is substring-filtered before entering fzf; users cannot broaden beyond those rows by clearing the picker query | Pass the whole eligible catalogue to fzf and seed its query; retain deterministic plain search |
| Disabled features | Default help hides unavailable commands; completion may offer them | Show a discoverable unavailable category with installation/recovery hints |
| History search | `?` toggles preview while other preview pickers use Ctrl+P; typing literal `?` no longer inserts it normally | Use one preview binding that leaves printable search characters available |
| Lightweight command help | Commands such as `extract --help` and `fkill --help` treat help as an operand/signal | Standardize `-h`/`--help`, usage errors and examples across public commands |
| Network helpers | `myip`, `headers` and weather have no explicit timeout budgets | Add connection/overall timeouts and concise failure messages; expose overrides where useful |
| Credential list | “Saved” refers to marker files; it does not establish backend availability or loaded state | Add names-only current-shell loaded status and an explicit backend diagnostic/reconciliation action |
| Search fallbacks | fd/find differ in ignore and symlink behavior; rg/grep differ in hidden/ignored-file behavior | Expose documented `--hidden`, `--no-ignore`, `--follow` and fixed-string controls where backends can support them consistently |
| Archive extraction | Bare compressed files can remove the source; archive extraction uses the current destination | Offer explicit keep-input and destination options; retain and document native behavior if compatibility requires it |
| Nix completion | Every completion reads all cached attribute files again | Cache parsed attributes in-session keyed by cache identity/mtime; retain the existing no-network completion rule |

These recommendations are grounded in [help implementation](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/lib/help-catalogue.zsh), [fzf configuration](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/40-fzf.zsh), [commands](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/lib/functions-catalogue.zsh), [CGM](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/62-cgm.zsh) and [completions](https://github.com/Thundernirmal/zsh/blob/8233c85ad52bd1e17d82cb1e7e05f944a227f00d/66-compdefs.zsh). They are not all defects; several deliberately change documented behavior.

**Status (2026-09-05): discovery rows fixed.** Help discovery ships `upkg-plan`, `npkg-remove`, and `cgm-env` action entries that resolve through their parent command; the palette now receives the whole eligible catalogue with the CLI query as a seed so clearing it broadens results (plain search stays filtered); and plain listings name hidden unavailable commands with a pointer to `zhelp --all`. The history row is fixed too: Ctrl+R uses the shared Ctrl+P preview toggle and Ctrl+/ wrap binding, leaving `?` searchable (covered by `preview_keys`). Covered by `test_action_entries_and_browsing`. The remaining workflow rows are now implemented: general helper `-h`/`--help`, positive bounded curl timeouts, names-only `cgm status` and explicit D-Bus `cgm check`, explicit search controls with documented fallback differences, keep-input/destination extraction, and in-session Nix completion caching. See GUIDE.md for current commands and limits.

## What to preserve

- `zhelp` queues editable text and never executes its selection.
- Semantic theme roles, shared finder chrome, selected-count hints and responsive preview layouts.
- Quiet startup and on-demand tips. Avoid adding banners or per-prompt diagnostics.
- Safe repository-local lazy loading, generated-integration validation and protected caches.
- Credential name/value separation, disabled tracing during value loading, parameter validation, and no reveal command or plaintext fallback.
- Explicit package privilege opt-in, preview workflows, and nonzero aggregate status for blocked/partial/failed backends.
- Native destructive file-command behavior rather than misleading safety aliases.

## Delivery order and acceptance criteria

1. **Correctness first:** fix H1, M1 and M2 in small changes. Tests must distinguish unrelated same-name local branches, retain partial scan output with failure status, and reject malformed files anywhere in the syntax list.
2. **Safer process selection:** fix H2. A user must distinguish otherwise identical processes before sending a signal; bulk/SIGKILL review must name the targets and signal.
3. **Discovery and setup:** add `zdoctor`, explicit installation/completion instructions, action-level help and consistent preview/help bindings. A clean installation must explain why a feature is unavailable.
4. **Compatibility:** make glyph support explicit, implement terminal-cell width handling and clarify search/global-alias policies.
5. **Maintenance:** split the catalogue while preserving startup characteristics and existing command contracts. Add real fzf PTY coverage at the supported minimum and a newer version, plus representative terminal widths, NO_COLOR, Unicode/ASCII and cancellation paths. Real backend compatibility checks should remain separate from destructive package operations.

Visual polish is already relatively mature. The next meaningful upgrade is making every selection, status and recovery path trustworthy.

## Remediation verification log

- 2026-09-05, compatibility stage: reviewed the inherited uncommitted M5/M6 and history-binding changes. Corrected an invalid Zsh pattern in the width fast path and restored completion-path reporting in `ztheme current`. The complete `zsh scripts/run-tests.zsh` runner passed under a 240-second timeout and a 1 GiB per-process virtual-memory limit. WSL crash diagnosis is outside this remediation at the maintainer’s request.

- 2026-09-05, workflow stage: completed the remaining UX rows and synchronized command help/completion/tips. Reviewed inherited edits locally after the Luna agents reached their usage limit. Fixed tar destination flags, Zsh help printing, fallback search semantics, credential probe status propagation, and extraction publication safety; branch recovery commands now use shell-safe quoting. Added command UX, extraction failure/symlink, credential metadata/health, and completion reuse/invalidation regression cases. The complete runner passed. Command metadata now lives in the fixed, data-only `lib/command-registry.zsh`, reused by help and completion, with canonical-command and mutation-category fields.

### Follow-up standards and specification review

- **Standards:** corrected documentation drift, first-use cached command guards in `zdoctor`, and inherited changes that bypassed existing fixture isolation. Fixed repository-relative loading and quiet startup remain intact. No unresolved hard standards violation was found in this stage.
- **Spec:** all prioritized findings H1/H2/M1–M6 and the workflow table are implemented. Catalogue domain splitting and real-fzf minimum/newer PTY acceptance are complete in the maintenance stage. Terminal-dependent emoji grapheme shaping is documented rather than claimed as universally exact.

- 2026-09-05, maintenance stage: split the monolithic implementation into fixed common, files/search, system/network, Git, package orchestration, backend adapter, and Nix modules. `mkcd`, `path`, and `fbr` no longer parse package code. Added a regression for removing Nix between startup and first use, so a missing executable cannot leave a recursive lazy loader. Disk collection now produces records plus explicit state, diagnostics, and status before rich/plain rendering; signal cleanup and partial-result behavior remain covered. Comparing Zsh’s parsed function bodies before/after the split found no removed implementations and only the intended changes to `dusage`, `bigfiles`, and `fbr` (local shell-option emulation).
- Real fzf PTY acceptance passes locally on **0.68.0 and 0.74.3**, including exported finder options, 50/100-column widths, Unicode/ASCII, preview toggling, multi-selection, `NO_COLOR`, and cancellation. The new separate CI matrix runs those same versions without package mutations. The minimum-version test found an upstream no-color footer default of ANSI black; the shared theme now explicitly resets that footer to terminal-default foreground. [fzf 0.68.0 no-color theme source](https://github.com/junegunn/fzf/blob/v0.68.0/src/tui/tui.go) corroborates the missing footer initialization.
- Final verification: `zsh scripts/run-tests.zsh` passes with **1,267 `ok:` assertions**, including syntax checks for every new Zsh helper and the fixed-install-path smoke test. These are assertions, not independent end-to-end scenarios. Each real-fzf version passes all four PTY cases. Actual package mutations, real stored credentials, and machine-specific font rendering are not exercised by this automated verification.

### Final acceptance

| Audit scope | Result |
|---|---|
| H1/H2 and M1–M6 | Implemented and regression-covered |
| Discovery, unavailable help, history, lightweight help | Implemented; shared metadata and editable examples retained |
| Network, credentials, search, extraction, Nix completion | Implemented with documented defaults, fallbacks, and explicit probes |
| Domain split and shared command registry | Implemented with fixed paths and lazy domain tests |
| Collection/rendering separation | Implemented for disk scans; rich/plain status parity preserved |
| Real fzf minimum/newer terminal coverage | Passed locally; separate CI matrix added |

No audit remediation item remains open. The terminal-dependent shaping limits and host/service checks above are documented verification boundaries, not claims of completed manual QA.
