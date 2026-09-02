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
fwt
fwt /path/to/repo
fwt -r
fwt -r /path/to/search-root
```

- `fwt` searches the Git repo containing the current directory.
- `fwt /path` searches the Git repo containing `/path`.
- `fwt -r` recursively discovers Git repos below the current directory.
- `fwt -r /path` recursively discovers Git repos below `/path`.

Recursive discovery streams into `fzf`: the picker opens after the first worktree is found while the rest of the scan continues.

## Display

Each fzf row shows an aliased worktree path on the left and the branch label on the right:

```text
~/code/app-auth                  [feature/auth]
~/code/app                       [main]
```

Paths under `$HOME` display with `~`. The selected path is stored in a hidden field, so display aliases, truncation, and paths with spaces do not affect `cd`.

Branch labels are not truncated by `fwt`. If a row would exceed the display width, `fwt` shortens only the visible path and keeps the full `[branch]` label.

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
FWT_DISPLAY_WIDTH="${COLUMNS:-120}"

FWT_POST_CD='zed . && omp'
```

`FWT_POST_CD` runs after `fwt` changes into the selected worktree. It is evaluated as local shell code, so only put commands you trust in your own config file.

For more control, define a function hook:

```bash
fwt_after_cd() {
  printf 'entered %s\n' "$1"
}
```

`fwt_after_cd` runs before `FWT_POST_CD` and receives the selected path.

