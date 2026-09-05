# Trusted lazy upkg-backends implementations; loaded by functions-catalogue.zsh.

_upkg_run_search_apt() {
  emulate -L zsh

  local output rc line header rest
  local current_name='' current_version='' current_desc=''
  local -a rows

  _upkg_search_progress apt ''
  output=$(command apt search --names-only -- "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear
  output=$(print -r -- "$output" | sed '/^WARNING: apt does not have a stable CLI interface\./d;/^Sorting\.\.\.$/d;/^Full Text Search\.\.\.$/d')
  if (( rc != 0 )); then
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'apt search failed'
    return 1
  fi

  for line in ${(f)output}; do
    [ -n "$line" ] || continue

    if [[ $line == [[:space:]]* ]]; then
      if [ -n "$current_name" ] && [ -z "$current_desc" ]; then
        current_desc=$(_upkg_search_trim "$line")
      fi
      continue
    fi

    if [ -n "$current_name" ]; then
      rows+=("${current_name}"$'\t'"${current_version}"$'\t'"${current_desc}")
    fi

    header=${line%% *}
    rest=${line#"$header"}
    rest=${rest# }
    current_name=${header%%/*}
    current_version=${rest%% *}
    current_desc=''
  done

  if [ -n "$current_name" ]; then
    rows+=("${current_name}"$'\t'"${current_version}"$'\t'"${current_desc}")
  fi

  _upkg_finish_search_results apt "${rows[@]}"
}

_upkg_run_search_dnf() {
  emulate -L zsh

  local output rc line name version query
  local -a rows fields query_patterns

  for query in "$@"; do
    query_patterns+=("*${query}*")
  done

  _upkg_search_progress dnf ''
  output=$(command dnf list --available "${query_patterns[@]}" 2>&1)
  rc=$?
  _upkg_search_progress_clear

  if (( rc != 0 )); then
    if [[ $output == *'No matching Packages to list'* ]]; then
      _upkg_finish_search_results dnf
      return 0
    fi
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'dnf list --available failed'
    return 1
  fi

  for line in ${(f)output}; do
    [ -n "$line" ] || continue
    [[ $line == 'Available Packages'* ]] && continue
    [[ $line == 'Last metadata expiration check:'* ]] && continue

    fields=( ${(z)line} )
    (( ${#fields[@]} >= 2 )) || continue
    name=${fields[1]}
    version=${fields[2]}
    rows+=("${name}"$'\t'"${version}"$'\t')
  done

  _upkg_finish_search_results dnf "${rows[@]}"
}

_upkg_run_search_pacman() {
  emulate -L zsh

  local output rc line header rest name version desc=''
  local -a rows

  _upkg_search_progress pacman ''
  output=$(command pacman -Ss -- "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear

  if (( rc != 0 )); then
    if (( rc == 1 )) && [ -z "$output" ]; then
      _upkg_finish_search_results pacman
      return 0
    fi
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'pacman -Ss failed'
    return 1
  fi

  for line in ${(f)output}; do
    [ -n "$line" ] || continue

    if [[ $line == [[:space:]]* ]]; then
      if (( ${#rows[@]} > 0 )); then
        desc=$(_upkg_search_trim "$line")
        rows[-1]=$(_upkg_append_search_description "${rows[-1]}" "$desc")
      fi
      continue
    fi

    header=${line%% *}
    rest=${line#"$header"}
    rest=${rest# }
    name=${header#*/}
    version=${rest%% *}
    rows+=("${name}"$'\t'"${version}"$'\t')
  done

  _upkg_finish_search_results pacman "${rows[@]}"
}

_upkg_run_search_paru() {
  emulate -L zsh

  local output rc line header rest name version desc=''
  local -a rows

  _upkg_search_progress paru ''
  output=$(command paru -Ss -- "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear

  if (( rc != 0 )); then
    if (( rc == 1 )) && [ -z "$output" ]; then
      _upkg_finish_search_results paru
      return 0
    fi
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'paru -Ss failed'
    return 1
  fi

  for line in ${(f)output}; do
    [ -n "$line" ] || continue

    if [[ $line == [[:space:]]* ]]; then
      if (( ${#rows[@]} > 0 )); then
        desc=$(_upkg_search_trim "$line")
        rows[-1]=$(_upkg_append_search_description "${rows[-1]}" "$desc")
      fi
      continue
    fi

    header=${line%% *}
    rest=${line#"$header"}
    rest=${rest# }
    name=${header#*/}
    version=${rest%% *}
    rows+=("${name}"$'\t'"${version}"$'\t')
  done

  _upkg_finish_search_results paru "${rows[@]}"
}

_upkg_run_search_brew() {
  emulate -L zsh

  local output rc line candidate meta version
  local info_limit=50 formula_total=0 cask_total=0
  local -a formulae casks formulae_for_info casks_for_info rows tokens
  local -A formula_wanted cask_wanted

  _upkg_search_progress brew 'formulae'
  output=$(HOMEBREW_NO_AUTO_UPDATE=1 command brew search --formula -- "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear
  if (( rc != 0 )); then
    if [[ $output != *'No formulae found'* && $output != *'No formulae or casks found'* ]]; then
      [ -n "$output" ] && print -r -- "$output"
      _upkg_set_last_result 'failed' 'brew search --formula failed'
      return 1
    fi
  else
    for line in ${(f)output}; do
      [ -n "$line" ] || continue
      [[ $line == '==>'* ]] && continue
      tokens=( ${(z)line} )
      formulae+=( "${tokens[@]}" )
    done
  fi

  _upkg_search_progress brew 'casks'
  output=$(HOMEBREW_NO_AUTO_UPDATE=1 command brew search --cask -- "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear
  if (( rc != 0 )); then
    if [[ $output != *'No casks found'* && $output != *'No formulae or casks found'* ]]; then
      [ -n "$output" ] && print -r -- "$output"
      _upkg_set_last_result 'failed' 'brew search --cask failed'
      return 1
    fi
  else
    for line in ${(f)output}; do
      [ -n "$line" ] || continue
      [[ $line == '==>'* ]] && continue
      tokens=( ${(z)line} )
      casks+=( "${tokens[@]}" )
    done
  fi

  if (( ${#formulae[@]} == 0 && ${#casks[@]} == 0 )); then
    _upkg_finish_search_results brew
    return 0
  fi

  formula_total=${#formulae[@]}
  cask_total=${#casks[@]}

  for candidate in "${formulae[@]}"; do
    (( ${#formulae_for_info[@]} >= info_limit )) && break
    formulae_for_info+=("$candidate")
    formula_wanted[$candidate]=1
  done
  for candidate in "${casks[@]}"; do
    (( ${#casks_for_info[@]} >= info_limit )) && break
    casks_for_info+=("$candidate")
    cask_wanted[$candidate]=1
  done

  if (( formula_total > info_limit )); then
    print -u2 -- "Homebrew formula search returned $formula_total matches; showing first $info_limit. Refine the query for more specific results."
  fi
  if (( cask_total > info_limit )); then
    print -u2 -- "Homebrew cask search returned $cask_total matches; showing first $info_limit. Refine the query for more specific results."
  fi

  if (( ${#formulae_for_info[@]} > 0 )); then
    _upkg_search_progress brew 'formula info'
    output=$(HOMEBREW_NO_AUTO_UPDATE=1 command brew info --formula "${formulae_for_info[@]}" 2>&1)
    rc=$?
    _upkg_search_progress_clear
    if (( rc != 0 )); then
      [ -n "$output" ] && print -r -- "$output"
      _upkg_set_last_result 'failed' 'brew info failed'
      return 1
    fi

    for line in ${(f)output}; do
      [ -n "$line" ] || continue
      candidate=$(_upkg_brew_name_from_header "$line")
      if [ -z "${formula_wanted[$candidate]}" ]; then
        continue
      fi

      meta=${line#*: }
      version=$(_upkg_brew_version_from_header "$meta")
      rows+=("${candidate}"$'\t'"${version}"$'\t'"formula")
    done
  fi

  if (( ${#casks_for_info[@]} > 0 )); then
    _upkg_search_progress brew 'cask info'
    output=$(HOMEBREW_NO_AUTO_UPDATE=1 command brew info --cask "${casks_for_info[@]}" 2>&1)
    rc=$?
    _upkg_search_progress_clear
    if (( rc != 0 )); then
      [ -n "$output" ] && print -r -- "$output"
      _upkg_set_last_result 'failed' 'brew info failed'
      return 1
    fi

    for line in ${(f)output}; do
      [ -n "$line" ] || continue
      candidate=$(_upkg_brew_name_from_header "$line")
      if [ -z "${cask_wanted[$candidate]}" ]; then
        continue
      fi

      meta=${line#*: }
      version=$(_upkg_brew_version_from_header "$meta")
      rows+=("${candidate}"$'\t'"${version}"$'\t'"cask")
    done
  fi

  _upkg_finish_search_results brew "${rows[@]}"
}

_upkg_run_search_flatpak() {
  emulate -L zsh

  local output rc app version name description display_name
  local -a rows

  _upkg_search_progress flatpak ''
  output=$(command flatpak search --columns=application,version,name,description -- "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear

  if (( rc != 0 )); then
    if [[ $output == *'No matches found'* ]]; then
      _upkg_finish_search_results flatpak
      return 0
    fi
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'flatpak search failed'
    return 1
  fi

  while IFS=$'\t' read -r app version name description _; do
    [ -n "$app" ] || continue
    [ "$app" = 'Application' ] && continue
    display_name=$(_upkg_search_trim "$name")
    description=$(_upkg_search_trim "$description")
    if [ -n "$display_name" ] && [ "$display_name" != "$app" ]; then
      if [ -n "$description" ]; then
        description="${display_name} - ${description}"
      else
        description=$display_name
      fi
    fi
    rows+=("${app}"$'\t'"${version}"$'\t'"${description}")
  done <<< "$output"

  _upkg_finish_search_results flatpak "${rows[@]}"
}

_upkg_run_search_nix() {
  emulate -L zsh

  local output output_lower rc line trimmed name version description=''
  local -a rows

  _upkg_search_progress nix ''
  output=$(_npkg_nix search nixpkgs "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear

  if (( rc != 0 )); then
    output_lower=${(L)output}
    if [[ $output_lower == *'no packages matched'* || $output_lower == *'no results for'* ]]; then
      _upkg_finish_search_results nix
      return 0
    fi
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'nix search failed'
    return 1
  fi

  for line in ${(f)output}; do
    [ -n "$line" ] || continue

    if [[ $line == [[:space:]]* ]]; then
      if (( ${#rows[@]} > 0 )); then
        description=$(_upkg_search_trim "$line")
        rows[-1]=$(_upkg_append_search_description "${rows[-1]}" "$description")
      fi
      continue
    fi

    trimmed=$line
    trimmed=${trimmed#\* }
    name=${trimmed%% \(*}
    version=${trimmed##*\(}
    version=${version%\)}
    if [ "$name" = "$trimmed" ] || [ "$version" = "$trimmed" ]; then
      continue
    fi
    rows+=("${name}"$'\t'"${version}"$'\t')
  done

  _upkg_finish_search_results nix "${rows[@]}"
}

_upkg_run_search_npm() {
  emulate -L zsh

  local output rc name description author date version
  local -a rows

  _upkg_search_progress npm ''
  output=$(command npm search --parseable -- "$@" 2>&1)
  rc=$?
  _upkg_search_progress_clear

  if (( rc != 0 )); then
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'npm search failed'
    return 1
  fi

  while IFS=$'\t' read -r name description author date version _; do
    [ -n "$name" ] || continue
    rows+=("${name}"$'\t'"${version}"$'\t'"$(_upkg_search_trim "$description")")
  done <<< "$output"

  _upkg_finish_search_results npm "${rows[@]}"
}

_upkg_run_outdated_apt() {
  emulate -L zsh

  local output line rc
  local -a packages

  _upkg_print_section apt

  output=$(command apt list --upgradable 2>&1)
  rc=$?
  output=$(print -r -- "$output" | sed '/^Listing\.\.\.$/d')
  if (( rc != 0 )); then
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'apt list --upgradable failed'
    return 1
  fi

  for line in ${(f)output}; do
    [[ $line == */* ]] || continue
    packages+=("$line")
  done

  if (( ${#packages[@]} == 0 )); then
    print 'No updates available.'
    _upkg_set_last_result 'up to date' ''
    return 0
  fi

  print -l -- "${packages[@]}"
  _upkg_set_last_result 'updates available' ''
}

_upkg_run_outdated_dnf() {
  emulate -L zsh

  local output rc

  _upkg_print_section dnf

  output=$(command dnf check-update 2>&1)
  rc=$?

  case $rc in
    0)
      print 'No updates available.'
      _upkg_set_last_result 'up to date' ''
      ;;
    100)
      [ -n "$output" ] && print -r -- "$output"
      _upkg_set_last_result 'updates available' ''
      ;;
    *)
      [ -n "$output" ] && print -r -- "$output"
      _upkg_set_last_result 'failed' 'dnf check-update failed'
      return 1
      ;;
  esac
}

_upkg_run_outdated_pacman() {
  emulate -L zsh

  local output rc

  _upkg_print_section pacman

  output=$(command pacman -Qu 2>&1)
  rc=$?

  if _upkg_arch_outdated_has_no_updates "$rc" "$output"; then
    print 'No updates available.'
    _upkg_set_last_result 'up to date' ''
    return 0
  fi

  if (( rc != 0 )); then
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'pacman -Qu failed'
    return 1
  fi

  if [ -n "$output" ]; then
    print -r -- "$output"
    _upkg_set_last_result 'updates available' ''
  else
    print 'No updates available.'
    _upkg_set_last_result 'up to date' ''
  fi
}

_upkg_run_outdated_paru() {
  emulate -L zsh

  local pacman_output='' paru_output='' repo_error=''
  local pacman_rc=0 paru_rc=0
  local had_updates=0 repo_failed=0

  _upkg_print_section paru

  if command -v pacman >/dev/null 2>&1; then
    pacman_output=$(command pacman -Qu 2>&1)
    pacman_rc=$?

    if _upkg_arch_outdated_has_no_updates "$pacman_rc" "$pacman_output"; then
      pacman_output=''
    elif (( pacman_rc != 0 )); then
      repo_failed=1
      repo_error='pacman -Qu failed while checking paru repo updates'
    fi
  else
    pacman_output=$(command paru -Qu 2>&1)
    pacman_rc=$?

    if _upkg_arch_outdated_has_no_updates "$pacman_rc" "$pacman_output"; then
      pacman_output=''
    elif (( pacman_rc != 0 )); then
      repo_failed=1
      repo_error='paru -Qu failed'
    fi
  fi

  paru_output=$(command paru -Qua 2>&1)
  paru_rc=$?

  if _upkg_arch_outdated_has_no_updates "$paru_rc" "$paru_output"; then
    paru_output=''
    paru_rc=0
  fi

  if (( repo_failed )); then
    print 'Repo updates:'
    if [ -n "$pacman_output" ]; then
      print -r -- "$pacman_output"
    else
      print 'Repo update check failed.'
    fi
    print 'Repo update check failed; continuing with AUR preview.'
  elif [ -n "$pacman_output" ]; then
    print 'Repo updates:'
    print -r -- "$pacman_output"
    had_updates=1
  fi

  if (( paru_rc != 0 )); then
    (( repo_failed || had_updates )) && print ''
    print 'AUR updates:'
    [ -n "$paru_output" ] && print -r -- "$paru_output"
    if (( repo_failed )); then
      _upkg_set_last_result 'failed' "$repo_error; paru -Qua failed"
    else
      _upkg_set_last_result 'failed' 'paru -Qua failed'
    fi
    return 1
  fi

  if [ -n "$paru_output" ]; then
    (( repo_failed || had_updates )) && print ''
    print 'AUR updates:'
    print -r -- "$paru_output"
    had_updates=1
  elif (( repo_failed )); then
    print ''
    print 'AUR updates:'
    print 'No updates available.'
  fi

  if (( repo_failed )); then
    _upkg_set_last_result 'failed' "$repo_error; AUR preview still shown"
    return 1
  fi

  if (( had_updates )); then
    _upkg_set_last_result 'updates available' ''
  else
    print 'No updates available.'
    _upkg_set_last_result 'up to date' ''
  fi
}

_upkg_run_outdated_brew() {
  emulate -L zsh

  local output rc

  _upkg_print_section brew

  output=$(command brew outdated 2>&1)
  rc=$?

  if (( rc != 0 )); then
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'brew outdated failed'
    return 1
  fi

  if [ -n "$output" ]; then
    print -r -- "$output"
    _upkg_set_last_result 'updates available' ''
  else
    print 'No updates available.'
    _upkg_set_last_result 'up to date' ''
  fi
}

_upkg_run_outdated_flatpak() {
  emulate -L zsh

  local output rc

  _upkg_print_section flatpak

  output=$(command flatpak remote-ls --updates 2>&1)
  rc=$?

  if (( rc != 0 )); then
    [ -n "$output" ] && print -r -- "$output"
    _upkg_set_last_result 'failed' 'flatpak remote-ls --updates failed'
    return 1
  fi

  if [ -n "$output" ]; then
    print -r -- "$output"
    _upkg_set_last_result 'updates available' ''
  else
    print 'No updates available.'
    _upkg_set_last_result 'up to date' ''
  fi
}

_upkg_run_outdated_nix() {
  emulate -L zsh

  local output output_file rc state changed unknown

  _upkg_print_section nix

  if ! command -v jq >/dev/null 2>&1; then
    print 'jq is required for npkg outdated; install jq or run upkg upgrade --only nix.'
    _upkg_set_last_result 'blocked' 'jq is required for nix outdated'
    return 0
  fi

  output_file=$(command mktemp "${TMPDIR:-/tmp}/upkg-nix-outdated.XXXXXX") || {
    _upkg_set_last_result 'failed' 'could not create a temp file for npkg outdated'
    return 1
  }

  npkg outdated >"$output_file" 2>&1
  rc=$?
  output=$(<"$output_file")
  command rm -f -- "$output_file"

  [ -n "$output" ] && print -r -- "$output"

  state=${_NPKG_OUTDATED_STATE:-partial}
  changed=${_NPKG_OUTDATED_CHANGED:-0}
  unknown=${_NPKG_OUTDATED_UNKNOWN:-0}

  case $state in
    current)
      if (( rc == 0 )); then
        _upkg_set_last_result 'up to date' ''
        return 0
      fi
      ;;
    changed)
      if (( rc == 0 )); then
        _upkg_set_last_result 'updates available' "${changed} change(s) available"
        return 0
      fi
      ;;
    partial)
      _upkg_set_last_result 'failed' "${changed} change(s), ${unknown} unknown"
      return 1
      ;;
  esac

  _upkg_set_last_result 'failed' 'npkg outdated returned inconsistent state'
  return 1
}

_upkg_run_outdated_npm() {
  emulate -L zsh

  local stdout_file stderr_file stdout_output stderr_output rc

  _upkg_print_section npm

  stdout_file=$(command mktemp "${TMPDIR:-/tmp}/upkg-npm.stdout.XXXXXX") || {
    _upkg_set_last_result 'failed' 'could not create a temp file for npm outdated'
    return 1
  }
  stderr_file=$(command mktemp "${TMPDIR:-/tmp}/upkg-npm.stderr.XXXXXX") || {
    command rm -f -- "$stdout_file"
    _upkg_set_last_result 'failed' 'could not create a temp file for npm outdated'
    return 1
  }

  command npm outdated -g --depth=0 >"$stdout_file" 2>"$stderr_file"
  rc=$?

  stdout_output=$(<"$stdout_file")
  stderr_output=$(<"$stderr_file")
  command rm -f -- "$stdout_file" "$stderr_file"

  case $rc in
    0)
      if [ -n "$stdout_output" ]; then
        print -r -- "$stdout_output"
        _upkg_set_last_result 'updates available' ''
      else
        print 'No updates available.'
        _upkg_set_last_result 'up to date' ''
      fi
      ;;
    1)
      if [ -z "$stderr_output" ] && _upkg_npm_outdated_looks_valid "$stdout_output"; then
        print -r -- "$stdout_output"
        _upkg_set_last_result 'updates available' ''
      else
        [ -n "$stdout_output" ] && print -r -- "$stdout_output"
        [ -n "$stderr_output" ] && print -u2 -- "$stderr_output"
        _upkg_set_last_result 'failed' 'npm outdated -g failed'
        return 1
      fi
      ;;
    *)
      [ -n "$stdout_output" ] && print -r -- "$stdout_output"
      [ -n "$stderr_output" ] && print -u2 -- "$stderr_output"
      _upkg_set_last_result 'failed' 'npm outdated -g failed'
      return 1
      ;;
  esac
}

_upkg_run_upgrade_apt() {
  emulate -L zsh

  local rc

  _upkg_print_section apt

  if (( ! _UPKG_ALLOW_SUDO )) && ! _upkg_is_root; then
    print 'apt upgrade requires root; rerun with: upkg upgrade --sudo --only apt'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only apt'
    return 0
  fi

  _upkg_require_sudo_command || return 0

  if _upkg_is_root; then
    command apt update
    rc=$?
    if (( rc != 0 )); then
      _upkg_set_last_result 'failed' 'apt update failed'
      return 1
    fi
    command apt full-upgrade
  else
    command sudo apt update
    rc=$?
    if (( rc != 0 )); then
      _upkg_set_last_result 'failed' 'sudo apt update failed'
      return 1
    fi
    command sudo apt full-upgrade
  fi
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'apt full-upgrade failed'
}

_upkg_run_upgrade_dnf() {
  emulate -L zsh

  local rc

  _upkg_print_section dnf

  if (( ! _UPKG_ALLOW_SUDO )) && ! _upkg_is_root; then
    print 'dnf upgrade requires root; rerun with: upkg upgrade --sudo --only dnf'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only dnf'
    return 0
  fi

  _upkg_require_sudo_command || return 0

  if _upkg_is_root; then
    command dnf upgrade --refresh
  else
    command sudo dnf upgrade --refresh
  fi
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'dnf upgrade --refresh failed'
}

_upkg_run_upgrade_pacman() {
  emulate -L zsh

  local rc

  _upkg_print_section pacman

  if (( ! _UPKG_ALLOW_SUDO )) && ! _upkg_is_root; then
    print 'pacman upgrade requires root; rerun with: upkg upgrade --sudo --only pacman'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only pacman'
    return 0
  fi

  _upkg_require_sudo_command || return 0

  if _upkg_is_root; then
    command pacman -Syu
  else
    command sudo pacman -Syu
  fi
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'pacman -Syu failed'
}

_upkg_run_upgrade_paru() {
  emulate -L zsh

  local rc

  _upkg_print_section paru

  if (( ! _UPKG_ALLOW_SUDO )); then
    print 'paru upgrade requires explicit --sudo opt-in; rerun with: upkg upgrade --sudo --only paru'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only paru'
    return 0
  fi

  command paru -Syu
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'paru -Syu failed'
}

_upkg_run_upgrade_brew() {
  emulate -L zsh

  local rc

  _upkg_print_section brew

  command brew upgrade
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'brew upgrade failed'
}

_upkg_run_upgrade_flatpak() {
  emulate -L zsh

  local rc

  _upkg_print_section flatpak

  command flatpak update
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'flatpak update failed'
}

_upkg_run_upgrade_nix() {
  emulate -L zsh

  local rc

  _upkg_print_section nix

  npkg upgrade
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'npkg upgrade failed'
}

_upkg_run_upgrade_npm() {
  emulate -L zsh

  local prefix rc

  _upkg_print_section npm

  prefix=$(_upkg_npm_prefix) || {
    print 'Failed to determine the npm global prefix.'
    _upkg_set_last_result 'failed' 'could not determine npm global prefix'
    return 1
  }

  if [ ! -d "$prefix" ] || [ ! -w "$prefix" ]; then
    print "npm global prefix '$prefix' is not writable by the current user."
    _upkg_print_npm_prefix_hint
    _upkg_set_last_result 'blocked' 'configure a user-writable npm prefix'
    return 0
  fi

  command npm update -g
  rc=$?

  _upkg_finish_upgrade_result "$rc" 'npm update -g failed'
}

_upkg_run_clean_apt() {
  emulate -L zsh

  local prefix
  local succeeded=0 failed=0
  local -a failures

  _upkg_print_section apt

  if (( _UPKG_DRY_RUN )); then
    prefix=$(_upkg_cleanup_privilege_prefix)
    _upkg_print_cleanup_phase 'Unused packages'
    print -r -- "preview: ${prefix}apt --simulate autoremove"
    _upkg_run_cleanup_step 'apt autoremove preview failed' apt --simulate autoremove

    _upkg_print_cleanup_phase 'Package cache'
    print -r -- "would run: ${prefix}apt autoclean"
    (( succeeded++ ))

    _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
    return $?
  fi

  if (( ! _UPKG_ALLOW_SUDO )) && ! _upkg_is_root; then
    print 'apt cleanup requires root; rerun with: upkg clean --sudo --only apt'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only apt'
    return 0
  fi

  _upkg_require_sudo_command || return 0

  _upkg_print_cleanup_phase 'Unused packages'
  if _upkg_is_root; then
    _upkg_run_cleanup_step 'apt autoremove failed' apt autoremove
  else
    _upkg_run_cleanup_step 'apt autoremove failed' sudo apt autoremove
  fi

  _upkg_print_cleanup_phase 'Package cache'
  if _upkg_is_root; then
    _upkg_run_cleanup_step 'apt autoclean failed' apt autoclean
  else
    _upkg_run_cleanup_step 'apt autoclean failed' sudo apt autoclean
  fi

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_clean_dnf() {
  emulate -L zsh

  local prefix
  local succeeded=0 failed=0
  local -a failures

  _upkg_print_section dnf

  if (( _UPKG_DRY_RUN )); then
    prefix=$(_upkg_cleanup_privilege_prefix)
    _upkg_print_cleanup_phase 'Unused packages'
    print 'preview: dnf --cacheonly repoquery --unneeded'
    _upkg_run_cleanup_step 'dnf cache-only unneeded-package preview failed' dnf --cacheonly repoquery --unneeded

    _upkg_print_cleanup_phase 'Package cache'
    print -r -- "would run: ${prefix}dnf clean all"
    (( succeeded++ ))

    _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
    return $?
  fi

  if (( ! _UPKG_ALLOW_SUDO )) && ! _upkg_is_root; then
    print 'dnf cleanup requires root; rerun with: upkg clean --sudo --only dnf'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only dnf'
    return 0
  fi

  _upkg_require_sudo_command || return 0

  _upkg_print_cleanup_phase 'Unused packages'
  if _upkg_is_root; then
    _upkg_run_cleanup_step 'dnf autoremove failed' dnf autoremove
  else
    _upkg_run_cleanup_step 'dnf autoremove failed' sudo dnf autoremove
  fi

  _upkg_print_cleanup_phase 'Package cache'
  if _upkg_is_root; then
    _upkg_run_cleanup_step 'dnf clean all failed' dnf clean all
  else
    _upkg_run_cleanup_step 'dnf clean all failed' sudo dnf clean all
  fi

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_clean_pacman() {
  emulate -L zsh

  local orphan_output rc prefix
  local succeeded=0 failed=0
  local -a failures orphans

  _upkg_print_section pacman

  if (( ! _UPKG_DRY_RUN && ! _UPKG_ALLOW_SUDO )) && ! _upkg_is_root; then
    print 'pacman cleanup requires root; rerun with: upkg clean --sudo --only pacman'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only pacman'
    return 0
  fi

  if (( ! _UPKG_DRY_RUN )); then
    _upkg_require_sudo_command || return 0
  fi

  prefix=$(_upkg_cleanup_privilege_prefix)
  _upkg_print_cleanup_phase 'Unused packages'
  orphan_output=$(command pacman -Qtdq)
  rc=$?
  if (( rc == 0 )); then
    orphans=( ${(f)orphan_output} )
    if (( ${#orphans[@]} == 0 )); then
      print 'No orphaned packages found.'
      (( succeeded++ ))
    elif (( _UPKG_DRY_RUN )); then
      print -r -- "$orphan_output"
      print -r -- "would run: ${prefix}pacman -Rs -- ${(j: :)orphans}"
      (( succeeded++ ))
    else
      if _upkg_is_root; then
        _upkg_run_cleanup_step 'pacman orphan removal failed' pacman -Rs -- "${orphans[@]}"
      else
        _upkg_run_cleanup_step 'pacman orphan removal failed' sudo pacman -Rs -- "${orphans[@]}"
      fi
    fi
  elif (( rc == 1 )) && [ -z "$orphan_output" ]; then
    print 'No orphaned packages found.'
    (( succeeded++ ))
  else
    [ -n "$orphan_output" ] && print -r -- "$orphan_output"
    (( failed++ ))
    failures+=('pacman orphan query failed')
  fi

  _upkg_print_cleanup_phase 'Package cache'
  if (( _UPKG_DRY_RUN )); then
    print -r -- "would run: ${prefix}pacman -Sc"
    (( succeeded++ ))
  else
    if _upkg_is_root; then
      _upkg_run_cleanup_step 'pacman -Sc failed' pacman -Sc
    else
      _upkg_run_cleanup_step 'pacman -Sc failed' sudo pacman -Sc
    fi
  fi

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_clean_paru() {
  emulate -L zsh

  local succeeded=0 failed=0
  local -a failures

  _upkg_print_section paru

  if (( _UPKG_DRY_RUN )); then
    _upkg_print_cleanup_phase 'Unused packages'
    print 'would run: paru -c'
    (( succeeded++ ))
    _upkg_print_cleanup_phase 'Package cache'
    print 'would run: paru -Sc'
    (( succeeded++ ))
    _upkg_finish_cleanup_result "$succeeded" "$failed" ''
    return $?
  fi

  if (( ! _UPKG_ALLOW_SUDO )); then
    print 'paru cleanup requires explicit --sudo opt-in; rerun with: upkg clean --sudo --only paru'
    _upkg_set_last_result 'blocked' 'rerun with --sudo --only paru'
    return 0
  fi

  _upkg_print_cleanup_phase 'Unused packages'
  _upkg_run_cleanup_step 'paru -c failed' paru -c

  _upkg_print_cleanup_phase 'Package cache'
  _upkg_run_cleanup_step 'paru -Sc failed' paru -Sc

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_clean_brew() {
  emulate -L zsh

  local succeeded=0 failed=0
  local -a failures

  _upkg_print_section brew

  _upkg_print_cleanup_phase 'Unused packages'
  if (( _UPKG_DRY_RUN )); then
    _upkg_run_cleanup_step 'brew autoremove preview failed' brew autoremove --dry-run
  else
    _upkg_run_cleanup_step 'brew autoremove failed' brew autoremove
  fi

  _upkg_print_cleanup_phase 'Package cache'
  if (( _UPKG_DRY_RUN )); then
    _upkg_run_cleanup_step 'brew cleanup preview failed' brew cleanup --dry-run
  else
    _upkg_run_cleanup_step 'brew cleanup failed' brew cleanup
  fi

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_clean_flatpak() {
  emulate -L zsh

  local succeeded=0 failed=0
  local -a failures

  _upkg_print_section flatpak

  if (( _UPKG_DRY_RUN )); then
    _upkg_print_cleanup_phase 'Unused user refs'
    print 'would run: flatpak uninstall --unused --user'
    (( succeeded++ ))
    _upkg_print_cleanup_phase 'Unused system refs'
    print 'would run: flatpak uninstall --unused --system'
    (( succeeded++ ))
    _upkg_finish_cleanup_result "$succeeded" "$failed" ''
    return $?
  fi

  _upkg_print_cleanup_phase 'Unused user refs'
  _upkg_run_cleanup_step 'flatpak user cleanup failed' flatpak uninstall --unused --user

  _upkg_print_cleanup_phase 'Unused system refs'
  _upkg_run_cleanup_step 'flatpak system cleanup failed' flatpak uninstall --unused --system

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_clean_nix() {
  emulate -L zsh

  local succeeded=0 failed=0
  local -a failures

  _upkg_print_section nix

  if ! command -v nix-collect-garbage >/dev/null 2>&1; then
    print 'nix-collect-garbage is required for Nix cleanup; ensure it is installed and available on PATH.'
    _upkg_set_last_result 'failed' 'nix-collect-garbage is not available'
    return 1
  fi

  _upkg_print_cleanup_phase 'Unreachable store objects'
  if (( _UPKG_DRY_RUN )); then
    _upkg_run_cleanup_step 'nix-collect-garbage failed' nix-collect-garbage --dry-run
  else
    _upkg_run_cleanup_step 'nix-collect-garbage failed' nix-collect-garbage
  fi

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

_upkg_run_npm_npx_cache_command() {
  emulate -L zsh
  setopt multios

  local action=$1
  local stdout_file='' stderr_file='' stdout_output='' stderr_output=''
  local rc
  integer stdout_fd stderr_fd

  typeset -g _UPKG_NPM_NPX_STDOUT=''
  typeset -g _UPKG_NPM_NPX_STDERR=''
  typeset -g _UPKG_NPM_NPX_DIAGNOSTIC=''

  stdout_file=$(command mktemp "${TMPDIR:-/tmp}/upkg-npm-npx.stdout.XXXXXX") || {
    print -u2 -- 'Could not create temporary output capture for npm npx cache cleanup.'
    return 1
  }
  stderr_file=$(command mktemp "${TMPDIR:-/tmp}/upkg-npm-npx.stderr.XXXXXX") || {
    command rm -f -- "$stdout_file"
    print -u2 -- 'Could not create temporary error capture for npm npx cache cleanup.'
    return 1
  }

  exec {stdout_fd}>&1 || {
    command rm -f -- "$stdout_file" "$stderr_file"
    return 1
  }
  exec {stderr_fd}>&2 || {
    exec {stdout_fd}>&-
    command rm -f -- "$stdout_file" "$stderr_file"
    return 1
  }

  # Zsh multios duplicate each native stream to its original descriptor and a
  # private diagnostic file, preserving output while allowing capability checks.
  command npm cache npx "$action" >&$stdout_fd >"$stdout_file" 2>&$stderr_fd 2>"$stderr_file"
  rc=$?

  exec {stdout_fd}>&-
  exec {stderr_fd}>&-

  stdout_output=$(<"$stdout_file")
  stderr_output=$(<"$stderr_file")
  _UPKG_NPM_NPX_STDOUT=$stdout_output
  _UPKG_NPM_NPX_STDERR=$stderr_output
  _UPKG_NPM_NPX_DIAGNOSTIC="${stdout_output}"$'\n'"${stderr_output}"
  command rm -f -- "$stdout_file" "$stderr_file"

  return $rc
}

_upkg_npm_npx_cache_unsupported() {
  emulate -L zsh

  local output=${(L)1}

  if [[ $output == *'unknown command'* ||
    $output == *'invalid subcommand'* ||
    $output == *'not a valid npm command'* ]]; then
    return 0
  fi

  if [[ $output == *'usage:'* || $output == *'npm cache usage:'* ]]; then
    [[ $output != *'npm cache npx ls'* && $output != *'npm cache npx rm'* ]]
    return $?
  fi

  return 1
}

_upkg_run_clean_npm() {
  emulate -L zsh

  local output listing line key rc npx_failure_detail
  local npx_unsupported=0 parse_failed=0 verify_failures_before=0
  local succeeded=0 failed=0
  local -a failures npx_keys

  _upkg_print_section npm

  _upkg_print_cleanup_phase 'npx cache'
  if (( _UPKG_DRY_RUN )); then
    _upkg_run_npm_npx_cache_command ls
    rc=$?
    output=${_UPKG_NPM_NPX_DIAGNOSTIC:-}
    unset _UPKG_NPM_NPX_STDOUT _UPKG_NPM_NPX_STDERR _UPKG_NPM_NPX_DIAGNOSTIC
    _upkg_record_cleanup_result "$rc" 'npx cache preview failed'
    if (( rc != 0 )) && _upkg_npm_npx_cache_unsupported "$output"; then
      print 'This npm release does not support the npx cache subcommand; upgrade npm to enable npx cache cleanup.'
    fi

    _upkg_print_cleanup_phase 'npm cache'
    print 'would run: npm cache verify'
    (( succeeded++ ))
    _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
    return $?
  fi

  _upkg_run_npm_npx_cache_command ls
  rc=$?
  output=${_UPKG_NPM_NPX_DIAGNOSTIC:-}
  listing=${_UPKG_NPM_NPX_STDOUT:-}
  unset _UPKG_NPM_NPX_STDOUT _UPKG_NPM_NPX_STDERR _UPKG_NPM_NPX_DIAGNOSTIC

  if (( rc != 0 )); then
    npx_failure_detail='npx cache listing failed'
    if _upkg_npm_npx_cache_unsupported "$output"; then
      npx_unsupported=1
      npx_failure_detail='npx cache cleanup is unsupported'
      print 'This npm release does not support the npx cache subcommand; upgrade npm to enable npx cache cleanup.'
    fi
    _upkg_record_cleanup_result "$rc" "$npx_failure_detail"
  elif [ -z "$listing" ]; then
    print 'No npx cache entries found.'
    _upkg_record_cleanup_result 0 ''
  else
    for line in ${(f)listing}; do
      [ -n "$line" ] || continue
      if [[ $line != *:* ]]; then
        parse_failed=1
        break
      fi

      key=${line%%:*}
      case $key in
        ''|-*|*[![:alnum:]_-]*)
          parse_failed=1
          break
          ;;
      esac
      npx_keys+=("$key")
    done

    if (( parse_failed || ${#npx_keys[@]} == 0 )); then
      print -u2 -- 'Could not safely parse npm npx cache keys; no npx entries were removed.'
      _upkg_record_cleanup_result 1 'npx cache listing could not be parsed'
    else
      _upkg_run_cleanup_step 'npx cache cleanup failed' npm cache npx rm "${npx_keys[@]}"
    fi
  fi

  _upkg_print_cleanup_phase 'npm cache'
  verify_failures_before=$failed
  _upkg_run_cleanup_step 'npm cache verify failed' npm cache verify
  if (( npx_unsupported && failed == verify_failures_before )); then
    failures[-1]='npx cache cleanup is unsupported; npm cache verified'
  fi

  _upkg_finish_cleanup_result "$succeeded" "$failed" "${(j:; :)failures}"
}

