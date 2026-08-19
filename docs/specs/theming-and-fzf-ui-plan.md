# Shared theming and fzf UI plan

**Status:** In progress — T7 complete; PF-01 and PF-02 scheduled

**Scope:** Shared terminal palette, fzf presentation, picker consistency, accessibility, and theme discovery

**Last revised:** 2026-08-19; minimum fzf version raised to 0.68.0 after upstream capability review

**Current usage:** [`GUIDE.md`](../../GUIDE.md) is the authoritative reference for the implemented theme settings, `ztheme`, and fzf workflows. This specification remains the task ledger until the final release gates and performance follow-ups are complete.

## Summary

Replace the repository's fixed, duplicated Catppuccin styling with a small pure-Zsh theme system. One semantic palette will drive both dashboard rendering and fzf, while layout, glyph capability, terminal color depth, and workflow behavior remain separate concerns.

The first release should:

- keep `catppuccin-mocha` as the default;
- add `catppuccin-latte`, `nord`, `gruvbox-dark`, and `terminal` built-ins;
- accept a validated custom palette without sourcing arbitrary theme files;
- theme all repository dashboards and fuzzy entry points consistently, including generated `**<Tab>` completion and zoxide's interactive finder;
- add a session-level `ztheme` command for discovery and switching;
- make `NO_COLOR` authoritative across fzf, its previews, and existing plain dashboard output;
- centralize responsive picker layout, section labels, ghost hints, footers, live selection status, word wrapping, and pointer/marker/gutter glyphs;
- raise the fzf minimum to 0.68.0 so every picker can use the same complete structured UI, while preserving every existing keybinding, preview, fallback, and security boundary.

This document is an implementation plan, not current behavior. Mark it **Implemented** only after every release gate is satisfied, then keep it as a historical decision record and point users to `GUIDE.md`.

## Why this work is needed

The code already uses semantic UI roles, but palette data and presentation policy are duplicated:

- `55-ui-helpers.zsh` contains one fixed Catppuccin-like truecolor and 256-color palette.
- `40-fzf.zsh` contains a second hard-coded palette inside one opaque `FZF_DEFAULT_OPTS` scalar.
- Those palettes disagree on border, marker, and informational colors.
- `fbr` and both Nix picker previews embed additional raw ANSI or RGB values.
- `fkill`, `fbr`, `zhelp`, and Nix pickers repeat pointer, marker, border, height, and preview-layout decisions.
- fzf loads before the shared UI helpers, so it cannot consume the existing semantic palette.
- fzf configuration is cached only by executable path, so an in-session theme or layout change would currently remain stuck.
- The repository overwrites inherited `FZF_DEFAULT_OPTS` instead of providing a defined composition contract.
- `NO_COLOR` disables color in the `zhelp` palette, but other fzf pickers and color-forced preview commands can still emit ANSI color.

The secure generated-integration cache is not a theme cache. Theme changes must rebuild exported option strings only; they must never regenerate or weaken validation of `fzf --zsh` output.

## Goals

1. Give users an explicit, predictable choice of light, dark, terminal-native, or custom palettes.
2. Use one set of semantic roles for fzf, dashboards, badges, panels, status output, and picker previews owned by this repository.
3. Preserve the current Catppuccin Mocha identity as the default while correcting internal palette inconsistencies.
4. Make every picker feel related: consistent focus, selected-row treatment, labels, key hints, cancellation behavior, and responsive previews.
5. Preserve deterministic plain output, ASCII fallbacks, safe text handling, and clean behavior in redirected or unsuitable terminals.
6. Keep startup lightweight: theme resolution must use Zsh builtins and must not contact services, probe executables, or launch subprocesses at module source time.
7. Keep configuration extensible without `eval`, arbitrary file loading, or unvalidated fzf argument injection.
8. Preserve user-owned fzf customization through an explicit and idempotent option-precedence contract.

## Non-goals

- Managing Starship, Oh My Zsh, terminal emulator, tmux, Zellij, or editor themes.
- Owning global `LS_COLORS`, Git color configuration, `bat` themes, or arbitrary external program output.
- Automatically detecting a terminal's light or dark background through OSC queries or heuristics.
- Recoloring an fzf process that is already open. The active theme applies to subsequent launches.
- Adding network-fetched themes or a package manager for theme files.
- Chasing the latest fzf release for popup behavior, decorative borders, or features that do not materially improve these workflows.
- Turning `50-completion.zsh` into a heavy or dynamic completion UI layer.
- Changing the data selection or action semantics of any picker.

## Research conclusions

The new minimum is **fzf 0.68.0**. This is the smallest release that contains the complete UX feature set selected for this project:

| Release | Capability used by this plan | UX value |
|---|---|---|
| 0.58 | `--style`, list/input/header borders and labels | Gives every picker a consistent visual hierarchy instead of one undifferentiated box |
| 0.59 | improved path scoring and bordered header lines | Improves file selection and table/header separation |
| 0.60 | `--accept-nth` and templated field projection | Lets pickers return only stable IDs, reducing fragile post-selection parsing |
| 0.61 | `--ghost` | Gives an empty search box a concise contextual hint |
| 0.62 | multiline color definitions, `alt-bg`, and a `selected-bg` ANSI-input fix | Makes generated themes readable and selected rows reliable |
| 0.63 | footer UI and `line` section borders | Creates a dedicated, consistent home for key hints and status |
| 0.64 | `multi` event | Allows multi-select pickers to show a live selected-item count in the footer |
| 0.66/0.66.1 | customizable gutter plus the `--no-color`/`NO_COLOR` fix | Improves focus cues and makes no-color behavior dependable |
| 0.67 | frozen left/right columns | Keeps identity fields visible when long table rows scroll |
| 0.68 | word-level list/preview wrapping, wrap indicators, Zsh multiline-history handling, and fixes ensuring path/directory completion options are honored | Makes long text readable and gives generated completion the same reliable themed overlays as every other entry point |

These capabilities and their release boundaries are documented in the [official fzf changelog](https://github.com/junegunn/fzf/blob/master/CHANGELOG.md). The current option and color contracts are documented in the [official fzf man page](https://github.com/junegunn/fzf/blob/master/man/man1/fzf.1).

The project intentionally stops at 0.68. Later releases add useful capabilities, but none is required for the target workflows:

- 0.71 adds tmux/Zellij popup integration, which is environment-specific and remains outside the shared default.
- 0.72 adds inline sections and dashed borders, which are mostly decorative once clean `line` section borders are available.
- 0.73 adds the `next` preview position, but the established responsive side/bottom layout already works across supported terminals.

Additional design conclusions:

- fzf accepts base schemes and semantic color mappings through `--color`; values may be ANSI names, 0-255 indexes, RGB hex, or terminal defaults. It treats current focus and multi-selected rows as distinct states.
- The fzf README warns against putting workflow-specific previews in global defaults because fzf is a general-purpose filter. Global options will therefore contain palette and shared chrome only; preview commands stay attached to their workflows. See the [official fzf README](https://github.com/junegunn/fzf/blob/master/README.md).
- fzf's generated Zsh completion exposes `FZF_COMPLETION_OPTS`, `FZF_COMPLETION_PATH_OPTS`, and `FZF_COMPLETION_DIR_OPTS`. Those are separate presentation surfaces from the three keybinding widgets and must be composed explicitly if `**<Tab>` completion is to match the rest of the UI. See the [official fzf completion source](https://github.com/junegunn/fzf/blob/master/shell/completion.zsh).
- `NO_COLOR` is still enforced explicitly with a final `--no-color`. Depending only on ambient detection would make option precedence harder to reason about even though the upstream bug is fixed at the new floor.
- fzf exposes no stable runtime action for replacing the complete palette. `ztheme` will update subsequent fzf launches, not an already-running process.
- There is one supported UI capability tier. Builds below 0.68.0 are hard-blocked; there is no reduced presentation mode for 0.60-0.67.

Palette values must come from their upstream definitions:

- [Catppuccin palette and style guide](https://catppuccin.com/palette/)
- [Nord palette](https://github.com/nordtheme/nord)
- [Gruvbox palette](https://github.com/morhetz/gruvbox)

## Design decisions

### 1. Load a dedicated theme module before zoxide and fzf

Add `25-theme.zsh` and source it between `20-aliases.zsh` and `30-zoxide.zsh`. Zoxide documents `_ZO_FZF_OPTS` as its interactive-finder customization point and requires configuration variables to be set before `zoxide init`. Loading the theme first lets `zi` and interactive zoxide completion use the same complete presentation policy as repository-owned pickers. See the [official zoxide configuration reference](https://github.com/ajeetdsouza/zoxide#configuration).

```text
~/.zshrc settings
       |
       v
25-theme.zsh ---- semantic roles + capability policy
       |                         |
       +------------+------------+
       v            v            v
30-zoxide.zsh   40-fzf.zsh  55-ui-helpers.zsh
       |            |            |
       +------------+------------+
                    v
       keybindings, pickers, dashboards,
       zhelp, tips, upkg, npkg, and cgm
```

`25-theme.zsh` owns only data selection, validation, color-depth resolution, glyph tiers, and reusable option fragments. `30-zoxide.zsh` composes those fragments into `_ZO_FZF_OPTS` before invoking `zoxide init`. `55-ui-helpers.zsh` continues to own rendering primitives. `40-fzf.zsh` continues to own fzf validation, integration caching, global/widget/completion option composition, and generated entry-point guards.

Capture an inherited `_ZO_FZF_OPTS` once and append it as the final zoxide-specific override. Re-sourcing or changing themes must not duplicate it. Because zoxide reads the environment when `query --interactive` runs, `ztheme use` can refresh `_ZO_FZF_OPTS` for subsequent `zi` and interactive-completion launches without regenerating zoxide's shell integration.

The module must use Zsh builtins only at source time. If terminal capability metadata is needed, prefer the `zsh/terminfo` module and cached shell data over `tput` or other subprocesses.

### 2. Keep palette, layout, and glyphs independent

The supported public settings are:

| Setting | Values | Default | Purpose |
|---|---|---|---|
| `ZSH_UI_THEME` | built-in name or `custom` | `catppuccin-mocha` | Shared semantic palette |
| `ZSH_FZF_THEME` | built-in name, `custom`, or empty | empty, meaning `ZSH_UI_THEME` | Optional fzf-only palette override |
| `ZSH_FZF_LAYOUT` | `compact`, `roomy`, `minimal` | `compact` | Finder height, chrome, and preview proportions |
| `ZSH_UI_GLYPHS` | `auto`, `nerd`, `unicode`, `ascii` | `auto` | Symbols independently of color |
| `ZSH_FZF_EXTRA_OPTS` | fzf option scalar | empty | Intentional final user override |
| `ZSH_UI_CUSTOM_COLORS` | Zsh associative array | unset | Validated custom semantic palette |

Do not use `ZSH_THEME`; that name belongs to Oh My Zsh in many setups.

Compatibility rules:

- Existing `NO_COLOR` remains authoritative. For dashboards it retains the currently documented deterministic plain output. For fzf it keeps interaction but appends `--no-color` and prevents color-forced repository previews.
- Existing `NO_NERD_FONT=1` remains accepted as an alias for avoiding Nerd Font glyphs. It should select ordinary Unicode, not force ASCII. `ZSH_UI_GLYPHS=ascii` is the explicit ASCII-only mode.
- Non-UTF-8 locales, `TERM=dumb`, non-TTY dashboard output, and narrow dashboard output retain existing plain/ASCII fallbacks.
- Do not infer light versus dark. Users select `catppuccin-latte` or another light palette explicitly.

### 3. Define a strict semantic theme contract

Every non-terminal palette must define these roles:

| Group | Roles | Primary consumers |
|---|---|---|
| Background | `base`, `surface`, `selected` | fzf base/current rows, panels |
| Structure | `border`, `gutter` | borders, separators, scroll areas |
| Content | `text`, `muted` | normal and secondary content |
| Interaction | `accent`, `query`, `match`, `focus` | titles, prompt, query, highlights, pointer |
| Status | `info`, `success`, `warning`, `danger` | badges, markers, results |

Aliases such as `rosewater`, `mauve`, or `peach` may exist inside a built-in palette, but renderer and picker code must consume semantic roles. This prevents palette-specific names from leaking back into workflows.

The fzf compiler maps those roles across the complete 0.68 UI surface:

| fzf targets | Semantic source |
|---|---|
| `bg`, `list-bg`, `input-bg`, `header-bg`, `footer-bg`, `preview-bg` | `base` or `surface` according to section depth |
| `current-bg`, `selected-bg`, `alt-bg` | `selected` and a contrast-checked surface variant |
| `fg`, `list-fg`, `preview-fg`, `current-fg`, `selected-fg` | `text` |
| `query`, `prompt`, `ghost`, `info`, `spinner` | `query`, `accent`, `muted`, and `info` |
| `hl`, `current-hl`, `selected-hl` | `match` |
| outer/list/input/header/footer/preview borders | `border` |
| outer/list/input/header/footer/preview labels | `accent` or `muted` according to hierarchy |
| `pointer`, `marker`, `gutter`, `scrollbar`, `separator` | `focus`, `success`, `gutter`, and `border` |

Current focus and multi-selection must remain visually distinct. Themes may not assign the same combination of background, foreground, and non-color cue to both states.

Each resolved role must have:

- a validated six-digit RGB value for truecolor;
- a deterministic xterm-256 value;
- a deterministic ANSI/base16 fallback;
- a foreground/background-safe SGR representation when needed outside fzf.

The resolver may derive 256 and ANSI values from RGB using pure integer arithmetic, but must cache the result. Built-ins may store reviewed explicit mappings when they produce better contrast. The `terminal` theme is a special built-in that prefers terminal-default foreground/background and named ANSI accents instead of fixed RGB backgrounds.

Theme validation must reject:

- unknown theme names;
- missing roles;
- malformed RGB values;
- keys outside the documented custom contract;
- values containing whitespace, quotes, shell syntax, or fzf options.

An invalid startup selection falls back to `catppuccin-mocha`. A normal interactive prompt prints at most one concise diagnostic; non-interactive sourcing and `zsh -i -c` remain quiet. Invalid input to `ztheme use` returns nonzero without changing the current theme.

### 4. Support custom palettes as data, not code

Users may define a custom palette before sourcing `init.zsh`:

```zsh
typeset -gA ZSH_UI_CUSTOM_COLORS=(
  base 1e1e2e
  surface 313244
  selected 45475a
  border 6c7086
  gutter 1e1e2e
  text cdd6f4
  muted a6adc8
  accent cba6f7
  query a6e3a1
  match f38ba8
  focus f5e0dc
  info 89b4fa
  success a6e3a1
  warning f9e2af
  danger f38ba8
)
typeset -g ZSH_UI_THEME=custom
```

The exact final role list and example belong in `GUIDE.md`. Do not source `~/.config/zsh/themes/*.zsh`, search the filesystem, download palettes, or evaluate serialized shell code.

### 5. Raise the fzf baseline to 0.68.0

Set `_FZF_MIN_VERSION=0.68.0` and update every dependency check, diagnostic, help label, test fixture, README requirement, and GUIDE reference in the same implementation.

This new floor is functional, not cosmetic. Every supported fzf installation receives the same complete feature set:

- `--style=full` or `--style=minimal` as selected by `ZSH_FZF_LAYOUT`;
- list, input, header, footer, outer, and preview borders/labels where the context uses them;
- `line` borders for clean section separation without nested rounded boxes;
- contextual `--ghost` search hints;
- readable multiline theme definitions and optional `alt-bg` row separation;
- explicit current, selected, alternate, gutter, ghost, header, footer, preview, label, and match colors;
- `--accept-nth` so direct pickers emit only their public result fields;
- footer key hints and live selection counts for multi-select workflows;
- customizable gutter/pointer/marker cues;
- frozen identity columns where horizontal scrolling could hide the selected object's name;
- word-level wrapping and explicit wrap indicators for long history, help, and preview text;
- adaptive height, path/history schemes, and responsive preview switching already supported by earlier releases.

Builds from 0.60 through 0.67 are intentionally unsupported. Do not implement per-version branches, silent feature removal, or a reduced theme. The subsystem keeps its existing all-or-nothing security model: unsupported fzf blocks fuzzy workflows without affecting unrelated shell configuration or established non-fzf fallbacks.

Once implemented, this decision supersedes only the **minimum version value** in HC-03 of [`high-priority-ux-remediation.md`](./high-priority-ux-remediation.md). HC-03's validation, cache safety, diagnostic, and fail-closed requirements remain binding.

### 5.1 Use a consistent section hierarchy

The default `compact` layout should use a restrained `full:line` treatment rather than drawing a rounded box around every section. The `roomy` layout may use rounded section borders and more padding; `minimal` uses fzf's minimal preset while retaining essential labels, focus cues, and footer hints.

The first implementation freezes these layout values:

| Profile | Finder frame | Wide preview (at least 100 columns) | Narrow preview |
|---|---|---|---|
| `compact` | adaptive `~60%`, `reverse`, `full:line`, inline-right info | right `50%` | down `40%` |
| `roomy` | fixed `80%`, `reverse`, `full:rounded`, inline-right info | right `55%` | down `45%` |
| `minimal` | adaptive `~45%`, `reverse`, `minimal`, inline-right info | right `45%`, labels retained | down `35%`, labels retained |

The breakpoint is exactly 100 columns. Picker-specific preview defaults may hide a preview, but when shown they use these proportions. Layout switching changes presentation only; candidate generation, selection, and actions are invariant.

Each picker uses the same information hierarchy:

1. **List label:** what is being selected, such as `Files`, `Branches`, or `Packages`.
2. **Input label and ghost:** `Search` plus a short context hint such as `Type to filter branches`.
3. **Header:** workflow-specific context or warnings only, such as the signal used by `fkill`; do not duplicate key help here.
4. **Preview label:** what the preview represents, such as `File`, `Log`, `Usage`, or `Package`.
5. **Footer:** key actions in a stable order and, for multi-select pickers, the live selected count.

Labels must remain short, ASCII-safe after glyph fallback, and useful without color. Avoid showing empty decorative sections.

### 5.2 Use advanced interaction features deliberately

- Use `--accept-nth` for `fkill`, `fbr`, `zhelp`, and Nix removal so hidden transport fields are not reparsed after selection.
- Use the 0.64 `multi` event only in multi-select pickers. Its `transform-footer` command must use shell builtins, never network or expensive external commands.
- Use `--wrap=word` for history, help summaries, and descriptive package rows. Keep paths, branch names, and process identity rows single-line unless manual QA proves wrapping improves them.
- Use preview `wrap-word` for textual help, Git logs, and Nix metadata; retain user control to toggle wrapping or hide the preview.
- Use `--freeze-left` only when the visible list is tabular and horizontal scrolling could hide its identity column. Do not freeze hidden transport fields.
- Use `alt-bg` sparingly. It may improve roomy tabular pickers, but the compact default must prioritize selected/current contrast over decorative striping.
- Raw mode, clickable footers, background transforms unrelated to status, tmux/Zellij popups, and network-backed dynamic labels remain out of scope.

### 6. Separate integration caching from presentation refresh

Keep the existing trusted integration cache keyed by fzf executable identity, cache schema, and Zsh version.

Replace `_FZF_CONFIGURED_BY_PATH` as the presentation guard with a configuration signature that includes at least:

- resolved fzf path;
- active fzf theme;
- color depth or no-color mode;
- glyph mode;
- fzf layout profile;
- relevant terminal width class;
- inherited global, widget, completion, and zoxide fzf-option identities plus explicit extra-option identities.

When the signature changes, rebuild the four global/widget option variables, the three completion overlays, and `_ZO_FZF_OPTS`. Do not rerun `fzf --version`, `fzf --zsh`, syntax validation, or cache creation merely because a theme, width, or glyph mode changed.

### 7. Define fzf option ownership and precedence

Build exported fzf settings in four layers:

1. repository structural defaults: style preset, section hierarchy, layout, info placement, gutter, and safe common behavior;
2. active palette mapped to all used 0.68 color targets, or final `--no-color`;
3. entry-point behavior in `FZF_CTRL_T_OPTS`, `FZF_CTRL_R_OPTS`, `FZF_ALT_C_OPTS`, `FZF_COMPLETION_OPTS`, `FZF_COMPLETION_PATH_OPTS`, and `FZF_COMPLETION_DIR_OPTS`;
4. inherited user options and documented `ZSH_FZF_EXTRA_OPTS`, with explicit extras last.

Capture inherited `FZF_DEFAULT_OPTS`, `FZF_CTRL_T_OPTS`, `FZF_CTRL_R_OPTS`, `FZF_ALT_C_OPTS`, `FZF_COMPLETION_OPTS`, `FZF_COMPLETION_PATH_OPTS`, and `FZF_COMPLETION_DIR_OPTS` exactly once. Re-sourcing `init.zsh` or changing themes must not duplicate repository fragments or recapture the already-composed output.

Apply shared chrome, palette, glyph, and footer fragments to `FZF_COMPLETION_OPTS`; add only context labels, ghosts, and path/directory-specific layout to the two specialized overlays. Do not add a global completion preview: completion is command-agnostic, and the generated `__fzf_comprun` wrapper must remain the authority for any command-aware preview behavior. Preserve fzf's candidate generation, trigger, multi-selection, result insertion, and generated-function behavior.

Compose `_ZO_FZF_OPTS` from the same palette, section, directory-search, glyph, layout, and footer fragments before `zoxide init`, followed by the captured inherited value. Keep zoxide's own candidate generation, scoring, and selection semantics authoritative. The shared layer owns presentation only.

Picker-specific prompts, headers, labels, previews, bindings, delimiters, and field selectors must be passed as Zsh arrays wherever the picker is invoked directly. Do not use `eval`. Keep complex preview commands out of global defaults.

Document that explicit command-line picker arguments have normal fzf precedence and that `ZSH_FZF_EXTRA_OPTS` can intentionally override managed defaults. If inherited user colors override the selected theme, `ztheme current` should report that an external option layer is present rather than attempting unsafe parsing.

### 8. Centralize picker presentation

Add array-returning internal helpers for:

- common chrome and active palette;
- list, input, header, footer, outer, and preview section policy;
- pointer and multi-select marker by glyph tier;
- border, label, ghost, gutter, wrap sign, and footer formatting;
- compact/roomy/minimal height policy;
- wide side preview versus narrow lower preview;
- standard key hints;
- live multi-selection footer status;
- no-color preview environment;
- safe role-to-SGR values for repository-owned preview text.

Picker contexts retain their unique data and actions:

| Context | Sections | Preview and interaction contract |
|---|---|---|
| Ctrl+T | Files / Search / File / footer | Path scheme; directory/file preview; toggle preview; word-wrap preview only |
| Ctrl+R | History / Search / Command / footer | History scheme; word-wrapped long commands; existing `?` preview toggle retained |
| Alt+C | Directories / Search / footer | Directory-focused filtering; preview hidden by default |
| fzf `**<Tab>` completion | Completions, Paths, or Directories / Search / footer | Compose general/path/directory completion overlays; no global preview; retain generated insertion and multi-select semantics |
| `zi` and zoxide interactive completion | Directories / Search / footer | Compose `_ZO_FZF_OPTS` before `zoxide init`; retain zoxide scoring and selection semantics |
| `fkill` | Processes / Search / signal header / footer | Multi-select; live selected count; `--accept-nth` emits PIDs only; no preview required |
| `fbr` | Branches / Search / Log / footer | Responsive word-wrapped Git log preview; worktree badge uses semantic status role; selected branch returned directly |
| `zhelp` | Commands / Search / Usage / footer | Word-wrapped responsive preview; Enter returns the example field and queues but never executes it |
| Nix install/find | Packages / Search / Package / footer | Multi-select with live count; responsive word-wrapped metadata preview |
| Nix remove | Installed packages / Search / Package / footer | Multi-select with live count; responsive preview; target fields returned directly |

Standard footer hint order is `Enter`, then `Tab` when multi-select is supported, then preview/wrap controls when present, then `Esc`. Use terse text that survives narrow layouts. The header is not a second key-hint surface. Esc and interrupted picker exits retain their current non-destructive behavior.

### 9. Improve responsive behavior without changing actions

- Use adaptive height for short candidate sets where it does not cause layout jitter.
- Use one 100-column breakpoint for side versus lower previews, preserving existing Nix and zhelp behavior at 99/100 columns.
- Make `fbr` and Ctrl+T follow the same responsive policy instead of always reserving 60% on the right.
- Add a consistent preview-toggle and preview-wrap binding where a textual preview exists, while retaining the documented Ctrl+R `?` binding.
- Give preview windows short context labels such as `File`, `Command`, `Log`, `Usage`, or `Package`.
- Keep list identity fields visible in long tabular rows with `--freeze-left` where it is semantically correct.
- Use `--accept-nth` to keep returned values stable even when visible columns or ANSI decoration change.
- Keep external preview theming conservative. Under `NO_COLOR`, replace `--color=always` with no-color equivalents for repository-managed `bat`, `tree`, `lsd`, Git, and preview text paths. Outside `NO_COLOR`, let those tools retain their own theme systems.

### 10. Improve glyph fallback independently of color

Use three glyph tiers:

1. `nerd`: current Nerd Font icons plus Unicode borders and indicators;
2. `unicode`: ordinary Unicode arrows, checks, box drawing, bars, and ellipsis without private-use glyphs;
3. `ascii`: `>`, `+`, `*`, `-`, `|`, and `...`.

`auto` selects `nerd` unless `NO_NERD_FONT` is set, in which case it selects `unicode`; non-UTF-8 locales select `ascii`. No workflow may communicate success, warning, selection, or danger through color alone.

The shared fzf glyph contract is fixed as follows:

| Tier | Pointer | Selected marker | Gutter | Scrollbar | Separator | Wrap sign |
|---|---|---|---|---|---|---|
| `nerd` | `󰘳` | `󰄬` | `│` | `┃` | `─` | `↳` |
| `unicode` | `›` | `✓` | `│` | `┃` | `─` | `↳` |
| `ascii` | `>` | `+` | `|` | `|` | `-` | `>` |

## Public `ztheme` command

Add a small function with no external dependency:

```text
ztheme list
ztheme current
ztheme show [name]
ztheme use <name>
ztheme reset
ztheme export <name>
```

Behavior:

- `list` prints stable built-in names and indicates the current/default selections.
- `current` reports UI theme, optional fzf override, layout, glyph tier, and color depth/no-color state.
- `show` renders a compact semantic swatch/status sample when rich output is available and a stable role/value table otherwise.
- `use` validates and applies a theme to the current shell, including future fzf launches and dashboards.
- `reset` returns both UI and fzf to `catppuccin-mocha` for the current shell.
- `export` prints the exact safe assignment to place before `source init.zsh` in the user's machine-local `.zshrc`.

The command does not edit `.zshrc`, create a persistence file, or recolor an already-open fzf instance. Theme selection remains machine-local configuration outside this repository.

## Built-in palette acceptance

| Theme | Type | Intent |
|---|---|---|
| `catppuccin-mocha` | dark | Compatibility default; canonicalize current semantic mappings |
| `catppuccin-latte` | light | First-class light-background option |
| `nord` | dark | Muted cool, higher structural restraint |
| `gruvbox-dark` | dark | Warm, higher-contrast alternative |
| `terminal` | adaptive | Prefer terminal defaults and ANSI accents |

For every built-in:

- all required roles resolve at truecolor, 256-color, and ANSI depth;
- text/background, current-row, match, warning, and danger pairs remain visually distinguishable;
- focused and multi-selected rows have both color and non-color cues;
- the default theme has no unintentional wholesale visual migration;
- canonical source and license attribution are recorded in comments or `GUIDE.md` where appropriate.

## Work packages

The work is divided so file ownership stays narrow and parallel tasks do not edit the same surfaces.

### T1. Freeze the contract and visual baseline

**Status:** Completed 2026-08-19

**Depends on:** none

**Primary files:** this specification; optional local screenshots or notes only

**Size:** small

- Confirm public variable names, initial built-ins, required roles, default, `NO_COLOR`, glyph tiers, and invalid-selection behavior.
- Capture current Mocha fzf/dashboard appearance and the 59/60 and 99/100 width boundaries.
- Prototype the `compact`, `roomy`, and `minimal` section hierarchy on fzf 0.68 before freezing exact borders and padding.
- Record intentional visual differences: full section hierarchy, ghost hints, footers, live multi counts, word wrapping, unified border/marker roles, fzf-wide no-color, Unicode-without-Nerd behavior, and responsive `fbr`.

**Done when:** no unresolved behavior choice remains for implementation tasks.

### T2. Implement the registry and resolver

**Status:** Completed 2026-08-19

**Depends on:** T1

**Primary files:** new `25-theme.zsh`, `init.zsh`, new `scripts/test-theme.zsh`

**Size:** large

- Add built-in semantic palette data and validated custom palette support.
- Resolve truecolor/256/ANSI depth and glyph tier with no source-time subprocesses.
- Expose `REPLY`/`reply`-based internal APIs for role values, SGR values, fzf colors, glyphs, and theme signatures.
- Implement deterministic fallback and mode-appropriate diagnostics.

**Done when:** all roles and failure modes pass isolated tests without touching fzf or dashboard call sites.

### T3. Migrate the dashboard renderer

**Status:** Completed 2026-08-19

**Depends on:** T2

**Primary files:** `55-ui-helpers.zsh`, theme/UI portions of `scripts/test-functions.zsh`, `scripts/test-upkg.zsh`, and `scripts/test-cgm.zsh`

**Size:** medium

- Replace fixed palette functions with registry lookups.
- Separate role-to-SGR resolution from printing so picker previews can consume safe escapes.
- Preserve rich/plain decisions, sanitization, truncation, status metadata, bars, borders, and independent-source fallbacks.
- Make `NO_NERD_FONT` select Unicode rather than ASCII while preserving explicit ASCII mode.

**Done when:** every dashboard renders from semantic roles and existing plain-output tests remain stable.

### T4. Refactor fzf option generation

**Status:** Completed 2026-08-19

**Depends on:** T2

**Primary files:** `30-zoxide.zsh`, `40-fzf.zsh`, `scripts/check-deps.sh`, shared minimum diagnostics in `60-functions.zsh` and `65-help.zsh`, fzf/zoxide portions of `scripts/test-init.zsh`

**Size:** large

**Parallel with:** T3

- Split global chrome, palette, widget behavior, and user extras.
- Make exports signature-aware and idempotent.
- Preserve version validation, hard blocking, generated widgets, safe cache ownership checks, and quiet command-mode startup.
- Prove theme/layout changes refresh options without regenerating integration code.
- Make `NO_COLOR` final and authoritative.
- Raise the minimum and every boundary fixture to 0.68.0; assert that 0.67.x is blocked.
- Compile style presets, section colors, ghost, footer, gutter, and word-wrap fragments from shared policy.
- Compose and refresh the general, path, and directory `FZF_COMPLETION_*_OPTS` overlays while preserving inherited options exactly once and leaving generated completion semantics intact.
- Compose and refresh `_ZO_FZF_OPTS` before zoxide initialization while preserving inherited options exactly once.

**Done when:** all supported 0.68+ fixtures retain the four global/widget exports, three completion overlays, zoxide options, the complete structured UI, generated bindings, and repository pickers under every built-in theme.

### T5. Build and migrate shared picker presentation

**Status:** Completed 2026-08-19

**Depends on:** T3 and T4

**Primary files:** `40-fzf.zsh`, fzf call sites in `60-functions.zsh` and `65-help.zsh`, related function/help tests

**Size:** large

- Add shared array-returning picker helpers.
- Migrate Ctrl+T, Ctrl+R, Alt+C, fzf `**<Tab>` completion, `fkill`, `fbr`, `zhelp`, and Nix install/remove.
- Replace Nix raw RGB preview strings and the `fbr` hard-coded badge.
- Standardize section labels, ghost hints, footer actions, live multi-selection counts, pointer/marker/gutter, layout profiles, responsive previews, word wrapping, and no-color preview behavior.
- Replace fragile post-selection field parsing with `--accept-nth` where the workflow returns a stable field.
- Keep identity columns visible with `--freeze-left` only in verified tabular contexts.
- Preserve all selection parsing, signals, checkout/worktree behavior, command queuing, and Nix mutations.

**Done when:** no repository picker owns theme colors or duplicates common presentation policy.

### T6. Add theme discovery and completion

**Status:** Completed 2026-08-19

**Depends on:** T2; use T4 for runtime fzf refresh

**Primary files:** command implementation location, `65-help.zsh`, `66-compdefs.zsh`, `scripts/test-help.zsh`, `scripts/test-completions.zsh`

**Size:** medium

**Parallel with:** late T3/T5 work once APIs are stable

- Implement `ztheme` subcommands and stable output contracts.
- Register one terse Meta help record.
- Add static completion for subcommands and built-ins without subprocesses or filesystem scanning.
- Test current-shell switching, invalid input, safe export text, and zero source-time subprocesses.

**Done when:** users can discover, inspect, apply, and persist-by-copying a theme safely.

### T7. Synchronize user and maintainer documentation

**Status:** Completed 2026-08-19

**Depends on:** T5 and T6 interfaces frozen

**Primary files:** `README.md`, `GUIDE.md`, `80-tips.zsh`, `AGENTS.md`

**Size:** medium

- Keep README to a one-line capability and minimal setup example.
- Add the complete theme reference, custom palette contract, picker behavior, accessibility, precedence, and gotchas to GUIDE.
- Add one short actionable theme tip.
- Update module ownership, the required fzf version, install/upgrade guidance, help dependency labels, and required verification lists.
- Preserve the boundary that prompt, Starship, terminal, and machine-local `.zshrc` configuration are outside the repo.

**Done when:** every public behavior is documented once at the correct level.

### T8. CI, integration, and manual visual QA

**Depends on:** T3-T7

**Primary files:** `.github/workflows/checks.yml`; local-only `qa-features.csv` for a stable-release pass

**Size:** medium

- Add syntax and execution steps for `scripts/test-theme.zsh`.
- Run the full ordered suite.
- Verify cold and cached interactive startup adds no theme-related subprocess or integration regeneration.
- Perform manual picker-by-picker visual QA across theme, width, color-depth, glyph, and no-color matrices.

**Done when:** all release gates below pass and the spec can be marked Implemented.

### Dependency graph

```text
T1 -> T2 -> T3 ----\
          \-> T4 ----> T5 ----\
              \------> T6 ----+--> T7 --> T8
```

T3 and T4 are the main parallel lane. T6 may begin after the resolver and fzf refresh API stabilize. T7 intentionally waits until public names and behavior stop moving.

## Implementation ledger

This section is updated inside each task commit. Git history is the authoritative task boundary; the final audit records the exact hashes for all task commits.

### Performance protocol

- Run `scripts/benchmark-startup.zsh 50` after the ordered automated checks for every task.
- The benchmark uses 3 warmups and 50 measured fresh Zsh processes for both command-mode sourcing and normal interactive startup with a warm fzf integration cache.
- Compare each median with the T1 baseline and the immediately preceding task. Treat a change as a slowdown only when the median is both more than 1.0 ms and more than 5% above the T1 baseline, then confirm it with a second 50-run sample.
- If confirmed, append a concrete remediation item under **Performance follow-ups** at the end of this specification and commit that plan update before beginning the next task.
- Record medians rather than one-off wall times; p95 remains diagnostic because it is more sensitive to unrelated host load.

### T1 ledger — contract and baseline

- **Commit:** task-scoped commit `chore(theming): freeze contract and startup baseline`
- **Outcome:** froze the 0.68 capability tier, exact layout profiles, 100-column preview breakpoint, glyph tiers, option precedence, theme safety boundaries, and all picker/completion/zoxide surfaces.
- **Capability probe:** fzf 0.74.3 accepted `full:line`, `full:rounded`, `minimal`, section labels, ghost text, footer, custom gutter, word-level list wrapping, and word-level preview wrapping.
- **Verification:** benchmark script syntax check and all ordered repository checks passed.
- **Performance:** command median 24.810 ms; interactive median 28.871 ms; 50 runs, warm cache. This is the baseline, so no slowdown follow-up was created.

### T2 ledger — registry and resolver

- **Commit:** task-scoped commit `feat(theming): add semantic theme registry`
- **Outcome:** added `25-theme.zsh` before zoxide with five built-ins, fifteen semantic roles, atomically validated custom palettes, truecolor/256/ANSI/terminal-default resolution, independent glyph resolution, safe fallbacks, cached active state, SGR/fzf-ready lookup APIs, and deterministic signatures.
- **Safety:** invalid names and custom values remain data; module sourcing uses no external commands; invalid startup settings are quiet outside a normal interactive prompt; re-sourcing is idempotent.
- **Verification:** `scripts/test-theme.zsh` covers built-ins, custom validation, fallback atomicity, depth and glyph modes, terminal defaults, unsafe input, idempotence, and zero source-time subprocesses. All ordered repository checks passed.
- **Performance:** command median 25.743 ms (+0.933 ms, +3.8% from baseline); interactive median 29.921 ms (+1.050 ms, +3.6%); 50 runs, warm cache. The change does not cross the combined 1 ms and 5% threshold, so no slowdown follow-up was created.

### T3 ledger — dashboard renderer migration

- **Commit:** task-scoped commit `feat(theming): migrate dashboard renderer`
- **Outcome:** removed the private dashboard palettes, routed all rich SGR output through semantic theme roles, kept deterministic plain output, and added a three-tier Nerd/Unicode/ASCII icon fallback without changing dashboard data or sanitization.
- **Compatibility:** `55-ui-helpers.zsh` can load the pure theme module when tested directly; `NO_COLOR`, redirected output, narrow terminals, dumb terminals, and non-UTF-8 locales remain plain and ASCII-safe. README, GUIDE, and tips describe the dashboard behavior now in effect.
- **Verification:** theme tests prove live palette changes, absence of the legacy palette functions, Unicode fallback, and colorless plain output. All ordered repository checks passed.
- **Performance:** first sample was command 25.111 ms and interactive 31.607 ms; the required confirmation sample was command 25.757 ms (+0.947 ms, +3.8% from baseline) and interactive 30.195 ms (+1.324 ms, +4.6%). The confirmation did not cross 5%, so no slowdown follow-up was created.

### T4 ledger — fzf and zoxide option generation

- **Commit:** task-scoped commit `feat(fzf): add theme-aware structured UI`
- **Outcome:** raised the hard floor to 0.68.0; replaced the path-only presentation guard with a theme/layout/glyph/width signature; added full semantic color/chrome compilation; themed Ctrl+T, Ctrl+R, Alt+C, generated completion overlays, and zoxide; and made inherited options idempotent with `NO_COLOR` final.
- **Security and compatibility:** integration generation, syntax validation, private cache checks, command-mode silence, runtime guards, and separate-shell `command -v` preview guards remain intact. Theme refresh does not rerun validation or generated integration.
- **Verification:** boundary fixtures accept 0.68/0.68.0 and reject 0.67.9; option tests cover all seven fzf option surfaces plus `_ZO_FZF_OPTS`, inherited precedence, re-source idempotence, theme/layout refresh, no-color previews, and no integration regeneration. Installed fzf accepts every compiled layout. All ordered repository checks passed.
- **Performance:** sample one was command 26.363 ms and interactive 32.391 ms; confirmation was command 32.227 ms (+7.417 ms, +29.9% from baseline) and interactive 35.700 ms (+6.829 ms, +23.7%). The regression is confirmed and tracked as PF-01.

### T5 ledger — shared direct-picker presentation

- **Commit:** task-scoped commit `feat(fzf): unify direct picker presentation`
- **Outcome:** added shared array-returning context, responsive-preview, and live multi-selection helpers; migrated `fkill`, `fbr`, `zhelp`, and both Nix pickers to labeled sections, contextual ghost hints, stable footers, semantic preview text, and consistent preview controls. Previously generated Ctrl+T, Ctrl+R, Alt+C, completion, and zoxide entry points continue to consume the same T4 presentation compiler.
- **Selection safety:** `--accept-nth` now returns raw PIDs, branch names, help examples, and Nix profile targets directly. Git and Nix rows place visible identity first before applying `--freeze-left=1`; cancellation and downstream signal, checkout/worktree, command-queueing, and Nix mutation behavior remain unchanged.
- **Verification:** tests cover the exact 99/100-column preview boundary, combined context/preview/multi arguments against installed fzf, stable result projection, live-count footer wiring, semantic badge/preview colors, and absence of duplicated pointer/marker policy. All ordered repository checks passed.
- **Performance:** sample one was command 25.615 ms and interactive 30.625 ms; confirmation was command 25.652 ms (+0.842 ms, +3.4% from baseline) and interactive 30.337 ms (+1.466 ms, +5.1%). Both medians improved materially from T4, so T5 introduced no new follow-up; the small remaining confirmed interactive baseline regression remains covered by PF-01.

### T6 ledger — theme discovery and completion

- **Commit:** task-scoped commit `feat(theming): add session theme command`
- **Outcome:** added `ztheme list`, `current`, `show`, `use`, `reset`, and `export`; safe plain tables and terminal swatches; atomic current-session switching; complete custom-palette export; one terse help record; and static subcommand/built-in completion.
- **Safety and refresh:** theme names remain validated data, invalid input changes nothing, and an fzf refresh failure rolls the public settings, resolved themes, and finder exports back. Successful switching refreshes future fzf and zoxide launches without subprocesses or persistent writes; exported settings are printed for deliberate placement in the machine-local `.zshrc`.
- **Verification:** tests cover switching, reset, refresh rollback, shell-like input, stable list/current/show output, external-option reporting, built-in and custom export, help coverage, static completion, and live fzf/zoxide export changes. All ordered repository checks passed.
- **Performance:** sample one was command 28.402 ms and interactive 32.181 ms; confirmation was command 27.198 ms (+2.388 ms, +9.6% from baseline; +1.546 ms, +6.0% from T5) and interactive 32.169 ms (+3.298 ms, +11.4% from baseline; +1.832 ms, +6.0% from T5). The new regression is confirmed and requires a dedicated performance follow-up.

### T7 ledger — documentation synchronization

- **Commit:** task-scoped commit `docs(theming): document themes and picker UX`
- **Outcome:** kept README as the short setup surface; made GUIDE authoritative for built-ins, all 15 custom roles, depth and glyph fallbacks, exact layout boundaries, option precedence, `ztheme`, picker controls, accessibility, persistence, and external-theme boundaries; and updated maintainer ownership and fzf upgrade guidance. The existing theme and picker tips were reviewed and remain concise and current.
- **Attribution:** GUIDE records canonical Catppuccin, Nord, and Gruvbox sources and their MIT licensing without adding startup-path metadata or executable work.
- **Verification:** documentation claims were checked against the live registry, option composition, command help, and generated exports. `zhelp --plain ztheme` reports the complete interface as available, and all ordered repository checks passed.
- **Performance:** sample one was command 26.053 ms and interactive 30.979 ms; confirmation was command 32.376 ms and interactive 31.223 ms. T7 changes documentation files only, so the executable startup tree is byte-identical to T6; the wide command-mode spread in the confirmation (p95 43.402 ms, max 48.823 ms) is host variance, while the remaining baseline regression is already covered by PF-01 and PF-02. No T7-specific follow-up was added.

## Automated acceptance criteria

### Registry and safety

- Every built-in defines every required role.
- Unknown, empty, malformed, and shell-like names cannot execute code or become fzf arguments.
- Custom palettes reject missing/extra roles and malformed values atomically.
- Invalid startup selection falls back once; invalid runtime selection preserves the active theme.
- Theme modules source without launching `fzf`, `tput`, `jq`, Python, or any other subprocess.
- Re-sourcing is idempotent.

### Color and glyph modes

- Truecolor, 256-color, ANSI, terminal-default, and no-color resolutions are deterministic.
- `NO_COLOR` produces no repository-owned ANSI color in fzf arguments, preview commands, or dashboards.
- `NO_NERD_FONT` produces ordinary Unicode without private-use glyphs.
- Non-UTF-8 and explicit ASCII modes contain no non-ASCII glyphs.
- Status and selection meaning remains visible without color.

### fzf integration

- Missing, malformed, prerelease, old, or broken fzf continues to hard-block fuzzy workflows exactly as documented.
- Supported 0.68, omitted-patch 0.68, newer minor, and newer major fixtures are accepted; 0.67.x and lower are blocked.
- All four global/widget `FZF_*` option variables, all three `FZF_COMPLETION_*_OPTS` overlays, `_ZO_FZF_OPTS`, generated keybindings/completion, and every repository picker remain available.
- Each built-in defines the complete section, current, selected, alternate, ghost, footer, gutter, preview, and no-color mapping used by the 0.68 UI.
- Compact, roomy, and minimal layouts emit only options available at the 0.68 floor.
- Theme, glyph, layout, width-class, and extra-option changes refresh presentation without rerunning `fzf --version` or `fzf --zsh`.
- Inherited global, widget, completion, zoxide, and explicit extra options are preserved once, with no duplication after re-source or theme switching.
- Non-interactive and `zsh -i -c` startup stay silent and avoid ZLE initialization.
- The minimum-version diagnostic, dependency checker, help labels, README, GUIDE, and tests all report 0.68.0 consistently.

### Picker behavior

- Ctrl+T, Ctrl+R, Alt+C, fzf `**<Tab>` completion, `zi`, `fkill`, `fbr`, `zhelp`, and Nix pickers use the same resolved theme and glyph policy.
- General, path, and directory `**<Tab>` completion receive the documented labels, ghost, footer, and no-color policy without changing candidate insertion, multi-selection, or generated `__fzf_comprun` behavior.
- Zoxide `zi` and interactive Space-Tab completion receive the shared directory-picker sections through `_ZO_FZF_OPTS` without replacing zoxide's generated functions.
- Responsive preview tests cover 99 and 100 columns.
- Dashboard mode tests retain the 59 and 60 column boundary.
- Every picker has the documented list/input/footer hierarchy; preview and header sections appear only when useful.
- Empty query fields show contextual ghost text.
- Multi-select footer tests cover zero, one, and multiple selected items without invoking external commands.
- `--accept-nth` results contain only the stable field expected by each migrated workflow.
- Long history/help/preview fixtures wrap by words and preserve explicit preview-wrap controls.
- Frozen identity columns stay visible in each picker that opts into horizontal scrolling.
- Cancel leaves command buffers and system state unchanged.
- `zhelp` still queues examples without executing them.
- `fkill`, Git worktree navigation, and Nix selection/mutation semantics are unchanged.
- Preview commands retain function-body/separate-shell `command -v` guards.

### Documentation and discovery

- `ztheme` has terse help, static completion, and one actionable tip.
- README remains a short entry point; GUIDE owns full configuration and caveats.
- Source-order and verification lists include the new theme module and test.
- No documentation claims that this repository controls the prompt or external application themes.

## Manual QA matrix

For a stable release, create the repository's local-only `qa-features.csv` and cover only interactive behavior:

| Axis | Cases |
|---|---|
| Theme | Mocha, Latte, Nord, Gruvbox Dark, terminal, custom |
| Color | truecolor, 256, ANSI/default, `NO_COLOR=1` |
| Glyph | Nerd, Unicode, ASCII, non-UTF-8 |
| Width | 59, 60, 99, 100, and a wide terminal |
| fzf | 0.68 boundary, one blocked 0.67.x build, and current installed version |
| Picker | Ctrl+T, Ctrl+R, Alt+C, general/path/directory `**<Tab>` completion, `zi`, fkill, fbr, zhelp, Nix install/remove |
| State | default startup, cached startup, session theme switch, invalid theme, re-source |

Check focus contrast, selected-versus-current distinction, border/label clarity, truncation, preview placement, key-hint readability, cancel behavior, and absence of color leakage under `NO_COLOR`.

## Ordered verification after implementation

Run:

```sh
zsh -n *.zsh
sh -n scripts/check-deps.sh
zsh scripts/test-init.zsh
zsh scripts/test-theme.zsh
zsh scripts/test-functions.zsh
zsh scripts/test-cgm.zsh
zsh scripts/test-upkg.zsh
zsh scripts/test-completions.zsh
zsh scripts/test-help.zsh
zsh -fc 'source "$HOME/.config/zsh/init.zsh"'
```

Then run the dependency checker as an optional environment check and complete the manual QA matrix for a stable release.

## Release gates

Do not mark this specification Implemented until:

1. all built-ins and custom validation pass at every supported color depth;
2. all fuzzy workflows require fzf 0.68.0, block older builds, and use no post-0.68 options;
3. a theme switch refreshes future fzf launches without regenerating integration code;
4. no repository-owned hard-coded palette remains in picker or dashboard call sites;
5. `NO_COLOR`, Unicode, Nerd Font, ASCII, redirected, dumb-terminal, and non-UTF-8 behavior is documented and tested;
6. README, GUIDE, help, tips, completion, CI, AGENTS, and source-order documentation are synchronized;
7. the full ordered verification suite passes; and
8. manual QA finds no unreadable theme, broken layout boundary, destructive cancel path, or startup regression.

## Rollback boundaries

The implementation should be landed in task-sized commits so failures can be isolated:

- Theme data/resolver can be reverted without touching fzf validation.
- Dashboard migration can be reverted independently from fzf option generation.
- Picker presentation can be reverted without reverting picker data/action logic.
- `ztheme` can be disabled without removing environment-based theme selection.
- A problematic non-default built-in can be removed while retaining Mocha and the registry contract.

Never roll back by weakening fzf validation, evaluating generated code earlier, deleting a picker, removing plain fallbacks, or silently ignoring `NO_COLOR`.

## Performance follow-ups

### PF-01. Recover theme/fzf startup overhead

**Status:** Open; execute after T8 and before the final audit

**Introduced by:** T4 (`a8b8e09`)

**Evidence:** the confirmation benchmark measured command startup at 32.227 ms versus the 24.810 ms baseline and interactive startup at 35.700 ms versus 28.871 ms. Both exceed the combined 1 ms and 5% threshold.

**Plan:**

- profile command and interactive startup separately to distinguish module parsing, semantic color compilation, zoxide initialization, and fzf export composition;
- cache or precompute repeated role-to-fzf mappings by theme/depth/layout/glyph signature and avoid rebuilding identical chrome for zoxide and fzf;
- reduce work on the command-mode path while preserving the requirement that `_ZO_FZF_OPTS` exists before `zoxide init`;
- keep version validation, generated-integration cache safety, option precedence, `NO_COLOR`, and all presentation acceptance criteria unchanged;
- add a regression assertion or a documented benchmark comparison that remains stable enough for this repository's environment.

**Exit criterion:** two consecutive 50-run samples must put both medians below the T1 slowdown threshold (command at or below 26.051 ms and interactive at or below 30.315 ms), with the full ordered suite passing. If host variance prevents that absolute target, document the profile evidence and demonstrate that the optimized task is not more than 5% slower than an immediately adjacent checkout of the T1 commit under interleaved measurements.

### PF-02. Remove `ztheme` command startup parsing overhead

**Status:** Open; execute with PF-01 after T8 and before the final audit

**Introduced by:** T6 (`bc8ad5b`)

**Evidence:** the confirmation benchmark measured command startup at 27.198 ms and interactive startup at 32.169 ms. Both are approximately 6.0% slower than the immediately preceding T5 tree, as well as above the T1 threshold.

**Plan:**

- profile parsing and definition cost separately from runtime switching to confirm how much of the regression comes from the new command helpers;
- keep only a small, source-time-safe public entry point on the startup path and defer swatch rendering, serialization, and other command-only implementation until the first `ztheme` invocation if profiling confirms that is cheaper;
- preserve help availability, static completion, atomic rollback, custom export, zero source-time subprocesses, and current-session fzf/zoxide refresh behavior;
- avoid an eager extra module source or any filesystem scan during normal shell initialization;
- cover first invocation, repeated invocation, re-sourcing, and missing/blocked fzf states after optimization.

**Exit criterion:** two consecutive 50-run samples must show that T6 is not more than 1.0 ms and 5% slower than T5 on either startup path. The stricter PF-01 baseline exit criterion still governs completion of the combined optimization work.
