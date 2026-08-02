# Command-specific completion definitions.
# Keep all setup behind the compdef guard so shells that have not run compinit
# can source this module without side effects or errors.

if (( $+functions[compdef] )); then
  typeset -ga _ZSH_UPKG_COMMAND_SPECS=(
    'outdated:Show outdated packages'
    'check:Alias for outdated'
    'list:Alias for outdated'
    'search:Search package names'
    'upgrade:Upgrade selected packages'
    'up:Alias for upgrade'
    'update:Alias for upgrade'
    'plan:Preview available upgrades'
    'clean:Remove unused packages and stale caches'
    'managers:Show detected managers and alternates'
    'help:Show usage help'
  )
  typeset -ga _ZSH_UPKG_FLAGS=(
    '--only:Include comma-separated manager IDs'
    '--skip:Exclude comma-separated manager IDs'
    '--sudo:Authorize privileged upgrade and cleanup backends'
    '--dry-run:Preview upgrades or cleanup without changing packages'
    '--help:Show usage help'
  )
  typeset -ga _ZSH_UPKG_MANAGERS=(
    apt dnf pacman paru brew flatpak nix npm
  )
  typeset -ga _ZSH_EXTRACT_EXTENSIONS=(
    tar.bz2 tar.gz tar.xz tar.zst bz2 rar gz tar tbz2 tgz tzst zip Z 7z
  )
  typeset -ga _ZSH_NPKG_COMMAND_SPECS=(
    'add:Add packages or open the package picker'
    'install:Alias for add'
    'i:Alias for add'
    'find:Fuzzy-pick cached nixpkgs attributes'
    'pick:Alias for find'
    'fzf:Alias for find'
    'search:Search nixpkgs with descriptions'
    's:Alias for search'
    'list:List packages in the current profile'
    'ls:Alias for list'
    'remove:Remove packages or open the removal picker'
    'rm:Alias for remove'
    'uninstall:Alias for remove'
    'delete:Alias for remove'
    'outdated:Show available package upgrades'
    'check:Alias for outdated'
    'diff:Alias for outdated'
    'refresh:Rebuild the cached nixpkgs attribute index'
    'upgrade:Upgrade all or selected packages'
    'up:Alias for upgrade'
    'update:Alias for upgrade'
    'help:Show usage help'
  )

  _zsh_upkg_managers() {
    local -a manager_specs
    local manager

    for manager in "${_ZSH_UPKG_MANAGERS[@]}"; do
      manager_specs+=("${manager}[package manager]")
    done

    _values -s , 'package manager' "${manager_specs[@]}"
  }

  _zsh_upkg() {
    local context state state_descr line
    typeset -A opt_args

    _arguments -C -s \
      '(-h --help)'{-h,--help}'[show usage help]' \
      '--only=[include comma-separated manager IDs]:manager list:_zsh_upkg_managers' \
      '--skip=[exclude comma-separated manager IDs]:manager list:_zsh_upkg_managers' \
      '--sudo[authorize privileged upgrade and cleanup backends]' \
      '--dry-run[preview upgrades or cleanup without changing packages]' \
      '1:upkg command:->command' \
      '*:command argument:->argument' && return 0

    case $state in
      command)
        _describe -t commands 'upkg command' _ZSH_UPKG_COMMAND_SPECS
        ;;
      argument)
        case ${line[1]-} in
          search)
            _message 'search query'
            ;;
          *)
            _message 'no additional arguments'
            ;;
        esac
        ;;
    esac
  }

  _zsh_npkg_cached_attributes() {
    emulate -L zsh

    local cache_dir cache_file attribute
    local -A seen
    typeset -ga reply
    reply=()

    cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/npkg
    for cache_file in "$cache_dir"/nixpkgs-attrs-*.txt(N.); do
      [[ -r $cache_file ]] || continue
      while IFS= read -r attribute; do
        [[ -n $attribute && -z ${seen[$attribute]-} ]] || continue
        reply+=("$attribute")
        seen[$attribute]=1
      done < "$cache_file"
    done
  }

  _zsh_npkg_cached_packages() {
    _zsh_npkg_cached_attributes
    (( ${#reply[@]} > 0 )) || return 1
    _wanted packages expl 'cached nixpkgs attribute' compadd -a reply
  }

  _zsh_npkg() {
    local context state state_descr line
    typeset -A opt_args

    _arguments -C \
      '(-h --help)'{-h,--help}'[show usage help]' \
      '1:npkg command:->command' \
      '*:command argument:->argument' && return 0

    case $state in
      command)
        _describe -t commands 'npkg command' _ZSH_NPKG_COMMAND_SPECS
        ;;
      argument)
        case ${line[1]-} in
          add|install|i|find|pick|fzf)
            _zsh_npkg_cached_packages
            ;;
          search|s)
            _message 'search query'
            ;;
          remove|rm|uninstall|delete)
            _message 'package name or profile element'
            ;;
          upgrade|up|update)
            _message 'package name'
            ;;
          *)
            _message 'no additional arguments'
            ;;
        esac
        ;;
    esac
  }

  _zsh_extract() {
    local context state state_descr line
    typeset -A opt_args

    _arguments -C '1:archive file:->archive' '*: :_message "no additional arguments"' && return 0
    [[ $state == archive ]] && _files -g "*.(${(j:|:)_ZSH_EXTRACT_EXTENSIONS})"
  }

  _zsh_peek() {
    _arguments '1:file:_files' '*: :_message "no additional arguments"'
  }

  _zsh_mkcd() {
    _arguments '1:directory:_directories' '*: :_message "no additional arguments"'
  }

  _zsh_find_helper() {
    _arguments '1:search pattern:' '2:search root:_directories' '*: :_message "no additional arguments"'
  }

  _zsh_dusage() {
    _arguments '1:directory:_directories' '2:result count:_guard "[0-9]#" "result count"' '*: :_message "no additional arguments"'
  }

  _zsh_bigfiles() {
    _arguments '1:file or directory:_files' '2:result count:_guard "[0-9]#" "result count"' '*: :_message "no additional arguments"'
  }

  _zsh_fkill() {
    _arguments '1:signal:_signals' '*: :_message "no additional arguments"'
  }

  _zsh_headers() {
    _arguments '1:URL:_message "URL"' '*: :_message "no additional arguments"'
  }

  _zsh_zhelp_commands() {
    local id
    local -a command_specs

    if (( ! $+parameters[_ZSH_HELP_ORDER] )); then
      _message 'command or search query'
      return 0
    fi

    for id in "${_ZSH_HELP_ORDER[@]}"; do
      command_specs+=("${id}:${_ZSH_HELP_SUMMARY[$id]}")
    done

    _describe -t commands 'zhelp command' command_specs
  }

  _zsh_zhelp() {
    _arguments \
      '(-h --help)'{-h,--help}'[show zhelp usage]' \
      '--all[include commands unavailable on this machine]' \
      '--plain[force deterministic plain-text output]' \
      '1:command or search query:_zsh_zhelp_commands' \
      '*:additional search term:'
  }

  _zsh_no_arguments() {
    _message 'no arguments'
  }

  compdef _zsh_upkg upkg
  compdef _zsh_extract extract
  compdef _zsh_peek peek
  compdef _zsh_mkcd mkcd
  compdef _zsh_find_helper ff ft
  compdef _zsh_dusage dusage
  compdef _zsh_bigfiles bigfiles
  compdef _zsh_fkill fkill
  compdef _zsh_headers headers
  compdef _zsh_zhelp zhelp
  compdef _zsh_no_arguments fbr croot path ports myip gitcount fanprofile tips

  if (( $+functions[npkg] )); then
    compdef _zsh_npkg npkg
  fi
fi
