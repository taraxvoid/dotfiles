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

- macOS: antidote, the Nerd Font cask and the two zsh plugins come from brew.
- Linux: `install.sh` apt-installs `zsh-autosuggestions` and
  `zsh-syntax-highlighting`, and clones antidote at a pinned commit
  into `~/.zsh/`. JetBrainsMono Nerd Font (into `~/.local/share/fonts`) is
  downloaded at a pinned version with a checksum. Bump that pin in `install.sh` on purpose.
- Both: CLI tools (neovim, fzf, rg, zoxide, just, yq, starship) are pinned in
  `.config/mise-global.toml` and installed by `mise install`, since Debian's apt
  versions are years old. mise, uv and bun come from their vendors' installers
  (brew on macOS) when missing and update themselves; keep uv and bun out of the
  mise config so a stray global copy can't mask an unpinned version in a project.
  The one third-party apt repo is eza's own (`deb.gierens.de`, added by
  `install.sh`; brew on macOS), since the release binary lacks the zsh completion.
- Prompt icons need a Nerd Font in the terminal itself. On Crostini the Terminal
  app renders text, so fonts in the container don't count: install the font on
  the ChromeOS side (or use a terminal that reads fontconfig) and select it.
- Debian names `fd` and `bat` as `fdfind` and `batcat`; the fzf settings resolve
  whichever exists.
- Aliases for `eza`, `bat`, `nvim`, `pip3` and `python3` are only defined when the
  tool exists. `dx` needs the Dashlane `dcli`.
- `gwc [issue] [slug]` starts an issue by hand the way Claude does: worktree
  `<N>-<slug>` on branch `worktree-<N>-<slug>` (same `worktree-create.sh`),
  pushed so `gws` counts it as tracked.
- git pages through delta (pinned in the global mise config) when it runs, and
  falls back to less.
- Generated init scripts (zoxide, fzf, starship) are cached in `~/.cache/zsh`
  and regenerated when the tool's binary changes; delete that dir to force it.

`install.sh` leaves `~/.config/gh/hosts.yml` and `~/.config/poolside` alone
(per-machine auth). It links `.ssh/config` but never keys or `~/.ssh/config.local`. It asks, default no, before linking `.claude/CLAUDE.md` and
`.claude/scripts/*.sh` into `~/.claude` (existing files are moved to
`*.pre-dotfiles`); `-y` answers yes. The rest of `~/.claude` (settings, hooks)
is machine-specific, diff it by hand.

## Checks

Tool versions are pinned in `mise.toml` (`mise install`, then `lefthook install` once per clone). `lefthook.yml` runs on pre-commit: `shellcheck`
on `install.sh` and `.claude/scripts/*.sh`, `zsh -n` on the zsh files, and a staged-diff `gitleaks` scan.
`scripts/check-ssh.sh` guards `.ssh/config` (linked to `~/.ssh/config`): it is the only
file allowed under `.ssh/`, with no key material, only allowlisted directives (no
`ProxyCommand`, `LocalCommand`, `SetEnv`, ...) and `IdentityFile` paths under `~/.ssh/`.
Private hosts and other accounts go in the untracked `~/.ssh/config.local`, which it
includes. `scripts/check-private-strings.sh` fails a commit whose staged changes add any
string listed in the untracked `~/.config/dotfiles/private-strings` (one per line,
case-insensitive); it is local-only, since CI cannot have the list without publishing it.
`.github/workflows/ci.yml` runs the same plus a full-history gitleaks scan with a
pinned, checksummed binary (keep its version in sync with `mise.toml`). gitleaks is feature-complete upstream; move to
betterleaks once it reaches 1.x.

## Claude worktree hooks

`.claude/scripts/worktree-create.sh` and `worktree-remove.sh` are the WorktreeCreate and
WorktreeRemove hooks: new worktrees go to `~/worktrees/<tier>/<repo>/<name>` on branch
`worktree-<name>` (tier = repo's dir under `~/projects`), and removal is a no-op.
`require-worktree.sh` is a PreToolUse hook that blocks Edit/Write/NotebookEdit and
`git commit` in a repo's main checkout (override with `CLAUDE_ALLOW_MAIN_EDITS=1`).
The `hooks` block in `~/.claude/settings.json` is machine-specific; wire it as:
`WorktreeCreate` and `WorktreeRemove` run the matching script; `PreToolUse` runs
`require-worktree.sh` for `Edit|Write|NotebookEdit` and for `Bash` with `if: Bash(git commit*)`.

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
  branches under `untrusted`; `gpo` asks (default no) before checking out
  someone else's PR here.
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
