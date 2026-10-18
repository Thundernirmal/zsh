_upkg_format_search_rows() {
  emulate -L zsh

  local row manager name version description
  local width manager_width name_width version_width desc_width REPLY
  local failed_count=0 cancelled_count=0
  local failed_managers=''
  local -a rows=( "$@" ) fields

  if (( ${#rows[@]} == 0 )); then
    for manager in "${_UPKG_SUMMARY_ORDER[@]}"; do
      case ${_UPKG_SUMMARY_STATE[$manager]} in
        failed) (( failed_count++ )) ;;
        cancelled) (( cancelled_count++ )) ;;
      esac
    done

    if (( cancelled_count > 0 )); then
      print 'Search cancelled; results are incomplete.'
    elif (( failed_count > 0 )); then
      failed_managers=$(_upkg_summary_managers_by_state failed)
      if [ -n "$failed_managers" ]; then
        print "Search results unavailable; failed manager(s): $failed_managers."
      else
        print 'Search results unavailable; one or more selected managers failed.'
      fi
    else
      print 'No matches found across selected managers.'
    fi
    return 0
  fi

  if _ui_plain_mode || [ -z "${_UPKG_THEME_MODE:-}" ]; then
    printf '%-8s %-36s %-18s %s\n' 'Manager' 'Package' 'Available' 'Description'
    printf '%-8s %-36s %-18s %s\n' '-------' '-------' '---------' '-----------'

    for row in "${rows[@]}"; do
      fields=("${(@ps:\t:)row}")
      manager=${fields[1]:-}; name=${fields[2]:-}; version=${fields[3]:-}; description=${fields[4]:-}
      [ -n "$version" ] || version='?'
      printf '%-8s %-36s %-18s %s\n' "$manager" "$name" "$version" "$description"
    done
  else
    _ui_term_width_reply
    width=$REPLY
    if (( width >= 130 )); then
      manager_width=10
      name_width=36
      version_width=18
    elif (( width >= 100 )); then
      manager_width=9
      name_width=30
      version_width=16
    elif (( width >= 80 )); then
      manager_width=8
      name_width=24
      version_width=14
    else
      manager_width=7
      name_width=18
      version_width=12
    fi
    desc_width=$(( width - manager_width - name_width - version_width - 13 ))
    (( desc_width < 18 )) && desc_width=18

    _ui_panel_kv 'Results' "${#rows[@]} match(es)" muted text
    _ui_section_break

    for row in "${rows[@]}"; do
      fields=("${(@ps:\t:)row}")
      manager=${fields[1]:-}; name=${fields[2]:-}; version=${fields[3]:-}; description=${fields[4]:-}
      [ -n "$version" ] || version='?'
      description=$(_upkg_search_trim "$description")

      _ui_panel_prefix
      _ui_color accent
      _ui_pad left "$manager_width" "$(_ui_truncate "$manager_width" "$manager")"
      _ui_reset
      print -nr -- ' '
      _ui_color text
      _ui_pad left "$name_width" "$(_ui_truncate "$name_width" "$name")"
      _ui_reset
      print -nr -- ' '
      _ui_color info
      _ui_pad left "$version_width" "$(_ui_truncate "$version_width" "$version")"
      _ui_reset
      if [ -n "$description" ]; then
        print -nr -- ' '
        _ui_color muted
        print -nr -- "$(_ui_truncate "$desc_width" "$description")"
        _ui_reset
      fi
      print ''
    done
  fi
}
