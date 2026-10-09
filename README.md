# dotfiles
My configs

## Setup (macOS, Debian/Ubuntu, ChromeOS Crostini)

```sh
./install.sh          # symlink zsh/bun configs into ~, install zsh plugins
./install.sh --chsh   # also make zsh the login shell
./install.sh -y       # no prompts, answer yes to all
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

`install.sh` leaves `~/.config/gh/hosts.yml` and `~/.config/poolside` alone
(per-machine auth). It asks, default no, before linking `.claude/CLAUDE.md` and
`.claude/scripts/*.sh` into `~/.claude` (existing files are moved to
`*.pre-dotfiles`); `-y` answers yes. The rest of `~/.claude` (settings, hooks)
is machine-specific, diff it by hand.

## Checks

Tool versions are pinned in `mise.toml` (`mise install`, then `lefthook install` once per clone). `lefthook.yml` runs on pre-commit: `shellcheck`
on `install.sh` and `.claude/scripts/*.sh`, `zsh -n` on the zsh files, and a staged-diff `gitleaks` scan.
`.github/workflows/ci.yml` runs the same plus a full-history gitleaks scan with a
pinned, checksummed binary (keep its version in sync with `mise.toml`). gitleaks is feature-complete upstream; move to
betterleaks once it reaches 1.x.

## Claude worktree cleanup

`.claude/scripts/cleanup-worktrees.sh [-n] [repo-dir]` removes git worktrees whose
PR is merged or closed (needs `gh`). It skips the main checkout, open PRs, dirty
trees, and branches with commits newer than any PR head. `install.sh` links it into
`~/.claude/scripts/` if you say yes at the Claude prompt.

## Project trust tiers

Repos live in `~/projects/<tier>/<repo>` and worktrees mirror that as
`~/worktrees/<tier>/<repo>/<branch>`:

- `personal`, `ravenflight`: first-party. mise reads their `mise.toml` without
  prompting (`trusted_config_paths` in `.config/mise-global.toml`, linked to
  `~/.config/mise/config.toml`), so `bun run dev` and friends auto-install any
  pinned tool that is missing. Nothing is trusted on `cd`; tools install when you
  run a command that needs them. Caveat: trust is by path, so a worktree where you
  check out someone else's branch or PR in these trees inherits it. Review such
  branches under `untrusted`.
- `untrusted`: third-party code. mise will not read its config, lefthook hooks are
  never installed, and nothing runs until you do it on purpose, preferably through
  `sbx`.

`sbx [--offline] [cmd...]` (from inside an `untrusted` tree) runs a command, or a
shell, in a bubblewrap sandbox: `/` read-only, a throwaway `$HOME` (no `~/.ssh`,
`~/.config/gh`, `~/.claude`, ssh-agent or tokens), scrubbed environment, only the
`untrusted` trees writable, mise trust and tool installs confined to the sandbox
(`~/.local/share/sbx`). It narrows what a hostile install script or dev server can
touch; it is not a VM. Needs `bubblewrap`.

`.config/git/template/hooks/post-checkout` installs lefthook's git hooks when a repo
is cloned or a worktree is created (git runs `post-checkout` for both), only inside
the two first-party trees. `install.sh` sets it as the git template, so new clones
get it, and copies it into existing first-party repos.

`git-autofetch.timer` (systemd user timer, Linux) runs `git fetch --all --prune` in
every repo under `~/projects/*/*` every 10 minutes. It needs a running ssh-agent
for SSH remotes.
