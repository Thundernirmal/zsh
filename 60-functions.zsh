# Useful shell functions.

# Extract any archive
extract() {
  if [ -z "$1" ]; then
    echo "Usage: extract <file>"
    return 1
  fi
  if [ ! -f "$1" ]; then
    echo "'$1' is not a valid file"
    return 1
  fi
  case $1 in
    *.tar.bz2)   tar xjf "$1" ;;
    *.tar.gz)    tar xzf "$1" ;;
    *.tar.xz)    tar xJf "$1" ;;
    *.tar.zst)   tar --zstd -xf "$1" ;;
    *.bz2)
      command -v bunzip2 >/dev/null 2>&1 || { echo "bunzip2 is required to extract '$1'"; return 1; }
      bunzip2 "$1"
      ;;
    *.rar)
      command -v unrar >/dev/null 2>&1 || { echo "unrar is required to extract '$1'"; return 1; }
      unrar x "$1"
      ;;
    *.gz)
      command -v gunzip >/dev/null 2>&1 || { echo "gunzip is required to extract '$1'"; return 1; }
      gunzip "$1"
      ;;
    *.tar)       tar xf "$1" ;;
    *.tbz2)      tar xjf "$1" ;;
    *.tgz)       tar xzf "$1" ;;
    *.tzst)      tar --zstd -xf "$1" ;;
    *.zip)
      command -v unzip >/dev/null 2>&1 || { echo "unzip is required to extract '$1'"; return 1; }
      unzip "$1"
      ;;
    *.Z)
      command -v uncompress >/dev/null 2>&1 || { echo "uncompress is required to extract '$1'"; return 1; }
      uncompress "$1"
      ;;
    *.7z)
      command -v 7z >/dev/null 2>&1 || { echo "7z is required to extract '$1'"; return 1; }
      7z x "$1"
      ;;
    *)           echo "'$1' cannot be extracted via extract()"; return 1 ;;
  esac
}

# Create directory and cd into it
mkcd() { command mkdir -p "$1" && cd "$1"; }

# Find files by name
ff() {
  if [ -z "$1" ]; then
    echo "Usage: ff <pattern> [path]"
    return 1
  fi

  local pattern=$1
  local search_root=${2:-.}

  if [ ! -d "$search_root" ]; then
    echo "'$search_root' is not a directory"
    return 1
  fi

  if command -v fd >/dev/null 2>&1; then
    fd --hidden --follow --glob --ignore-case -- "*$pattern*" "$search_root"
  elif command -v fdfind >/dev/null 2>&1; then
    fdfind --hidden --follow --glob --ignore-case -- "*$pattern*" "$search_root"
  else
    command find "$search_root" -iname "*$pattern*" 2>/dev/null
  fi
}

# Find text in files (uses ripgrep if available, falls back to grep)
ft() {
  if [ -z "$1" ]; then
    echo "Usage: ft <pattern> [path]"
    return 1
  fi

  if command -v rg >/dev/null 2>&1; then
    rg --color=always -- "$1" "${2:-.}"
  else
    command grep -rnI --color=auto -- "$1" "${2:-.}" 2>/dev/null
  fi
}

# Fuzzy kill process
fkill() {
  if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf is required for fkill"
    return 1
  fi

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "fkill requires an interactive terminal"
    return 1
  fi

  local signal=${1:-9}
  local selected pid
  local -a pids

  signal=${signal#-}
  selected=$(
    ps -ef | sed 1d | awk '
      {
        pid = $2
        $1 = $2 = $3 = $4 = $5 = $6 = $7 = ""
        sub(/^ +/, "")
        print pid "\t" $0
      }
    ' | fzf -m --delimiter=$'\t' --with-nth=2.. --header="Select process(es) to kill with SIG${signal}"
  ) || return 0

  while IFS=$'\t' read -r pid _; do
    [ -n "$pid" ] && pids+=("$pid")
  done <<< "$selected"

  (( ${#pids[@]} > 0 )) || return 0
  kill "-$signal" "${pids[@]}"
}

# Quick HTTP header check
headers() {
  if [ -z "$1" ]; then
    echo "Usage: headers <url>"
    return 1
  fi

  curl -sIL -- "$1"
}

# Preview file (uses bat if available)
peek() {
  if [ -z "$1" ]; then
    echo "Usage: peek <file>"
    return 1
  fi

  if command -v bat >/dev/null 2>&1; then
    bat --style=numbers --paging=never -- "$1"
  else
    command cat -- "$1"
  fi
}

# Disk usage summary for current directory
dusage() {
  local target=${1:-.}
  local limit=${2:-20}
  local -a entries

  if [ ! -d "$target" ]; then
    echo "'$target' is not a directory"
    return 1
  fi

  case $limit in
    ''|*[!0-9]*)
      echo "Usage: dusage [path] [count]"
      return 1
      ;;
  esac

  entries=( "$target"/*(DN) )
  if (( ${#entries[@]} == 0 )); then
    echo "No entries found in '$target'"
    return 0
  fi

  du -sh -- "${entries[@]}" 2>/dev/null | sort -rh | head -n "$limit"
}

# Largest files in current directory tree
bigfiles() {
  local target=${1:-.}
  local limit=${2:-20}

  if [ ! -e "$target" ]; then
    echo "'$target' does not exist"
    return 1
  fi

  case $limit in
    ''|*[!0-9]*)
      echo "Usage: bigfiles [path] [count]"
      return 1
      ;;
  esac

  command find "$target" -type f -exec du -h {} + 2>/dev/null | sort -rh | head -n "$limit"
}

# Jump to the root of the current git repository
croot() {
  local root

  root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Not in a git repo"
    return 1
  }

  cd "$root" || return
}

# Print PATH one entry per line
path() {
  print -l -- ${(s/:/)PATH}
}

# Fuzzy-pick and checkout a git branch
fbr() {
  if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf is required for fbr"
    return 1
  fi

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "fbr requires an interactive terminal"
    return 1
  fi

  git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "Not in a git repo"
    return 1
  }

  local selection branch local_branch
  selection=$(
    git for-each-ref --sort=-committerdate \
      --format=$'%(refname:short)\t%(committerdate:relative)\t%(subject)' \
      refs/heads refs/remotes |
      command grep -v $'^[^[:space:]]+/HEAD\t' |
      fzf --ansi --height=50% --delimiter=$'\t' --with-nth=1,2,3 \
        --prompt='Branch> ' \
        --preview 'git log --oneline --decorate --color=always -20 {1}' \
        --preview-window=right,60%,border-left,wrap
  ) || return 0

  branch=${selection%%$'\t'*}

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout "$branch"
    return
  fi

  if git show-ref --verify --quiet "refs/remotes/$branch"; then
    local_branch=${branch#*/}
    if git show-ref --verify --quiet "refs/heads/$local_branch"; then
      git checkout "$local_branch"
    else
      git checkout --track "$branch"
    fi
    return
  fi

  echo "Branch '$branch' was not found"
  return 1
}

# Thin apt-like wrapper around nix profile with optional fzf pickers.
if command -v nix >/dev/null 2>&1; then
  _npkg_nix() {
    command nix --extra-experimental-features "nix-command flakes" "$@"
  }

  _npkg_usage() {
    print 'Usage: npkg <command> [args]'
    print ''
    print 'Commands:'
    print '  add [pkg ...]        Add package(s); with no args opens an fzf picker'
    print '  install [pkg ...]    Alias for add'
    print '  find [query]         Fuzzy-pick nixpkgs attribute names and add selections'
    print '  search <query>       Run a plain nixpkgs search with descriptions'
    print '  list                 List packages in the current profile'
    print '  remove [pkg ...]     Remove package(s); with no args opens an fzf picker'
    print '  outdated             Show available package upgrades before running upgrade'
    print '  refresh              Rebuild the cached nixpkgs attribute index'
    print '  upgrade [pkg ...]    Upgrade all packages or only the named ones'
    print '  help                 Show this help text'
    print ''
    print 'Examples:'
    print '  npkg add bat'
    print '  npkg find nvim'
    print '  npkg remove'
    print '  npkg outdated'
    print '  npkg refresh'
    print '  npkg upgrade'
    print ''
    print 'Notes:'
    print '  - Bare install names are expanded to nixpkgs#<name>'
    print '  - npkg find searches a cached list of nixpkgs attribute names'
    print '  - npkg refresh and outdated need jq'
    print '  - Interactive add/find/remove needs jq and fzf'
    print '  - Advanced nix flags can be passed through by calling nix directly'
  }

  _npkg_current_system() {
    _npkg_nix eval --impure --raw --expr 'builtins.currentSystem'
  }

  _npkg_attr_cache_file() {
    emulate -L zsh

    local system cache_dir

    system=$(_npkg_current_system) || return 1
    cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/npkg

    print -r -- "${cache_dir}/nixpkgs-attrs-${system}.txt"
  }

  _npkg_cache_is_stale() {
    local cache_file=$1

    if [ ! -s "$cache_file" ]; then
      return 0
    fi

    [ -n "$(command find "$cache_file" -mtime +1 2>/dev/null)" ]
  }

  _npkg_refresh_index() {
    emulate -L zsh
    setopt pipefail

    local system cache_dir cache_file error_file

    if ! command -v jq >/dev/null 2>&1; then
      echo "jq is required for npkg refresh"
      return 1
    fi

    system=$(_npkg_current_system) || return 1
    cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/npkg
    cache_file="${cache_dir}/nixpkgs-attrs-${system}.txt"
    error_file="${cache_file}.err"

    command mkdir -p "$cache_dir" || return 1

    _npkg_nix eval --json "nixpkgs#legacyPackages.${system}" --apply builtins.attrNames 2>"$error_file" |
      command jq -r '.[]' > "${cache_file}.tmp" || {
        [ -f "${cache_file}.tmp" ] && command rm -f "${cache_file}.tmp"
        if [ -s "$error_file" ]; then
          command cat "$error_file"
          command rm -f "$error_file"
        fi
        return 1
      }

    command mv "${cache_file}.tmp" "$cache_file" || return 1
    command rm -f "$error_file"
    print -r -- "$cache_file"
  }

  _npkg_attr_index() {
    emulate -L zsh

    local cache_file

    cache_file=$(_npkg_attr_cache_file) || return 1

    if _npkg_cache_is_stale "$cache_file"; then
      if [ -f "$cache_file" ]; then
        print -u2 -- 'Refreshing nixpkgs attribute cache...'
      else
        print -u2 -- 'Building nixpkgs attribute cache...'
      fi

      _npkg_refresh_index >/dev/null || return 1
    fi

    print -r -- "$cache_file"
  }

  _npkg_require_picker() {
    local action=$1

    if ! command -v jq >/dev/null 2>&1; then
      echo "jq is required for interactive npkg ${action}"
      echo "Install jq or use non-interactive commands like 'npkg search <query>'"
      return 1
    fi

    if ! command -v fzf >/dev/null 2>&1; then
      echo "fzf is required for interactive npkg ${action}"
      return 1
    fi

    if [ ! -t 0 ] || [ ! -t 1 ]; then
      echo "Interactive npkg ${action} requires a terminal"
      return 1
    fi
  }

  _npkg_pick_installables() {
    emulate -L zsh

    local cache_file selection attr query
    local -a installables

    _npkg_require_picker 'install' || return 1

    query="${(j: :)@}"
    cache_file=$(_npkg_attr_index) || return 1

    selection=$(
      command cat "$cache_file" |
        command fzf -m \
          --prompt='Nix install> ' \
          --query="$query" \
          --header='Type to filter attribute names, Tab marks packages, Enter adds' \
          --preview '
            attr={}
            printf "\033[1;36mAttr:\033[0m %s\n" "$attr"
            printf "\033[1;36mInstall ref:\033[0m nixpkgs#%s\n\n" "$attr"
            meta_json=$(command nix --extra-experimental-features "nix-command flakes" \
              eval --json --apply "p: { v = p.version or \"\"; d = p.meta.description or \"\"; h = p.meta.homepage or \"\"; }" "nixpkgs#$attr" 2>/dev/null || echo "{}")

            desc=$(echo "$meta_json" | command jq -r ".d | select(. != \"\") // empty")
            ver=$(echo "$meta_json" | command jq -r ".v | select(. != \"\") // empty")
            hp=$(echo "$meta_json" | command jq -r ".h | select(. != \"\") // empty")

            if [ -n "$desc" ]; then
              printf "\033[1;33mDescription:\033[0m\n%s\n\n" "$desc"
            else
              printf "\033[2m(no description available)\033[0m\n\n"
            fi

            if [ -n "$ver" ]; then
              printf "\033[1;33mVersion:\033[0m %s\n" "$ver"
            fi

            if [ -n "$hp" ]; then
              printf "\033[1;33mHomepage:\033[0m %s\n" "$hp"
            fi
          ' \
          --preview-window=right,45%,border-left,wrap
    ) || return 0

    while IFS= read -r attr; do
      [ -n "$attr" ] && installables+=("nixpkgs#$attr")
    done <<< "$selection"

    (( ${#installables[@]} > 0 )) || return 0
    _npkg_nix profile add "${installables[@]}"
  }

  _npkg_remove_picker() {
    emulate -L zsh
    setopt pipefail

    local candidates selection
    local -a targets

    _npkg_require_picker 'remove' || return 1

    candidates=$(
      _npkg_nix profile list --json |
        command jq -r '
          def clean_text:
            tostring
            | gsub("[\r\n\t]+"; " ")
            | gsub("  +"; " ");

          def manifest_entries:
            if (.elements | type) == "object" then
              .elements
              | to_entries
              | sort_by(.key)
              | map(select(.value.active // true))
              | .[]
              | {
                  target: .key,
                  name: .key,
                  attr: (.value.attrPath // ""),
                  source: (.value.originalUrl // .value.originalUri // .value.url // .value.uri // "")
                }
            elif (.elements | type) == "array" then
              .elements[]
              | select(.active // true)
              | {
                  target: (.storePaths[0] // .attrPath // ""),
                  name: ((.attrPath // (.storePaths[0] // "")) | split(".")[-1]),
                  attr: (.attrPath // ""),
                  source: (.originalUrl // .originalUri // .url // .uri // "")
                }
            else
              empty
            end;

          manifest_entries
          | select(.target != "")
          | [
              .target,
              .name,
              .attr,
              (.source | clean_text)
            ]
          | @tsv
        '
    ) || return 1

    if [ -z "$candidates" ]; then
      echo "No packages are installed in the current Nix profile"
      return 0
    fi

    selection=$(
      print -r -- "$candidates" |
        command fzf -m --delimiter=$'\t' --with-nth=2,3,4 \
          --prompt='Nix remove> ' \
          --header='Tab marks packages, Enter removes' \
          --preview 'printf "Name: %s\nAttr: %s\nSource: %s\n" {2} {3} {4}' \
          --preview-window=right,60%,border-left,wrap
    ) || return 0

    while IFS=$'\t' read -r target _; do
      [ -n "$target" ] && targets+=("$target")
    done <<< "$selection"

    (( ${#targets[@]} > 0 )) || return 0
    _npkg_nix profile remove "${targets[@]}"
  }

  _npkg_outdated() {
    emulate -L zsh
    setopt pipefail NO_MONITOR NO_NOTIFY

    if ! command -v jq >/dev/null 2>&1; then
      echo "jq is required for npkg outdated"
      return 1
    fi

    local profile_json pkg_count tmp_dir
    local -a names attrs installed_versions

    profile_json=$(_npkg_nix profile list --json 2>/dev/null) || {
      echo "Failed to read profile"
      return 1
    }

    # Extract name, attrPath last segment, and store-path-derived version
    # for each nixpkgs-sourced element.
    # version_from_path strips known Nix multi-output suffixes (man, lib,
    # dev, doc, info, bin, out, debug, static) so that e.g.
    # "tree-2.3.1-man" yields "2.3.1" instead of "2.3.1-man".
    local entry_data
    entry_data=$(
      print -r -- "$profile_json" | command jq -r '
        def version_from_path:
          split("/")[-1]            # basename
          | split("-")              # split on hyphens
          # strip known Nix multi-output suffixes from the end
          | if .[-1] | test("^(out|lib|dev|man|doc|info|bin|static|debug|py)$")
            then .[:-1] else . end
          | . as $parts
          | (length - 1) as $last
          | reduce range($last; 0; -1) as $i (
              null;
              if . == null and ($parts[$i] | test("^[0-9]")) then $i else . end
            )
          | if . then [$parts[.:][] ] | join("-") else "??" end;

        if (.elements | type) == "object" then
          .elements | to_entries[]
          | select(.value.originalUrl // "" | test("nixpkgs"; "i"))
          | select(.value.active // true)
          | .key as $name
          | (.value.attrPath // "") as $attr
          | ($attr | split(".")[-1]) as $short
          | (.value.storePaths[0] // "") as $sp
          | ($sp | version_from_path) as $ver
          | [$name, $short, $ver] | @tsv
        elif (.elements | type) == "array" then
          .elements[]
          | select(.active // true)
          | select((.originalUrl // .url // "") | test("nixpkgs"; "i"))
          | (.attrPath // "") as $attr
          | ($attr | split(".")[-1]) as $name
          | (.storePaths[0] // "") as $sp
          | ($sp | version_from_path) as $ver
          | [$name, $name, $ver] | @tsv
        else
          empty
        end
      '
    ) || return 1

    if [ -z "$entry_data" ]; then
      echo "No nixpkgs packages found in the current profile"
      return 0
    fi

    # Read entries into arrays
    while IFS=$'\t' read -r name attr ver; do
      [ -z "$name" ] && continue
      names+=("$name")
      attrs+=("$attr")
      installed_versions+=("$ver")
    done <<< "$entry_data"

    pkg_count=${#names[@]}
    if (( pkg_count == 0 )); then
      echo "No nixpkgs packages found in the current profile"
      return 0
    fi

    echo "Checking $pkg_count package(s) for updates..."

    # Evaluate latest versions in parallel via temp files
    tmp_dir=$(command mktemp -d) || return 1
    trap "command rm -rf '$tmp_dir'" INT TERM

    local max_jobs=8 running=0 idx attr_name
    for (( idx = 1; idx <= pkg_count; idx++ )); do
      attr_name="${attrs[$idx]}"
      (
        local latest
        latest=$(_npkg_nix eval --raw "nixpkgs#${attr_name}.version" 2>/dev/null) || latest="??"
        print -r -- "$latest" > "${tmp_dir}/${idx}"
      ) &
      (( running++ ))
      if (( running >= max_jobs )); then
        wait
        running=0
      fi
    done
    wait

    # Collect results and build output
    local -a latest_versions
    local upgrades=0
    for (( idx = 1; idx <= pkg_count; idx++ )); do
      if [ -f "${tmp_dir}/${idx}" ]; then
        latest_versions+=("$(< "${tmp_dir}/${idx}")")
      else
        latest_versions+=("??")
      fi
    done

    # Print table
    local name inst avail marker
    printf '\n'
    printf '\033[1m%-25s %-20s %-20s %s\033[0m\n' 'Package' 'Installed' 'Available' ''
    printf '%-25s %-20s %-20s %s\n' '───────' '─────────' '─────────' ''

    for (( idx = 1; idx <= pkg_count; idx++ )); do
      name="${names[$idx]}"
      inst="${installed_versions[$idx]}"
      avail="${latest_versions[$idx]}"

      if [ "$inst" = "??" ] || [ "$avail" = "??" ]; then
        marker='—'
      elif [ "$inst" = "$avail" ]; then
        marker='\033[32m✓\033[0m'
      else
        marker='\033[33m⬆\033[0m'
        (( upgrades++ ))
      fi

      printf '%-25s %-20s %-20s %b\n' "$name" "$inst" "$avail" "$marker"
    done

    printf '\n'
    if (( upgrades > 0 )); then
      printf '\033[33m%d upgrade(s) available.\033[0m Run \033[1mnpkg upgrade\033[0m to apply.\n' "$upgrades"
    else
      printf '\033[32mEverything is up to date.\033[0m\n'
    fi

    command rm -rf "$tmp_dir"
    trap - INT TERM
  }

  npkg() {
    emulate -L zsh

    local cmd=${1:-help}
    local installable
    local -a expanded

    if (( $# > 0 )); then
      shift
    fi

    case $cmd in
      install|add|i)
        if (( $# == 0 )); then
          _npkg_pick_installables
          return
        fi

        if [[ $1 == -* ]]; then
          _npkg_nix profile add "$@"
          return
        fi

        for installable in "$@"; do
          case $installable in
            *'#'*|*':'*|/*|./*|../*) expanded+=("$installable") ;;
            *) expanded+=("nixpkgs#$installable") ;;
          esac
        done

        _npkg_nix profile add "${expanded[@]}"
        ;;
      find|pick|fzf)
        _npkg_pick_installables "$@"
        ;;
      search|s)
        if (( $# == 0 )); then
          echo "Usage: npkg search <query>"
          return 1
        fi

        if [[ $1 == -* ]]; then
          _npkg_nix search "$@"
        else
          _npkg_nix search nixpkgs "$@"
        fi
        ;;
      list|ls)
        _npkg_nix profile list "$@"
        ;;
      refresh)
        _npkg_refresh_index >/dev/null || return 1
        echo 'Refreshed nixpkgs attribute cache'
        ;;
      remove|rm|uninstall|delete)
        if (( $# == 0 )); then
          _npkg_remove_picker
        else
          _npkg_nix profile remove "$@"
        fi
        ;;
      outdated|check|diff)
        _npkg_outdated
        ;;
      upgrade|up|update)
        if (( $# == 0 )); then
          _npkg_nix profile upgrade --all
        else
          _npkg_nix profile upgrade "$@"
        fi
        ;;
      help|-h|--help)
        _npkg_usage
        ;;
      *)
        echo "Unknown npkg command: $cmd"
        _npkg_usage
        return 1
        ;;
    esac
  }
fi
