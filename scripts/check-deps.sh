#!/bin/sh

set -u

missing_required=""
missing_optional=""

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
      printf '  sudo apt install zsh git lsd zoxide fzf bat tree fd-find jq\n'
      printf '  Optional for npkg: install Nix from https://nixos.org/download/\n'
      ;;
    dnf)
      printf '  sudo dnf install zsh git lsd zoxide fzf bat tree fd-find jq\n'
      printf '  Optional for npkg: install Nix from https://nixos.org/download/\n'
      ;;
    pacman)
      printf '  sudo pacman -S zsh git lsd zoxide fzf bat tree fd jq\n'
      printf '  Optional for npkg: install Nix from https://nixos.org/download/\n'
      ;;
    brew)
      printf '  brew install zsh git lsd zoxide fzf bat tree fd jq\n'
      printf '  Optional for npkg: install Nix from https://nixos.org/download/\n'
      ;;
    *)
      printf '  Install these commands manually: zsh git lsd zoxide fzf bat tree fd/fdfind jq\n'
      printf '  Optional for npkg: install Nix from https://nixos.org/download/\n'
      ;;
  esac
}

printf 'Checking shared Zsh config dependencies...\n\n'

check_cmd zsh required
check_cmd git required
check_cmd lsd required
check_cmd zoxide required
check_cmd fzf required
check_cmd bat optional
check_cmd tree optional
check_any_cmd 'fd/fdfind' optional fd fdfind
check_cmd jq optional
check_cmd nix optional

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
