# Shared Zsh Configuration Guide

This is the complete user and maintainer reference for the shared configuration in `~/.config/zsh`. For the shortest setup path, start with [`README.md`](./README.md). When documentation and code disagree, the module files are authoritative.

The configuration is a GNU/Linux-focused layer that is sourced by a machine-local `~/.zshrc`. Oh My Zsh, Starship, PATH setup, `compinit`, and host-specific choices remain outside this repository.

## Contents

- [Setup and scope](#setup-and-scope)
- [Module layout](#module-layout)
- [Dependencies](#dependencies)
- [Terminal output modes](#terminal-output-modes)
- [Shell options and history](#shell-options-and-history)
- [Completion](#completion)
- [Command discovery](#command-discovery)
- [Aliases](#aliases)
- [Zoxide and fzf](#zoxide-and-fzf)
- [Function reference](#function-reference)
- [Credential manager: cgm](#credential-manager-cgm)
- [Package manager: upkg](#package-manager-upkg)
- [Nix profile manager: npkg](#nix-profile-manager-npkg)
- [Gotchas and safety boundaries](#gotchas-and-safety-boundaries)
- [Maintenance and verification](#maintenance-and-verification)

## Setup and scope

The repository is expected at `~/.config/zsh` because `init.zsh` loads modules from that fixed location. Clone it into an empty target directory:

```sh
git clone https://github.com/Thundernirmal/zsh.git "$HOME/.config/zsh"
```

Add this near the end of `~/.zshrc`:

```zsh
if [ -r "$HOME/.config/zsh/init.zsh" ]; then
  source "$HOME/.config/zsh/init.zsh"
fi
```

Source it after Oh My Zsh when these aliases and functions should override framework defaults. Without a framework, run `compinit` before the snippet so Tab completion registers:

```zsh
autoload -Uz compinit && compinit -i
```

Reload and verify with:

```zsh
exec zsh
$HOME/.config/zsh/scripts/check-deps.sh
zdoctor
```

The shared layer manages:

- Zsh options and history defaults
- aliases, global aliases, and shell functions
- guarded zoxide, fzf, Nix, and Secret Service integrations
- lightweight completion styles and command-specific completions
- terminal UI helpers, `zhelp`, and `tips`

It does not manage:

- framework or plugin installation
- prompt configuration
- machine-local PATH entries
- `compinit` startup
- non-Zsh shells

Unreadable module files are skipped. The optional credential module is skipped entirely when `secret-tool` is absent at startup. Either silence means a degraded shell without an error, so run `zdoctor` when a feature is missing: it reports install location, unreadable modules, completion readiness, tool availability, glyph settings, and integration status, and returns nonzero while a real failure is present.

## Module layout

`init.zsh` sets the shared options, then sources modules in this order:

| Module | Responsibility |
|---|---|
| `10-history.zsh` | Shared 100,000-entry history |
| `20-aliases.zsh` | Navigation, file, and Git aliases |
| `25-theme.zsh` | Semantic palette registry, validation, color depth, glyphs, and reusable fzf presentation fragments |
| `30-zoxide.zsh` | Guarded zoxide initialization and `zi` fzf gate |
| `40-fzf.zsh` | fzf validation, secure integration cache, structured presentation, previews, and bindings |
| `50-completion.zsh` | Lightweight global completion styles |
| `55-ui-helpers.zsh` | Rich terminal rendering and plain fallbacks |
| `60-functions.zsh` | Fixed lazy registrations for general helpers, session-only `ztheme`, `upkg`, optional `npkg`, and `zdoctor` |
| `62-cgm.zsh` | Optional Secret Service credential manager |
| `65-help.zsh` | Fixed lazy-loader registration for `zhelp` |
| `66-compdefs.zsh` | Command-aware completion definitions |
| `70-globals.zsh` | Global pipe and redirection aliases |
| `80-tips.zsh` | Fixed lazy-loader registration for hook-free, on-demand tips |

The numbered filenames define load order. `50-completion.zsh` assumes an earlier layer already ran `compinit`; `66-compdefs.zsh` becomes a silent no-op when `compdef` is unavailable.

The repo-local `functions/ztheme`, `functions/_fbr_format_entry`, `lib/functions-*.zsh`, `lib/command-registry.zsh`, `lib/ui-width-data.zsh`, `lib/theme-*.zsh`, `lib/help-catalogue.zsh`, and `lib/tips-catalogue.zsh` files are lazy implementation helpers rather than startup modules. Their numbered modules register fixed loaders, while general command implementations, package workflows, command-only swatch/export logic, catalogues, fbr row formatting, palette data, validation, and color conversion code are parsed on first use. `lib/upkg-registry.zsh` is instead a lightweight registry sourced during startup by `60-functions.zsh` and reused by `66-compdefs.zsh` when `compdef` is available. A configured custom or colored non-default startup loads the theme pieces it needs before composing finder options.

General helpers load their fixed domain on first use: files/search, system diagnostics/network, Git, package orchestration/backend adapters, or Nix. Shared presentation fallbacks load once. Calling `mkcd` or `path` leaves package implementations unloaded; later calls use installed implementations directly. All paths remain fixed beneath the repository. Disk scanners collect records plus explicit state, diagnostics, and exit status before choosing a rich or plain renderer; both preserve partial-scan failures. `lib/command-registry.zsh` is data-only and shared by help and command-name completion; it records canonical names and descriptive mutation categories without authorizing any operation.

## Dependencies

Run the checker after installing or changing tools:

```sh
$HOME/.config/zsh/scripts/check-deps.sh
```

### Required for the intended setup

| Command | Used for |
|---|---|
| `zsh` | Shell and module syntax |
| `git` | Git helpers and `fbr` |
| `curl` | `weather`, `headers`, and `myip` |
| `ss` | `ports` |
| `lsd` | Preferred file listing |
| `zoxide` | `z` and `zi` navigation |
| `fzf` 0.68.0+ | Keybindings and every fuzzy picker |

`fzf` must report a stable numeric version. Missing, malformed, prerelease, and older builds fail the dependency check and hard-block fuzzy workflows.

If the distribution package is older than 0.68.0, upgrade through a current package source or use the [official fzf installation instructions](https://github.com/junegunn/fzf#installation), then restart the shell and rerun `scripts/check-deps.sh`. There is no reduced UI for 0.60–0.67.

### Optional integrations and fallbacks

| Command | Effect when present | Fallback or absence behavior |
|---|---|---|
| `bat` | Highlighted `cat` alias, `peek`, and file previews | `peek` uses `cat`; fzf previews use `sed` |
| `tree` | `lt` and directory previews when `lsd` is absent | Preview uses `ls`; `lt` is unavailable without `lsd` or `tree` |
| `fd` / `fdfind` | Faster `ff` search | GNU `find` |
| `rg` | Faster `ft` content search | Recursive `grep` |
| `jq` | `npkg refresh`, `npkg outdated`, and Nix pickers | Those workflows are unavailable; basic Nix commands still work |
| `secret-tool` | Defines `cgm` | The entire module is skipped |
| `gdbus` | Explicit `cgm check` backend health probe | Health check explains the missing GLib tool; storage and loading still work |
| `nix` | Defines `npkg` and the `upkg` Nix backend | Nix commands are absent |
| `nix-collect-garbage` | `upkg clean --only nix` | Nix cleanup reports a failure |
| `unzip`, `unrar`, `7z`, and related tools | Format-specific extraction | `extract` reports the missing tool when used |

Package managers are detected at runtime; they are not setup dependencies. The checker reports the primary optional integrations, while format-specific unpackers and ordinary GNU userland tools are checked only by the workflows that need them.

On Debian and Ubuntu, the distribution may expose `bat` as `batcat`. This repository looks specifically for `bat`, so install a package that provides that command or add a deliberate local wrapper.

## Terminal output modes

Dashboards use the shared semantic theme renderer only when all of these are true:

- stdout is a terminal
- `TERM` is set and is not `dumb`
- the locale is UTF-8
- the terminal is at least 60 columns wide
- `NO_COLOR` is unset

Pipes, redirects, narrow terminals, non-UTF-8 locales, and dumb terminals receive deterministic plain text.

| Setting | Effect |
|---|---|
| `ZSH_UI_THEME=terminal` | Select the dashboard palette; built-ins are `catppuccin-mocha`, `catppuccin-latte`, `nord`, `gruvbox-dark`, and `terminal` |
| `ZSH_FZF_THEME=` | Inherit `ZSH_UI_THEME`; set a built-in name or `custom` for an fzf-only override |
| `ZSH_FZF_LAYOUT=compact` | Select the `compact`, `roomy`, or `minimal` finder layout |
| `ZSH_FZF_EXTRA_OPTS=` | Append an intentional final user option layer to shared fzf defaults |
| `ZSH_UI_GLYPHS=auto` | Select `auto`, `nerd`, `unicode`, or `ascii` dashboard and finder glyphs independently of color |
| `ZSH_UI_CUSTOM_COLORS` | Provide all semantic roles as a validated associative array for the `custom` theme |
| `NO_COLOR=1` | Force dashboards to plain output and fzf to its no-color presentation |
| `NO_NERD_FONT=1` | Downgrade Nerd Font tiers to ordinary Unicode without touching color |
| `zhelp --plain` | Force the stable plain help view |

Set theme variables before sourcing `init.zsh`. `terminal` is the default. Invalid names and incomplete or malformed custom palettes fall back to it without evaluating input as shell code. The `terminal` palette prefers terminal-default backgrounds and ANSI accents.

`NO_COLOR` does not disable fuzzy interaction. It removes repository-managed fzf colors, prevents color-forced file previews, and remains the final option even when inherited or extra options request colors.

### Built-ins, color depth, and glyphs

| Theme | Background intent | Notes |
|---|---|---|
| `catppuccin-mocha` | dark | Compatibility palette (former default) |
| `catppuccin-latte` | light | Explicit light-background choice; background brightness is never guessed |
| `nord` | dark | Muted cool palette |
| `gruvbox-dark` | dark | Warm, higher-contrast palette |
| `terminal` | terminal-owned | Default; uses default terminal foreground/background and named ANSI accents |

The fixed palette values are adapted from the MIT-licensed [Catppuccin](https://catppuccin.com/palette/), [Nord](https://github.com/nordtheme/nord), and [Gruvbox](https://github.com/morhetz/gruvbox) projects. The resolver emits RGB when `COLORTERM` is `truecolor` or `24bit`, xterm-256 values when `TERM` contains `256color`, and deterministic ANSI colors otherwise. It uses no terminal query or source-time subprocess.

Glyph selection is independent of palette and color depth. UTF-8 support alone does not prove private-use icons exist in the font, so automatic mode stays with ordinary Unicode and Nerd Font icons are an explicit opt-in:

| Mode | Behavior |
|---|---|
| `auto` | Ordinary Unicode in UTF-8 locales; ASCII outside UTF-8 |
| `nerd` | Private-use Nerd Font icons plus Unicode structure symbols |
| `unicode` | Ordinary Unicode only, with no private-use glyphs |
| `ascii` | ASCII pointers, markers, separators, and status symbols only |

`NO_NERD_FONT=1` records that the terminal lacks private-use glyphs and downgrades even an explicit `nerd` tier to Unicode. Verify the resolved tier and its sample symbols with `ztheme current` before settling on a mode.

Selection, focus, success, warning, and danger retain text, pointer, marker, label, or status-word cues rather than relying only on color. `NO_NERD_FONT` affects symbols, not color; `NO_COLOR` affects repository-managed color, not picker availability. The no-color options explicitly reset the footer to terminal-default foreground to work around fzf 0.68.0’s incomplete no-color theme.

### Custom palette contract

Define a custom palette before sourcing `init.zsh`, then select it for the shared UI and optionally for fzf:

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
typeset -g ZSH_FZF_THEME=''
```

All 15 keys are required, extra keys are rejected, and every value must be exactly six hexadecimal digits without `#`. Validation is atomic: a missing, extra, or malformed value makes startup fall back to the terminal theme rather than partially applying the palette. Theme names and values are data only; the configuration does not evaluate them, source a theme directory, scan the filesystem, or download palettes.

### Finder layout and option precedence

| Layout | Frame | Preview at 100+ columns | Preview below 100 columns |
|---|---|---|---|
| `compact` | adaptive `~60%`, one rounded frame, `0,1` padding | right `50%` | down `40%` |
| `roomy` | fixed `80%`, one rounded frame, `1,2` padding | right `55%` | down `45%` |
| `minimal` | adaptive `~45%`, one rounded frame, `0,1` padding | right `45%` | down `35%` |

Every profile uses a single rounded outer box. The input and footer share the base finder background instead of drawing filled inner boxes. The input and optional header have one lower divider, the footer has one upper divider, and the list does not draw a nested box. The picker label sits in the outer border and `Search` sits in the input divider, avoiding the stacked top rules produced by fzf's `full:line` height-mode preset.

The 100-column boundary affects presentation only. Candidate generation, selected values, and actions do not change. Palette, layout, glyphs, and the secure generated-integration cache are separate: changing presentation refreshes exported options without regenerating `fzf --zsh`.

fzf options are composed in this order:

1. repository-managed structure and semantic palette;
2. captured inherited `FZF_DEFAULT_OPTS`;
3. `ZSH_FZF_EXTRA_OPTS` as the intentional final global override;
4. widget, completion, zoxide, or direct-picker arguments for their own workflow;
5. a final `--no-color` whenever `NO_COLOR` is set.

Inherited widget, general/path/directory completion, and `_ZO_FZF_OPTS` values are likewise captured once and appended to their managed presentation. Re-sourcing does not duplicate or recapture composed values. Because inherited and explicit layers are intentionally allowed to override managed fzf options, `ztheme current` reports whether an external option layer exists; it does not attempt to parse arbitrary user option strings.

### Theme discovery and session switching

`ztheme` inspects or switches the shared dashboard and finder palette without invoking an external program:

```zsh
ztheme list                 # list built-ins and mark active/default themes
ztheme current              # show theme, layout, glyph tier with a sample, depth, and option layers
ztheme show nord            # show semantic role values or terminal swatches
ztheme use nord             # switch dashboards and future fzf launches now
ztheme reset                # restore the terminal theme now
ztheme export nord          # print settings to copy into ~/.zshrc
```

`use` and `reset` affect only the current shell session and refresh future fzf and zoxide picker launches; a picker that is already open is unchanged. `use` switches the dashboard palette and preserves an explicit `ZSH_FZF_THEME` fzf-only override, so a deliberate finder choice survives unrelated dashboard switches. `reset` restores the default `terminal` theme and clears any such override so fzf inherits the UI theme again. Invalid names and invalid custom palettes return nonzero without changing the active theme or finder exports.

To persist a built-in choice, copy the output of `ztheme export <name>` above the `source init.zsh` line in the machine-local `~/.zshrc`. The command prints text only and never edits that file. Exporting a validated `custom` theme also prints its complete role array in stable order.

`dusage`, `bigfiles`, and `path` sanitize filesystem- or environment-controlled labels before rendering. Named controls such as newline, tab, escape, and bell become visible escapes; other C0, DEL, and C1 bytes use forms such as `\x7f`. Sanitization happens before measuring or truncating, keeps each value on one logical line, and preserves printable Unicode.

Rich output is for people, not parsers. Pipe a command or use its explicit plain option when output will be consumed by another program.

## Shell options and history

### Options set by init.zsh

| Option | State | Behavior |
|---|---|---|
| `AUTO_PUSHD` | on | Every directory change pushes the previous directory |
| `PUSHD_IGNORE_DUPS` | on | The directory stack omits duplicates |
| `PUSHD_SILENT` | on | Stack changes do not print automatically |
| `EXTENDED_GLOB` | on | Enables Zsh glob qualifiers and exclusions |
| `GLOB_DOTS` | off | Ordinary globs exclude leading-dot entries |
| `NUMERIC_GLOB_SORT` | on | `file2` sorts before `file10` |
| `CORRECT` | off | Command spell-correction prompts are disabled |
| `NO_BEEP` | on | The terminal bell is suppressed |
| `INTERACTIVE_COMMENTS` | on | `#` starts a comment on an interactive command line |

Hidden files require an explicit opt-in:

```zsh
print -rl -- *        # visible entries
print -rl -- *(D)     # visible and hidden entries
print -rl -- **/*(D)  # recursive, including hidden entries
```

Useful extended-glob examples:

```zsh
print -rl -- **/*.js
print -rl -- *(.m-1)
print -rl -- *(Lk+100)
```

### Directory stack

```zsh
cd /etc
cd /var/log
dirs -v
cd ~1
popd
```

Because `AUTO_PUSHD` is active, ordinary `cd` participates in this stack.

### History

| Setting | Value or state |
|---|---|
| `HISTFILE` | `~/.zsh_history` |
| `HISTSIZE` / `SAVEHIST` | `100000` |
| `APPEND_HISTORY` | on |
| `SHARE_HISTORY` | on |
| `HIST_IGNORE_ALL_DUPS` | on |
| `HIST_FIND_NO_DUPS` | on |
| `HIST_IGNORE_SPACE` | on |
| `HIST_REDUCE_BLANKS` | on |

History is shared across open shells. Commands beginning with a space are omitted, duplicate search results are suppressed, and redundant spaces are reduced before saving.

## Completion

The global layer is intentionally small:

- case-insensitive filename and command matching
- repeated slash cleanup
- process details for `kill <Tab>`

Command-specific completion covers the complete public command set:

```zsh
upkg      npkg       cgm        ztheme     zhelp      tips
extract   peek       mkcd       ff         ft         headers
dusage    bigfiles   fkill      fbr        croot      path
ports     myip       gitcount   fanprofile
```

`npkg` and `cgm` are registered only when their optional commands are available. The definitions understand subcommands, aliases, manager lists, archive suffixes, directories, counts, URLs, and signals. `npkg` completion may read an existing attribute cache, and `cgm` completion reads the name-only catalogue. Pressing Tab never runs Nix, refreshes a cache, contacts Secret Service, or retrieves a credential value.

If the parent `~/.zshrc` has not run `compinit`, command-specific completion is not registered. Heavy menu selection, grouped listings, and global coloured completion lists are intentionally omitted because they made completion noticeably slower.

## Command discovery

### zhelp

`zhelp` searches the repository's public functions and important aliases:

```zsh
zhelp                  # interactive palette, or a plain list
zhelp package          # search all catalogue fields
zhelp upkg             # exact command record
zhelp --all npkg       # include unavailable commands
zhelp --plain file     # stable text for a pipe or log
zhelp --help
```

The default result set hides commands that cannot run in the current shell. `--all` includes them and shows the missing requirement. A plain listing that hides entries says how many are unavailable and points at `zhelp --all`. Exact names show usage, an example, and live availability.

The catalogue also carries action entries for multi-step workflows: `upkg-plan` (preview upgrades), `npkg-remove` (remove a Nix package), and `cgm-env` (load credentials) resolve through their parent command, so they disappear together when the parent is unavailable.

In the palette, Enter places the selected example in the editable command buffer. It does not evaluate or execute the text. A CLI query only seeds the picker's search text; the whole eligible catalogue stays browsable, so clearing the query broadens results instead of trapping the selection in the pre-filtered rows. Piped or redirected search keeps the deterministic substring filter. Ctrl+P toggles the responsive usage preview, Ctrl+/ toggles preview word wrapping, and Escape closes the palette without changing the buffer. When fzf or a suitable terminal is unavailable, `zhelp` uses plain output and does not invoke a blocked fzf binary.

Sourcing `65-help.zsh` registers only a fixed repository-local loader. The catalogue, availability checks, and any subprocesses are deferred until `zhelp` is called; command completion loads catalogue data only when zhelp completion is invoked.

### tips

`tips` prints one short hint:

```text
tip: Run mkcd <dir> to create and enter a directory
```

It is on demand and installs no prompt or command-cycle hook. Its fixed repository-local catalogue is loaded on first use, so environment-dependent tips reflect the shell state at that first call. Run it again for another hint.

### zdoctor

`zdoctor` checks the setup and reports problems without changing anything:

```zsh
zdoctor              # local checks only
zdoctor --network    # also probe the myip and weather endpoints
zdoctor --secrets    # also check secret-tool (values are never retrieved)
zdoctor --help
```

It covers the fixed install location, unreadable modules, `compinit` readiness, required and optional tool availability and the fzf version (minimum 0.68.0), glyph resolution, and integration state for fzf, zoxide, `cgm`, `npkg`, and global aliases. Network endpoints and Secret Service stay untouched unless the matching flag is passed. The exit status is nonzero while any failure is present; warnings alone keep it zero.

## Aliases

### Navigation

| Alias | Expansion |
|---|---|
| `..` | `cd ..` |
| `...` | `cd ../..` |
| `....` | `cd ../../..` |
| `-` | `cd -` |

### File operations and viewing

| Alias | Behavior |
|---|---|
| `ls` | `lsd`, otherwise a guarded `ls` colour form |
| `ll` | Long listing including hidden entries and readable sizes |
| `la` | Listing including hidden entries |
| `lt` | Tree to depth 3; defined only with `lsd` or `tree` |
| `cat` | `bat --style=numbers --paging=never` when `bat` is present |
| `grep` | Adds `--color=auto` on Linux |
| `diff` | Adds `--color=auto` on Linux |

Under the zero-probe startup policy, the built-in `ls`, `ll`, and `la` fallbacks and the `grep` and `diff` aliases add automatic color only on Linux. On macOS and BSD they keep the corresponding plain command behavior rather than running capability probes while the shell starts. `lsd`, when installed, remains the preferred listing backend on every platform where it is available.

### Git extras

| Alias | Expansion |
|---|---|
| `glog` | `git log --oneline --graph --decorate -20` |
| `gpr` | `git pull --rebase` |
| `gun` | `git reset HEAD~1 --soft` |
| `gcount` | `gitcount` |

`gcount` deliberately replaces the conflicting Oh My Zsh alias when this layer is sourced afterward.

### Weather

`weather` runs a concise forecast request over HTTPS:

```zsh
weather
```

It is a lazy function using curl over HTTP/1.1 and does not implement a location argument. `weather --help` prints usage without making a request.

### Global aliases

Global aliases are opt-in because unquoted tokens such as `H`, `T`, `G`, and `L` expand anywhere in a command line. For example, with aliases enabled, an interactively parsed `echo H` behaves as `echo | head`; a filename or search term can become shell syntax. They stay undefined by default. Personal users who want the previous behavior preserve it with one setting before startup:

```zsh
export ZSH_GLOBAL_ALIASES=1  # in ~/.zshrc, before sourcing init.zsh
```

Quote a token to keep it literal (`echo 'H'` prints `H`). When disabled, `zhelp` lists these entries as unavailable rather than offering them:

| Alias | Expansion | Example |
|---|---|---|
| `G` | `| grep` | `git log G fix` |
| `L` | `| less` | `git diff L` |
| `W` | `| wc -l` | `ps aux W` |
| `H` | `| head` | `dmesg H` |
| `T` | `| tail` | `cat app.log T` |
| `NE` | `2>/dev/null` | `optional-command NE` |
| `NUL` | `>/dev/null 2>&1` | `noisy-command NUL` |

## Zoxide and fzf

### Zoxide

When `zoxide` is available at startup, its generated Zsh integration defines `z` and `zi`:

```zsh
z projects
z myapp src
z -l
zi projects
```

`z` performs ranked directory jumps. `zi` uses zoxide's interactive picker but is wrapped by the shared fzf version gate.

The shared directory theme is exported through zoxide's `_ZO_FZF_OPTS` interface before `zoxide init`, so `zi` and zoxide interactive completion match the generated fzf widgets without replacing zoxide's scoring or candidate generation.

Zoxide's generated shell integration is never evaluated directly. For a new zoxide executable, the configuration writes the output to a private temporary file, validates it with `zsh -fn`, and only then sources it. A validated, owner-only cache under `${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zoxide/` is keyed by the zoxide executable metadata and Zsh version, so warm shells avoid rerunning both generation and validation. If no absolute cache home is available or the cache cannot be created safely, startup uses a temporary validated file instead.

### fzf requirement and startup

Every fuzzy workflow requires stable `fzf` 0.68.0 or newer. At the first normal prompt for a new fzf executable, the configuration:

1. validates the version;
2. captures non-empty `fzf --zsh` output;
3. syntax-checks the generated Zsh;
4. writes a private integration cache when possible;
5. loads the validated integration and shared theme.

The cache is stored below `${XDG_CACHE_HOME:-$HOME/.cache}/zsh/fzf/` and is keyed by the fzf file identity, Zsh version, and cache schema. A matching cache is reused without launching fzf or a validation shell. Cache files and their directory must be regular, user-owned, non-symlink paths that are not group- or world-writable. A changed executable or PATH selection is validated before use. Removing the `zsh/fzf` directory below the active cache home forces a rebuild.

Missing, old, prerelease, malformed, or broken builds block only fuzzy workflows and print an actionable diagnostic. Non-interactive sourcing and `zsh -i -c ...` remain silent and do not initialize ZLE bindings.

Finder presentation is compiled separately from the trusted integration cache. Changing theme, layout, glyph mode, terminal width class, or `NO_COLOR` refreshes future launches without rerunning `fzf --version` or regenerating `fzf --zsh`. Existing `FZF_DEFAULT_OPTS`, widget options, completion options, and `_ZO_FZF_OPTS` are captured once and appended after managed presentation. `ZSH_FZF_EXTRA_OPTS` follows the inherited global layer; `--no-color` is always final when requested.

### Keybindings

| Binding | Action |
|---|---|
| Ctrl+T | Select a file or directory and insert its path at the cursor |
| Ctrl+R | Select a history entry and insert it for editing |
| Alt+C | Select a directory and change to it |

Ctrl+T previews directories with `lsd`, `tree`, or `ls`, and files with `bat` or the first 200 lines from `sed`. Ctrl+R previews the full command for the focused row. Every preview picker uses the same Ctrl+P toggle and Ctrl+/ wrap binding, so printable characters such as `?` stay available for searching.

Generated `**<Tab>` completion uses separate general, path, and directory labels through `FZF_COMPLETION_OPTS`, `FZF_COMPLETION_PATH_OPTS`, and `FZF_COMPLETION_DIR_OPTS`. The shared layer does not add a command-agnostic preview or change completion insertion semantics.

The shared gate also covers `fkill`, `fbr`, `zi`, the `zhelp` palette, and interactive `npkg` install, find, and remove paths. Every picker uses the same list/search/footer hierarchy and contextual ghost hint. At 100 columns and wider, textual previews sit beside the list; below 100 columns they move underneath. `fkill` and the Nix multi-select pickers show a live selected-item count in the footer. Git and Nix table pickers keep the visible identity column frozen, while `--accept-nth` returns undecorated branch, PID, example, or profile-target fields to the calling workflow; `fbr` also previews that undecorated branch rather than its optional `[WT]` display badge.

Picker-specific actions are unchanged: Escape and interruption remain non-destructive, `zhelp` only queues text, `fkill` confirms SIGKILL and multi-selections naming targets and signal before sending, `fbr` enters an existing worktree or checks out the branch, and Nix mutations run only after their picker returns selected targets. Under `NO_COLOR`, repository previews avoid forced colour while retaining labels, glyph-independent cues, and interaction.

## Function reference

### General helpers

| Command | Purpose |
|---|---|
| `extract [--keep] [--destination <dir>] <archive>` | Unpack a supported archive |
| `mkcd <dir>` | Create a directory and enter it |
| `ff [options] <pattern> [path]` | Find names case-insensitively |
| `ft [options] <pattern> [path]` | Search file contents |
| `peek <file>` | Preview with `bat` or `cat` |
| `headers <url>` | Follow redirects and print HTTP headers |
| `fanprofile` | Show the current Linux platform or ASUS fan profile |
| `dusage [path] [count]` | Rank immediate entries by disk usage |
| `bigfiles [path] [count]` | Rank files recursively |
| `ports` | Show listening sockets and owning processes |
| `myip` | Show the public IP over HTTPS |
| `path` | Print PATH entries |
| `croot` | Change to the current Git repository root |
| `gitcount` | Show non-merge commit counts by contributor |
| `fkill [--all] [signal]` | Select processes and send a signal |
| `fbr` | Select a branch; enter its worktree or check it out |
| `zdoctor [--network] [--secrets]` | Diagnose setup and integration status |

#### extract

Supported suffixes are `.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tar.zst`, `.zip`, `.rar`, `.7z`, `.gz`, `.bz2`, `.Z`, `.tar`, `.tbz2`, `.tgz`, and `.tzst`. Format-specific commands are checked when invoked, so a missing unpacker produces a direct error. Bare `.gz`, `.bz2`, and `.Z` files retain native in-place behavior by default, which usually removes the compressed input after success. Use `extract --keep file.gz` to preserve it, or `extract --destination existing-dir archive.tar.gz` to choose an existing destination. A destination implies keep-input for bare compressed files; those outputs are published only after successful decompression and refuse existing paths. Multi-file archives retain the unpacker's native overwrite and archive-path policies. Use `--` before a leading-dash filename.

#### ff and ft

`ff` prefers `fd`, then `fdfind`, then `find`. It matches a case-insensitive substring glob, includes hidden entries, and follows symlinks by default on every backend. `--no-hidden` and `--no-follow` disable those behaviors; `--hidden` and `--follow` make the defaults explicit. `--no-ignore` includes fd-ignored files. The find fallback has no ignore-file filtering and explains that difference when `--no-ignore` is requested.

`ft` prefers `rg`, whose defaults exclude hidden and ignored files and do not follow symlinks. Use `--hidden`, `--no-ignore`, `--follow`, and `--fixed-strings` (`-F`) explicitly. The recursive grep fallback skips binary files, already searches hidden/ignored files, maps `--follow` to `grep -R`, and supports fixed strings. It explains redundant hidden/ignore flags. Backend defaults differ; use explicit flags for broad searches.

```zsh
ff --no-ignore config .
ft --hidden --no-ignore --fixed-strings 'a.b' src
extract --keep -- file.gz
```

Text search uses automatic color for clean redirected output. General helpers accept `-h`/`--help` before work; usage errors return 1. Use `--` to end option parsing in `extract`, `ff`, and `ft`.

`headers`, `myip`, and `weather` use 5-second connection and 15-second overall timeout budgets. Override them with positive integer `ZSH_HTTP_CONNECT_TIMEOUT` and `ZSH_HTTP_MAX_TIME` settings. Zero is rejected. Curl failures preserve the exit status and add a command-specific diagnostic.

#### fanprofile

`fanprofile` reads the standard Linux `/sys/firmware/acpi/platform_profile` interface when available. On older ASUS/TUF systems it falls back to `fan_boost_mode`:

| Raw value | Profile |
|---|---|
| `0` | `normal` |
| `1` | `overboost` |
| `2` | `silent` |

The command reports state only; it does not change the profile.

#### dusage, bigfiles, and path

`dusage` includes hidden immediate children and defaults to 20 rows. `bigfiles` searches recursively and also defaults to 20. Both preserve readable results when another entry or subtree cannot be measured, but they report `Incomplete scan (<tool> exit <code>); results are partial` on stderr, mark the rich dashboard with a warning and `(incomplete scan)` footer, and return nonzero. A clean scan still returns 0.

`path` preserves empty PATH components. In command lookup, an empty component means the current directory; rich output labels it `.`, while plain output preserves an empty line.

All three commands apply the safe-text contract described in [Terminal output modes](#terminal-output-modes).

#### ports and myip

`ports` uses `ss -tulnp`. Process details can be limited by system permissions. `myip` queries `https://ifconfig.me/ip`. Both use rich dashboards only in capable terminals.

#### fkill and fbr

`fkill` requires a terminal and defaults to `SIGTERM` (`15`), allowing graceful shutdown. Numeric and named forms are normalized, so `15`, `-15`, `TERM`, and `SIGTERM` all select the same signal. Invalid signals fail before the picker opens. The list shows PID, owner, elapsed time, and command with a preview of full details and working directory; it covers the current user's processes unless `--all` is given. A single SIGTERM sends immediately, while SIGKILL or a multi-selection names the targets and signal for confirmation first. Each kill reports its own outcome, and no privilege escalation is attempted. Pass `9` only when force is necessary:

```zsh
fkill
fkill SIGTERM
fkill 9
fkill --all 15
```

`fbr` lists local and remote branches by recent commit and previews the log. Its branch and relative-date display columns use fixed terminal-cell widths, so subjects begin in one stable column even when branch names differ; wide CJK characters count as two cells and Unicode nonspacing and format marks as zero. Committed Unicode 16.0 intervals load on first non-ASCII measurement and use pure-Zsh binary search. Emoji grapheme shaping and ambiguous-width characters remain terminal-dependent. Long values are visibly truncated without changing the hidden raw branch returned by Enter. A local branch registered to another Git worktree has a prominent `[WT]` badge immediately before its branch name and includes the worktree path later in the row; the current checkout is intentionally unmarked. The badge is coloured in capable terminals and remains plain text otherwise. Selecting a marked branch changes the current shell to its worktree path. A remote selection enters that worktree only when the local branch tracks the selected remote. Other selections keep the checkout behavior: a remote branch creates a tracking branch when no local branch with the same short name exists. When a same-named local branch exists but does not track the selected remote, `fbr` refuses to switch and explains the three safe moves: enter the local branch, track the remote under a new name, or inspect the remote detached. The picker footer reads `Enter worktree/checkout` to reflect both outcomes.

## Credential manager: cgm

`cgm` is defined only when `secret-tool` is present during startup. It stores single-line credential values in the current user's Linux Secret Service collection and exports them only on request.

### Commands

| Command | Behavior |
|---|---|
| `cgm set <name>` | Prompt invisibly and store or replace one value |
| `cgm list` | List saved names without retrieving values |
| `cgm status` | Show saved names and whether each is exported in this shell |
| `cgm check` | Ping Secret Service explicitly, without retrieving values |
| `cgm env <name ...>` | Load selected values into this shell |
| `cgm env --all` | Load every catalogued value into this shell |
| `cgm unset <name ...>` | Remove variables from this shell only |
| `cgm delete <name ...>` | Delete stored values and unset local copies |
| `cgm help` | Show concise command help |

Names must match `[A-Z_][A-Z0-9_]*`. CGM rejects Zsh special, read-only, and non-scalar parameters, so values such as `PATH` cannot be replaced accidentally.

### Storage and secrecy

- Values are sent to `secret-tool` through its hidden input path, never as command arguments.
- No plaintext fallback exists.
- Sourcing the module does not contact Secret Service, unlock a keyring, or read the catalogue.
- `cgm list`, completion, status output, and help never retrieve or display values.
- The name-only catalogue lives under `${XDG_DATA_HOME:-$HOME/.local/share}/cgm/entries/`; directories are created under `umask 077`, remain mode `0700`, and empty markers are `0600`. `XDG_DATA_HOME` is used only when absolute; a relative value falls back to an absolute `$HOME/.local/share`, and the operation fails when neither base is safe.
- Secret loading disables inherited Zsh xtrace locally and restores the caller's state afterward.
- `cgm env --all` retrieves and validates every value before exporting any, so one failure leaves the environment unchanged.

“Saved” means a name-only marker exists; it does not prove the backend item still exists. `cgm status` inspects parameter metadata only: “loaded” means an exported scalar is present, including a value set outside CGM; it does not compare that value with storage. `cgm check` uses a bounded D-Bus peer ping through `gdbus`. A successful ping confirms the service is reachable, not that a collection is unlocked or each saved credential exists. Neither command retrieves values.

### Shell scope

Loaded variables affect the current shell and processes started from it afterward. They cannot change another terminal, an already-running process, or a parent shell. For that reason, `cgm env`, `cgm unset`, and `cgm delete` reject pipelines, command substitutions, and subshells.

Deleting a credential cannot recall copies already inherited by child processes. If a stored item is deleted but its current-shell variable has become unsafe to unset, `cgm delete` reports the retained variable and returns nonzero.

## Package manager: upkg

`upkg` detects supported managers each time it runs and provides one interface for read-only checks, search, upgrades, and conservative cleanup.

### Detection

The active order is:

1. one distro backend: `paru`, otherwise `pacman`, otherwise `apt`, otherwise `dnf`;
2. `brew`;
3. `flatpak`;
4. Nix through `npkg`;
5. global `npm`.

When both `paru` and `pacman` exist, `paru` is active and `pacman` remains available through `--only pacman`.

### Commands

| Command | Behavior |
|---|---|
| `upkg` | Read-only outdated check |
| `upkg outdated` / `check` / `list` | Same read-only check |
| `upkg search <query>` | Search selected managers |
| `upkg plan` | Preview available upgrades |
| `upkg upgrade` / `up` / `update` | Run selected upgrades |
| `upkg clean` | Remove manager-classified unused or stale data |
| `upkg managers` | Show active managers and alternates |
| `upkg help` | Show command help |

### Flags

| Flag | Behavior |
|---|---|
| `--only <ids>` / `--only=<ids>` | Run only comma-separated manager IDs |
| `--skip <ids>` / `--skip=<ids>` | Exclude comma-separated manager IDs |
| `--sudo` | Authorize privileged distro upgrade or cleanup paths |
| `--dry-run` | Preview upgrades or cleanup |

Supported IDs are `apt`, `dnf`, `pacman`, `paru`, `brew`, `flatpak`, `nix`, and `npm`. `--only` preserves the order supplied by the user.

### Check and upgrade backends

| Manager | Outdated check | Upgrade |
|---|---|---|
| `apt` | `apt list --upgradable` | `apt update`, then `apt full-upgrade` |
| `dnf` | `dnf check-update` | `dnf upgrade --refresh` |
| `pacman` | `pacman -Qu` | `pacman -Syu` |
| `paru` | repo check plus `paru -Qua` | `paru -Syu` |
| `brew` | `brew outdated` | `brew upgrade` |
| `flatpak` | `flatpak remote-ls --updates` | `flatpak update` |
| `nix` | `npkg outdated` | `npkg upgrade` |
| `npm` | `npm outdated -g --depth=0` | `npm update -g` |

`apt`, `dnf`, and `pacman` upgrade paths require root or explicit `--sudo`. Paru also requires the explicit flag, but runs unprefixed so Paru controls privilege escalation. Homebrew and npm always remain unprefixed; an unwritable npm global prefix blocks the upgrade with a user-space setup hint.

The Nix outdated and plan paths require `jq`; Nix upgrade does not. Nix cleanup depends on `nix-collect-garbage`, not `jq`.

`upkg` never auto-confirms native prompts. It does not inject `-y`, `--assumeyes`, `--noconfirm`, or `sudo` without the explicit authorization flag.

### Search behavior

Search accepts multiple words and passes them as separate query arguments:

```zsh
upkg search ripgrep
upkg search ripgrep --only=nix
upkg search ripgrep viewer --only=brew,npm
```

Results are normalized into one table with manager, package, available version, and a cheap native description when available. A no-match result is summarized once. Backend failures name the affected managers, and other managers continue.

Nix search works directly in a fresh shell when `nix` is installed; running `npkg` first is unnecessary.

Homebrew formulae and casks are queried separately. Broad searches cap follow-up metadata calls at 50 formulae and 50 casks; refine the query when the cap warning appears.

### Cleanup policy

`upkg clean` is mutating. Use `upkg clean --dry-run` first.

| Manager | Unused phase | Cache or store phase |
|---|---|---|
| `apt` | `apt autoremove` | `apt autoclean` |
| `dnf` | `dnf autoremove` | `dnf clean all` |
| `pacman` | remove the non-empty `pacman -Qtdq` orphan array with `pacman -Rs --` | `pacman -Sc` |
| `paru` | `paru -c` | `paru -Sc` |
| `brew` | `brew autoremove` | `brew cleanup` |
| `flatpak` | `flatpak uninstall --unused --user`, then `--system` | handled by the uninstall pruning |
| `nix` | none | `nix-collect-garbage` |
| `npm` | remove explicit keys from `npm cache npx ls` | `npm cache verify` |

Cleanup uses manager-owned commands. It does not directly delete cache directories, application data, project files, lockfiles, virtual environments, build output, user configuration, or Nix profile generations. It does not claim a portable reclaimed-byte total.

Dry-run uses native probes where safe. Steps without a safe unprivileged simulation are printed as `would run` and are not invoked. A preview never calls `sudo` or requires `--sudo`.

Nix cleanup removes unreachable store objects without generation-deletion flags, preserving rollback history. Flatpak cleanup does not pass `--delete-data`. npm cleanup never uses the keyless, forced whole-cache removal form; old npm releases without the npx cache subcommands still run `npm cache verify` and report a partial result.

Flatpak updates and system cleanup may request authorization through polkit. User and system cleanup are attempted as separate phases.

### Results and exit status

Multi-manager runs continue after a backend fails:

| State | Meaning |
|---|---|
| `up to date` | A complete outdated check found no changes |
| `updates available` | A complete check found changes |
| `cleaned` | Every requested cleanup phase succeeded |
| `planned` | A cleanup preview completed successfully |
| `partial` | Some phases succeeded and others failed |
| `failed` | Required work or a preview probe failed |
| `blocked` | Authorization or a required capability was missing |
| `skipped` | A filter intentionally omitted the manager |

A partial, failed, or blocked selected backend makes the aggregate command return nonzero.

Distribution outdated checks use existing local metadata; `upkg` does not refresh it automatically. On Arch-family systems, an empty status-1 repo or AUR check is treated as no updates. A failed Paru repo check can still show AUR results but leaves the backend failed.

### Examples

```zsh
upkg
upkg search ripgrep
upkg search ripgrep --only=nix
upkg managers
upkg managers --only=npm,flatpak
upkg plan --only=brew,npm
upkg upgrade --sudo --only=apt
upkg clean --dry-run
upkg clean --only=brew,npm
upkg clean --sudo --only=apt
```

## Nix profile manager: npkg

`npkg` is defined only when `nix` is available. It wraps the current `nix profile` with shorter commands and optional pickers while enabling the required `nix-command flakes` features.

### Commands

| Command | Behavior |
|---|---|
| `npkg add <pkg ...>` / `install` / `i` | Add packages |
| `npkg add` | Open the install picker |
| `npkg find [query]` / `pick` / `fzf` | Open a seeded install picker |
| `npkg search <query>` / `s` | Plain nixpkgs search |
| `npkg list` / `ls` | List the current profile |
| `npkg remove <pkg ...>` / `rm` / `uninstall` / `delete` | Remove profile elements |
| `npkg remove` | Open the removal picker |
| `npkg outdated` / `check` / `diff` | Compare installed and evaluated outputs |
| `npkg refresh` | Rebuild the attribute-name cache |
| `npkg upgrade [pkg ...]` / `up` / `update` | Upgrade all or selected elements |
| `npkg help` | Show help |

Bare install names become `nixpkgs#<name>`. Flake references, paths, and arguments beginning with `-` pass through without that expansion. Use `nix` directly for advanced flags not represented by the wrapper.

### Picker cache and dependencies

`npkg refresh` and `npkg outdated` require `jq`. Interactive add, find, and remove also require a real terminal and supported fzf.

The attribute cache lives under `${XDG_CACHE_HOME:-$HOME/.cache}/npkg/` and refreshes on install or find picker use after 24 hours. `XDG_CACHE_HOME` is used only when absolute; a relative value falls back to an absolute `$HOME/.cache`. Refreshes build per-call temporary files in the cache directory and publish a complete index atomically, so concurrent or interrupted refreshes do not expose partial data. Building the cache evaluates nixpkgs and can take time or require network access. Tab completion may read an existing cache but never creates or refreshes it. Picker previews evaluate package metadata to show description, version, and homepage; they move below the list when the terminal is narrower than 100 columns. Tab marks multiple packages, and the footer updates the selected count before Enter confirms the add or remove operation.

### Outdated semantics

`npkg outdated` compares the complete installed store-path set for each active nixpkgs profile element with the output set selected by the currently evaluated installable:

| State | Meaning |
|---|---|
| `current` | Installed and evaluated output sets match |
| `change available` | The sets differ |
| `unknown` | Profile data or evaluation is incomplete |

A change is not necessarily an upgrade. It can be a downgrade, rebuild, changed input, output-selection change, or packaging change. Display versions are informational and never determine state.

A complete report containing current or changed rows returns zero. Any unknown row produces a partial summary and nonzero status; only a complete all-current report may say `Everything is up to date.` A profile with no active nixpkgs elements is a complete zero-count result.

Ctrl+C stops and reaps only the command's recorded evaluation workers, removes its temporary files, preserves unrelated background jobs, and returns `130`. The `upkg` Nix bridge consumes the stable internal `current`, `changed`, or `partial` state rather than matching display text.

## Gotchas and safety boundaries

These are the cross-cutting rules most likely to surprise a new user:

1. **The install path is fixed.** `init.zsh` loads `$HOME/.config/zsh/*.zsh`. A clone elsewhere needs a symlink or a deliberate code change. Run `zdoctor` to confirm the location and catch silently skipped modules.
2. **Source order matters.** Source this layer after frameworks when its aliases should win. `~/.zshrc` itself is not versioned here.
3. **File operations keep native semantics.** `mkdir`, `cp`, `mv`, and `rm` are not redefined. Add flags deliberately and keep real backups; shell prompts are not a backup strategy.
4. **Interactive flags are situational.** If you opt into `-i`, remember that later flags such as `-f` can override it. Review the final command line before destructive operations.
5. **Ordinary globs exclude dotfiles.** Use `*(D)` only when hidden entries are intentional. In contrast, `ff` and `dusage` explicitly include hidden entries by design.
6. **Leading-space history is convenience, not secret storage.** `HIST_IGNORE_SPACE` reduces accidental persistence but does not protect process arguments, logs, terminal capture, or already-shared history.
7. **Global aliases are opt-in and expand anywhere.** They stay undefined unless `ZSH_GLOBAL_ALIASES=1` is exported before startup. Once enabled, unquoted tokens such as `G` or `NUL` can change a command far from its first word. Quote literal occurrences.
8. **An empty PATH component means the current directory.** `path` preserves and exposes it because silently normalizing PATH would change command lookup.
9. **Completion needs compinit.** Without `compdef`, command-specific completion quietly does nothing. Run `zdoctor` to confirm readiness.
10. **fzf is all-or-nothing at 0.68.0+.** An unsupported build blocks fuzzy workflows instead of enabling a reduced theme or partial bindings. Plain `zhelp` remains available.
11. **Theme choice is machine-local.** `ztheme use` changes only the current shell, and `ztheme export` prints settings without editing `.zshrc`. This repository does not theme the prompt, terminal, tmux, editor, `bat`, Git, or `LS_COLORS`.
12. **Ctrl+R does not execute the selection.** It inserts history into the command buffer for review and editing.
13. **`fkill` defaults to SIGTERM.** `fkill 9` is a force-kill and should be the exception.
14. **CGM is startup-optional.** Installing `secret-tool` mid-session does not define `cgm` until the module is sourced again or the shell restarts.
15. **CGM changes only the current shell.** Run `env`, `unset`, and `delete` directly, not through a pipe, command substitution, or subshell. Deletion cannot revoke values inherited by existing processes.
16. **`upkg` is not entirely read-only.** The default, `outdated`, `search`, and `plan` are read-only; `upgrade` and `clean` mutate manager state. Preview cleanup with `clean --dry-run`.
17. **`--sudo` authorizes but does not auto-confirm.** Native package-manager and polkit prompts remain authoritative.
18. **Outdated data can be stale.** Distro checks use local metadata, and `npkg` reports output identity—not version ordering.
19. **Partial package results fail.** `upkg` continues other managers but returns nonzero for partial, failed, or blocked selected backends. `npkg` returns nonzero when any row is unknown.
20. **Rich output is presentation.** Use a pipe, redirect, `NO_COLOR`, or an explicit plain option for stable machine-readable text.
21. **The target platform is GNU/Linux.** `ss`, GNU flags, sysfs profile paths, and several `find`/`du` flows are Linux-oriented.
22. **Network helpers contact external services.** `weather` requests `wttr.in`, `myip` requests `ifconfig.me`, and `headers` contacts the URL supplied by the user.
23. **Automation must load the layer explicitly.** Aliases and functions are interactive shell features; scripts should call real binaries or source `init.zsh` inside Zsh.
24. **Helper failures stay on stderr.** Successful data remains pipeable on stdout; usage errors, missing dependencies, and invalid paths do not contaminate command substitutions.
25. **Leading-dash inputs are data.** File helpers normalize archive paths, directory helpers terminate options, and package search backends separate wrapper flags from query terms.

## Maintenance and verification

### Documentation ownership

Keep each surface at one level:

| Surface | Owns |
|---|---|
| `README.md` | Purpose, five-minute setup, requirements summary, and links |
| `GUIDE.md` | Full behavior, examples, dependencies, safety boundaries, and gotchas |
| `lib/help-catalogue.zsh` | One-line command discovery, usage, example, and availability |
| `lib/tips-catalogue.zsh` | Short, actionable reminders for user-facing actions only |
| `docs/specs/` | Historical decisions and acceptance criteria |

When user-facing behavior changes, update every affected surface without copying long explanations between them.

### Editing rules

- Startup-time dependency guards use `(( $+commands[tool] ))`.
- Guards inside functions use `command -v ... >/dev/null 2>&1` so PATH changes and test stubs are visible.
- Keep external integrations guarded and preserve fallbacks.
- Keep `50-completion.zsh` lightweight and `80-tips.zsh` hook-free.
- Never add a plaintext CGM fallback, value-retrieving completion, or `eval`-based secret export.
- Treat aliases in `20-aliases.zsh` as high-impact changes.

Nix attribute completion reuses parsed names in the current session while each cache file’s device, inode, size, and modification time match. Replacing, adding, or removing cache files is reflected on the next completion. It never refreshes the index over the network.

### Required checks

Run the repository-owned ordered sequence:

```sh
zsh scripts/run-tests.zsh
```

The runner owns the syntax checks, regression suites, and fixed-install-path smoke test used by CI. Maintainers can regenerate width intervals with `python3 scripts/generate-width-data.py`; review the recorded Unicode version when doing so. A separate CI job runs `python3 scripts/test-fzf-pty.py` against real fzf 0.68.0 and 0.74.3, covering 50/100-column terminals, Unicode/ASCII, `NO_COLOR`, preview toggling, multi-selection, and cancellation. Run that command locally with Python 3 and supported fzf installed; set `FZF_BIN` to test another binary. These checks use fixture rows and perform no package mutations. `skills-lock.json` records maintainer skill provenance and is not a runtime dependency or package-manager lockfile.

The environment check is optional because it reflects the current machine rather than repository correctness:

```sh
$HOME/.config/zsh/scripts/check-deps.sh
```

For a full stable-release manual pass, use the ignored `qa-features.csv` checklist described in [`AGENTS.md`](./AGENTS.md).
