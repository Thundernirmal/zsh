#!/bin/sh

set -u

missing_required=""
missing_optional=""
fzf_min_version=0.68.0
fzf_min_major=0
fzf_min_minor=68
fzf_min_patch=0
fzf_problem=0

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

record_missing() {
  kind=$1
  name=$2

  if [ "$kind" = "required" ]; then
    missing_required="$missing_required $name"
  else
    missing_optional="$missing_optional $name"
  fi
}

check_cmd() {
  name=$1
  kind=$2

  if have_cmd "$name"; then
    printf 'ok: %s\n' "$name"
  else
    printf 'missing %s: %s\n' "$kind" "$name"
    record_missing "$kind" "$name"
  fi
}

check_any_cmd() {
  display=$1
  kind=$2
  shift 2

  for name in "$@"; do
    if have_cmd "$name"; then
      printf 'ok: %s\n' "$display"
      return 0
    fi
  done

  printf 'missing %s: %s\n' "$kind" "$display"
  record_missing "$kind" "$display"
}

check_fzf() {
  if ! have_cmd fzf; then
    fzf_problem=1
    printf 'missing required: fzf (minimum %s)\n' "$fzf_min_version"
    record_missing required "fzf>=$fzf_min_version"
    return
  fi

  fzf_version_output=$(fzf --version 2>/dev/null)
  fzf_version_status=$?
  if [ "$fzf_version_status" -ne 0 ]; then
    fzf_problem=1
    printf 'unsupported required: fzf version check failed (minimum %s)\n' "$fzf_min_version"
    record_missing required "fzf>=$fzf_min_version"
    return
  fi

  old_ifs=$IFS
  IFS='
'
  set -- $fzf_version_output
  IFS=$old_ifs
  fzf_version_line=${1-}
  set -- $fzf_version_line
  fzf_version=${1-}

  case $fzf_version in
    [0-9]*-*)
      fzf_problem=1
      printf 'unsupported required: fzf %s is a prerelease (minimum %s)\n' "$fzf_version" "$fzf_min_version"
      record_missing required "fzf>=$fzf_min_version"
      return
      ;;
    ''|*[!0-9.]*|.*|*.|*..*)
      fzf_problem=1
      printf 'unsupported required: fzf has an unparseable version (minimum %s)\n' "$fzf_min_version"
      record_missing required "fzf>=$fzf_min_version"
      return
      ;;
  esac

  old_ifs=$IFS
  IFS=.
  set -- $fzf_version
  IFS=$old_ifs
  if [ "$#" -ne 2 ] && [ "$#" -ne 3 ]; then
    fzf_problem=1
    printf 'unsupported required: fzf has an unparseable version (minimum %s)\n' "$fzf_min_version"
    record_missing required "fzf>=$fzf_min_version"
    return
  fi

  fzf_major=$1
  fzf_minor=$2
  fzf_patch=${3:-0}
  case "$fzf_major$fzf_minor$fzf_patch" in
    ''|*[!0-9]*)
      fzf_problem=1
      printf 'unsupported required: fzf has an unparseable version (minimum %s)\n' "$fzf_min_version"
      record_missing required "fzf>=$fzf_min_version"
      return
      ;;
  esac
  if [ "${#fzf_major}" -gt 9 ] || [ "${#fzf_minor}" -gt 9 ] || [ "${#fzf_patch}" -gt 9 ]; then
    fzf_problem=1
    printf 'unsupported required: fzf has an unparseable version (minimum %s)\n' "$fzf_min_version"
    record_missing required "fzf>=$fzf_min_version"
    return
  fi

  if [ "$fzf_major" -gt "$fzf_min_major" ] ||
    { [ "$fzf_major" -eq "$fzf_min_major" ] && [ "$fzf_minor" -gt "$fzf_min_minor" ]; } ||
    { [ "$fzf_major" -eq "$fzf_min_major" ] && [ "$fzf_minor" -eq "$fzf_min_minor" ] && [ "$fzf_patch" -ge "$fzf_min_patch" ]; }; then
    printf 'ok: fzf %s (minimum %s)\n' "$fzf_version" "$fzf_min_version"
    return
  fi

  printf 'unsupported required: fzf %s (minimum %s)\n' "$fzf_version" "$fzf_min_version"
  fzf_problem=1
  record_missing required "fzf>=$fzf_min_version"
}

detect_manager() {
  for manager in apt dnf pacman brew; do
    if have_cmd "$manager"; then
      printf '%s\n' "$manager"
      return 0
    fi
  done

  printf 'unknown\n'
}

print_hints() {
  manager=$(detect_manager)

  printf '\nInstall hints (%s):\n' "$manager"

  case "$manager" in
    apt)
      printf '  sudo apt update\n'
      printf '  sudo apt install zsh git curl iproute2 lsd zoxide tree fd-find jq libsecret-tools\n'
      printf '  Debian/Ubuntu expose bat as batcat; install the expected bat command with one of:\n'
      printf '    nix profile add nixpkgs#bat\n'
      printf '    brew install bat\n'
      printf '  Optional for npkg: install Nix from https://nixos.org/download/\n'
      ;;
    dnf)
      printf '  sudo dnf install zsh git curl iproute lsd zoxide bat tree fd-find jq libsecret\n'
      printf '  Optional for npkg: install Nix from https://nixos.org/download/\n'
      ;;
    pacman)
      printf '  sudo pacman -S zsh git curl iproute2 lsd zoxide bat tree fd jq libsecret\n'
      printf '  Optional for npkg: install Nix from https://nixos.org/download/\n'
      ;;
    brew)
      printf '  brew install zsh git curl lsd zoxide bat tree fd jq libsecret\n'
      printf '  On GNU/Linux, install ss via your distro package for iproute/iproute2.\n'
      printf '  Optional for npkg: install Nix from https://nixos.org/download/\n'
      ;;
    *)
      printf '  Install these commands manually: zsh git curl ss lsd zoxide bat tree fd/fdfind jq secret-tool\n'
      printf '  Optional for npkg: install Nix from https://nixos.org/download/\n'
      ;;
  esac

  if [ "$fzf_problem" -ne 0 ]; then
    printf '  Install fzf %s+ from a current supported package or https://github.com/junegunn/fzf#installation\n' "$fzf_min_version"
  fi
}

printf 'Checking shared Zsh config dependencies...\n\n'

check_cmd zsh required
check_cmd git required
check_cmd curl required
check_cmd ss required
check_cmd lsd required
check_cmd zoxide required
check_fzf
check_cmd bat optional
check_cmd tree optional
check_any_cmd 'fd/fdfind' optional fd fdfind
check_cmd jq optional
check_cmd secret-tool optional
check_cmd nix optional
if have_cmd nix; then
  check_cmd nix-collect-garbage optional
fi

if [ -n "$missing_required" ] || [ -n "$missing_optional" ]; then
  print_hints
fi

if [ -n "$missing_required" ]; then
  printf '\nResult: missing required dependencies:%s\n' "$missing_required"
  exit 1
fi

if [ -n "$missing_optional" ]; then
  printf '\nResult: optional dependencies missing:%s\n' "$missing_optional"
  exit 0
fi

printf '\nResult: all shared dependencies are available.\n'
