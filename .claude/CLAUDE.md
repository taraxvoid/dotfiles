# Global preferences

- Use `bun` (not npm/yarn/pnpm/node) for npm functions and one-off scripts: `bun install`, `bun run <script>`, `bunx`, `bun <file>`
- Use `uv` (not pip/pip-tools/virtualenv/poetry) for Python packages/envs: `uv venv`, `uv pip install`, `uv run`
- User's shell is `zsh` 
- Prefer `rg`/`fd`/`jq`/`yq`/GNU `parallel` over grep/find/manual JSON-YAML parsing/serial loops
- All changes to a git repo happen in a worktree. Before the first edit or commit in a repo's main checkout (wherever the session was launched), call `EnterWorktree` with a short kebab-case name; do not ask first. A PreToolUse hook (`require-worktree.sh`) blocks Edit/Write/NotebookEdit and `git commit` in a main checkout. Skip this only for files outside git repos (e.g. `~/.claude`, scratchpad, memory).
- Commit on worktrees without asking: small logical commits as work progresses, and always before finishing a task (never leave a worktree with uncommitted work). Never commit on main/master. Pushing and opening PRs (`gh pr create`) is allowed on worktrees without asking first; still never push directly to main/master or force-push
- Run gh, git fetch/pull/push/ls-remote as standalone commands: no pipes, &&, or git -C; they only skip the sandbox when unwrapped.
- Claude-created worktrees (`--worktree`, subagent isolation) are placed at `~/worktrees/<tier>/<repo>/<name>` (`<tier>` is the repo's dir under `~/projects`: personal, ravenflight or untrusted) by WorktreeCreate/WorktreeRemove hooks in settings.json (`~/.claude/scripts/worktree-{create,remove}.sh`). Branches are named `worktree-<name>`. The `worktree.location` setting is desktop-SSH only and not read by the CLI, so the hook is the supported way to relocate them.
- Never remove or prune worktrees yourself (`git worktree remove/prune`, `ExitWorktree` with `remove`, `rm -rf` on a worktree dir); these are denied in settings. When a worktree's work is done and its PR is open, leave it (`ExitWorktree` with `keep`) and, if it's locked, run `git worktree unlock <path>`. `~/.claude/scripts/cleanup-worktrees.sh` removes worktrees (any location) whose PR is merged or closed. Don't touch the main checkout's branch/state to "tidy up" after a worktree session.
- Bash runs in a strict sandbox. `gh`, `git push/fetch/pull/ls-remote` (also with `git -C <dir>`) are excluded and run with real credentials, but only when the whole call matches: run each as its own Bash call, with no pipe, `&&`/`;` chain, `cd`, redirect to a file, `VAR=x` prefix, `git -c ...`, or backticks/`$(...)` anywhere in the arguments (use `--body-file`, `--jq`/`-q`, `-L`). A keyring/TLS/`~/.ssh` error from these means the call didn't match; fix the call shape, don't swap remotes, credential helpers or skip hooks. Push and open PRs yourself; never hand `! git push`/`gh pr create` to Tara unless the sandbox blocks it for another reason, and then say which.
- Prefer quiet/minimal-output flags on commands by default (e.g. `--reporter=dot`, `--quiet`, `-q`, `--silent`, piping through `rg`/`jq` to trim noise). Drop to verbose output only when debugging a failure.
- Writing style: avoid stock filler words like "genuinely" and similar hedging/intensifier cruft. Never use em dashes (U+2014), en dashes (U+2013), middle dots (U+00B7), bullet dots (U+2022) or unicode arrows (U+2192 and friends), in prose, code, comments, UI strings or separators. Use plain ASCII instead: commas, parentheses, "to", a hyphen, or markdown `-` lists.

# Threads of work

Tara should never have to remember in-flight work. Every thread beyond a simple or local-only fix lives on GitHub: an open PR, or a pushed branch linked to an issue. `gws` lists anything that isn't (orphans); the status line shows the current worktree's state and the orphan count.

- A thread is anything beyond a simple or local-only fix: multi-session work, anything that goes through brainstorming (bounded or architectural), research or spikes whose findings are worth keeping. When unsure, create the issue.
- Issue first: `gh issue create` with a short goal and context, then `EnterWorktree` named `<N>-<slug>` so the branch is `worktree-<N>-<slug>`. That branch name is the only issue link; don't use `gh issue develop`.
- Push the branch early (after its first commit). A pushed `worktree-<N>-*` branch with issue #N open counts as tracked.
- Log milestones as issue comments, not body edits: spec approved (artifact link), plan written (artifact link), key decisions or dead ends, PR opened.
- PR bodies always contain `Closes #N` (or `Refs #N` for partial work).
- Research or informational threads end by closing the issue with a findings comment.
- A fix that grows into a thread: if the branch is unpushed, create the issue and `git branch -m worktree-<N>-<slug>`; if already pushed, open the PR with `Refs #N`.
- Specs and plans (overrides superpowers' `docs/superpowers/...` default): write markdown to `~/.claude/plans/<repo>/<YYYY-MM-DD>-<topic>.md`, never commit it, write an HTML rendering next to it (same basename, `.html`), publish that as an artifact, and comment the link on the issue. Republish the same file path on revisions so the link stays stable.
- The Stop hook may block a turn with a `gws:` message when the worktree holds unpushed commits and isn't tracked. Push it with a PR or linked issue, or tell Tara why it stays local; don't just retry.
- Run `gws` when asked what is in flight or orphaned. Like `gh`, it is excluded from the sandbox only as a bare call of its own (it writes `~/.cache` and calls `gh`); `gws --clean --yes` is denied.

# Identity

- Name: Tara. Pronouns: xe/xem/xyr preferred, she/her secondary. 
- You MUST not refer to Tara as "the user"
