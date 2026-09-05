# Trusted lazy files implementations; loaded by functions-catalogue.zsh.

_extract_usage() {
  print 'Usage: extract [--keep] [--destination <dir>] <file>'
  print ''
  print 'Supported archives: tar, zip, rar, 7z, gzip, bzip2, and compress.'
  print 'Archive inputs are kept; bare compressed inputs use native in-place removal.'
  print -r -- '--keep preserves a bare compressed input, and --destination implies keep.'
}

_extract_stream_to() {
  emulate -L zsh

  local output=$1 source=$2 tool=$3 temp rc

  temp=$(command mktemp "${output}.partial.XXXXXX") || {
    print -u2 -r -- "extract: cannot create a temporary output beside '$output'"
    return 1
  }
  {
    command "$tool" -c "$source" >| "$temp" || return $?
    # Same-directory hard-link publication refuses every existing destination,
    # including a dangling symlink, without a check-then-overwrite race.
    command ln -T -- "$temp" "$output" || {
      print -u2 -r -- "extract: cannot publish '$output'; destination must not exist"
      return 1
    }
  } always {
    command rm -f -- "$temp"
  }

}

# Extract any archive. Archive formats retain their input. Bare compressed
# files retain the native decompressor behavior unless --keep or --destination
# is used explicitly.
extract() {
  emulate -L zsh
  setopt localoptions noclobber

  local archive_arg='' destination='' archive output rc arg value
  local -i keep_input=0 options_done=0
  local -a operands tar_args unzip_args

  while (( $# > 0 )); do
    arg=$1
    shift
    if (( ! options_done )); then
      case $arg in
        -h|--help)
          _extract_usage
          return 0
          ;;
        -k|--keep|--keep-input)
          keep_input=1
          continue
          ;;
        -C|--destination|--dest)
          if (( $# == 0 )); then
            print -u2 -r -- 'extract: missing value for --destination'
            _extract_usage >&2
            return 1
          fi
          destination=$1
          shift
          continue
          ;;
        --destination=*|--dest=*)
          destination=${arg#*=}
          [[ -n $destination ]] || {
            print -u2 -r -- 'extract: --destination requires a directory'
            _extract_usage >&2
            return 1
          }
          continue
          ;;
        --)
          options_done=1
          continue
          ;;
        -*)
          print -u2 -r -- "extract: unknown option: $arg"
          _extract_usage >&2
          return 1
          ;;
      esac
    fi
    operands+=("$arg")
  done

  if (( ${#operands[@]} != 1 )); then
    print -u2 -r -- 'extract: expected exactly one archive file'
    _extract_usage >&2
    return 1
  fi
  archive_arg=${operands[1]}
  if [ ! -f "$archive_arg" ]; then
    print -u2 -r -- "'$archive_arg' is not a valid file"
    return 1
  fi
  if [[ -n $destination && ! -d $destination ]]; then
    print -u2 -r -- "extract: destination '$destination' is not a directory"
    return 1
  fi

  archive=${archive_arg:A}
  [[ -n $destination ]] && destination=${destination:A}

  case $archive in
    *.tar.bz2)
      [[ -n $destination ]] && tar_args=(-C "$destination")
      command tar "${tar_args[@]}" -xjf "$archive"
      ;;
    *.tar.gz)
      [[ -n $destination ]] && tar_args=(-C "$destination")
      command tar "${tar_args[@]}" -xzf "$archive"
      ;;
    *.tar.xz)
      [[ -n $destination ]] && tar_args=(-C "$destination")
      command tar "${tar_args[@]}" -xJf "$archive"
      ;;
    *.tar.zst)
      [[ -n $destination ]] && tar_args=(-C "$destination")
      command tar "${tar_args[@]}" --zstd -xf "$archive"
      ;;
    *.tar)
      [[ -n $destination ]] && tar_args=(-C "$destination")
      command tar "${tar_args[@]}" -xf "$archive"
      ;;
    *.tbz2)
      [[ -n $destination ]] && tar_args=(-C "$destination")
      command tar "${tar_args[@]}" -xjf "$archive"
      ;;
    *.tgz)
      [[ -n $destination ]] && tar_args=(-C "$destination")
      command tar "${tar_args[@]}" -xzf "$archive"
      ;;
    *.tzst)
      [[ -n $destination ]] && tar_args=(-C "$destination")
      command tar "${tar_args[@]}" --zstd -xf "$archive"
      ;;
    *.zip)
      command -v unzip >/dev/null 2>&1 || { print -u2 -r -- "unzip is required to extract '$archive_arg'"; return 1; }
      [[ -n $destination ]] && unzip_args=(-d "$destination")
      command unzip "${unzip_args[@]}" -- "$archive"
      ;;
    *.rar)
      command -v unrar >/dev/null 2>&1 || { print -u2 -r -- "unrar is required to extract '$archive_arg'"; return 1; }
      if [[ -n $destination ]]; then
        command unrar x "$archive" "$destination/"
      else
        command unrar x "$archive"
      fi
      ;;
    *.7z)
      command -v 7z >/dev/null 2>&1 || { print -u2 -r -- "7z is required to extract '$archive_arg'"; return 1; }
      if [[ -n $destination ]]; then
        command 7z x "$archive" "-o$destination"
      else
        command 7z x "$archive"
      fi
      ;;
    *.bz2)
      command -v bunzip2 >/dev/null 2>&1 || { print -u2 -r -- "bunzip2 is required to extract '$archive_arg'"; return 1; }
      if [[ -n $destination ]]; then
        output="$destination/${archive:t:r}"
        _extract_stream_to "$output" "$archive" bunzip2 || return
      elif (( keep_input )); then
        command bunzip2 -k -- "$archive"
      else
        command bunzip2 -- "$archive"
      fi
      ;;
    *.gz)
      command -v gunzip >/dev/null 2>&1 || { print -u2 -r -- "gunzip is required to extract '$archive_arg'"; return 1; }
      if [[ -n $destination ]]; then
        output="$destination/${archive:t:r}"
        _extract_stream_to "$output" "$archive" gunzip || return
      elif (( keep_input )); then
        command gunzip -k -- "$archive"
      else
        command gunzip -- "$archive"
      fi
      ;;
    *.Z)
      command -v uncompress >/dev/null 2>&1 || { print -u2 -r -- "uncompress is required to extract '$archive_arg'"; return 1; }
      if [[ -n $destination || $keep_input -eq 1 ]]; then
        output="${destination:-${archive:h}}/${archive:t:r}"
        _extract_stream_to "$output" "$archive" uncompress || return
      else
        command uncompress "$archive"
      fi
      ;;
    *)
      print -u2 -r -- "'$archive_arg' cannot be extracted via extract()"
      return 1
      ;;
  esac
}

# Create directory and cd into it
mkcd() {
  emulate -L zsh

  case ${1:-} in
    -h|--help)
      print 'Usage: mkcd <directory>'
      print 'Create the directory if needed, then enter it.'
      return 0
      ;;
  esac

  if (( $# != 1 )); then
    print -u2 -r -- 'Usage: mkcd <directory>'
    return 1
  fi

  command mkdir -p -- "$1" && builtin cd -- "$1"
}

# Print the name-search options without depending on a backend.
_ff_usage() {
  print 'Usage: ff [--hidden|--no-hidden] [--no-ignore] [--follow|--no-follow] <pattern> [path]'
  print 'Find names case-insensitively; hidden entries and symlink following are enabled by default.'
  print -r -- '--no-ignore includes entries ignored by fd; find fallback has no ignore-file filtering.'
}

# Find files by name
ff() {
  emulate -L zsh

  local arg pattern='' search_root='.'
  local -i hidden=1 no_ignore=0 follow=1 options_done=0
  local -a operands fd_args

  while (( $# > 0 )); do
    arg=$1
    shift
    if (( ! options_done )); then
      case $arg in
        -h|--help)
          _ff_usage
          return 0
          ;;
        --hidden)
          hidden=1
          continue
          ;;
        --no-hidden)
          hidden=0
          continue
          ;;
        --no-ignore)
          no_ignore=1
          continue
          ;;
        --follow)
          follow=1
          continue
          ;;
        --no-follow)
          follow=0
          continue
          ;;
        --)
          options_done=1
          continue
          ;;
        -*)
          print -u2 -r -- "ff: unknown option: $arg"
          _ff_usage >&2
          return 1
          ;;
      esac
    fi
    operands+=("$arg")
  done

  if (( ${#operands[@]} < 1 || ${#operands[@]} > 2 )); then
    print -u2 -r -- 'ff: expected a pattern and optional path'
    _ff_usage >&2
    return 1
  fi
  pattern=${operands[1]}
  (( ${#operands[@]} == 2 )) && search_root=${operands[2]}

  if [ ! -d "$search_root" ]; then
    print -u2 -r -- "'$search_root' is not a directory"
    return 1
  fi
  search_root=${search_root:A}

  if command -v fd >/dev/null 2>&1; then
    (( hidden )) && fd_args+=(--hidden)
    (( no_ignore )) && fd_args+=(--no-ignore)
    (( follow )) && fd_args+=(--follow)
    fd_args+=(--glob --ignore-case -- "*$pattern*" "$search_root")
    command fd "${fd_args[@]}"
  elif command -v fdfind >/dev/null 2>&1; then
    (( hidden )) && fd_args+=(--hidden)
    (( no_ignore )) && fd_args+=(--no-ignore)
    (( follow )) && fd_args+=(--follow)
    fd_args+=(--glob --ignore-case -- "*$pattern*" "$search_root")
    command fdfind "${fd_args[@]}"
  else
    local -a find_args
    find_args=()
    (( follow )) && find_args+=(-L)
    find_args+=("$search_root")
    (( no_ignore )) && print -u2 -r -- 'ff: find fallback has no ignore-file filtering; --no-ignore is already in effect'
    if (( hidden )); then
      find_args+=(-iname "*$pattern*")
    else
      # The fallback has no hidden-file switch, so explicitly prune hidden
      # directories and exclude hidden files while retaining the requested root.
      find_args+=( \( -name '.*' ! -path "$search_root" -prune \) -o \( ! -name '.*' -iname "*$pattern*" -print \) )
    fi
    command find "${find_args[@]}" 2>/dev/null
  fi
}

# Print the content-search options without depending on a backend.
_ft_usage() {
  print 'Usage: ft [--hidden] [--no-ignore] [--follow] [--fixed-strings] <pattern> [path]'
  print 'Search text with rg or grep; fixed-string matching is available on both backends.'
  print 'The grep fallback already traverses hidden files and does not read ignore files.'
}

# Find text in files (uses ripgrep if available, falls back to grep)
ft() {
  emulate -L zsh

  local arg pattern='' search_root='.'
  local -i hidden=0 no_ignore=0 follow=0 fixed_strings=0 options_done=0
  local -a operands search_args

  while (( $# > 0 )); do
    arg=$1
    shift
    if (( ! options_done )); then
      case $arg in
        -h|--help)
          _ft_usage
          return 0
          ;;
        --hidden)
          hidden=1
          continue
          ;;
        --no-ignore)
          no_ignore=1
          continue
          ;;
        --follow)
          follow=1
          continue
          ;;
        --fixed-strings|-F)
          fixed_strings=1
          continue
          ;;
        --)
          options_done=1
          continue
          ;;
        -*)
          print -u2 -r -- "ft: unknown option: $arg"
          _ft_usage >&2
          return 1
          ;;
      esac
    fi
    operands+=("$arg")
  done

  if (( ${#operands[@]} < 1 || ${#operands[@]} > 2 )); then
    print -u2 -r -- 'ft: expected a pattern and optional path'
    _ft_usage >&2
    return 1
  fi
  pattern=${operands[1]}
  (( ${#operands[@]} == 2 )) && search_root=${operands[2]}

  if command -v rg >/dev/null 2>&1; then
    (( hidden )) && search_args+=(--hidden)
    (( no_ignore )) && search_args+=(--no-ignore)
    (( follow )) && search_args+=(--follow)
    (( fixed_strings )) && search_args+=(--fixed-strings)
    search_args+=(--color=auto -- "$pattern" "$search_root")
    command rg "${search_args[@]}"
  else
    (( hidden )) && print -u2 -r -- 'ft: grep fallback includes hidden files by default; --hidden is already in effect'
    (( no_ignore )) && print -u2 -r -- 'ft: grep fallback has no ignore-file filtering; --no-ignore is already in effect'
    if (( follow )); then
      search_args=(-RnI)
    else
      search_args=(-rnI)
    fi
    (( fixed_strings )) && search_args+=(-F)
    search_args+=(--color=auto -- "$pattern" "$search_root")
    command grep "${search_args[@]}" 2>/dev/null
  fi
}

# Preview file (uses bat if available)
peek() {
  emulate -L zsh

  case ${1:-} in
    -h|--help)
      print 'Usage: peek <file>'
      print 'Preview a file with bat when available, otherwise cat.'
      return 0
      ;;
  esac

  if (( $# != 1 )); then
    print -u2 -r -- 'Usage: peek <file>'
    return 1
  fi

  if command -v bat >/dev/null 2>&1; then
    bat --style=numbers --paging=never -- "$1"
  else
    command cat -- "$1"
  fi
}

# Collect disk records before choosing a renderer. The caller owns local
# records (array), scan_result (association), and signal_status. Partial scans
# are successful collections with an explicit nonzero result status; setup
# failures/signals return early. Neither rich nor plain rendering runs here.
_zsh_scan_collect() {
  emulate -L zsh
  setopt localtraps
  local mode=$1 target=$2 entry_path kib path_list_file='' raw_output_file=''
  integer du_status=0 find_status=0 result_status=0
  shift 2
  trap 'signal_status=130; return 130' INT
  trap 'signal_status=143; return 143' TERM
  trap 'signal_status=129; return 129' HUP
  records=()
  scan_result=( state complete status 0 du_status 0 find_status 0 diagnostic '' )
  {
    path_list_file=$(command mktemp "${TMPDIR:-/tmp}/${mode}.paths.XXXXXX") || return 1
    raw_output_file=$(command mktemp "${TMPDIR:-/tmp}/${mode}.raw.XXXXXX") || return 1
    if [[ $mode == dusage ]]; then
      for entry_path in "$@"; do
        print -rn -- "$entry_path"$'\0'
      done >"$path_list_file"
      command du -sk --null --files0-from="$path_list_file" 2>/dev/null >"$raw_output_file"
      du_status=$?
    else
      command find "$target" -type f -print0 2>/dev/null >"$path_list_file"
      find_status=$?
      if [[ -s $path_list_file ]]; then
        command du -k --null --files0-from="$path_list_file" 2>/dev/null >"$raw_output_file"
        du_status=$?
      fi
    fi
    while IFS=$'\t' read -r -d '' kib entry_path; do
      [[ $kib == <-> ]] || continue
      records+=("${kib}"$'\t'"${entry_path}")
    done <"$raw_output_file"
  } always {
    command rm -f -- "$path_list_file" "$raw_output_file"
  }
  scan_result[du_status]=$du_status
  scan_result[find_status]=$find_status
  if (( find_status )); then
    result_status=$find_status
    scan_result[diagnostic]="find exit $find_status"
  fi
  if (( du_status )); then
    result_status=$du_status
    [[ -n ${scan_result[diagnostic]} ]] && scan_result[diagnostic]+=', '
    scan_result[diagnostic]+="du exit $du_status"
  fi
  scan_result[status]=$result_status
  (( result_status )) && scan_result[state]=partial
  return 0
}

# Disk usage summary for current directory
dusage() {
  emulate -L zsh
  setopt localtraps

  case ${1:-} in
    -h|--help)
      print 'Usage: dusage [path] [count]'
      print 'Rank immediate entries, retaining partial rows when du reports an error.'
      return 0
      ;;
  esac
  if (( $# > 2 )); then
    print -u2 -r -- 'Usage: dusage [path] [count]'
    return 1
  fi

  local target=${1:-.}
  local limit=${2:-20}
  local line kib entry_path label icon shown visible_count more total_kib=0 bar_width name_width width size_width percent_width
  local size_text percent_text header_meta footer_text display_target
  local scan_status=0 signal_status=0 incomplete_detail=''
  local -a entries records lines

  # Signal traps escape every nested renderer loop, then return the recorded status.
  while true; do
  trap 'signal_status=130; break 1000' INT
  trap 'signal_status=143; break 1000' TERM
  trap 'signal_status=129; break 1000' HUP

  display_target=$(_ui_safe_text "$target")

  if [ ! -d "$target" ]; then
    print -u2 -r -- "'$display_target' is not a directory"
    return 1
  fi

  case $limit in
    ''|*[!0-9]*)
      print -u2 -r -- 'Usage: dusage [path] [count]'
      return 1
      ;;
  esac

  entries=( "$target"/*(DN) )
  if (( ${#entries[@]} == 0 )); then
    echo "No entries found in '$display_target'"
    return 0
  fi

  local -A scan_result
  _zsh_scan_collect dusage "$target" "${entries[@]}" || return $?
  scan_status=${scan_result[status]}
  incomplete_detail=${scan_result[diagnostic]}

  if (( ${#records[@]} == 0 )); then
    if (( scan_status != 0 )); then
      print -u2 -r -- "Incomplete scan in '$display_target' (du exit $scan_status); results are partial"
      return $scan_status
    fi
    echo "No entries found in '$display_target'"
    return 0
  fi

  lines=( "${(@On)records}" )

  if _ui_plain_mode; then
    shown=$limit
    (( shown > ${#lines[@]} )) && shown=${#lines[@]}

    integer plain_idx
    for (( plain_idx = 1; plain_idx <= shown; plain_idx++ )); do
      line=${lines[$plain_idx]}
      kib=${line%%$'\t'*}
      entry_path=${line#*$'\t'}
      printf '%-8s %s\n' "$(_ui_human_kib "$kib")" "$(_ui_safe_text "$entry_path")"
    done
    if (( scan_status != 0 )); then
      print -u2 -r -- "Incomplete scan in '$display_target' (du exit $scan_status); results are partial"
      return $scan_status
    fi
    return 0
  fi

  for line in "${lines[@]}"; do
    kib=${line%%$'\t'*}
    case $kib in
      ''|*[!0-9]*) continue ;;
    esac
    total_kib=$(( total_kib + kib ))
  done

  shown=$(_ui_visible_count "$limit" "${#lines[@]}" 6)
  more=$(( ${#lines[@]} - shown ))
  visible_count=$shown
  width=$(_ui_term_width)
  size_width=9
  bar_width=16
  percent_width=5
  (( width < 80 )) && bar_width=10

  name_width=$(( width - size_width - percent_width - bar_width - 8 ))
  (( name_width < 10 )) && name_width=10

  header_meta=$display_target
  footer_text="showing ${visible_count}/${#lines[@]} entries"
  if (( scan_status != 0 )); then
    footer_text+=" (incomplete scan)"
  fi
  _ui_title_line 'Disk Usage' "$header_meta" accent '󰋊' '*'
  _ui_panel_kv 'Entries' "${#lines[@]}" muted text
  _ui_panel_kv 'Total' "$(_ui_human_kib "$total_kib")" muted text
  if (( scan_status != 0 )); then
    _ui_panel_kv 'Warning' "Incomplete scan ($incomplete_detail); results are partial" warning text
  fi
  _ui_section_break

  integer idx
  for (( idx = 1; idx <= visible_count; idx++ )); do
    line=${lines[$idx]}
    kib=${line%%$'\t'*}
    entry_path=${line#*$'\t'}
    size_text=$(_ui_human_kib "$kib")
    percent_text=''

    if (( total_kib > 0 && percent_width > 0 )); then
      percent_text="$(( kib * 100 / total_kib ))%"
    fi

    label=${entry_path##*/}
    [ -n "$label" ] || label=$entry_path
    label=$(_ui_safe_text "$label")
    icon=$(_ui_usage_entry_icon "$entry_path")
    label=$(_ui_safe_truncate "$name_width" "$label")

    _ui_panel_prefix
    print -nr -- "$icon "
    _ui_color text
    _ui_pad left "$name_width" "$label"
    _ui_reset
    print -nr -- ' '
    _ui_color muted
    _ui_pad right "$size_width" "$size_text"
    _ui_reset
    (( percent_width > 0 )) && printf ' %*s' "$percent_width" "$percent_text"
    print -nr -- ' '
    _ui_bar "$bar_width" "$kib" "$total_kib" info
    print ''
  done

  if (( more > 0 )); then
    _ui_panel_kv 'More' "+${more} not shown" muted muted
  fi

  _ui_section_break
  print -nr -- '  '
  _ui_color muted
  print -r -- "$footer_text"
  _ui_reset
  if (( scan_status != 0 )); then
    print -u2 -r -- "Incomplete scan in '$display_target' ($incomplete_detail); results are partial"
  fi
  break
  done

  (( signal_status == 0 )) || return $signal_status
  (( scan_status == 0 )) || return $scan_status
}

# Largest files in current directory tree
bigfiles() {
  emulate -L zsh
  setopt localtraps

  case ${1:-} in
    -h|--help)
      print 'Usage: bigfiles [path] [count]'
      print 'Rank files recursively, retaining partial rows when find or du reports an error.'
      return 0
      ;;
  esac
  if (( $# > 2 )); then
    print -u2 -r -- 'Usage: bigfiles [path] [count]'
    return 1
  fi

  local target=${1:-.}
  local limit=${2:-20}
  local line kib file_path label shown more total_kib=0 bar_width path_width footer_text icon width size_width
  local signal_status=0 display_target incomplete_status=0
  local line_count=0 incomplete_detail=''
  local -a records lines

  # Signal traps escape every nested renderer loop, then return the recorded status.
  while true; do
  trap 'signal_status=130; break 1000' INT
  trap 'signal_status=143; break 1000' TERM
  trap 'signal_status=129; break 1000' HUP

  display_target=$(_ui_safe_text "$target")

  if [ ! -e "$target" ]; then
    print -u2 -r -- "'$display_target' does not exist"
    return 1
  fi
  target=${target:A}

  case $limit in
    ''|*[!0-9]*)
      print -u2 -r -- 'Usage: bigfiles [path] [count]'
      return 1
      ;;
  esac

  local -A scan_result
  _zsh_scan_collect bigfiles "$target" || return $?

  incomplete_detail=${scan_result[diagnostic]}
  incomplete_status=${scan_result[status]}

  if (( ${#records[@]} == 0 )); then
    if (( incomplete_status != 0 )); then
      print -u2 -r -- "Incomplete scan in '$display_target' ($incomplete_detail); results are partial"
      return $incomplete_status
    fi

    if _ui_plain_mode; then
      return 0
    fi

    _ui_title_line 'Big Files' "$display_target" accent '󰉋' '*'
    _ui_panel_kv 'Status' 'No files found under target' muted text
    _ui_section_break
    print -nr -- '  '
    _ui_color muted
    print -r -- 'Nothing to display'
    _ui_reset
    return 0
  fi

  lines=( "${(@On)records}" )
  line_count=${#lines[@]}

  if _ui_plain_mode; then
    shown=$limit
    (( shown > line_count )) && shown=$line_count

    integer plain_idx
    for (( plain_idx = 1; plain_idx <= shown; plain_idx++ )); do
      line=${lines[$plain_idx]}
      kib=${line%%$'\t'*}
      file_path=${line#*$'\t'}
      printf '%-8s %s\n' "$(_ui_human_kib "$kib")" "$(_ui_safe_text "$file_path")"
    done
    if (( incomplete_status != 0 )); then
      print -u2 -r -- "Incomplete scan in '$display_target' ($incomplete_detail); results are partial"
      return $incomplete_status
    fi
    return 0
  fi

  for line in "${lines[@]}"; do
    kib=${line%%$'\t'*}
    total_kib=$(( total_kib + kib ))
  done

  shown=$(_ui_visible_count "$limit" "$line_count" 6)
  more=$(( line_count - shown ))

  width=$(_ui_term_width)
  size_width=9
  bar_width=16
  (( width < 80 )) && bar_width=10

  path_width=$(( width - size_width - bar_width - 7 ))
  (( path_width < 10 )) && path_width=10

  _ui_title_line 'Big Files' "$display_target" accent '󰉋' '*'
  _ui_panel_kv 'Files found' "$line_count" muted text
  _ui_panel_kv 'Total' "$(_ui_human_kib "$total_kib")" muted text
  if (( incomplete_status != 0 )); then
    _ui_panel_kv 'Warning' "Incomplete scan ($incomplete_detail); results are partial" warning text
  fi
  _ui_section_break

  integer idx
  for (( idx = 1; idx <= shown; idx++ )); do
    line=${lines[$idx]}
    kib=${line%%$'\t'*}
    file_path=${line#*$'\t'}
    icon=$(_ui_usage_entry_icon "$file_path")

    if (( width < 80 )); then
      label=${file_path##*/}
    else
      label=$file_path
    fi

    label=$(_ui_safe_text "$label")
    label=$(_ui_safe_truncate "$path_width" "$label")

    _ui_panel_prefix
    print -nr -- "$icon "
    _ui_color text
    _ui_pad left "$path_width" "$label"
    _ui_reset
    print -nr -- ' '
    _ui_color muted
    _ui_pad right "$size_width" "$(_ui_human_kib "$kib")"
    _ui_reset
    print -nr -- ' '
    _ui_bar "$bar_width" "$kib" "$total_kib" accent
    print ''
  done

  if (( more > 0 )); then
    _ui_panel_kv 'More' "+${more} not shown" muted muted
  fi

  footer_text="showing ${shown}/${line_count} files"
  if (( incomplete_status != 0 )); then
    footer_text+=" (incomplete scan)"
  fi
  _ui_section_break
  print -nr -- '  '
  _ui_color muted
  print -r -- "$footer_text"
  _ui_reset
  if (( incomplete_status != 0 )); then
    print -u2 -r -- "Incomplete scan in '$display_target' ($incomplete_detail); results are partial"
  fi
  break
  done

  (( signal_status == 0 )) || return $signal_status
  (( incomplete_status == 0 )) || return $incomplete_status
}

