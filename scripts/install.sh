#!/bin/sh

set -u

repo=${ZSH_INSTALL_REPO:-Thundernirmal/zsh}
tag=${ZSH_INSTALL_TAG:-latest}
target_dir=${ZSH_INSTALL_DIR:-"$HOME/.config/zsh"}
zshrc=${ZSH_INSTALL_ZSHRC:-"$HOME/.zshrc"}
archive_url=${ZSH_INSTALL_ARCHIVE_URL:-}
update_zshrc=1

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Install the shared Zsh config from a GitHub release archive.

Options:
  --repo owner/name      GitHub repo to install from (default: Thundernirmal/zsh)
  --tag tag             Release tag to install (default: latest)
  --dir path            Install directory (default: $HOME/.config/zsh)
  --zshrc path          Zsh rc file to update (default: $HOME/.zshrc)
  --no-zshrc            Do not append the source block to .zshrc
  --archive-url url     Download this archive URL instead of GitHub release archive
  -h, --help            Show this help

Environment overrides:
  ZSH_INSTALL_REPO, ZSH_INSTALL_TAG, ZSH_INSTALL_DIR, ZSH_INSTALL_ZSHRC,
  ZSH_INSTALL_ARCHIVE_URL
EOF
}

die() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

quote_sh() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g; 1s/^/'/; \$s/\$/'/"
}

strip_trailing_slashes() {
  path=$1

  while [ "$path" != "/" ] && [ "${path%/}" != "$path" ]; do
    path=${path%/}
  done

  printf '%s\n' "$path"
}

zshrc_sources_file() {
  source_file=$1
  quoted_source=$(quote_sh "$source_file")

  [ -f "$zshrc" ] || return 1

  while IFS= read -r line; do
    case $line in
      "source $quoted_source"|"  source $quoted_source"|". $quoted_source"|"  . $quoted_source")
        return 0
        ;;
    esac
  done < "$zshrc"

  return 1
}

resolve_latest_tag() {
  latest_url="https://github.com/$repo/releases/latest"
  final_url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "$latest_url") || {
    die "failed to resolve latest release for $repo"
  }

  case $final_url in
    */releases/tag/*)
      printf '%s\n' "${final_url##*/releases/tag/}"
      ;;
    *)
      die "could not determine latest release tag from $final_url"
      ;;
  esac
}

append_zshrc_block() {
  source_file=$1
  marker='shared zsh config'
  start_marker="# >>> $marker >>>"
  end_marker="# <<< $marker <<<"

  [ "$update_zshrc" -eq 1 ] || return 0

  if zshrc_sources_file "$source_file"; then
    printf 'zshrc already sources this config: %s\n' "$zshrc"
    return 0
  fi

  zshrc_dir=$(dirname "$zshrc")
  mkdir -p "$zshrc_dir" || die "failed to create $zshrc_dir"

  quoted_source=$(quote_sh "$source_file")

  if [ -f "$zshrc" ] && grep -F -- "$start_marker" "$zshrc" >/dev/null 2>&1; then
    start_count=$(grep -F -x -c -- "$start_marker" "$zshrc" || true)
    end_count=$(grep -F -x -c -- "$end_marker" "$zshrc" || true)

    if [ "$start_count" != "$end_count" ]; then
      die "found an incomplete managed block in $zshrc; fix the shared zsh config markers before rerunning"
    fi

    tmp_zshrc=$(mktemp "${TMPDIR:-/tmp}/zshrc.XXXXXX") || die "mktemp failed for zshrc update"
    sed "/^# >>> shared zsh config >>>$/,/^# <<< shared zsh config <<<$/d" "$zshrc" > "$tmp_zshrc" || {
      rm -f "$tmp_zshrc"
      die "failed to prepare updated $zshrc"
    }
    cat "$tmp_zshrc" > "$zshrc" || {
      rm -f "$tmp_zshrc"
      die "failed to update $zshrc"
    }
    rm -f "$tmp_zshrc"
  fi

  {
    printf '\n'
    printf '%s\n' "$start_marker"
    printf 'if [ -r %s ]; then\n' "$quoted_source"
    printf '  source %s\n' "$quoted_source"
    printf 'fi\n'
    printf '%s\n' "$end_marker"
  } >> "$zshrc" || die "failed to update $zshrc"

  printf 'Updated zshrc: %s\n' "$zshrc"
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --repo)
      shift
      [ "$#" -gt 0 ] || die "missing value for --repo"
      repo=$1
      ;;
    --repo=*)
      repo=${1#--repo=}
      [ -n "$repo" ] || die "missing value for --repo"
      ;;
    --tag)
      shift
      [ "$#" -gt 0 ] || die "missing value for --tag"
      tag=$1
      ;;
    --tag=*)
      tag=${1#--tag=}
      [ -n "$tag" ] || die "missing value for --tag"
      ;;
    --dir)
      shift
      [ "$#" -gt 0 ] || die "missing value for --dir"
      target_dir=$1
      ;;
    --dir=*)
      target_dir=${1#--dir=}
      [ -n "$target_dir" ] || die "missing value for --dir"
      ;;
    --zshrc)
      shift
      [ "$#" -gt 0 ] || die "missing value for --zshrc"
      zshrc=$1
      ;;
    --zshrc=*)
      zshrc=${1#--zshrc=}
      [ -n "$zshrc" ] || die "missing value for --zshrc"
      ;;
    --archive-url)
      shift
      [ "$#" -gt 0 ] || die "missing value for --archive-url"
      archive_url=$1
      ;;
    --archive-url=*)
      archive_url=${1#--archive-url=}
      [ -n "$archive_url" ] || die "missing value for --archive-url"
      ;;
    --no-zshrc)
      update_zshrc=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

case $repo in
  */*) ;;
  *) die "repo must look like owner/name" ;;
esac

case $target_dir in
  /*) ;;
  *) target_dir=$(pwd -P)/$target_dir ;;
esac
target_dir=$(strip_trailing_slashes "$target_dir")

case $zshrc in
  /*) ;;
  *) zshrc=$(pwd -P)/$zshrc ;;
esac

need_cmd curl
need_cmd tar
need_cmd mktemp
need_cmd sed

if [ "$tag" = "latest" ] && [ -z "$archive_url" ]; then
  tag=$(resolve_latest_tag)
fi

if [ -z "$archive_url" ]; then
  archive_url="https://github.com/$repo/archive/refs/tags/$tag.tar.gz"
fi

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/zsh-install.XXXXXX") || die "mktemp failed"
archive_file="$tmp_dir/release.tar.gz"
extract_dir="$tmp_dir/extract"
backup_dir=''

cleanup() {
  rm -rf "$tmp_dir"
}

trap cleanup EXIT INT TERM

printf 'Installing %s@%s\n' "$repo" "$tag"
printf 'Target: %s\n' "$target_dir"

mkdir -p "$extract_dir" || die "failed to create temporary extraction directory"
curl -fsSL "$archive_url" -o "$archive_file" || die "failed to download $archive_url"
tar -xzf "$archive_file" -C "$extract_dir" || die "failed to extract release archive"

set -- "$extract_dir"/*
[ -e "$1" ] || die "release archive did not contain a top-level directory"
source_dir=$1

[ -f "$source_dir/init.zsh" ] || die "release archive does not look like this zsh config"
[ -d "$source_dir/scripts" ] || die "release archive is missing scripts/"

target_parent=$(dirname "$target_dir")
mkdir -p "$target_parent" || die "failed to create $target_parent"

if [ -e "$target_dir" ]; then
  stamp=$(date +%Y%m%d%H%M%S)
  backup_dir="${target_dir}.backup.${stamp}"
  backup_index=1
  while [ -e "$backup_dir" ]; do
    backup_dir="${target_dir}.backup.${stamp}.${backup_index}"
    backup_index=$((backup_index + 1))
  done
  mv "$target_dir" "$backup_dir" || die "failed to back up existing $target_dir"
  printf 'Backed up existing config: %s\n' "$backup_dir"
fi

mv "$source_dir" "$target_dir" || {
  if [ -n "$backup_dir" ] && [ -e "$backup_dir" ]; then
    mv "$backup_dir" "$target_dir" 2>/dev/null || true
  fi
  die "failed to install into $target_dir"
}

append_zshrc_block "$target_dir/init.zsh"

printf '\nInstalled shared Zsh config.\n'
if [ "$update_zshrc" -eq 1 ]; then
  printf 'Next shell startup will source: %s\n' "$target_dir/init.zsh"
else
  printf 'To load it manually, add this to your .zshrc:\n'
  printf '  source %s\n' "$(quote_sh "$target_dir/init.zsh")"
fi
printf 'Optional dependency check: sh %s/scripts/check-deps.sh\n' "$target_dir"
