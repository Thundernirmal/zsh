# Trusted lazy Nix implementations; registration stays conditional in 60-functions.zsh.

# Thin apt-like wrapper around nix profile with optional fzf pickers.
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
    print '  outdated             Compare installed and evaluated Nix output identities'
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
    print '  - Interactive add/find/remove needs jq and fzf 0.68.0+'
    print '  - Advanced nix flags can be passed through by calling nix directly'
  }

  _npkg_current_system() {
    _npkg_nix eval --impure --raw --expr 'builtins.currentSystem'
  }

  _npkg_cache_dir() {
    emulate -L zsh

    if [[ -n ${XDG_CACHE_HOME:-} && $XDG_CACHE_HOME == /* ]]; then
      print -r -- "$XDG_CACHE_HOME/npkg"
      return 0
    fi
    if [[ -n ${HOME:-} && $HOME == /* ]]; then
      print -r -- "$HOME/.cache/npkg"
      return 0
    fi

    print -u2 -r -- 'npkg: HOME and XDG_CACHE_HOME do not provide an absolute cache path.'
    return 1
  }

  _npkg_attr_cache_file() {
    emulate -L zsh

    local system cache_dir

    system=$(_npkg_current_system) || return 1
    cache_dir=$(_npkg_cache_dir) || return 1

    print -r -- "${cache_dir}/nixpkgs-attrs-${system}.txt"
  }

  _npkg_cache_is_stale() {
    emulate -L zsh

    local cache_file=$1
    local -A cache_stat

    if [ ! -s "$cache_file" ]; then
      return 0
    fi

    zmodload zsh/datetime 2>/dev/null || return 0
    zmodload zsh/stat 2>/dev/null || return 0
    zstat -H cache_stat -- "$cache_file" 2>/dev/null || return 0

    (( EPOCHSECONDS - cache_stat[mtime] >= 86400 ))
  }

  _npkg_refresh_index() {
    emulate -L zsh
    setopt localtraps pipefail

    local system cache_dir cache_file error_file='' temp_file=''
    local pipeline_status=0 signal_status=0

    # Signal traps escape the pipeline boundary, then return the recorded status.
    while true; do
    trap 'signal_status=130; break 1000' INT
    trap 'signal_status=143; break 1000' TERM
    trap 'signal_status=129; break 1000' HUP

    if ! command -v jq >/dev/null 2>&1; then
      print -u2 -r -- 'jq is required for npkg refresh'
      return 1
    fi

    system=$(_npkg_current_system) || return 1
    cache_dir=$(_npkg_cache_dir) || return 1
    cache_file="${cache_dir}/nixpkgs-attrs-${system}.txt"

    command mkdir -p -- "$cache_dir" || return 1

    {
      temp_file=$(command mktemp "${cache_file}.tmp.XXXXXX") || return 1
      error_file=$(command mktemp "${cache_file}.err.XXXXXX") || return 1

      _npkg_nix eval --json "nixpkgs#legacyPackages.${system}" --apply builtins.attrNames 2>"$error_file" |
        command jq -r '.[]' >"$temp_file"
      pipeline_status=$?
      if (( pipeline_status != 0 )); then
        if [ -s "$error_file" ]; then
          command cat -- "$error_file" >&2
        fi
        return 1
      fi

      command mv -- "$temp_file" "$cache_file" || return 1
      temp_file=''
      print -r -- "$cache_file"
    } always {
      [[ -z $temp_file ]] || command rm -f -- "$temp_file"
      [[ -z $error_file ]] || command rm -f -- "$error_file"
    }
    break
    done

    (( signal_status == 0 )) || return $signal_status
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
      print -u2 -r -- "jq is required for interactive npkg ${action}"
      print -u2 -r -- "Install jq or use non-interactive commands like 'npkg search <query>'"
      return 1
    fi

    _zsh_require_fzf || return 1

    if [ ! -t 0 ] || [ ! -t 1 ]; then
      print -u2 -r -- "Interactive npkg ${action} requires a terminal"
      return 1
    fi
  }

  _npkg_fzf_preview_window() {
    emulate -L zsh

    if (( $+functions[_zsh_theme_fzf_preview_window] )); then
      _zsh_theme_fzf_preview_window || return 1
      print -r -- "$REPLY"
      return
    fi

    print -r -- 'down,40%,border-top,wrap-word'
  }

  _npkg_pick_installables() {
    emulate -L zsh

    local cache_file selection attr query multi_footer
    local -a installables fzf_args context_args preview_args multi_args
    local _c_attr='' _c_muted='' _c_success='' _c_info='' _c0=''

    _npkg_require_picker 'install' || return 1

    if (( $+functions[_ui_is_rich_terminal] )) && _ui_is_rich_terminal; then
      _zsh_theme_sgr accent fg ui && _c_attr=$REPLY
      _zsh_theme_sgr muted fg ui && _c_muted=$REPLY
      _zsh_theme_sgr success fg ui && _c_success=$REPLY
      _zsh_theme_sgr info fg ui && _c_info=$REPLY
      _c0=$'\e[0m'
    fi

    query="${(j: :)@}"
    cache_file=$(_npkg_attr_index) || return 1
    _fzf_picker_multi_args add
    multi_footer=$REPLY
    multi_args=( "${reply[@]}" )
    _fzf_picker_context_args Packages 'Type to filter packages' "$multi_footer"
    context_args=( "${reply[@]}" )
    _fzf_picker_preview_args Package
    preview_args=( "${reply[@]}" )
    fzf_args=(
      "${context_args[@]}"
      "${preview_args[@]}"
      "${multi_args[@]}"
      "--query=$query"
    )

    selection=$(
      _c_attr="$_c_attr" _c_muted="$_c_muted" _c_success="$_c_success" \
      _c_info="$_c_info" _c0="$_c0" \
      command fzf "${fzf_args[@]}" \
        --preview '
            attr={}
            printf "${_c_attr}Attr:${_c0} %s\n" "$attr"
            printf "${_c_attr}Install ref:${_c0} nixpkgs#%s\n\n" "$attr"
            meta_json=$(command nix --extra-experimental-features "nix-command flakes" \
              eval --json --apply "p: { v = p.version or \"\"; d = p.meta.description or \"\"; h = p.meta.homepage or \"\"; }" "nixpkgs#$attr" 2>/dev/null || echo "{}")

            desc=$(echo "$meta_json" | command jq -r ".d | select(. != \"\") // empty")
            ver=$(echo "$meta_json" | command jq -r ".v | select(. != \"\") // empty")
            hp=$(echo "$meta_json" | command jq -r ".h | select(. != \"\") // empty")

            if [ -n "$desc" ]; then
              printf "${_c_muted}Description:${_c0}\n%s\n\n" "$desc"
            else
              printf "${_c_muted}(no description available)${_c0}\n\n"
            fi

            if [ -n "$ver" ]; then
              printf "${_c_success}Version:${_c0} %s\n" "$ver"
            fi

            if [ -n "$hp" ]; then
              printf "${_c_info}Homepage:${_c0} %s\n" "$hp"
            fi
          ' \
        < "$cache_file"
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

    local candidates selection multi_footer target
    local -a targets fzf_args context_args preview_args multi_args
    local _c_attr='' _c_muted='' _c_info='' _c0=''

    _npkg_require_picker 'remove' || return 1

    if (( $+functions[_ui_is_rich_terminal] )) && _ui_is_rich_terminal; then
      _zsh_theme_sgr accent fg ui && _c_attr=$REPLY
      _zsh_theme_sgr muted fg ui && _c_muted=$REPLY
      _zsh_theme_sgr info fg ui && _c_info=$REPLY
      _c0=$'\e[0m'
    fi

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
              .name,
              .attr,
              (.source | clean_text),
              .target
            ]
          | @tsv
        '
    ) || return 1

    if [ -z "$candidates" ]; then
      echo "No packages are installed in the current Nix profile"
      return 0
    fi

    _fzf_picker_multi_args remove
    multi_footer=$REPLY
    multi_args=( "${reply[@]}" )
    _fzf_picker_context_args 'Installed packages' 'Type to filter installed packages' "$multi_footer"
    context_args=( "${reply[@]}" )
    _fzf_picker_preview_args Package
    preview_args=( "${reply[@]}" )
    fzf_args=(
      "${context_args[@]}"
      "${preview_args[@]}"
      "${multi_args[@]}"
      --delimiter=$'\t'
      --with-nth=1,2,3
      --nth=1,2,3
      --accept-nth=4
      --freeze-left=1
      --wrap=word
    )

    selection=$(
      print -r -- "$candidates" |
        _c_attr="$_c_attr" _c_muted="$_c_muted" _c_info="$_c_info" _c0="$_c0" \
        command fzf "${fzf_args[@]}" \
          --preview 'printf "${_c_attr}Name:${_c0} %s\n${_c_muted}Attr:${_c0} %s\n${_c_info}Source:${_c0} %s\n" {1} {2} {3}'
    ) || return 0

    while IFS= read -r target; do
      [ -n "$target" ] && targets+=("$target")
    done <<< "$selection"

    (( ${#targets[@]} > 0 )) || return 0
    _npkg_nix profile remove "${targets[@]}"
  }

  _npkg_set_outdated_state() {
    typeset -g _NPKG_OUTDATED_STATE=$1
    typeset -gi _NPKG_OUTDATED_TOTAL=${2:-0}
    typeset -gi _NPKG_OUTDATED_CHANGED=${3:-0}
    typeset -gi _NPKG_OUTDATED_UNKNOWN=${4:-0}
  }

  _npkg_eval_installable_record() {
    emulate -L zsh

    local source=$1
    local attr_path=$2
    local outputs_json=$3
    local selection apply_expr output_name
    local -a output_names

    if [[ $outputs_json == null ]]; then
      selection='if (package.outputSpecified or false) then [ package.outputName ] else if (package ? meta) && (package.meta ? outputsToInstall) then package.meta.outputsToInstall else [ "out" ]'
    else
      print -r -- "$outputs_json" | command jq -e '
        type == "array"
        and length > 0
        and all(.[]; type == "string" and (. == "*" or test("^[A-Za-z0-9+._?=-]+$")))
        and ((map(select(. == "*")) | length) == 0 or (length == 1 and .[0] == "*"))
      ' >/dev/null 2>&1 || return 1

      output_names=( "${(@f)$(print -r -- "$outputs_json" | command jq -r '.[]')}" )
      if (( ${#output_names[@]} == 1 )) && [[ ${output_names[1]} == '*' ]]; then
        selection='package.outputs or [ "out" ]'
      else
        selection='[ '
        for output_name in "${output_names[@]}"; do
          selection+='"'"$output_name"'" '
        done
        selection+=']'
      fi
    fi

    apply_expr="package:
      let
        selectedOutputs = ${selection};
        outputPath = output:
          if builtins.hasAttr output package
          then builtins.toString (builtins.getAttr output package)
          else throw \"selected output is missing from the evaluated package\";
      in {
        paths = builtins.sort builtins.lessThan (builtins.map outputPath selectedOutputs);
        version = if package ? version then builtins.toString package.version else null;
      }"

    _npkg_nix eval --json "${source}#${attr_path}" --apply "$apply_expr"
  }

  _npkg_outdated() {
    emulate -L zsh
    setopt pipefail localtraps NO_MONITOR NO_NOTIFY

    _npkg_set_outdated_state partial 0 0 0

    if ! command -v jq >/dev/null 2>&1; then
      print -u2 -r -- 'jq is required for npkg outdated'
      return 1
    fi

    local profile_json profile_error_file profile_error entry_data entry_json name attr_path source locked_uri
    local store_paths_json outputs_json structural_value
    local tmp_dir current_record locked_record installed_paths available_paths
    local installed_version available_version package_state display_state marker role detail error_output
    local width name_width version_width visible_count more
    local current_file locked_file pid
    integer pkg_count=0 changed=0 unknown=0 idx interrupted=0
    integer max_jobs=8
    local -a names attrs sources locked_uris installed_path_sets output_specs structurally_valid
    local -a installed_versions available_versions statuses unknown_details job_pids

    profile_error_file=$(command mktemp "${TMPDIR:-/tmp}/npkg-profile-error.XXXXXX") || {
      print -u2 -r -- 'Failed to create temporary storage for npkg outdated.'
      return 1
    }
    trap 'command rm -f -- "$profile_error_file"; trap - INT TERM; return 130' INT TERM

    profile_json=$(_npkg_nix profile list --json 2>"$profile_error_file") || {
      profile_error=$(<"$profile_error_file")
      command rm -f -- "$profile_error_file"
      trap - INT TERM
      print -u2 -r -- 'Failed to read Nix profile.'
      [[ -n $profile_error ]] && print -u2 -r -- "Diagnostic: $(_ui_safe_text "$profile_error")"
      return 1
    }
    command rm -f -- "$profile_error_file"
    trap - INT TERM

    print -r -- "$profile_json" | command jq -e '
      type == "object"
      and (((.elements | type) == "object") or ((.elements | type) == "array"))
    ' >/dev/null 2>&1 || {
      print -u2 -r -- 'Failed to parse Nix profile JSON.'
      return 1
    }

    entry_data=$(
      print -r -- "$profile_json" | command jq -c '
        def text: if type == "string" then . else "" end;
        def manifest_entries:
          if (.elements | type) == "object" then
            .elements
            | to_entries
            | sort_by(.key)
            | .[]
            | {
                fallbackName: .key,
                value: (.value | if type == "object" then . else {} end)
              }
          else
            .elements
            | to_entries[]
            | {
                fallbackName: "element-\(.key + 1)",
                value: (.value | if type == "object" then . else {} end)
              }
          end;

        manifest_entries
        | .fallbackName as $fallback
        | .value as $value
        | select(($value.active // true) == true)
        | (($value.attrPath // "") | text) as $attr
        | (($value.originalUrl // $value.originalUri // "") | text) as $original
        | (($value.uri // $value.url // "") | text) as $locked
        | ($value.storePaths // null) as $stores
        | select((($original + " " + $locked) | ascii_downcase | contains("nixpkgs")))
        | {
            displayName: (
              if (($value.name // "") | text) != "" then (($value.name // "") | text)
              elif $attr != "" then ($attr | split(".") | last)
              elif (($stores | type) == "array" and ($stores | length) > 0 and (($stores[0] | type) == "string")) then ($stores[0] | split("/") | last)
              else $fallback
              end
            ),
            attrPath: $attr,
            originalUrl: $original,
            lockedUri: $locked,
            storePaths: $stores,
            outputs: ($value.outputs // null)
          }
      '
    ) || {
      print -u2 -r -- 'Failed to parse Nix profile elements.'
      return 1
    }

    while IFS= read -r entry_json; do
      [[ -n $entry_json ]] || continue

      name=$(print -r -- "$entry_json" | command jq -r '.displayName') || return 1
      attr_path=$(print -r -- "$entry_json" | command jq -r '.attrPath') || return 1
      source=$(print -r -- "$entry_json" | command jq -r '.originalUrl') || return 1
      locked_uri=$(print -r -- "$entry_json" | command jq -r '.lockedUri') || return 1
      store_paths_json=$(print -r -- "$entry_json" | command jq -c '.storePaths') || return 1
      outputs_json=$(print -r -- "$entry_json" | command jq -c '.outputs') || return 1

      if print -r -- "$entry_json" | command jq -e '
        (.displayName | type == "string" and length > 0)
        and (.attrPath | type == "string" and length > 0)
        and (.originalUrl | type == "string" and length > 0)
        and (.lockedUri | type == "string")
        and (.storePaths | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
        and (
          .outputs == null
          or (
            (.outputs | type) == "array"
            and (.outputs | length) > 0
            and all(.outputs[]; type == "string" and (. == "*" or test("^[A-Za-z0-9+._?=-]+$")))
            and (([.outputs[] | select(. == "*")] | length) == 0 or ((.outputs | length) == 1 and .outputs[0] == "*"))
          )
        )
      ' >/dev/null 2>&1; then
        structural_value=1
      else
        structural_value=0
      fi

      names+=("$(_ui_safe_text "$name")")
      attrs+=("$attr_path")
      sources+=("$source")
      locked_uris+=("$locked_uri")
      installed_path_sets+=("$store_paths_json")
      output_specs+=("$outputs_json")
      structurally_valid+=("$structural_value")
    done <<< "$entry_data"

    pkg_count=${#names[@]}
    if (( pkg_count == 0 )); then
      _npkg_set_outdated_state current 0 0 0
      echo "No nixpkgs packages found in the current profile."
      return 0
    fi

    echo "Checking $pkg_count package(s) for changes..."

    tmp_dir=$(command mktemp -d "${TMPDIR:-/tmp}/npkg-outdated.XXXXXX") || {
      print -u2 -r -- 'Failed to create temporary storage for npkg outdated.'
      return 1
    }
    [[ -n $tmp_dir && -d $tmp_dir ]] || {
      print -u2 -r -- 'Failed to create temporary storage for npkg outdated.'
      return 1
    }

    trap 'command rm -rf -- "$tmp_dir"' EXIT
    trap 'interrupted=1; for pid in "${job_pids[@]}"; do command kill "$pid" 2>/dev/null; done' INT TERM

    for (( idx = 1; idx <= pkg_count; idx++ )); do
      (( interrupted )) && break
      (( structurally_valid[$idx] )) || continue

      (
        _npkg_eval_installable_record \
          "${sources[$idx]}" \
          "${attrs[$idx]}" \
          "${output_specs[$idx]}" \
          >"${tmp_dir}/${idx}.current" \
          2>"${tmp_dir}/${idx}.current.error"

        if [[ -n ${locked_uris[$idx]} ]]; then
          _npkg_eval_installable_record \
            "${locked_uris[$idx]}" \
            "${attrs[$idx]}" \
            "${output_specs[$idx]}" \
            >"${tmp_dir}/${idx}.locked" \
            2>"${tmp_dir}/${idx}.locked.error"
        fi
        :
      ) &
      job_pids+=("$!")

      if (( interrupted )); then
        command kill "${job_pids[-1]}" 2>/dev/null
        break
      fi

      if (( ${#job_pids[@]} >= max_jobs )); then
        for pid in "${job_pids[@]}"; do
          wait "$pid" 2>/dev/null
        done
        job_pids=()
        (( interrupted )) && break
      fi
    done

    for pid in "${job_pids[@]}"; do
      wait "$pid" 2>/dev/null
    done
    job_pids=()

    if (( interrupted )); then
      trap - INT TERM
      command rm -rf -- "$tmp_dir"
      trap - EXIT
      return 130
    fi

    for (( idx = 1; idx <= pkg_count; idx++ )); do
      (( interrupted )) && break
      installed_version='?'
      available_version='?'
      package_state=unknown
      detail=''
      current_file="${tmp_dir}/${idx}.current"
      locked_file="${tmp_dir}/${idx}.locked"

      if (( ! structurally_valid[$idx] )); then
        detail='incomplete profile data'
      fi

      if [[ -s $locked_file ]]; then
        locked_record=$(<"$locked_file")
        if print -r -- "$locked_record" | command jq -e '
          type == "object" and (.version == null or (.version | type) == "string")
        ' >/dev/null 2>&1; then
          installed_version=$(print -r -- "$locked_record" | command jq -r 'if .version == null or .version == "" then "?" else .version end')
          installed_version=$(_ui_safe_text "$installed_version")
        fi
      fi

      if (( structurally_valid[$idx] )) && [[ -s $current_file ]]; then
        current_record=$(<"$current_file")
        if print -r -- "$current_record" | command jq -e '
          type == "object"
          and (.paths | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
          and (.version == null or (.version | type) == "string")
        ' >/dev/null 2>&1; then
          installed_paths=$(print -r -- "${installed_path_sets[$idx]}" | command jq -c 'sort | unique')
          available_paths=$(print -r -- "$current_record" | command jq -c '.paths | sort | unique')
          available_version=$(print -r -- "$current_record" | command jq -r 'if .version == null or .version == "" then "?" else .version end')
          available_version=$(_ui_safe_text "$available_version")

          if [[ $installed_paths == $available_paths ]]; then
            package_state=current
          else
            package_state=changed
            (( changed++ ))
          fi
        else
          detail='evaluation returned unusable output-path data'
        fi
      elif (( structurally_valid[$idx] )); then
        if [[ -s "${tmp_dir}/${idx}.current.error" ]]; then
          error_output=$(<"${tmp_dir}/${idx}.current.error")
          detail="evaluation failed: $(_ui_safe_text "$error_output")"
        else
          detail='evaluation failed without a diagnostic'
        fi
      fi

      if [[ $package_state == unknown ]]; then
        (( unknown++ ))
      fi

      installed_versions+=("$installed_version")
      available_versions+=("$available_version")
      statuses+=("$package_state")
      unknown_details+=("$detail")
    done

    trap - INT TERM
    if (( interrupted )); then
      command rm -rf -- "$tmp_dir"
      trap - EXIT
      return 130
    fi

    command rm -rf -- "$tmp_dir"
    trap - EXIT

    if (( unknown > 0 )); then
      _npkg_set_outdated_state partial "$pkg_count" "$changed" "$unknown"
    elif (( changed > 0 )); then
      _npkg_set_outdated_state changed "$pkg_count" "$changed" 0
    else
      _npkg_set_outdated_state current "$pkg_count" 0 0
    fi

    if _ui_plain_mode; then
      printf '\n'
      printf '%-25s %-20s %-20s %s\n' 'Package' 'Installed' 'Available' 'Status'
      printf '%-25s %-20s %-20s %s\n' '-------' '---------' '---------' '------'

      for (( idx = 1; idx <= pkg_count; idx++ )); do
        case ${statuses[$idx]} in
          changed) display_state='change available' ;;
          *) display_state=${statuses[$idx]} ;;
        esac
        printf '%-25s %-20s %-20s %s\n' \
          "${names[$idx]}" \
          "${installed_versions[$idx]}" \
          "${available_versions[$idx]}" \
          "$display_state"
      done

      if (( unknown > 0 )); then
        for (( idx = 1; idx <= pkg_count; idx++ )); do
          [[ ${statuses[$idx]} == unknown ]] || continue
          printf 'Unknown: %s - %s\n' "${names[$idx]}" "${unknown_details[$idx]}"
        done
      fi

      printf '\n'
      if (( unknown > 0 )); then
        printf 'Partial result: %d change(s) available; %d unknown.\n' "$changed" "$unknown"
        return 1
      elif (( changed > 0 )); then
        printf '%d change(s) available. Run: npkg upgrade\n' "$changed"
      else
        printf 'Everything is up to date.\n'
      fi
      return 0
    fi

    width=$(_ui_term_width)
    if (( width >= 120 )); then
      name_width=28
      version_width=18
    elif (( width >= 80 )); then
      name_width=22
      version_width=14
    else
      name_width=16
      version_width=10
    fi

    visible_count=$(_ui_visible_count "$pkg_count" "$pkg_count" 9)
    more=$(( pkg_count - visible_count ))

    _ui_title_line 'Nix Package Drift' "$pkg_count package(s) checked" accent '󱄅' '*'
    _ui_panel_kv 'Command' 'npkg outdated' muted text
    _ui_section_break

    for (( idx = 1; idx <= visible_count; idx++ )); do
      package_state=${statuses[$idx]}
      case $package_state in
        current) marker=current; role=success ;;
        changed) marker='change available'; role=warning ;;
        *) marker=unknown; role=danger ;;
      esac

      _ui_panel_prefix
      _ui_badge "$marker" "$role"
      print -nr -- ' '
      _ui_color text
      _ui_pad left "$name_width" "$(_ui_safe_truncate "$name_width" "${names[$idx]}")"
      _ui_reset
      print -nr -- ' '
      _ui_color muted
      _ui_pad left "$version_width" "$(_ui_safe_truncate "$version_width" "${installed_versions[$idx]}")"
      _ui_reset
      print -nr -- ' '
      _ui_color info
      _ui_pad left "$version_width" "$(_ui_safe_truncate "$version_width" "${available_versions[$idx]}")"
      _ui_reset
      print ''
    done

    if (( more > 0 )); then
      _ui_panel_kv 'More' "+${more} not shown" muted muted
    fi

    if (( unknown > 0 )); then
      for (( idx = 1; idx <= pkg_count; idx++ )); do
        [[ ${statuses[$idx]} == unknown ]] || continue
        _ui_panel_kv 'Unknown' "${names[$idx]} - ${unknown_details[$idx]}" danger text
      done
    fi

    _ui_section_break
    print -nr -- '  '
    if (( unknown > 0 )); then
      _ui_color danger
      print -r -- "Partial result: $changed change(s) available; $unknown unknown."
      _ui_reset
      return 1
    elif (( changed > 0 )); then
      _ui_color warning
      print -r -- "$changed change(s) available. Run npkg upgrade to apply."
    else
      _ui_color success
      print -r -- 'Everything is up to date.'
    fi
    _ui_reset
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
          print -u2 -r -- 'Usage: npkg search <query>'
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
        print -u2 -r -- "Unknown npkg command: $cmd"
        _npkg_usage >&2
        return 1
        ;;
    esac
  }

