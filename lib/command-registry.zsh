# Shared on-demand command metadata. Data only: no tool or backend probes.
# Help and completion consume these same records; workflows remain in GUIDE.md.

typeset -ga _ZSH_HELP_ORDER
typeset -gA _ZSH_HELP_CATEGORY
typeset -gA _ZSH_HELP_SUMMARY
typeset -gA _ZSH_HELP_USAGE
typeset -gA _ZSH_HELP_EXAMPLE
typeset -gA _ZSH_HELP_DEPS
typeset -gA _ZSH_HELP_KIND
typeset -gA _ZSH_COMMAND_CANONICAL _ZSH_COMMAND_MUTATION
typeset -gA _ZSH_HELP_CHECK

_ZSH_HELP_ORDER=()
_ZSH_HELP_CATEGORY=()
_ZSH_HELP_SUMMARY=()
_ZSH_HELP_USAGE=()
_ZSH_HELP_EXAMPLE=()
_ZSH_HELP_DEPS=()
_ZSH_HELP_KIND=()
_ZSH_HELP_CHECK=()
_ZSH_COMMAND_CANONICAL=()
_ZSH_COMMAND_MUTATION=()

_zsh_help_register() {
  emulate -L zsh

  local id=${1-}
  local category=${2-}
  local summary=${3-}
  local usage=${4-}
  local example=${5-}
  local dependencies=${6-}
  local kind=${7-}
  local check=${8-}
  local value

  [[ -n $id && -n $category && -n $summary && -n $usage && -n $example ]] || return 1
  [[ $kind == function || $kind == alias || $kind == action ]] || return 1
  [[ -z ${_ZSH_HELP_CATEGORY[$id]-} ]] || return 1

  for value in "$id" "$category" "$summary" "$usage" "$example" "$dependencies"; do
    [[ $value != *$'\t'* && $value != *$'\n'* && $value != *$'\r'* ]] || return 1
  done

  _ZSH_HELP_ORDER+=("$id")
  _ZSH_HELP_CATEGORY[$id]=$category
  _ZSH_HELP_SUMMARY[$id]=$summary
  _ZSH_HELP_USAGE[$id]=$usage
  _ZSH_HELP_EXAMPLE[$id]=$example
  _ZSH_HELP_DEPS[$id]=${dependencies:-none}
  _ZSH_HELP_KIND[$id]=$kind
  _ZSH_HELP_CHECK[$id]=$check
}

# Navigation
_zsh_help_register '..' Navigation 'Move up one directory' '..' '..' none alias none
_zsh_help_register '...' Navigation 'Move up two directories' '...' '...' none alias none
_zsh_help_register '....' Navigation 'Move up three directories' '....' '....' none alias none
_zsh_help_register '-' Navigation 'Return to the previous directory' '-' '-' none alias none
_zsh_help_register z Navigation 'Jump with zoxide' 'z <query>' 'z projects' zoxide function zoxide
_zsh_help_register zi Navigation 'Pick a zoxide directory' 'zi [query]' 'zi projects' 'zoxide and fzf 0.68.0+' function zoxide-fzf
_zsh_help_register mkcd Navigation 'Create a directory and enter it' 'mkcd <directory>' 'mkcd new-project' none function none
_zsh_help_register croot Navigation 'Enter the Git repository root' 'croot' 'croot' git function git

# Files and search
_zsh_help_register ls Files 'List directory contents' 'ls [path]' 'ls' 'lsd or GNU ls' alias none
_zsh_help_register ll Files 'List all entries with details' 'll [path]' 'll' 'lsd or GNU ls' alias none
_zsh_help_register la Files 'List entries including hidden files' 'la [path]' 'la' 'lsd or GNU ls' alias none
_zsh_help_register lt Files 'Show a three-level directory tree' 'lt [path]' 'lt' 'lsd or tree' alias none
_zsh_help_register cat Files 'Print files with bat highlighting' 'cat <file>' 'cat README.md' bat alias none
_zsh_help_register extract Files 'Unpack a supported archive' 'extract [--keep] [--destination <dir>] <archive>' 'extract archive.tar.gz' 'tar; format-specific unpackers when needed' function none
_zsh_help_register peek Files 'Preview a file with bat or cat' 'peek <file>' 'peek README.md' 'bat or cat' function peek
_zsh_help_register dusage Files 'Rank immediate entries by disk usage' 'dusage [path] [count]' 'dusage . 10' 'GNU du and find' function disk
_zsh_help_register bigfiles Files 'Rank files recursively by size' 'bigfiles [path] [count]' 'bigfiles . 10' 'GNU find and du' function disk
_zsh_help_register grep Search 'Search text with automatic colour' 'grep <pattern> [file ...]' 'grep TODO README.md' 'grep with --color=auto support' alias none
_zsh_help_register diff Files 'Compare files with automatic colour' 'diff <file-a> <file-b>' 'diff before.txt after.txt' 'diff with --color=auto support' alias none
_zsh_help_register ff Search 'Find files by name' 'ff [options] <pattern> [path]' 'ff config .' 'fd, fdfind, or find' function file-search
_zsh_help_register ft Search 'Search file contents' 'ft [options] <pattern> [path]' 'ft TODO .' 'rg or grep' function text-search

# Git
_zsh_help_register glog Git 'Graph the latest 20 commits' 'glog' 'glog' git alias git
_zsh_help_register gpr Git 'Pull with rebase' 'gpr' 'gpr' git alias git
_zsh_help_register gun Git 'Undo the latest commit; keep changes staged' 'gun' 'gun' git alias git
_zsh_help_register gitcount Git 'Count non-merge commits by contributor' 'gitcount' 'gitcount' git function git
_zsh_help_register gcount Git 'Alias for gitcount' 'gcount' 'gcount' git alias git
_zsh_help_register fbr Git 'Pick a branch; enter its worktree or check it out' 'fbr' 'fbr' 'git and fzf 0.68.0+' function git-fzf

# System
_zsh_help_register weather System 'Show the default HTTPS forecast' 'weather' 'weather' curl function curl
_zsh_help_register fkill System 'Pick processes and send a signal' 'fkill [--all] [signal]' 'fkill 15' 'ps and fzf 0.68.0+' function process-fzf
_zsh_help_register headers System 'Print response headers after redirects' 'headers <url>' 'headers https://example.com' curl function curl
_zsh_help_register fanprofile System 'Show the laptop performance profile' 'fanprofile' 'fanprofile' 'Linux ACPI or ASUS WMI profile interface' function fan-profile
_zsh_help_register ports System 'Show listening sockets and processes' 'ports' 'ports' ss function ss
_zsh_help_register myip System 'Show the public IP address' 'myip' 'myip' curl function curl
_zsh_help_register path System 'List PATH entries' 'path' 'path' none function none

# Credentials
_zsh_help_register cgm Security 'Store and load shell credentials securely' 'cgm <command> [credential ...]' 'cgm env OPENAI_KEY' 'secret-tool and a Secret Service provider' function secret-tool
_zsh_help_register cgm-env Security 'Load credentials into this shell' 'cgm env <name ...>' 'cgm env OPENAI_KEY' 'secret-tool and a Secret Service provider' action secret-tool
_zsh_help_register cgm-status Security 'Check exported credential names' 'cgm status' 'cgm status' 'secret-tool' action secret-tool
_zsh_help_register cgm-check Security 'Check Secret Service health without values' 'cgm check' 'cgm check' 'secret-tool and gdbus' action secret-health

# Packages and meta helpers
_zsh_help_register upkg Packages 'Check, search, upgrade, and clean detected managers' 'upkg [command] [args] [flags]' 'upkg search ripgrep --only=apt,nix' 'a supported package manager' function package-manager
_zsh_help_register upkg-plan Packages 'Preview upgrades' 'upkg plan [--only <list>]' 'upkg plan' 'a supported package manager' action package-manager
_zsh_help_register npkg Packages 'Manage the current Nix profile' 'npkg <command> [args]' 'npkg search ripgrep' 'nix; jq and fzf 0.68.0+ for optional workflows' function nix
_zsh_help_register npkg-remove Packages 'Remove packages from the Nix profile' 'npkg remove [package ...]' 'npkg remove' 'nix; jq and fzf 0.68.0+ for optional workflows' action nix
_zsh_help_register G Meta 'Pipe command output to grep' '<command> G <pattern>' 'git log --oneline G fix' grep alias grep
_zsh_help_register L Meta 'Pipe command output to less' '<command> L' 'git diff L' less alias less
_zsh_help_register W Meta 'Pipe command output to a line count' '<command> W' 'git log --oneline W' wc alias wc
_zsh_help_register H Meta 'Pipe command output to head' '<command> H' 'git log --oneline H' head alias head
_zsh_help_register T Meta 'Pipe command output to tail' '<command> T' 'git log --oneline T' tail alias tail
_zsh_help_register NE Meta 'Suppress stderr for one command' '<command> NE' 'optional-command NE' none alias none
_zsh_help_register NUL Meta 'Suppress stdout and stderr for one command' '<command> NUL' 'noisy-command NUL' none alias none
_zsh_help_register zdoctor Meta 'Diagnose setup and integration status' 'zdoctor [--network] [--secrets]' 'zdoctor' none function none
_zsh_help_register tips Meta 'Print one short usage tip' 'tips' 'tips' none function none
_zsh_help_register ztheme Meta 'Inspect or switch shared terminal themes' 'ztheme <list|current|show|use|reset|export> [theme]' 'ztheme use nord' none function none
_zsh_help_register zhelp Meta 'Find commands and queue an example' 'zhelp [--all] [--plain] [query]' 'zhelp package' 'fzf 0.68.0+ for the optional interactive palette' function none

# Canonical command and mutation category are descriptive metadata, never an
# authorization mechanism. Mixed commands require their own argument checks.
local _zsh_registry_id
for _zsh_registry_id in "${_ZSH_HELP_ORDER[@]}"; do
  _ZSH_COMMAND_CANONICAL[$_zsh_registry_id]=$_zsh_registry_id
  _ZSH_COMMAND_MUTATION[$_zsh_registry_id]=read
  case $_zsh_registry_id in
    gcount) _ZSH_COMMAND_CANONICAL[$_zsh_registry_id]=gitcount ;;
    cgm-env|cgm-status|cgm-check) _ZSH_COMMAND_CANONICAL[$_zsh_registry_id]=cgm ;;
    upkg-plan) _ZSH_COMMAND_CANONICAL[$_zsh_registry_id]=upkg ;;
    npkg-remove) _ZSH_COMMAND_CANONICAL[$_zsh_registry_id]=npkg ;;
  esac
  case $_zsh_registry_id in
    extract|mkcd|gpr|gun|fkill|npkg-remove) _ZSH_COMMAND_MUTATION[$_zsh_registry_id]=write ;;
    cgm|upkg|npkg) _ZSH_COMMAND_MUTATION[$_zsh_registry_id]=mixed ;;
    ..|...|....|-|z|zi|croot|fbr|cgm-env|ztheme) _ZSH_COMMAND_MUTATION[$_zsh_registry_id]=session ;;
  esac
done
unset _zsh_registry_id
