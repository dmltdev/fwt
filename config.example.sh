# Copy to ~/.config/fwt/config.sh and edit locally.
# This file is shell code and is sourced by fwt on each invocation.

# Extra fzf options. Internal delimiter/field options are added after these.
FWT_FZF_OPTS=(
  --height=40%
  --reverse
  --prompt='worktree> '
)

# Display alias for paths underneath $HOME.
FWT_HOME_LABEL='~'

# Width used to right-align branch labels and truncate only the visible path.
# Branch labels are not truncated by fwt.
FWT_DISPLAY_WIDTH="${COLUMNS:-120}"

# Command to run after fwt changes into the selected worktree.
# Runs in the current shell, inside the selected directory.
# Example:
# FWT_POST_CD='zed . && omp'
FWT_POST_CD=''

# Optional function hook. Runs before FWT_POST_CD and receives the selected path.
# fwt_after_cd() {
#   printf 'entered %s\n' "$1"
# }
