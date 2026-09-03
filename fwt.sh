# Source this file from an interactive shell. fwt must be a function so it can
# change the current shell's working directory.

_fwt_load_config() {
  local config_file

  config_file="${FWT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/fwt/config.sh}"
  if [[ -r "$config_file" ]]; then
    source "$config_file"
  fi
}

_fwt_usage() {
  cat <<'EOF'
fwt - jump to Git worktrees with fzf

Usage:
  fwt [options] [path]

Arguments:
  path                  Repo/path to inspect, or recursive scan root with -r.
                        Defaults to current directory.

Options:
  -r, --recursive       Recursively discover Git repos under path and stream
                        their worktrees into fzf.
  -b, --basename        Display only each worktree directory name.
                        Selection still cd's to the full real path.
  --after-cd <cmd>      Override FWT_POST_CD for this invocation.
  -h, --help            Show this help.

Config:
  FWT_CONFIG            Config file path. Defaults to ~/.config/fwt/config.sh.
  FWT_HOME_LABEL        Alias for paths under $HOME. Defaults to ~.
  FWT_DISPLAY_WIDTH     Row width override.
  FWT_FZF_CHROME_COLUMNS
                        Columns reserved for fzf pointer/gutter when
                        FWT_DISPLAY_WIDTH is not set. Defaults to 4.
  FWT_POST_CD           Shell command shown in fzf and run after cd.
  FWT_FZF_OPTS          Extra fzf options array.
  fwt_after_cd()        Optional function hook called after cd with selected path.
EOF
}

_fwt_emit_worktrees_for_repo() {
  local repo sep alias_root alias_label display_mode width chrome_columns terminal_width
  repo="$1"
  sep="$2"
  alias_root="${3:-}"
  display_mode="${4:-path}"
  alias_label="${FWT_HOME_LABEL:-~}"
  if [[ -n "${FWT_DISPLAY_WIDTH:-}" ]]; then
    width="$FWT_DISPLAY_WIDTH"
  else
    chrome_columns="${FWT_FZF_CHROME_COLUMNS:-4}"
    terminal_width="${COLUMNS:-120}"
    if [[ "$terminal_width" -le 0 ]]; then
      terminal_width=120
    fi
    width="$((terminal_width - chrome_columns))"
    if [[ "$width" -lt 20 ]]; then
      width=20
    fi
  fi

  command git -C "$repo" worktree list --porcelain 2>/dev/null |
    awk -v sep="$sep" -v width="$width" -v alias_root="$alias_root" -v alias_label="$alias_label" -v display_mode="$display_mode" '
      function display_path_for(real_path) {
        if (alias_root != "" && real_path == alias_root) {
          return alias_label
        }

        if (alias_root != "" && substr(real_path, 1, length(alias_root) + 1) == alias_root "/") {
          return alias_label substr(real_path, length(alias_root) + 1)
        }

        return real_path
      }

      function basename_for(real_path) {
        sub("/$", "", real_path)
        sub("^.*/", "", real_path)
        return real_path
      }

      function truncate_path(display_path, max_path) {
        if (max_path <= 0) {
          return ""
        }

        if (length(display_path) <= max_path) {
          return display_path
        }

        if (substr(display_path, 1, length(alias_label) + 1) == alias_label "/" && max_path > length(alias_label) + 2) {
          tail_len = max_path - length(alias_label) - 2
          return alias_label "/…" substr(display_path, length(display_path) - tail_len + 1)
        }

        if (max_path == 1) {
          return "…"
        }

        return "…" substr(display_path, length(display_path) - max_path + 2)
      }

      function emit() {
        if (path == "") {
          return
        }

        label = branch
        sub("^refs/heads/", "", label)
        if (label == "") {
          label = "detached"
        }

        branch_text = "[" label "]"
        if (display_mode == "basename") {
          rendered_path = basename_for(path)
        } else {
          rendered_path = display_path_for(path)
        }
        max_path = width - length(branch_text) - 2
        rendered_path = truncate_path(rendered_path, max_path)

        pad = width - length(rendered_path) - length(branch_text)
        if (pad < 2) {
          pad = 2
        }

        printf "%s%*s%s%s%s\n", rendered_path, pad, "", branch_text, sep, path
        fflush()
        path = ""
        branch = ""
      }

      /^worktree / {
        path = substr($0, 10)
        branch = ""
        next
      }

      /^branch / {
        branch = substr($0, 8)
        next
      }

      /^detached$/ {
        branch = "detached"
        next
      }

      /^bare$/ {
        branch = "bare"
        next
      }

      /^$/ {
        emit()
        next
      }

      END {
        emit()
      }
    '
}

_fwt_recursive_worktrees() {
  local root repo sep home_root display_mode
  root="$1"
  sep="$2"
  home_root="${3:-}"
  display_mode="${4:-path}"

  {
    command git -C "$root" rev-parse --show-toplevel 2>/dev/null || true
    command fd --hidden --no-ignore --prune '^\.git$' "$root" 2>/dev/null |
      while IFS= read -r repo; do
        command git -C "$(dirname -- "$repo")" rev-parse --show-toplevel 2>/dev/null || true
      done
  } |
    awk 'NF && !seen[$0]++ { print; fflush() }' |
    while IFS= read -r repo; do
      _fwt_emit_worktrees_for_repo "$repo" "$sep" "$home_root" "$display_mode"
    done |
    awk -v sep="$sep" '!seen[$0]++ { print; fflush() }'
}

_fwt_select() {
  local sep post_cd_hint first selected
  local -a fzf_opts

  sep="$1"
  post_cd_hint="$2"
  fzf_opts=(--prompt='worktree> ' --height=40% --reverse --header="$post_cd_hint")
  if typeset -p FWT_FZF_OPTS >/dev/null 2>&1; then
    fzf_opts+=("${FWT_FZF_OPTS[@]}")
  fi
  fzf_opts+=(--delimiter="$sep" --with-nth=1)

  if IFS= read -r first; then
    selected="$(
      {
        printf '%s\n' "$first"
        cat
      } |
        fzf "${fzf_opts[@]}"
    )" || return
  else
    return 3
  fi

  [[ -n "$selected" ]] || return 1
  printf '%s\n' "${selected##*$sep}"
}

_fwt_post_cd_hint() {
  local post_cd_cmd
  post_cd_cmd="$1"

  if [[ -n "$post_cd_cmd" ]]; then
    printf 'after cd: %s\n' "$post_cd_cmd"
  else
    printf 'after cd: set FWT_POST_CD in ~/.config/fwt/config.sh\n'
  fi
}

_fwt_run_post_cd() {
  local dir post_cd_cmd
  dir="$1"
  post_cd_cmd="$2"

  if typeset -f fwt_after_cd >/dev/null 2>&1; then
    fwt_after_cd "$dir"
  fi

  if [[ -n "$post_cd_cmd" ]]; then
    eval "$post_cd_cmd"
  fi
}

fwt() {
  local recursive basename root home_root display_mode selected sep fwt_status worktrees post_cd_cmd post_cd_hint
  recursive=0
  basename=0
  display_mode=path
  post_cd_cmd=""
  _fwt_load_config
  post_cd_cmd="${FWT_POST_CD:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--recursive)
        recursive=1
        shift
        ;;
      -b|--basename)
        basename=1
        shift
        ;;
      --after-cd)
        shift
        if [[ $# -eq 0 ]]; then
          echo "fwt: --after-cd requires a command" >&2
          _fwt_usage >&2
          return 2
        fi
        post_cd_cmd="$1"
        shift
        ;;
      --after-cd=*)
        post_cd_cmd="${1#--after-cd=}"
        shift
        ;;
      -h|--help)
        _fwt_usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        echo "fwt: unknown option: $1" >&2
        _fwt_usage >&2
        return 2
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ $# -gt 1 ]]; then
    _fwt_usage >&2
    return 2
  fi

  root="${1:-$PWD}"
  if [[ ! -d "$root" ]]; then
    echo "fwt: not a directory: $root" >&2
    return 1
  fi

  root="$(cd -- "$root" && pwd -P)" || return
  home_root="$(cd -- "${HOME:-}" 2>/dev/null && pwd -P || true)"
  sep="$(printf '\034')"

  if [[ "$basename" -eq 1 ]]; then
    display_mode=basename
  fi
  post_cd_hint="$(_fwt_post_cd_hint "$post_cd_cmd")"

  if [[ "$recursive" -eq 1 ]]; then
    if selected="$(_fwt_recursive_worktrees "$root" "$sep" "$home_root" "$display_mode" | _fwt_select "$sep" "$post_cd_hint")"; then
      :
    else
      fwt_status="$?"
      case "$fwt_status" in
        3)
          echo "fwt: no worktrees found" >&2
          return 1
          ;;
        *) return "$fwt_status" ;;
      esac
    fi
  else
    if ! command git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
      echo "fwt: not inside a git repo: $root" >&2
      return 1
    fi

    worktrees="$(_fwt_emit_worktrees_for_repo "$root" "$sep" "$home_root" "$display_mode")"
    if [[ -z "$worktrees" ]]; then
      echo "fwt: no worktrees found" >&2
      return 1
    fi

    selected="$(printf '%s\n' "$worktrees" | _fwt_select "$sep" "$post_cd_hint")" || return
  fi

  [[ -n "$selected" ]] || return 1
  cd -- "$selected" || return
  _fwt_run_post_cd "$selected" "$post_cd_cmd"
}
