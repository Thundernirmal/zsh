#!/usr/bin/env zsh
# Cross-backend regressions from the package/system command audit.
emulate -L zsh
setopt NO_UNSET
repo_dir=${0:A:h:h}
scratch=$(mktemp -d) || exit 1
original_path=$PATH
trap 'PATH=$original_path; command rm -rf -- "$scratch"' EXIT
source "$repo_dir/60-functions.zsh"
upkg help >/dev/null || exit 1
_ui_plain_mode() { return 0; }
assert() {
  if ! "$@"; then
    print -u2 -r -- "not ok: $*"
    exit 1
  fi
}
write_fake() {
  print -r -- '#!/bin/sh' > "$scratch/$1"
  print -r -- "$2" >> "$scratch/$1"
  command chmod +x "$scratch/$1"
}
# Detection override and backends stay in subshells so later tests remain isolated.
(
  _upkg_detect_managers() {
    typeset -ga _UPKG_ACTIVE_MANAGERS=(brew flatpak)
    typeset -ga _UPKG_ALTERNATE_MANAGERS=()
  }
  _upkg_run_upgrade_brew() { print -r -- called >> "$scratch/calls"; }
  _upkg_run_upgrade_flatpak() { print -r -- called >> "$scratch/calls"; }
  for flag in --only --skip; do
    for empty in '' '   ' ',' ',brew' 'brew,' 'brew,,flatpak' 'brew, ,flatpak'; do
      upkg upgrade "$flag" "$empty" >/dev/null 2>&1
      assert test "$?" -eq 1
      upkg upgrade "$flag=$empty" >/dev/null 2>&1
      assert test "$?" -eq 1
    done
  done
  assert test ! -e "$scratch/calls"
) || exit 1
print 'ok: empty lists and empty manager IDs never invoke upgrade backends'
(
  _upkg_detect_managers() {
    typeset -ga _UPKG_ACTIVE_MANAGERS=(brew flatpak)
    typeset -ga _UPKG_ALTERNATE_MANAGERS=()
  }
  export AUDIT_LOG="$scratch/cancel-calls"
  write_fake brew 'printf "%s\n" "brew $*" >> "$AUDIT_LOG"; exit "$AUDIT_RC"'
  write_fake flatpak 'printf "%s\n" "flatpak $*" >> "$AUDIT_LOG"; exit 0'
  PATH="$scratch:$original_path"
  for code in 129 130 143; do
    export AUDIT_RC=$code
    for operation in upgrade clean; do
      : > "$AUDIT_LOG"
      upkg "$operation" --only brew,flatpak >/dev/null 2>&1
      assert test "$?" -eq "$code"
      assert test "${_UPKG_SUMMARY_STATE[brew]}" = cancelled
      assert test "${#_UPKG_SUMMARY_ORDER}" -eq 1
      calls=$(<"$AUDIT_LOG")
      call_lines=( "${(@f)calls}" )
      assert test "${#call_lines}" -eq 1
    done
  done
  export AUDIT_RC=1
  upkg upgrade --only brew,flatpak >/dev/null 2>&1
  assert test "$?" -eq 1
  assert test "${#_UPKG_SUMMARY_ORDER}" -eq 2
) || exit 1
print 'ok: cancellation stops managers and cleanup phases while ordinary errors continue'
(
  _zsh_functions_load_domain nix || exit 1
  write_fake jq 'exit 0'
  PATH="$scratch:$original_path"
  _zsh_run_owned_query() { "$@"; }
  _npkg_nix() { return "$AUDIT_RC"; }
  _upkg_detect_managers() {
    typeset -ga _UPKG_ACTIVE_MANAGERS=(nix brew)
    typeset -ga _UPKG_ALTERNATE_MANAGERS=()
  }
  for code in 129 130 143; do
    export AUDIT_RC=$code
    upkg outdated --only nix,brew >/dev/null 2>&1
    assert test "$?" -eq "$code"
    assert test "${#_UPKG_SUMMARY_ORDER}" -eq 1
    assert test "${_UPKG_SUMMARY_STATE[nix]}" = cancelled
  done
) || exit 1
print 'ok: cancelled Nix profile queries stop later package managers'
if command -v jq >/dev/null 2>&1; then
  (
    _zsh_functions_load_domain nix || exit 1
    _zsh_run_owned_query() { "$@"; }
    _npkg_nix() {
      print -r -- '{"elements":{"pkg":{"active":true,"originalUrl":"nixpkgs","url":"github:NixOS/nixpkgs/rev","attrPath":"packages.test.pkg","storePaths":["/nix/store/pkg"]}}}'
    }
    _npkg_eval_installable_record() { return "$AUDIT_RC"; }
    _upkg_detect_managers() {
      typeset -ga _UPKG_ACTIVE_MANAGERS=(nix brew)
      typeset -ga _UPKG_ALTERNATE_MANAGERS=()
    }
    for code in 129 130 143; do
      AUDIT_RC=$code
      upkg outdated --only nix,brew >/dev/null 2>&1
      assert test "$?" -eq "$code"
      assert test "${#_UPKG_SUMMARY_ORDER}" -eq 1
    done
  ) || exit 1
  print 'ok: cancelled Nix evaluation workers stop later package managers'
fi
(
  write_fake dnf '
case "$*" in
  "--color=never list --available *ripgrep*")
    printf "%s\n" "Updating and loading repositories:" "Repositories loaded." "Available packages" "ripgrep.x86_64 15.2.0-1.fc44 updates"
    printf "%s\n" "metadata warning" >&2 ;;
  "--color=never list --available *empty4*") printf "%s\n" "Error: No matching Packages to list" >&2; exit 1 ;;
  "-q --color=never list --available *empty5*") exit 1 ;;
  "--color=never list --available *empty5*") printf "%s\n" "No matches found." >&2; exit 1 ;;
  *) printf "%s\n" "repository failure" >&2; exit 1 ;;
esac'
  PATH="$scratch:$original_path"
  _UPKG_SEARCH_ROWS=()
  _upkg_run_search_dnf ripgrep >"$scratch/dnf-out" 2>"$scratch/dnf-err"
  assert test "$?" -eq 0
  assert test "${#_UPKG_SEARCH_ROWS}" -eq 1
  assert test "${_UPKG_SEARCH_ROWS[1]}" = $'dnf\tripgrep.x86_64\t15.2.0-1.fc44\t'
  assert test "$(<"$scratch/dnf-err")" = 'metadata warning'
  for query in empty4 empty5; do
    _upkg_run_search_dnf "$query" >/dev/null 2>&1
    assert test "$?" -eq 0
    assert test "$_UPKG_LAST_STATE" = 'no matches'
  done
  _upkg_run_search_dnf broken >/dev/null 2>&1
  assert test "$?" -eq 1
  assert test "$_UPKG_LAST_STATE" = failed
) || exit 1
print 'ok: DNF4/5 search distinguishes packages, diagnostics, no matches, and failures'
if command -v jq >/dev/null 2>&1; then
  (
    _zsh_functions_load_domain nix || exit 1
    _zsh_run_owned_query() { "$@"; }
    _npkg_nix() { print -r -- "$AUDIT_PROFILE"; }
    _npkg_eval_installable_record() { print -r -- '{"paths":["/nix/store/pkg"],"version":"1"}'; }
    inactive='{"active":false,"originalUrl":"nixpkgs","attrPath":"packages.test.inactive","storePaths":[]}'
    active='{"originalUrl":"nixpkgs","url":"github:NixOS/nixpkgs/rev","attrPath":"packages.test.pkg","storePaths":["/nix/store/pkg"]}'
    for AUDIT_PROFILE in "{\"elements\":{\"inactive\":$inactive,\"active\":$active}}" "{\"elements\":[$inactive,$active]}"; do
      npkg outdated >/dev/null 2>&1
      assert test "$?" -eq 0
      assert test "$_NPKG_OUTDATED_TOTAL" -eq 1
      assert test "$_NPKG_OUTDATED_STATE" = current
      # Capture actual picker candidates, cancel before any removal operation.
      _npkg_require_picker() { return 0; }
      _fzf_picker_multi_args() { REPLY=''; reply=(); }
      _fzf_picker_context_args() { reply=(); }
      _fzf_picker_preview_args() { reply=(); }
      export AUDIT_CANDIDATES="$scratch/nix-candidates"
      write_fake fzf 'cat > "$AUDIT_CANDIDATES"; exit 1'
      PATH="$scratch:$original_path"
      command rm -f -- "$scratch/jq"
      npkg remove >/dev/null 2>&1
      candidate_text=$(<"$AUDIT_CANDIDATES")
      assert test "${candidate_text#*inactive}" = "$candidate_text"
      assert test -n "$candidate_text"
    done
  ) || exit 1
  print 'ok: inactive object/array Nix elements are excluded from checks and removal'
fi
(
  write_fake checkupdates 'printf "%s\n" "query warning" >&2; exit "$AUDIT_RC"'
  for audit_manager in brew flatpak pacman paru; do
    write_fake "$audit_manager" 'printf "%s\n" "query warning" >&2; exit "${AUDIT_RC:-0}"'
  done
  PATH="$scratch:$original_path"
  for audit_manager in brew flatpak pacman paru; do
    _upkg_detect_managers() {
      typeset -ga _UPKG_ACTIVE_MANAGERS=("$audit_manager")
      typeset -ga _UPKG_ALTERNATE_MANAGERS=()
    }
    AUDIT_RC=0; export AUDIT_RC
    upkg outdated --only "$audit_manager" >"$scratch/warning-out" 2>"$scratch/warning-err"
    assert test "$?" -eq 0
    assert test "${_UPKG_SUMMARY_STATE[$audit_manager]}" = 'up to date'
    assert test -s "$scratch/warning-err"
    output=$(<"$scratch/warning-out")
    assert test "${output#*query warning}" = "$output"
    if [[ $audit_manager == pacman || $audit_manager == paru ]]; then
      AUDIT_RC=1
      upkg outdated --only "$audit_manager" >/dev/null 2>&1
      assert test "$?" -eq 1
    fi
  done
) || exit 1
print 'ok: warning-only update checks stay current and Arch errors remain failures'
(
  _upkg_detect_managers() {
    typeset -ga _UPKG_ACTIVE_MANAGERS=(brew)
    typeset -ga _UPKG_ALTERNATE_MANAGERS=()
  }
  _upkg_run_outdated_brew() { _upkg_set_last_result 'up to date' ''; }
  _upkg_run_upgrade_brew() { exit 99; }
  for args in 'plan' 'upgrade --dry-run'; do
    output=$(upkg ${=args} --only brew)
    assert test "$?" -eq 0
    assert test "${output#*Update inventory:}" != "$output"
  done
) || exit 1
print 'ok: plan and upgrade dry-run identify inventory scope without invoking upgrades'
(
  export AUDIT_LOG="$scratch/apt-calls"
  write_fake apt '
printf "%s\n" "$*" >> "$AUDIT_LOG"
case "$*" in
  "-o APT::Update::Error-Mode=any update") exit "$AUDIT_RC" ;;
  "full-upgrade") exit 0 ;;
  *) exit 99 ;;
esac'
  write_fake sudo 'exec "$@"'
  PATH="$scratch:$original_path"
  _upkg_detect_managers() {
    typeset -ga _UPKG_ACTIVE_MANAGERS=(apt)
    typeset -ga _UPKG_ALTERNATE_MANAGERS=()
  }
  for root in 0 1; do
    _upkg_is_root() { (( root )); }
    export AUDIT_RC=100
    : > "$AUDIT_LOG"
    upkg upgrade --sudo --only apt >/dev/null 2>&1
    assert test "$?" -eq 1
    calls=$(<"$AUDIT_LOG")
    assert test "$calls" = '-o APT::Update::Error-Mode=any update'
    AUDIT_RC=0
    upkg upgrade --sudo --only apt >/dev/null 2>&1
    assert test "$?" -eq 0
    calls=$(<"$AUDIT_LOG")
    assert test "${calls#*full-upgrade}" != "$calls"
  done
) || exit 1
print 'ok: root and sudo APT upgrades require a successful strict refresh'
if command -v jq >/dev/null 2>&1; then
  (
    _zsh_functions_load_domain nix || exit 1
    _zsh_run_owned_query() { "$@"; }
    _npkg_nix() { print -r -- "$AUDIT_PROFILE"; }
    _npkg_eval_installable_record() { print -r -- '{"paths":["/nix/store/current"],"version":"1"}'; }
    AUDIT_PROFILE='{"elements":{"custom":{"active":true,"originalUrl":"github:example/custom","url":"github:example/custom/rev","attrPath":"packages.test.custom","storePaths":["/nix/store/old"]},"unsupported":{"active":true,"storePaths":["/nix/store/local"]}}}'
    npkg outdated >/dev/null 2>&1
    assert test "$?" -eq 1
    assert test "$_NPKG_OUTDATED_TOTAL" -eq 2
    assert test "$_NPKG_OUTDATED_CHANGED" -eq 1
    assert test "$_NPKG_OUTDATED_UNKNOWN" -eq 1
    AUDIT_PROFILE='{"elements":{"custom":{"active":true,"originalUrl":"github:example/custom","url":"github:example/custom/rev","attrPath":"packages.test.custom","storePaths":["/nix/store/current"]}}}'
    npkg outdated >/dev/null 2>&1
    assert test "$?" -eq 0
    assert test "$_NPKG_OUTDATED_TOTAL" -eq 1
    assert test "$_NPKG_OUTDATED_STATE" = current
  ) || exit 1
  print 'ok: Nix inventories include custom flakes and expose unsupported active entries'
fi

(
  detection_dir="$scratch/detection"
  command mkdir "$detection_dir"
  for tool in paru pacman apt dnf; do
    print -r -- '#!/bin/sh' > "$detection_dir/$tool"
    command chmod +x "$detection_dir/$tool"
  done
  PATH=$detection_dir
  _upkg_detect_managers
  assert test "${(j:,:)_UPKG_ACTIVE_MANAGERS}" = paru
  assert test "${(j:,:)_UPKG_ALTERNATE_MANAGERS}" = pacman,apt,dnf
  _upkg_apply_filters dnf '' || exit 1
  assert test "${(j:,:)_UPKG_SELECTED_MANAGERS}" = dnf
  PATH=$original_path
  command rm "$detection_dir/paru" "$detection_dir/pacman"
  PATH=$detection_dir
  _upkg_detect_managers
  assert test "${(j:,:)_UPKG_ACTIVE_MANAGERS}" = apt
  assert test "${(j:,:)_UPKG_ALTERNATE_MANAGERS}" = dnf
  _upkg_apply_filters dnf '' || exit 1
  assert test "${(j:,:)_UPKG_SELECTED_MANAGERS}" = dnf
) || exit 1
print 'ok: every installed distro backend remains explicitly selectable'

(
  _zsh_functions_load_domain files || exit 1
  fallback_dir="$scratch/fallbacks"
  command mkdir "$fallback_dir"
  command ln -s "$(command -v find)" "$fallback_dir/find"
  command ln -s "$(command -v grep)" "$fallback_dir/grep"
  PATH=$fallback_dir
  ff needle "$scratch/nonexistent" > "$scratch/search.stdout" 2> "$scratch/search.stderr"
  assert test "$?" -eq 1
  assert test -s "$scratch/search.stderr"
  assert test ! -s "$scratch/search.stdout"
  ft needle "$scratch/nonexistent" > "$scratch/search.stdout" 2> "$scratch/search.stderr"
  assert test "$?" -eq 2
  assert test -s "$scratch/search.stderr"
  ft '[' "$scratch/fallbacks" > "$scratch/search.stdout" 2> "$scratch/search.stderr"
  assert test "$?" -eq 2
  assert test -s "$scratch/search.stderr"
) || exit 1
print 'ok: find and grep fallbacks preserve missing-path and invalid-pattern errors'

(
  export AUDIT_LOG="$scratch/paru-scope.log"
  write_fake pacman 'printf "%s\n" "unexpected pacman $*" >> "$AUDIT_LOG"; exit 2'
  write_fake paru 'printf "%s\n" "paru $*" >> "$AUDIT_LOG"; printf "%s\n" "$AUDIT_SCOPE"'
  PATH="$scratch:$original_path"
  for inventory in 'repo-only 1 -> 2' 'aur-only 1 -> 2' 'custom-devel 1 -> latest-commit'; do
    export AUDIT_SCOPE=$inventory
    : > "$AUDIT_LOG"
    output=$(_upkg_run_outdated_paru) || exit 1
    assert test "${output#*$inventory}" != "$output"
    assert test "$(<"$AUDIT_LOG")" = 'paru -Qu'
  done
) || exit 1
print 'ok: Paru inventories delegate configured scope to one native query'

(
  refresh_dir="$scratch/arch-refresh"
  command mkdir "$refresh_dir"
  for tool in mktemp rm setsid; do
    command ln -s "$(command -v "$tool")" "$refresh_dir/$tool"
  done
  export AUDIT_LOG="$scratch/arch-refresh.log"
  print -r -- '#!/bin/sh
printf "%s\n" "$CHECKUPDATES_DB" >> "$AUDIT_LOG"
[ -d "$CHECKUPDATES_DB" ] || exit 99
[ "$*" = --nocolor ] || exit 99
[ "$AUDIT_RC" != 0 ] || printf "%s\n" "fresh-package 1 -> 2"
exit "$AUDIT_RC"' > "$refresh_dir/checkupdates"
  command chmod +x "$refresh_dir/checkupdates"
  PATH=$refresh_dir
  for code in 0 1 2 130 143 129; do
    export AUDIT_RC=$code
    _upkg_run_outdated_pacman >/dev/null 2>&1
    result=$?
    case $code in
      0) assert test "$result" -eq 0; assert test "$_UPKG_LAST_STATE" = 'updates available' ;;
      2) assert test "$result" -eq 0; assert test "$_UPKG_LAST_STATE" = 'up to date' ;;
      1) assert test "$result" -eq 1; assert test "$_UPKG_LAST_STATE" = failed ;;
      *) assert test "$result" -eq "$code" ;;
    esac
    databases=( "${(@f)$(<"$AUDIT_LOG")}" )
    for database in "${databases[@]}"; do
      assert test ! -e "$database"
    done
  done
  PATH=$original_path
  command rm "$refresh_dir/checkupdates"
  print -r -- '#!/bin/sh
exit 1' > "$refresh_dir/pacman"
  command chmod +x "$refresh_dir/pacman"
  PATH=$refresh_dir
  output=$(_upkg_run_outdated_pacman) || exit 1
  assert test "${output#*Cached repository inventory}" != "$output"
  _upkg_run_outdated_pacman >/dev/null
  assert test "${_UPKG_LAST_DETAIL#*cached repository metadata}" != "$_UPKG_LAST_DETAIL"
) || exit 1
print 'ok: Arch refresh uses a private database, handles native statuses, and cleans up'

(
  _zsh_functions_load_domain nix || exit 1
  export AUDIT_LOG="$scratch/search-info.log"
  query_tmp="$scratch/query-captures"
  command mkdir "$query_tmp"
  export TMPDIR=$query_tmp
  for audit_manager in apt pacman paru brew flatpak nix npm; do
    write_fake "$audit_manager" '
printf "%s\n" "warning: optional configuration is deprecated" >&2
case "$*" in
  "info --formula sample")
    printf "%s\n" "$*" >> "$AUDIT_LOG"
    printf "%s\n" "==> sample: stable 999.0 (diagnostic only)" >&2
    printf "%s\n" "==> sample: stable 1.2.0 (bottled)"
    exit "${AUDIT_INFO_RC:-0}" ;;
  info*) printf "%s\n" "$*" >> "$AUDIT_LOG"; exit 99 ;;
  "search --cask -- example") exit "$AUDIT_SEARCH_RC" ;;
esac
if [ "$AUDIT_SEARCH_MODE" = valid ]; then
  printf "%s\n" "$AUDIT_SEARCH_BODY"
elif [ "$AUDIT_SEARCH_MODE" = malformed ]; then
  printf "%s\n" "unstructured output with no package fields"
fi
exit "$AUDIT_SEARCH_RC"'
  done
  PATH="$scratch:$original_path"
  for audit_manager in apt pacman paru brew flatpak nix npm; do
    case $audit_manager in
      apt) AUDIT_SEARCH_BODY=$'sample/stable 1.2.0 amd64\n  package description'; expected_row=$'apt\tsample\t1.2.0\tpackage description' ;;
      pacman|paru) AUDIT_SEARCH_BODY=$'extra/sample 1.2.0\n    package description'; expected_row="${audit_manager}"$'\tsample\t1.2.0\tpackage description' ;;
      brew) AUDIT_SEARCH_BODY=sample; expected_row=$'brew\tsample\t1.2.0\tformula' ;;
      flatpak) AUDIT_SEARCH_BODY=$'org.example.Sample\t\tSample App\tpackage description'; expected_row=$'flatpak\torg.example.Sample\t\tSample App - package description' ;;
      nix) AUDIT_SEARCH_BODY=$'* legacyPackages.test.sample (1.2.0)\n    package description'; expected_row=$'nix\tlegacyPackages.test.sample\t1.2.0\tpackage description' ;;
      npm) AUDIT_SEARCH_BODY=$'@example/sample\t\tmaintainer\t2026-09-30\t1.2.0\tkeyword'; expected_row=$'npm\t@example/sample\t1.2.0\t' ;;
    esac
    export AUDIT_SEARCH_BODY npm_config_json=true npm_config_color=true
    for AUDIT_SEARCH_MODE in empty valid malformed; do
      # Brew's token output cannot distinguish arbitrary words from real
      # package names; stderr isolation and metadata headers provide its schema.
      [[ $audit_manager == brew && $AUDIT_SEARCH_MODE == malformed ]] && continue
      for AUDIT_SEARCH_RC in 0 2 130; do
        export AUDIT_SEARCH_MODE AUDIT_SEARCH_RC
        : > "$AUDIT_LOG"
        _UPKG_SEARCH_ROWS=()
        "_upkg_run_search_${audit_manager}" example >"$scratch/search-out" 2>"$scratch/search-err"
        result=$?
        case $AUDIT_SEARCH_RC in
          0)
            assert test "$result" -eq 0
            if [[ $AUDIT_SEARCH_MODE == valid ]]; then
              assert test "${#_UPKG_SEARCH_ROWS}" -eq 1
              assert test "${_UPKG_SEARCH_ROWS[1]}" = "$expected_row"
              if [[ $audit_manager == flatpak ]]; then
                rendered=$(_upkg_format_search_rows "${_UPKG_SEARCH_ROWS[@]}")
                assert test "${rendered#*'?'}" != "$rendered"
                assert test "${rendered#*'Sample App - package description'}" != "$rendered"
              fi
              assert test "$_UPKG_LAST_STATE" = 'matches found'
            else
              assert test "${#_UPKG_SEARCH_ROWS}" -eq 0
              assert test "$_UPKG_LAST_STATE" = 'no matches'
            fi ;;
          2) assert test "$result" -eq 1; assert test "$_UPKG_LAST_STATE" = failed; assert test "${#_UPKG_SEARCH_ROWS}" -eq 0 ;;
          130) assert test "$result" -eq 130; assert test "$_UPKG_LAST_STATE" = cancelled; assert test "${#_UPKG_SEARCH_ROWS}" -eq 0 ;;
        esac
        diagnostics=$(<"$scratch/search-err")
        assert test "${diagnostics#*warning: optional configuration}" != "$diagnostics"
        output=$(<"$scratch/search-out")
        assert test "${output#*warning: optional configuration}" = "$output"
        assert test -z "$(command ls -A "$query_tmp")"
        if [[ $audit_manager == brew ]]; then
          if [[ $AUDIT_SEARCH_MODE == valid && $AUDIT_SEARCH_RC == 0 ]]; then
            assert test "$(<"$AUDIT_LOG")" = 'info --formula sample'
          else
            assert test ! -s "$AUDIT_LOG"
          fi
        fi
      done
    done
    print -r -- "ok: $audit_manager search separates warning/data/error streams and cleans captures"
  done
  export AUDIT_SEARCH_MODE=valid AUDIT_SEARCH_BODY=sample AUDIT_SEARCH_RC=0
  for AUDIT_INFO_RC in 1 130; do
    export AUDIT_INFO_RC
    _UPKG_SEARCH_ROWS=()
    _upkg_run_search_brew example >/dev/null 2>"$scratch/search-err"
    result=$?
    assert test "$result" -eq "$AUDIT_INFO_RC"
    assert test "${#_UPKG_SEARCH_ROWS}" -eq 0
  done
  print 'ok: Homebrew metadata failures and interrupts retain their status'
) || exit 1

(
  export AUDIT_LOG="$scratch/flatpak-inventory.log"
  write_fake flatpak '
printf "%s\n" "$*" >> "$AUDIT_LOG"
case "$*" in
  "remote-ls --updates") exit 0 ;;
  "remote-ls --updates --all")
    printf "%s\n" "flatpak inventory warning" >&2
    [ -z "$AUDIT_FLATPAK_REF" ] || printf "%s\n" "$AUDIT_FLATPAK_REF"
    exit "$AUDIT_RC" ;;
  *) exit 99 ;;
esac'
  PATH="$scratch:$original_path"
  for AUDIT_FLATPAK_REF in '' 'org.example.App.Locale/x86_64/stable' 'org.example.App.Debug/x86_64/stable' 'org.example.Platform/i386/stable'; do
    export AUDIT_FLATPAK_REF
    for AUDIT_RC in 0 1 130; do
      export AUDIT_RC
      : > "$AUDIT_LOG"
      _upkg_run_outdated_flatpak >"$scratch/flatpak-out" 2>"$scratch/flatpak-err"
      result=$?
      case $AUDIT_RC in
        0)
          assert test "$result" -eq 0
          if [[ -z $AUDIT_FLATPAK_REF ]]; then
            assert test "$_UPKG_LAST_STATE" = 'up to date'
          else
            assert test "$_UPKG_LAST_STATE" = 'updates available'
            output=$(<"$scratch/flatpak-out")
            assert test "${output#*$AUDIT_FLATPAK_REF}" != "$output"
          fi ;;
        1) assert test "$result" -eq 1; assert test "$_UPKG_LAST_STATE" = failed ;;
        130) assert test "$result" -eq 130; assert test "$_UPKG_LAST_STATE" = cancelled ;;
      esac
      assert test "$(<"$AUDIT_LOG")" = 'remote-ls --updates --all'
      assert test "$(<"$scratch/flatpak-err")" = 'flatpak inventory warning'
    done
  done
) || exit 1
print 'ok: Flatpak inventories include extension and secondary-architecture refs without changing scope'

(
  write_fake npm 'printf "%s\n" "$AUDIT_NPM_ROWS"'
  PATH="$scratch:$original_path"
  export AUDIT_NPM_ROWS=$'current\tdescription\t2026-09-30\t1.2.3\tkeyword\nno-keywords\tdescription\t2026-09-30\t2.0.0\t\nno-description\t2026-09-30\t3.0.0\t\nold-layout\tdescription\tauthor\t2026-09-30\t4.0.0\tkeyword\nold-empty\t\tauthor\tprehistoric\t5.0.0-beta.1+build.2\t'
  _UPKG_SEARCH_ROWS=()
  _upkg_run_search_npm sample || exit 1
  assert test "${#_UPKG_SEARCH_ROWS}" -eq 5
  assert test "${_UPKG_SEARCH_ROWS[1]}" = $'npm\tcurrent\t1.2.3\tdescription'
  assert test "${_UPKG_SEARCH_ROWS[2]}" = $'npm\tno-keywords\t2.0.0\tdescription'
  assert test "${_UPKG_SEARCH_ROWS[3]}" = $'npm\tno-description\t3.0.0\t'
  assert test "${_UPKG_SEARCH_ROWS[4]}" = $'npm\told-layout\t4.0.0\tdescription'
  assert test "${_UPKG_SEARCH_ROWS[5]}" = $'npm\told-empty\t5.0.0-beta.1+build.2\t'
) || exit 1
print 'ok: npm search supports omitted descriptions, authors, and empty keywords'

(
  write_fake nix '
case "$*" in
  *" --quiet search nixpkgs "*) ;;
  *) printf "evaluating attribute %s\n" one two three >&2; exit 99 ;;
esac
printf "%s\n" "$AUDIT_NIX_DIAGNOSTIC" >&2
[ "$AUDIT_NIX_RC" = 0 ] && printf "%s\n" "* legacyPackages.test.sample (1.2.0)"
exit "$AUDIT_NIX_RC"'
  PATH="$scratch:$original_path"
  export AUDIT_NIX_RC=0 AUDIT_NIX_DIAGNOSTIC='warning: native warning'
  _UPKG_SEARCH_ROWS=()
  _upkg_run_search_nix sample >"$scratch/nix-search-out" 2>"$scratch/nix-search-err" || exit 1
  assert test "${#_UPKG_SEARCH_ROWS}" -eq 1
  assert test "$(<"$scratch/nix-search-err")" = 'warning: native warning'
  export AUDIT_NIX_RC=1 AUDIT_NIX_DIAGNOSTIC='error: evaluation failed'
  _upkg_run_search_nix sample >"$scratch/nix-search-out" 2>"$scratch/nix-search-err"
  assert test "$?" -eq 1
  assert test "$(<"$scratch/nix-search-err")" = 'error: evaluation failed'
) || exit 1
print 'ok: Nix search requests quiet evaluation while retaining warnings and errors'

(
  write_fake jq 'exit 0'
  PATH="$scratch:$original_path"
  npkg() {
    typeset -g _NPKG_OUTDATED_STATE=$AUDIT_NPKG_STATE
    typeset -g _NPKG_OUTDATED_CHANGED=1 _NPKG_OUTDATED_UNKNOWN=1
    print -r -- 'package row'
    print -u2 -r -- 'evaluation diagnostic'
    return "$AUDIT_NPKG_RC"
  }
  for AUDIT_NPKG_STATE in current changed partial; do
    AUDIT_NPKG_RC=0
    [[ $AUDIT_NPKG_STATE == partial ]] && AUDIT_NPKG_RC=1
    _upkg_run_outdated_nix >"$scratch/bridge-out" 2>"$scratch/bridge-err"
    assert test "$?" -eq "$AUDIT_NPKG_RC"
    assert test "$(<"$scratch/bridge-err")" = 'evaluation diagnostic'
    [[ $(<"$scratch/bridge-out") == *'package row'* && $(<"$scratch/bridge-out") != *'evaluation diagnostic'* ]] || exit 1
    case $AUDIT_NPKG_STATE in
      current) assert test "$_UPKG_LAST_STATE" = 'up to date' ;;
      changed) assert test "$_UPKG_LAST_STATE" = 'updates available' ;;
      partial) assert test "$_UPKG_LAST_STATE" = failed ;;
    esac
  done
) || exit 1
print 'ok: Nix bridge preserves result globals and separates diagnostic streams'

(
  _upkg_detect_managers() {
    typeset -ga _UPKG_ACTIVE_MANAGERS=(brew flatpak)
    typeset -ga _UPKG_ALTERNATE_MANAGERS=()
  }
  _upkg_run_search_brew() { _upkg_check_interrupt 130; }
  _upkg_run_search_flatpak() { _upkg_finish_search_results flatpak $'org.example.Sample\t1.0.0\tdescription'; }
  upkg search sample --only brew,flatpak >"$scratch/cancel-search" 2>/dev/null
  assert test "$?" -eq 130
  assert test "${#_UPKG_SUMMARY_ORDER}" -eq 1
  text=$(<"$scratch/cancel-search")
  [[ $text == *'Search cancelled; results are incomplete.'* && $text == *'across 1 manager(s), 1 cancelled (brew).'* && $text != *'No matches found'* ]] || exit 1
  upkg search sample --only flatpak,brew >"$scratch/cancel-search" 2>/dev/null
  assert test "$?" -eq 130
  text=$(<"$scratch/cancel-search")
  [[ $text == *'org.example.Sample'* && $text == *'across 2 manager(s), 1 cancelled (brew).'* ]] || exit 1
  _ui_plain_mode() { return 1; }
  _UPKG_THEME_MODE=1
  text=$(_upkg_print_search_summary)
  [[ $text == *'1 cancelled'* && $text == *'Cancelled managers: brew'* ]] || exit 1
  _ui_plain_mode() { return 0; }
  upkg search sample --skip brew >"$scratch/skip-search" 2>/dev/null || exit 1
  text=$(<"$scratch/skip-search")
  [[ $text == *'across 1 manager(s).'* ]] || exit 1
) || exit 1
print 'ok: cancelled search summaries retain results and count attempted backends'

(
  source "$repo_dir/55-ui-helpers.zsh"
  _ui_plain_mode() { return 1; }
  _UPKG_THEME_MODE=1
  _UPKG_OPERATION=clean
  typeset -ga _UPKG_SUMMARY_ORDER
  typeset -gA _UPKG_SUMMARY_STATE _UPKG_SUMMARY_DETAIL
  _UPKG_SUMMARY_ORDER=(brew)
  _UPKG_SUMMARY_STATE=(brew cancelled)
  _UPKG_SUMMARY_DETAIL=(brew 'interrupted')
  output=$(_upkg_print_summary)
  [[ $output == *'0 cleaned'* && $output == *'1 cancelled'* && $output != *'1 failed'* && $output != *'0 ok'* ]] || exit 1
  metadata=$(_ui_status_metadata cancelled)
  [[ $metadata == *$'\tcancelled\t'* ]] || exit 1
) || exit 1
print 'ok: rich cancellation has its own aggregate bucket and preserves cleanup layout'

# Reaped workers must leave the cancellation set before a later worker cancels.
(
  _zsh_functions_load_domain nix || exit 1
  local -a job_pids=(9001 9002 9003)
  local -A job_identities=(9001 first 9002 second 9003 third)
  integer interrupted=0
  local signalled=''
  wait() { [[ $1 == 9002 ]] && return 130; return 0; }
  _zsh_stop_owned_jobs() { signalled="${(j: :)@}"; }
  _npkg_wait_workers
  assert test "$signalled" = 9003
  assert test "${#job_pids}" -eq 0
  assert test "${#job_identities}" -eq 0
  assert test "$interrupted" -eq 130
) || exit 1
print 'ok: completed workers leave the cancellation ownership set immediately'

# Signals target only the wrapper PID; no terminal/group signal reaches children.
(
  zmodload zsh/system || exit 1
  zmodload zsh/zselect || exit 1
  _zsh_functions_load_domain nix || exit 1
  signal_dir="$scratch/owned-signals"
  command mkdir "$signal_dir"
  print -r -- '#!/bin/sh
sleep 30 &
child=$!
trap '\''sleep 30 & late=$!; printf "%s\n" "$late" >> "$AUDIT_OWNED_PIDS"; wait "$child" 2>/dev/null; exit 143'\'' TERM
printf "%s %s\n" "$$" "$child" > "$AUDIT_OWNED_PIDS"
wait "$child"' > "$signal_dir/backend"
  command chmod +x "$signal_dir/backend"
  command mkdir "$signal_dir/bin"
  command cat > "$signal_dir/bin/nix" <<'NIX_FIXTURE'
#!/bin/sh
shift 2
if [ "$AUDIT_SIGNAL_MODE" = profile ] || [ "$1" = eval ]; then
  exec sh "$AUDIT_SIGNAL_BACKEND"
fi
printf '%s\n' '{"elements":{"sample":{"originalUrl":"nixpkgs","attrPath":"legacyPackages.test.sample","storePaths":["/nix/store/sample"],"outputs":null}}}'
NIX_FIXTURE
  command chmod +x "$signal_dir/bin/nix"
  for mode in query profile evaluation; do
    [[ $mode == query ]] || command -v jq >/dev/null 2>&1 || continue
    for signal in INT TERM HUP; do
      case $signal in INT) expected=130 ;; TERM) expected=143 ;; HUP) expected=129 ;; esac
      case_dir="$signal_dir/$mode-$signal"
      command mkdir "$case_dir"
      export AUDIT_OWNED_PIDS="$case_dir/pids"
      (
        emulate -L zsh
        setopt localtraps NO_MONITOR
        local unrelated_pid rc process_state proc_text child_pid
        local -a child_pids fields leftovers
        integer alive=0 running=0
        command sleep 30 &
        unrelated_pid=$!
        trap 'builtin kill -TERM "$unrelated_pid" 2>/dev/null; wait "$unrelated_pid" 2>/dev/null' EXIT
        export TMPDIR=$case_dir
        unfunction _zsh_run_owned_query 2>/dev/null
        source "$repo_dir/lib/functions-common.zsh"
        export AUDIT_SIGNAL_MODE=$mode AUDIT_SIGNAL_BACKEND="$signal_dir/backend"
        export PATH="$signal_dir/bin:$PATH"
        if [[ $mode == query ]]; then
          _upkg_capture_query sh "$signal_dir/backend"
        else
          _npkg_outdated >/dev/null 2>&1
        fi
        rc=$?
        builtin kill -0 "$unrelated_pid" 2>/dev/null && alive=1
        child_pids=( ${=$(<"$AUDIT_OWNED_PIDS")} )
        for child_pid in "${child_pids[@]}"; do
          [[ -r /proc/$child_pid/stat ]] || continue
          proc_text=$(</proc/$child_pid/stat); fields=( ${=${proc_text##*\) }} )
          [[ ${fields[1]-} == Z ]] || (( running++ ))
        done
        leftovers=( "$case_dir"/zsh-query-owner.*(N) "$case_dir"/upkg-query.*(N) "$case_dir"/npkg-profile.*(N) "$case_dir"/npkg-outdated.*(N) )
        print -r -- "rc=$rc unrelated=$alive running=$running leftovers=${#leftovers}" > "$case_dir/result"
      ) >"$case_dir/stdout" 2>"$case_dir/stderr" &
      harness_pid=$!
      integer ticks=0
      while [[ ! -s $AUDIT_OWNED_PIDS ]] && (( ticks++ < 300 )); do zselect -t 1; done
      [[ -s $AUDIT_OWNED_PIDS ]] || { _zsh_stop_owned_jobs "$harness_pid"; wait "$harness_pid"; exit 1; }
      builtin kill -s "$signal" "$harness_pid" || exit 1
      ticks=0
      while [[ ! -s $case_dir/result ]] && (( ticks++ < 300 )); do zselect -t 1; done
      if [[ ! -s $case_dir/result ]]; then
        _zsh_stop_owned_jobs "$harness_pid"
        wait "$harness_pid" 2>/dev/null
        print -u2 -r -- "not ok: $mode $signal cancellation did not finish promptly"
        exit 1
      fi
      wait "$harness_pid" 2>/dev/null
      assert test "$(<"$case_dir/result")" = "rc=$expected unrelated=1 running=0 leftovers=0"
    done
  done
) || exit 1
print 'ok: wrapper INT/TERM/HUP stop owned query/profile/evaluation descendants only'
