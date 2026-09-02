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
  echo "usage: fwt [-r] [path]"
}

_fwt_emit_worktrees_for_repo() {
  local repo sep width
  repo="$1"
  sep="$2"
  width="${FWT_DISPLAY_WIDTH:-${COLUMNS:-120}}"

  command git -C "$repo" worktree list --porcelain 2>/dev/null |
    awk -v sep="$sep" -v width="$width" '
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
        pad = width - length(path) - length(branch_text)
        if (pad < 2) {
          pad = 2
        }

        printf "%s%*s%s%s%s\n", path, pad, "", branch_text, sep, path
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
  local root repo sep
  root="$1"
  sep="$2"

  {
    command git -C "$root" rev-parse --show-toplevel 2>/dev/null || true
    command fd --hidden --no-ignore --prune '^\.git$' "$root" 2>/dev/null |
      while IFS= read -r repo; do
        command git -C "$(dirname -- "$repo")" rev-parse --show-toplevel 2>/dev/null || true
      done
  } |
    awk 'NF && !seen[$0]++ { print; fflush() }' |
    while IFS= read -r repo; do
      _fwt_emit_worktrees_for_repo "$repo" "$sep"
    done |
    awk '!seen[$0]++ { print; fflush() }'
}

_fwt_select() {
  local sep first selected
  local -a fzf_opts

  sep="$1"
  fzf_opts=(--prompt='worktree> ' --height=40% --reverse)
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

_fwt_run_post_cd() {
  local dir
  dir="$1"

  if typeset -f fwt_after_cd >/dev/null 2>&1; then
    fwt_after_cd "$dir"
  fi

  if [[ -n "${FWT_POST_CD:-}" ]]; then
    eval "$FWT_POST_CD"
  fi
}

fwt() {
  local recursive root selected sep fwt_status worktrees
  recursive=0

  _fwt_load_config

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--recursive)
        recursive=1
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
  sep="$(printf '\034')"

  if [[ "$recursive" -eq 1 ]]; then
    if selected="$(_fwt_recursive_worktrees "$root" "$sep" | _fwt_select "$sep")"; then
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

    worktrees="$(_fwt_emit_worktrees_for_repo "$root" "$sep")"
    if [[ -z "$worktrees" ]]; then
      echo "fwt: no worktrees found" >&2
      return 1
    fi

    selected="$(printf '%s\n' "$worktrees" | _fwt_select "$sep")" || return
  fi

  [[ -n "$selected" ]] || return 1
  cd -- "$selected" || return
  _fwt_run_post_cd "$selected"
}
