# Global preferences

- Use `bun` (not npm/yarn/pnpm/node) for npm functions and one-off scripts: `bun install`, `bun run <script>`, `bunx`, `bun <file>`
- Use `uv` (not pip/pip-tools/virtualenv/poetry) for Python packages/envs: `uv venv`, `uv pip install`, `uv run`
- Prefer `rg`/`fd`/`jq`/`yq`/GNU `parallel` over grep/find/manual JSON-YAML parsing/serial loops
- All changes to a git repo happen in a worktree: before the first edit or commit in a main checkout, call `EnterWorktree` with a short kebab-case name without asking (a hook blocks edits and commits there). Files outside git repos (`~/.claude`, scratchpad, memory) are exempt.
- Worktrees live at `~/worktrees/<tier>/<repo>/<name>` (`<tier>`: personal, ravenflight or untrusted, the repo's dir under `~/projects`), placed by WorktreeCreate/Remove hooks. Branches are `worktree-<name>`.
- Commit on worktrees without asking: small logical commits as work progresses, and always before finishing a task. Pushing and opening PRs is allowed without asking. Never commit or push to main/master, never force-push.
- Never remove or prune worktrees (denied in settings). When work is done and its PR is open, `ExitWorktree` with `keep` and `git worktree unlock <path>` if locked. Don't touch the main checkout's branch/state to "tidy up".
- Bash runs in a strict sandbox. `gh`, `git push/fetch/pull/ls-remote` (also with `git -C <dir>`) are excluded and run with real credentials, but only when the whole call matches: run each as its own Bash call, with no pipe, `&&`/`;` chain, `cd`, redirect to a file, `VAR=x` prefix, `git -c ...`, or backticks/`$(...)` anywhere in the arguments (use `--body-file`, `--jq`/`-q`, `-L`). A keyring/TLS/`~/.ssh` error from these means the call didn't match; fix the call shape, don't swap remotes, credential helpers or skip hooks. Push and open PRs yourself; never hand `! git push`/`gh pr create` to Tara unless the sandbox blocks it for another reason, and then say which.
- Prefer quiet/minimal-output flags on commands by default (e.g. `--reporter=dot`, `--quiet`, `-q`, `--silent`, piping through `rg`/`jq` to trim noise). Drop to verbose output only when debugging a failure.
- Writing style: avoid stock filler words like "genuinely" and similar hedging/intensifier cruft. Avoid em dashes (—) and unicode arrows (→, ⟶, etc.) in prose; use plain punctuation instead (commas, "to", parentheses). Avoid decorative unicode bullet dots (•); use markdown `-` lists instead.

# Threads of work

Tara should never have to remember in-flight work. Every thread lives on GitHub: an open PR, or a pushed branch linked to an issue. A thread is anything beyond a simple or local-only fix: multi-session work, anything that goes through brainstorming, research or spikes worth keeping. When unsure, create the issue.

- Issue first: `gh issue create` with a short goal and context, then `EnterWorktree` named `<N>-<slug>` so the branch is `worktree-<N>-<slug>`. That branch name is the only issue link; don't use `gh issue develop`.
- Push the branch early (after its first commit). A pushed `worktree-<N>-*` branch with issue #N open counts as tracked.
- Log milestones as issue comments, not body edits: spec approved (artifact link), plan written (artifact link), key decisions or dead ends, PR opened.
- PR bodies always contain `Closes #N` (or `Refs #N` for partial work).
- Research or informational threads end by closing the issue with a findings comment.
- A fix that grows into a thread: if the branch is unpushed, create the issue and `git branch -m worktree-<N>-<slug>`; if already pushed, open the PR with `Refs #N`.
- Specs and plans (overrides superpowers' `docs/superpowers/...` default): write markdown to `~/.claude/plans/<repo>/<YYYY-MM-DD>-<topic>.md`, never commit it, write an HTML rendering next to it (same basename, `.html`), publish that as an artifact, and comment the link on the issue. Republish the same file path on revisions so the link stays stable.
- The Stop hook may block a turn with a `gws:` message when the worktree holds unpushed commits and isn't tracked. Push it with a PR or linked issue, or tell Tara why it stays local; don't just retry.
- `gws` lists in-flight and orphaned work; run it when asked. Like `gh`, it only escapes the sandbox as a bare call of its own.

# Identity

- Name: Tara. Pronouns: xe/xem/xyr preferred, she/her secondary.
- Never refer to Tara as "the user".
