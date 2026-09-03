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

# Optional row width override. Branch labels are not truncated by fwt.
# If unset, fwt uses terminal width minus FWT_FZF_CHROME_COLUMNS.
# FWT_DISPLAY_WIDTH=120
FWT_FZF_CHROME_COLUMNS=4

# Command shown in fzf and run after fwt changes into the selected worktree.
# Override once with: fwt --after-cd 'zed . && omp'
# Example:
# FWT_POST_CD='zed . && omp'
FWT_POST_CD=''

# Optional function hook. Runs before FWT_POST_CD and receives the selected path.
# fwt_after_cd() {
#   printf 'entered %s\n' "$1"
# }
