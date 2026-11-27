# dotfiles
My configs

## Setup (macOS, Debian/Ubuntu, ChromeOS Crostini)

```sh
./install.sh          # symlink zsh/bun configs into ~, install zsh plugins, optionally copy Claude scripts and setup
./install.sh --chsh   # also make zsh the login shell
./install.sh [-y/-n|--yes/--no]       # no prompts, answer yes to all
./install.sh --from-here  # point global configs to those in this branch (for testing)
./install.sh --link-only  # only (re)link, install nothing
```

Safe to re-run, from any checkout or worktree. Every link in `~` points through
one symlink, `~/.dotfiles`, which points at the repo's main checkout, so a
worktree being cleaned up never breaks `~`. `--from-here` points it at the
current worktree instead (`cleanup-worktrees.sh` won't remove that one); a run
without the flag switches back. Existing real files are moved to
`<name>.pre-dotfiles` first.

The zsh config detects what is installed instead of branching on OS:

- macOS: antidote, the Nerd Font cask and the two zsh plugins come from brew.
- Linux: `install.sh` apt-installs `zsh-autosuggestions` and
  `zsh-syntax-highlighting`, and clones antidote at a pinned commit
  into `~/.zsh/`. JetBrainsMono Nerd Font (into `~/.local/share/fonts`) is
  downloaded at a pinned version with a checksum. Bump that pin in `install.sh` on purpose.
- Both: CLI tools (neovim, fzf, rg, fd, sd, bat, zoxide, just, yq, starship) are pinned in
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
- `ghelp` lists the git/gh shortcuts (`gps`, `gpm`, `gpo`, `grw`, ...) with their
  usage and what they do; `ghelp <word>` filters, e.g. `ghelp merge`.
- `gwc [issue] [slug]` starts an issue by hand the way Claude does: worktree
  `<N>-<slug>` on branch `worktree-<N>-<slug>` (same `worktree-create.sh`),
  pushed so `gws` counts it as tracked.
- `cw [issue]`, `cfix [pr]` and `crv [pr]` start Claude (Opus unless `-s`/`-m`)
  on an issue in its worktree, a PR's CI/conflict/review follow-up, or a
  `/code-review` of a PR.
- `gcl <repo>` clones into `~/projects/<tier>/<name>` (your repos personal,
  owners in `_gcl_tiers` their tier, anyone else untrusted) and cds there.
- Merge conflicts show ours and theirs only; `git base <file>` re-renders one
  with the merge base when you need it.
- git pages through delta (pinned in the global mise config) when it runs, and
  falls back to less.
- git-branchless (pinned in the global mise config): `git sl` smartlog,
  `git restack`, `git absorb`, `git submit` for stacked agent commits. Run
  `git branchless init` once per repo to install its aliases and hooks.
- yazi (file manager, pinned in the global mise config): `y [dir]` runs it and cds
  to wherever you quit (`Q` quits without moving); `prefix+e` in herdr opens it in a
  popup at the focused pane's dir. Config is in `.config/yazi` (each file linked
  into `~/.config/yazi`): hidden files shown, nvim as the editor, git status
  signs, `l`/Enter open files too, `gp`/`gw`/`g.` jump to `~/projects`,
  `~/worktrees`, `~/.dotfiles`, `!` drops to a shell and `gi` runs lazygit. Its
  plugins (git, smart-enter) are pinned by commit and hash in
  `.config/yazi/package.toml` and fetched by `install.sh` (`ya pkg install`);
  bump them with `ya pkg upgrade`, Renovate doesn't.
- Generated init scripts (zoxide, fzf, starship) are cached in `~/.cache/zsh`
  and regenerated when the tool's binary changes; delete that dir to force it.
- rtk (trial, pinned in the global mise config): `rtk init -g` registers a
  Claude Code PreToolUse hook that rewrites supported commands to `rtk <cmd>`
  so the agent reads compressed output. It writes `~/.claude/settings.json`
  directly; merge-settings only adds fragment hooks, so it survives install.sh
  re-runs. Remove with `rtk init -g --uninstall`.

`install.sh` leaves `~/.config/gh/hosts.yml` and `~/.config/poolside` alone
(per-machine auth). It links `.ssh/config` but never keys or `~/.ssh/config.local`. It asks, default no, before linking `.claude/CLAUDE.md` and
`.claude/scripts/*.sh` into `~/.claude` (existing files are moved to
`*.pre-dotfiles`); `-y` answers yes, `-n` no. The same step merges
`.claude/settings.fragment.json` (status line, every hook below, the worktree
deny rules, and Claude Code's built-in sandbox with its write, network and
credential allowlists, plus `~/.claude/plans` so plans can be written
sandboxed) into `~/.claude/settings.json`, backing it up first; the
rest of that file stays machine-specific. The sandbox keeps its "retry
unsandboxed" escape hatch until you set `sandbox.allowUnsandboxedCommands` to
`false` yourself.

`.config/devin/config.json` (Devin CLI/Desktop permissions, fetch allows and
the `--sandbox` domain/exclusion lists) is linked whole. Approval grants made
in the Desktop UI persist into that same file, so expect it to drift and need
committing after interactive sessions. It deliberately sets no `agent.model`:
Devin's default routing can switch models per turn ("auto"/adaptive), a sharp
edge for predictable behavior and cost. Pin `agent.model` in the file if that
becomes annoying.

Every package manager refuses releases younger than 3 days: bun (`.bunfig.toml`),
uv (`.config/uv/uv.toml`), mise (`minimum_release_age` in the global config),
and npm and pnpm (set in their user config by `install.sh`).

## Checks

Tool versions are pinned in `mise.toml` (`mise install`, then `lefthook install` once per clone). `lefthook.yml` runs on pre-commit: `shellcheck`
on the shell scripts, `zsh -n` on the zsh files, `actionlint` and `zizmor` on the
workflows, `typos` on everything (exceptions in `_typos.toml`), and a staged-diff
`gitleaks` scan.
`scripts/check-ssh.sh` guards `.ssh/config` (linked to `~/.ssh/config`): it is the only
file allowed under `.ssh/`, with no key material, only allowlisted directives (no
`ProxyCommand`, `LocalCommand`, `SetEnv`, ...) and `IdentityFile` paths under `~/.ssh/`.
Private hosts and other accounts go in the untracked `~/.ssh/config.local`, which it
includes. `scripts/check-private-strings.sh` fails a commit whose staged changes add any
string listed in the untracked `~/.config/dotfiles/private-strings` (one per line,
case-insensitive); it is local-only, since CI cannot have the list without publishing it.
`.github/workflows/ci.yml` runs the same tools (installed from `mise.toml` by
`jdx/mise-action`) plus a full-history gitleaks scan and the bats tests. Its
install job runs `scripts/smoke-install.sh` in a clean Debian container:
`install.sh -y` twice (the second run must change nothing), then an
interactive zsh that must start without errors. macOS is not in CI (GitHub bills
its minutes at 10x); run the same script locally after changing `install.sh`. gitleaks is feature-complete
upstream; move to betterleaks once it reaches 1.x.

Renovate (`renovate.json`, weekly, 3-day minimum release age) bumps the mise tools
in `mise.toml` and the global config, the action SHAs, the mise version CI uses,
the zsh plugin pins and antidote. The Nerd Font pin carries a sha256 Renovate
cannot compute, so bump it by hand.

## Claude worktree hooks

`.claude/scripts/worktree-create.sh` and `worktree-remove.sh` are the WorktreeCreate and
WorktreeRemove hooks: new worktrees go to `~/worktrees/<tier>/<repo>/<name>` on branch
`worktree-<name>` (tier = repo's dir under `~/projects`), and removal is a no-op.
`require-worktree.sh` is a PreToolUse hook that blocks Edit/Write/NotebookEdit and
`git commit` in a repo's main checkout (override with `CLAUDE_ALLOW_MAIN_EDITS=1`).
All of them are wired in `.claude/settings.fragment.json`, which `install.sh`
merges into `~/.claude/settings.json`: `WorktreeCreate` and `WorktreeRemove` run
the matching script; `PreToolUse` runs `require-worktree.sh` for
`Edit|Write|NotebookEdit` and for `Bash` with `if: Bash(git commit*)`.

## Claude gh api guard

`gh` runs outside the sandbox with real credentials, so `gh api` is kept read-only
two ways, both in `.claude/settings.fragment.json`. `permissions.allow` lists the
read endpoints Claude may call unprompted (`repos/*`, `/repos/*`, `user`,
`rate_limit`), and `permissions.deny` blocks the write flags (`-X`, `--method`,
`--input`, and `-f`/`-F`/`--field`/`--raw-field` on repo endpoints). Globs miss
spellings like `-XPOST`, so `gh-api-guard.sh` (a PreToolUse hook on Bash) parses
the call too: it exits 2 on any non-GET method or body flag and asks before
`gh api graphql`, which is always a POST, unless the call is a lone query it can
show is read-only (no `mutation`, no `@file` or `--input` body, no `$(...)`, no
chaining, pipes or redirects), which it allows. Override with `CLAUDE_ALLOW_GH_API_WRITES=1`.
Prefer the dedicated subcommands (`gh pr view`, `gh issue view`, `gh run view`,
`gh pr checks`) and keep `gh api` for what they do not cover.

Replying to and resolving review threads needs writes `gh` has no subcommand for, so
two fixed-shape aliases in `.config/gh/config.yml` cover them: `gh reply-thread <pr>
<comment-id> <body>` (REST reply, scoped to the current repo via `{owner}/{repo}`) and
`gh resolve-thread <thread-node-id>` (GraphQL `resolveReviewThread` only). Both are in
`permissions.allow`. They start with `gh`, so the sandbox exclusion matches, and the
hook ignores them because it only inspects `gh api`. Claude supplies IDs and reply text,
never a method or query, so it cannot delete, edit or merge anything through them.
Thread node IDs (and the REST comment IDs to reply to) come from a
`gh api graphql` query over `reviewThreads`, which the hook allows because it is read-only.

Deployment reviews (environments with required reviewers) work the same way. `gh
pending-deploys` (zsh `gdl`) lists waiting runs with their environments and is in
`permissions.allow`. `gh review-deploy <approved|rejected> <run-id> [comment]` (zsh `gda`
approves, `gdx` rejects; bare, both open an fzf picker) looks up the environments you can review and POSTs the decision.
It is deliberately not in `permissions.allow`, so Claude has to ask before it runs.
GitHub notifies you of waiting reviews itself (Settings > Notifications > Actions).

The hook also single-quotes bare `{owner}`/`{repo}`/`{branch}` words in `gh api`
calls (via `updatedInput`). Unquoted, next to a quoted argument such as
`-q '.[0].number'`, they stop the sandbox matching `gh *` as an excluded command,
so the call runs sandboxed and fails with `x509: OSStatus -26276`.

## Claude gh aw compile

`gh aw compile --strict` is allowed unprompted (`permissions.allow`) so compile errors
surface locally before a push instead of turning CI red. Compiling only regenerates
`*.lock.yml` from the `.github/workflows/*.md` sources, so the self-modification risk
is in editing those sources:

- `gh-aw-frontmatter-guard.sh` (PreToolUse on Edit|Write) asks when an edit to a
  `.github/workflows/*.md` file changes `permissions`, `tools`, `network`,
  `safe-outputs`, `engine` or `imports` compared with `origin/main`, or when the
  file is new on the branch. Prompt-body edits pass silently.
- `permissions.ask` covers `Edit` and `Write` on `**/.github/workflows/**` (plain
  Actions workflows and lock files). A leading single `/` in a user-settings rule
  is relative to `~/.claude`, so the earlier `/.github/...` form never matched.
- `gh-aw-pre-push.sh` (PreToolUse on `git push`) runs `gh aw compile --strict` in
  repos that have gh aw sources and blocks the push if it fails or rewrites a lock
  file. Skip with `CLAUDE_SKIP_GH_AW_PUSH_CHECK=1`.

These local rules are only a guard against mistakes. The intended real boundary is
server-side and is planned, not in place: CODEOWNERS on `.github/workflows/`,
required review, and a CI check that lock files are in sync, set up per target
repo. See issue #109.

## Claude sandbox boundaries

The sandbox only helps if nothing it can write is later run outside it. Excluded
commands (`gh`, `git push`, `git fetch`, `gws`), hooks, and Tara's own shell all run
unsandboxed, so `.claude/settings.fragment.json` keeps their inputs out of reach:

- `denyWrite` covers the parts of the dotfiles main checkout that `~/.dotfiles`
  makes live: `.claude` (hooks), `.config` (gh aliases, mise, uv, Devin),
  `.local/bin` (`gws`, `sbx`), `.ssh` (`ProxyCommand`), `.gitconfig` and
  `.bunfig.toml`. Seatbelt resolves symlinks, so these name the checkout, not
  `~/.claude/scripts` and friends. Edit them in a worktree as usual.
- `~/.local/share/mise` is not writable: the installed tools there (gh included)
  run unsandboxed. Install or bump mise tools from your own shell.
- `git pull` is not excluded, because it merges in the unsandboxed process and
  runs post-merge/post-checkout hooks. Fetch, then merge sandboxed.
- `git-push-no-verify.sh` (PreToolUse on `git push`) runs the repo's pre-push
  hook itself, inside `srt` (sandbox-runtime) with the rules of Claude's sandbox
  read from `~/.claude/settings.json`, the worktree and a fresh `TMPDIR` writable,
  and git's usual arguments and stdin. A failing hook blocks the push with its
  output; a passing one (or none) gets the call rewritten to
  `git push --no-verify ...`, so git doesn't run the hook again unsandboxed (it
  would run lefthook, `lefthook.yml` and project code from the worktree). A push
  that already says `--no-verify` is still checked, unless that commit already
  passed for that remote branch (passes are recorded in
  `~/.cache/claude-push-checks`, outside the sandbox's reach): auto mode makes
  Claude re-issue a rewritten call, and that shouldn't run the checks twice. A
  missing `srt` blocks, and any error in the hook script blocks rather than
  letting git run the hook. The hook runs with `LEFTHOOK_EXCLUDE=ci` (added to
  any value already set): CI owns the full test gate, so a repo tags heavy or
  host-dependent lefthook jobs `tags: [ci]` and the sandboxed check skips them
  (your own pushes still run them). A failure leads with the lines that look like
  failures, notes permission errors that may be the sandbox, shows the last 40
  lines, and saves the full log to `~/.cache/claude-push-checks/failed-<repo>.log`.
  Override with `CLAUDE_ALLOW_PUSH_HOOKS=1` (git runs the hook unsandboxed).
- `git-remote-guard.sh` (PreToolUse on `git push|fetch|ls-remote`) blocks the call
  unless git would read its config only from the expected files. The sandbox
  protects `.git/config` and `.git/hooks`, but a worktree's `.git` file and its
  gitdir's `commondir` are writable, and repointing them at a git dir in a scratch
  dir would hand its `core.sshCommand`, credential helper or `receivepack` to the
  unsandboxed git. Override with `CLAUDE_ALLOW_GIT_REMOTE_ANYWHERE=1`.
- `gh` subcommands that leave code behind, print the token or check out code
  unsandboxed (which runs the post-checkout hook and so mise) are denied: `gh alias
  set/import`, `gh extension`, `gh config set`, `gh auth status -t`, `gh auth
  login/refresh/setup-git`, `gh codespace`, `gh pr checkout`, `gh repo clone/fork`.
  `gh gist`, `gh repo create`, `gh release create`, and `gh issue/pr create` or
  `comment` aimed at another repo (`-R`/`--repo`) ask. Claude fetches PR branches
  with `git fetch` instead.
- `~/worktrees` is not writable as a whole. Claude Code adds the session's own
  worktree, so one session can't plant a `mise.toml` or `lefthook.yml` in another
  repo's worktree.
- Inside the sandbox `.zshenv` points the uv and bun caches, the aube store and
  cache, and pnpm's store, cache, state and `PNPM_HOME` at `~/.cache/sandbox/...`,
  the only package dir the sandbox may write. The ones your own shell installs
  from and runs out of (aube runs packages from its cache's global virtual store,
  pnpm runs its self-managed versions from `PNPM_HOME`) stay read-only to it.
  `~/Library/Caches/aube` stays writable; it holds only network tuning state.
  `CARGO_HOME`, `GOPATH` and `GOCACHE` move there too (cargo's registry holds the
  crate sources whose `build.rs` runs on build); `~/.cargo/bin` stays on `PATH`.
  So do miniflare's and wrangler's dev registries (`CLOUDFLARE_DEV_REGISTRY_PATH`,
  `WRANGLER_REGISTRY_PATH`), which local workers use to find each other: a
  sandboxed dev server can't point your own ones elsewhere. `workers.cloudflare.com`
  is allowed for miniflare's `cf.json` fetch.
- pnpm 12 takes its store lock in `/tmp/pnpm-store-operation-locks-<uid>` whatever
  `TMPDIR` says, so that dir and the lock files in it are writable (the glob needs
  a separate `/**` entry, since `*` does not cross `/`).
- `enableWeakerNetworkIsolation` lets sandboxed commands reach
  `com.apple.trustd.agent`. aube and pnpm 12 (Rust, rustls-platform-verifier) and
  Go tools verify TLS through Security.framework, which fails without it
  (`OSStatus -26276`). The cost: trustd fetches OCSP/CRL/AIA URLs for the
  certificates it checks, outside the proxy, a narrow exfiltration path.
- `CF_TOKEN_ADMIN` and `CLOUDFLARE_API_TOKEN` are withheld from sandboxed commands,
  for when Claude starts from a shell where fnox has loaded them.

The fragment's `obsolete` lists name entries an earlier version added and that are
now unsafe (`~/.local/share/mise` in `allowWrite`, `git pull *` in
`excludedCommands`); `merge-settings.sh` removes them from an existing settings
file. Remove `~/.cache/uv`, `~/.bun/install/cache` and `~/worktrees` from an
existing `sandbox.filesystem.allowWrite` by hand.

`.config/devin/config.json` follows the same rules where Devin has them: no mise
writes, no `git pull` exclusion, the same `gh` denies. Devin keeps `~/worktrees`
and the shared caches writable, and has no push hooks.

Known gaps, accepted for now: `gh` and `github.com` remain exfiltration channels.
The sandbox can reach the macOS keychain (sandbox-runtime always allows
`securityd`), so a sandboxed command can read fnox's keychain secrets without a
prompt; see #149.

## Claude worktree cleanup

`gws --clean` rescans and lists every `done` item (a merged or closed PR's head is
exactly the branch HEAD) across all repos; `gws --clean --yes` removes those
worktrees and deletes those local branches. Each one is rechecked first and kept if
it has local changes, moved since the scan, or its directory is gone. Orphans are
never removed, however old: the age column in `gws` is for triage only. Ignored
files in a removed worktree (`node_modules`, `.env.local`) go with it.

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

`sbx [--offline] [--rw-git] [cmd...]` (from inside an `untrusted` tree) runs a
command, or a shell, in a bubblewrap sandbox: `/` read-only, a throwaway `$HOME`
per repo (no `~/.ssh`, `~/.config/gh`, `~/.claude`, ssh-agent or tokens), scrubbed
environment, only the current repo writable, mise trust and tool installs confined
to the sandbox (`~/.local/share/sbx`). The repo's `.git` stays read-only, because
git on the host runs whatever `.git/config` names (`core.fsmonitor`,
`core.sshCommand`, hooks); `--rw-git` lifts that for a trusted git command only. It
narrows what a hostile install script or dev server can touch; it is not a VM.
Needs `bubblewrap` on Linux. On macOS (no `bwrap`) it uses `srt`
(`@anthropic-ai/sandbox-runtime`, pinned in the global mise config, Seatbelt
underneath; `SBX_BACKEND=bwrap|srt` forces one): the real `$HOME` stays but is
unreadable except the repo, its git dirs, mise and bun binaries and a cache dir of
sbx's own (`~/.local/share/sbx/cache`), the same scrubbed environment, only the
repo writable, and the network limited to the npm, PyPI and GitHub hosts (add more
with `SBX_DOMAINS="host ..."`; `--offline` allows none).

`sbx --audit TREE cmd...` and `sbx --audit-prepare TREE cmd...` are for running
proof-of-concept code from an untrusted repo (security audits) with enforced
limits. **Use them in a disposable Linux VM, not on a workstation**: bwrap only
(refused on `srt`, with `--rw-git`, or when the systemd scope limits cannot be
applied, checked with a probe). Always offline, a fresh tmpfs `$HOME` per call, the
toolchain (`~/.local/share/sbx/mise`) read-only, and only `/work` writable.
`--audit` copies TREE (bound read-only) into a size-limited tmpfs at `/work` and
runs there, so every PoC starts from the same prepared tree. `--audit-prepare` binds
TREE itself writable at `/work` (its `.git` stays read-only, since host git runs what
`.git/config` and hooks name): use it once, offline, to run install and build
scripts after fetching dependencies with scripts disabled; the shared path keeps
absolute paths in virtualenvs and native builds valid in each `--audit` copy. Limits
come from a transient `systemd-run --user --scope` plus `ulimit -f`, overridable per
call: `SBX_AUDIT_MEM` (2G), `SBX_AUDIT_TASKS` (256), `SBX_AUDIT_CPU` (100%),
`SBX_AUDIT_TIME` (300 seconds), `SBX_AUDIT_FSIZE_MB` (1024, one file),
`SBX_AUDIT_WORK_MB` (1024, size of `/work` for `--audit` only: `--audit-prepare`
writes to TREE's own filesystem and can use all the space there), `SBX_AUDIT_SCRATCH_MB` (256, size of
`$HOME` and `/tmp`). Tests: `tests/sbx-audit.bats` (fake `bwrap` and `systemd-run`,
runs anywhere) and `tests/sbx-audit-real.bats` (real limits, skipped without bwrap
and a user scope).

`.config/git/template/hooks/post-checkout` installs lefthook's git hooks when a repo
is cloned or a worktree is created (git runs `post-checkout` for both), only inside
the two first-party trees. `install.sh` sets it as the git template, so new clones
get it, and copies it into existing first-party repos.

`git-autofetch.timer` (systemd user timer, Linux) runs `git fetch --all --prune` in
every first-party repo under `~/projects/*/*` every 10 minutes (untrusted repos are
skipped: fetch them with `sbx --rw-git git fetch`). It needs a running ssh-agent
for SSH remotes.
