# dotfiles
My configs

## Setup (macOS, Debian/Ubuntu, ChromeOS Crostini)

```sh
./install.sh          # symlink zsh/bun configs into ~, install zsh plugins
./install.sh --chsh   # also make zsh the login shell
```

Safe to re-run; re-run it from whichever checkout `~` should point at (for
example after merging a worktree). Existing real files are moved to
`<name>.pre-dotfiles` first.

The zsh config detects what is installed instead of branching on OS:

- macOS: antidote, spaceship and the two zsh plugins come from brew.
- Linux: `install.sh` apt-installs `zsh-autosuggestions` and
  `zsh-syntax-highlighting`, and clones antidote and spaceship at pinned commits
  into `~/.zsh/`. Bump those SHAs in `install.sh` on purpose.
- Debian names `fd` and `bat` as `fdfind` and `batcat`; the fzf settings resolve
  whichever exists.
- Aliases for `eza`, `bat`, `nvim`, `pip3` and `python3` are only defined when the
  tool exists. `dx` needs the Dashlane `dcli`.

`install.sh` leaves `~/.config/gh`, `~/.config/poolside` and `~/.claude` alone
because they hold per-machine auth or hooks; diff those by hand.
