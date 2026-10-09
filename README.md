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

- macOS: antidote, starship, the Nerd Font cask and the two zsh plugins come from brew.
- Linux: `install.sh` apt-installs `zsh-autosuggestions` and
  `zsh-syntax-highlighting`, and clones antidote at a pinned commit
  into `~/.zsh/`. starship (musl release tarball into `~/.local/bin`) and
  JetBrainsMono Nerd Font (into `~/.local/share/fonts`) are downloaded at pinned
  versions with checksums. Bump those pins in `install.sh` on purpose.
- Prompt icons need a Nerd Font in the terminal itself. On Crostini the Terminal
  app renders text, so fonts in the container don't count: install the font on
  the ChromeOS side (or use a terminal that reads fontconfig) and select it.
- Debian names `fd` and `bat` as `fdfind` and `batcat`; the fzf settings resolve
  whichever exists.
- Aliases for `eza`, `bat`, `nvim`, `pip3` and `python3` are only defined when the
  tool exists. `dx` needs the Dashlane `dcli`.

`install.sh` leaves `~/.config/gh`, `~/.config/poolside` and `~/.claude` alone
because they hold per-machine auth or hooks; diff those by hand.

## Checks

Tool versions are pinned in `mise.toml` (`mise install`, then `lefthook install` once per clone). `lefthook.yml` runs on pre-commit: `shellcheck`
on `install.sh` and `.claude/scripts/*.sh`, `zsh -n` on the zsh files, and a staged-diff `gitleaks` scan.
`.github/workflows/ci.yml` runs the same plus a full-history gitleaks scan with a
pinned, checksummed binary (keep its version in sync with `mise.toml`). gitleaks is feature-complete upstream; move to
betterleaks once it reaches 1.x.

## Claude worktree cleanup

`.claude/scripts/cleanup-worktrees.sh [-n] [repo-dir]` removes git worktrees whose
PR is merged or closed (needs `gh`). It skips the main checkout, open PRs, dirty
trees, and branches with commits newer than any PR head. Link it to
`~/.claude/scripts/` by hand, like the rest of `~/.claude`.
