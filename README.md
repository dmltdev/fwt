# fwt

`fwt` is a sourceable shell function for jumping between Git worktrees with `fzf`.

It is a shell function, not a standalone executable, because a child process cannot change the working directory of the current shell.

## Requirements

- `git`
- `fzf`
- `fd` for recursive mode
- `awk`, `sed`, `dirname`, `cat`, `printf`

## Install

Source `fwt.sh` from an interactive shell:

```bash
source /path/to/fwt.sh
```

NixOS example:

```nix
environment.etc."fwt/fwt.sh".source = inputs.fwt + "/fwt.sh";

environment.interactiveShellInit = ''
  source /etc/fwt/fwt.sh
'';
```

## Usage

```bash
fwt [options] [path]
```

Arguments:

- `path` — repo/path to inspect, or recursive scan root with `-r`. Defaults to the current directory.

Options:

- `-r`, `--recursive` — recursively discover Git repos under `path` and stream their worktrees into `fzf`.
- `-b`, `--basename` — display only each worktree directory name. Selection still `cd`s to the full real path.
- `-h`, `--help` — print usage, options, and config variables.

Examples:

```bash
fwt
fwt /path/to/repo
fwt -r
fwt -r /path/to/search-root
fwt --basename
fwt -r --basename ~/work
```

Recursive discovery streams into `fzf`: the picker opens after the first worktree is found while the rest of the scan continues.

## Display

Each fzf row shows an aliased worktree path on the left and the branch label on the right:

```text
~/code/app-auth                  [feature/auth]
~/code/app                       [main]
```

Paths under `$HOME` display with `~`. The selected path is stored in a hidden field, so display aliases, truncation, and paths with spaces do not affect `cd`.

Branch labels are not truncated by `fwt`. If a row would exceed the display width, `fwt` shortens only the visible path and keeps the full `[branch]` label. If the branch alone is wider than the picker row, the terminal/fzf viewport can still clip it.

## Config

Optional config lives at:

```bash
~/.config/fwt/config.sh
```

Example:

```bash
FWT_FZF_OPTS=(
  --height=40%
  --reverse
  --prompt='worktree> '
)

FWT_HOME_LABEL='~'
FWT_FZF_CHROME_COLUMNS=4
# FWT_DISPLAY_WIDTH=120

FWT_POST_CD='zed . && omp'
```

Config variables:

- `FWT_CONFIG` — config file path. Defaults to `~/.config/fwt/config.sh`.
- `FWT_HOME_LABEL` — alias for paths under `$HOME`. Defaults to `~`.
- `FWT_DISPLAY_WIDTH` — explicit row width override.
- `FWT_FZF_CHROME_COLUMNS` — columns reserved for fzf pointer/gutter when `FWT_DISPLAY_WIDTH` is unset. Defaults to `4`.
- `FWT_POST_CD` — shell command to run after `cd` in the selected worktree.
- `FWT_FZF_OPTS` — extra fzf options array.
- `fwt_after_cd()` — optional function hook called after `cd` with selected path.

`FWT_POST_CD` runs after `fwt` changes into the selected worktree. It is evaluated as local shell code, so only put commands you trust in your own config file.

For more control, define a function hook:

```bash
fwt_after_cd() {
  printf 'entered %s\n' "$1"
}
```

`fwt_after_cd` runs before `FWT_POST_CD` and receives the selected path.

