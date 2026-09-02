#!/usr/bin/env bash
set -euo pipefail
trap 'echo "failed: line $LINENO: $BASH_COMMAND" >&2' ERR

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
FWT_SH="$ROOT_DIR/fwt.sh"

quote() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
}

run() {
  "$@"
}

make_repo() {
  local repo="$1"

  mkdir -p -- "$repo"
  git -C "$repo" init -b main >/dev/null
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name 'Test User'
  printf x > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -m init >/dev/null
}

write_fzf_stub() {
  local bin_dir="$1"
  local seen="$2"

  cat > "$bin_dir/fzf" <<EOF
#!/usr/bin/env bash
cat > $(quote "$seen")
printf '%s\n' "\$@" > $(quote "$seen.args")
if [[ -n "\${FZF_SELECT_SUFFIX:-}" ]]; then
  line="\$(awk -v suffix="\$FZF_SELECT_SUFFIX" 'index(\$0, suffix) == length(\$0) - length(suffix) + 1 { print; exit }' $(quote "$seen"))"
  if [[ -n "\$line" ]]; then
    printf '%s' "\$line"
    exit 0
  fi
  echo "fzf stub: suffix not in input: \$FZF_SELECT_SUFFIX" >&2
  cat $(quote "$seen") >&2
  exit 90
fi
exit 130
EOF
  chmod +x "$bin_dir/fzf"
}

run_case() {
  local shell="$1"
  local cwd="$2"
  local body="$3"
  local select_suffix="${4:-}"
  local home_dir="${5:-$cwd}"
  local bin_dir script seen

  bin_dir="$cwd/bin-$shell-$RANDOM"
  mkdir -p -- "$bin_dir"
  seen="$bin_dir/fzf-input"
  write_fzf_stub "$bin_dir" "$seen"

  script="$cwd/case-$shell-$RANDOM.$shell"
  cat > "$script" <<EOF
cd -- $(quote "$cwd")
source $(quote "$FWT_SH")
$body
EOF

  HOME="$home_dir" PATH="$bin_dir:$PATH" FZF_SELECT_SUFFIX="$select_suffix" "$shell" "$script"
}

assert_shell_syntax() {
  bash -n "$FWT_SH"
  zsh -n "$FWT_SH"
}

assert_help_lists_all_flags() {
  local shell="$1"
  local out

  out="$(run_case "$shell" "$(mktemp -d -t fwt-help.XXXXXX)" 'fwt --help')"
  [[ "$out" == *'Usage:'* ]]
  [[ "$out" == *'-r, --recursive'* ]]
  [[ "$out" == *'-b, --basename'* ]]
  [[ "$out" == *'-h, --help'* ]]
  [[ "$out" == *'FWT_CONFIG'* ]]
  [[ "$out" == *'FWT_FZF_CHROME_COLUMNS'* ]]
}

assert_nonrecursive_path_with_spaces() {
  local shell="$1"
  local root repo wt out sep

  root="$(mktemp -d -t fwt-nonrecursive.XXXXXX)"
  repo="$root/repo main"
  wt="$root/feature worktree"
  make_repo "$repo"
  git -C "$repo" worktree add "$wt" -b feature >/dev/null 2>&1
  sep="$(printf '\034')"

  out="$(run_case "$shell" "$root" "fwt $(quote "$repo")
printf 'PWD=%s\\n' \"\$PWD\"" "$sep$wt")"
  [[ "$out" == *"PWD=$wt"* ]]
}

assert_recursive_finds_linked_worktree_marker_file() {
  local shell="$1"
  local root outside scan_root linked out sep

  root="$(mktemp -d -t fwt-recursive.XXXXXX)"
  outside="$root/outside repo"
  scan_root="$root/scan root"
  linked="$scan_root/linked worktree"
  make_repo "$outside"
  mkdir -p -- "$scan_root"
  git -C "$outside" worktree add "$linked" -b linked >/dev/null 2>&1
  sep="$(printf '\034')"

  out="$(run_case "$shell" "$root" "fwt -r $(quote "$scan_root")
printf 'PWD=%s\\n' \"\$PWD\"" "$sep$linked")"
  [[ "$out" == *"PWD=$linked"* ]]
}

assert_branch_label_displayed() {
  local shell="$1"
  local root repo wt sep seen_path

  root="$(mktemp -d -t fwt-branch.XXXXXX)"
  repo="$root/repo main"
  wt="$root/feature worktree"
  make_repo "$repo"
  git -C "$repo" worktree add "$wt" -b feature/label >/dev/null 2>&1
  sep="$(printf '\034')"

  run_case "$shell" "$root" "fwt $(quote "$repo") >/dev/null" "$sep$wt" >/dev/null
  seen_path="$(printf '%s\n' "$root"/bin-$shell-*/fzf-input)"
  grep -F '[feature/label]' $seen_path >/dev/null
}

assert_home_alias_displayed_without_affecting_selection() {
  local shell="$1"
  local root repo wt sep seen_path line visible

  root="$(mktemp -d -t fwt-root-alias.XXXXXX)"
  repo="$root/repo main"
  wt="$root/feature worktree"
  make_repo "$repo"
  git -C "$repo" worktree add "$wt" -b feature >/dev/null 2>&1
  sep="$(printf '\034')"

  run_case "$shell" "$root" "fwt -r $(quote "$root") >/dev/null" "$sep$wt" >/dev/null
  seen_path="$(printf '%s\n' "$root"/bin-$shell-*/fzf-input)"
  line="$(awk -v suffix="$sep$wt" 'index($0, suffix) == length($0) - length(suffix) + 1 { print; exit }' "$seen_path")"
  visible="${line%%$sep*}"

  [[ "$visible" == *'~/feature worktree'* ]]
  [[ "$line" == *"$sep$wt" ]]
}

assert_basename_displayed_without_affecting_selection() {
  local shell="$1"
  local root repo wt sep seen_path line visible

  root="$(mktemp -d -t fwt-basename.XXXXXX)"
  repo="$root/repo main"
  wt="$root/worktrees/feature worktree"
  make_repo "$repo"
  mkdir -p -- "$(dirname -- "$wt")"
  git -C "$repo" worktree add "$wt" -b feature >/dev/null 2>&1
  sep="$(printf '\034')"

  run_case "$shell" "$root" "fwt --basename $(quote "$repo") >/dev/null" "$sep$wt" >/dev/null
  seen_path="$(printf '%s\n' "$root"/bin-$shell-*/fzf-input)"
  line="$(awk -v suffix="$sep$wt" 'index($0, suffix) == length($0) - length(suffix) + 1 { print; exit }' "$seen_path")"
  visible="${line%%$sep*}"

  [[ "$visible" == feature\ worktree* ]]
  [[ "$visible" != *"$root"* ]]
  [[ "$line" == *"$sep$wt" ]]
}

assert_long_branch_visible_truncates_path_first() {
  local shell="$1"
  local root repo wt sep seen_path line visible branch

  root="$(mktemp -d -t fwt-long-branch.XXXXXX)"
  repo="$root/repo main with a very long display prefix"
  wt="$root/worktrees/feature worktree with a long display name"
  branch="feature/this-branch-name-remains-visible"
  make_repo "$repo"
  mkdir -p -- "$(dirname -- "$wt")"
  git -C "$repo" worktree add "$wt" -b "$branch" >/dev/null 2>&1
  sep="$(printf '\034')"

  run_case "$shell" "$root" "COLUMNS=80
fwt $(quote "$repo") >/dev/null" "$sep$wt" >/dev/null
  seen_path="$(printf '%s\n' "$root"/bin-$shell-*/fzf-input)"
  line="$(awk -v suffix="$sep$wt" 'index($0, suffix) == length($0) - length(suffix) + 1 { print; exit }' "$seen_path")"
  visible="${line%%$sep*}"

  [[ "$visible" == *"[$branch]" ]]
  [[ "${#visible}" -le 80 ]]
}

assert_branch_only_width_keeps_full_branch() {
  local shell="$1"
  local root repo wt sep seen_path line visible branch width

  root="$(mktemp -d -t fwt-branch-width.XXXXXX)"
  repo="$root/repo main with a very long display prefix"
  wt="$root/worktrees/feature worktree with a long display name"
  branch="feature/branch-fills-row"
  width=$((${#branch} + 4))
  make_repo "$repo"
  mkdir -p -- "$(dirname -- "$wt")"
  git -C "$repo" worktree add "$wt" -b "$branch" >/dev/null 2>&1
  sep="$(printf '\034')"

  run_case "$shell" "$root" "FWT_DISPLAY_WIDTH=$width
fwt $(quote "$repo") >/dev/null" "$sep$wt" >/dev/null
  seen_path="$(printf '%s\n' "$root"/bin-$shell-*/fzf-input)"
  line="$(awk -v suffix="$sep$wt" 'index($0, suffix) == length($0) - length(suffix) + 1 { print; exit }' "$seen_path")"
  visible="${line%%$sep*}"

  [[ "$visible" == "  [$branch]" ]]
  [[ "${#visible}" -eq "$width" ]]
}

assert_zero_columns_uses_default_terminal_width() {
  local shell="$1"
  local root repo wt sep seen_path line visible branch

  root="$(mktemp -d -t fwt-zero-columns.XXXXXX)"
  repo="$root/repo main with a very long display prefix"
  wt="$root/worktrees/feature worktree with a long display name"
  branch="feature/zero-columns-fallback"
  make_repo "$repo"
  mkdir -p -- "$(dirname -- "$wt")"
  git -C "$repo" worktree add "$wt" -b "$branch" >/dev/null 2>&1
  sep="$(printf '\034')"

  run_case "$shell" "$root" "COLUMNS=0
fwt $(quote "$repo") >/dev/null" "$sep$wt" >/dev/null
  seen_path="$(printf '%s\n' "$root"/bin-$shell-*/fzf-input)"
  line="$(awk -v suffix="$sep$wt" 'index($0, suffix) == length($0) - length(suffix) + 1 { print; exit }' "$seen_path")"
  visible="${line%%$sep*}"

  [[ "$visible" == *"[$branch]" ]]
  [[ "${#visible}" -eq 116 ]]
}

assert_small_columns_keep_narrow_width() {
  local shell="$1"
  local root repo wt sep seen_path line visible branch

  root="$(mktemp -d -t fwt-small-columns.XXXXXX)"
  repo="$root/repo main with a very long display prefix"
  wt="$root/worktrees/feature worktree with a long display name"
  branch="feature/small"
  make_repo "$repo"
  mkdir -p -- "$(dirname -- "$wt")"
  git -C "$repo" worktree add "$wt" -b "$branch" >/dev/null 2>&1
  sep="$(printf '\034')"

  run_case "$shell" "$root" "COLUMNS=35
fwt $(quote "$repo") >/dev/null" "$sep$wt" >/dev/null
  seen_path="$(printf '%s\n' "$root"/bin-$shell-*/fzf-input)"
  line="$(awk -v suffix="$sep$wt" 'index($0, suffix) == length($0) - length(suffix) + 1 { print; exit }' "$seen_path")"
  visible="${line%%$sep*}"

  [[ "$visible" == *"[$branch]" ]]
  [[ "${#visible}" -eq 31 ]]
}

assert_real_fzf_filter_uses_visible_text() {
  local shell="$1"
  local root repo wt sep seen_path line branch visible_match hidden_match

  root="$(mktemp -d -t fwt-search-fields.XXXXXX)"
  repo="$root/repo main"
  wt="$root/worktrees/hidden searchable segment/display name"
  branch="feature/searchable-branch"
  make_repo "$repo"
  mkdir -p -- "$(dirname -- "$wt")"
  git -C "$repo" worktree add "$wt" -b "$branch" >/dev/null 2>&1
  sep="$(printf '\034')"

  run_case "$shell" "$root" "COLUMNS=35
fwt --basename $(quote "$repo") >/dev/null" "$sep$wt" >/dev/null
  seen_path="$(printf '%s\n' "$root"/bin-$shell-*/fzf-input)"
  line="$(awk -v suffix="$sep$wt" 'index($0, suffix) == length($0) - length(suffix) + 1 { print; exit }' "$seen_path")"

  visible_match="$(printf '%s\n' "$line" | fzf --delimiter="$sep" --with-nth=1 --filter "$branch")"
  hidden_match="$(printf '%s\n' "$line" | fzf --delimiter="$sep" --with-nth=1 --filter 'hidden searchable segment' || true)"

  [[ "$visible_match" == "$line" ]]
  [[ -z "$hidden_match" ]]
}


assert_post_cd_runs_inside_selected_dir() {
  local shell="$1"
  local root repo wt home config out_file sep

  root="$(mktemp -d -t fwt-hook.XXXXXX)"
  repo="$root/repo main"
  wt="$root/feature worktree"
  home="$root/home"
  out_file="$root/hook-pwd"
  make_repo "$repo"
  git -C "$repo" worktree add "$wt" -b feature >/dev/null 2>&1
  mkdir -p -- "$home/.config/fwt"
  cat > "$home/.config/fwt/config.sh" <<EOF
FWT_POST_CD='pwd > $(quote "$out_file")'
EOF
  sep="$(printf '\034')"

  run_case "$shell" "$root" "fwt $(quote "$repo")" "$sep$wt" "$home" >/dev/null
  [[ "$(cat "$out_file")" == "$wt" ]]
}

assert_recursive_streams_to_fzf() {
  local shell="$1"
  local root bin scan_root repo wt script started

  root="$(mktemp -d -t fwt-stream.XXXXXX)"
  bin="$root/bin"
  scan_root="$root/scan root"
  repo="$scan_root/repo one"
  wt="$root/chosen worktree"
  started="$root/fzf-started"
  mkdir -p -- "$bin" "$repo/.git" "$wt"

  cat > "$bin/fd" <<EOF
#!/usr/bin/env bash
printf '%s\\n' $(quote "$repo/.git")
sleep 2
EOF
  chmod +x "$bin/fd"

  cat > "$bin/git" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "-C" ]]; then
  dir="\$2"; shift 2
  if [[ "\$1 \$2" == "rev-parse --show-toplevel" ]]; then
    if [[ "\$dir" == $(quote "$repo") ]]; then printf '%s\\n' $(quote "$repo"); exit 0; fi
    exit 1
  fi
  if [[ "\$1 \$2" == "worktree list" ]]; then
    printf 'worktree %s\\nHEAD abc123\\nbranch refs/heads/streaming\\n\\n' $(quote "$wt")
    exit 0
  fi
fi
exit 1
EOF
  chmod +x "$bin/git"

  cat > "$bin/fzf" <<EOF
#!/usr/bin/env bash
date +%s%3N > $(quote "$started")
IFS= read -r first || exit 130
printf '%s' "\$first"
EOF
  chmod +x "$bin/fzf"

  script="$root/stream.$shell"
  cat > "$script" <<EOF
source $(quote "$FWT_SH")
fwt -r $(quote "$scan_root")
EOF

  PATH="$bin:$PATH" "$shell" "$script" >/dev/null 2>&1 &
  local pid=$!
  sleep 0.5
  [[ -f "$started" ]]
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
}

assert_no_worktrees_message() {
  local shell="$1"
  local root err status

  root="$(mktemp -d -t fwt-empty.XXXXXX)"
  set +e
  err="$(run_case "$shell" "$root" 'fwt -r .' '' 2>&1 >/dev/null)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]]
  [[ "$err" == *'fwt: no worktrees found'* ]]
}

assert_shell_syntax
for shell in bash zsh; do
  assert_help_lists_all_flags "$shell"
  assert_nonrecursive_path_with_spaces "$shell"
  assert_recursive_finds_linked_worktree_marker_file "$shell"
  assert_branch_label_displayed "$shell"
  assert_home_alias_displayed_without_affecting_selection "$shell"
  assert_long_branch_visible_truncates_path_first "$shell"
  assert_basename_displayed_without_affecting_selection "$shell"
  assert_branch_only_width_keeps_full_branch "$shell"
  assert_real_fzf_filter_uses_visible_text "$shell"
  assert_zero_columns_uses_default_terminal_width "$shell"
  assert_small_columns_keep_narrow_width "$shell"
  assert_post_cd_runs_inside_selected_dir "$shell"
  assert_recursive_streams_to_fzf "$shell"
  assert_no_worktrees_message "$shell"
  printf 'ok %s\n' "$shell"
done
