# Global preferences

- Use `bun` (not npm/yarn/pnpm/node) for npm functions and one-off scripts: `bun install`, `bun run <script>`, `bunx`, `bun <file>`
- Use `uv` (not pip/pip-tools/virtualenv/poetry) for Python packages/envs: `uv venv`, `uv pip install`, `uv run`
- User's shell is `zsh` 
- Prefer `rg`/`fd`/`jq`/`yq`/GNU `parallel` over grep/find/manual JSON-YAML parsing/serial loops
- All changes to a git repo happen in a worktree. Before the first edit or commit in a repo's main checkout (wherever the session was launched), call `EnterWorktree` with a short kebab-case name; do not ask first. A PreToolUse hook (`require-worktree.sh`) blocks Edit/Write/NotebookEdit and `git commit` in a main checkout. Skip this only for files outside git repos (e.g. `~/.claude`, scratchpad, memory).
- Commit on worktrees without asking: small logical commits as work progresses, and always before finishing a task (never leave a worktree with uncommitted work). Never commit on main/master. Pushing and opening PRs (`gh pr create`) is allowed on worktrees without asking first; still never push directly to main/master or force-push
- Claude-created worktrees (`--worktree`, subagent isolation) are placed at `~/worktrees/<tier>/<repo>/<name>` (`<tier>` is the repo's dir under `~/projects`: personal, ravenflight or untrusted) by WorktreeCreate/WorktreeRemove hooks in settings.json (`~/.claude/scripts/worktree-{create,remove}.sh`). Branches are named `worktree-<name>`. The `worktree.location` setting is desktop-SSH only and not read by the CLI, so the hook is the supported way to relocate them.
- Never remove or prune worktrees yourself (`git worktree remove/prune`, `ExitWorktree` with `remove`, `rm -rf` on a worktree dir); these are denied in settings. When a worktree's work is done and its PR is open, leave it (`ExitWorktree` with `keep`) and, if it's locked, run `git worktree unlock <path>`. `~/.claude/scripts/cleanup-worktrees.sh` removes worktrees (any location) whose PR is merged or closed. Don't touch the main checkout's branch/state to "tidy up" after a worktree session.
- Prefer quiet/minimal-output flags on commands by default (e.g. `--reporter=dot`, `--quiet`, `-q`, `--silent`, piping through `rg`/`jq` to trim noise). Drop to verbose output only when debugging a failure.
- Writing style: avoid stock filler words like "genuinely" and similar hedging/intensifier cruft. Avoid em dashes (—) and unicode arrows (→, ⟶, etc.) in prose; use plain punctuation instead (commas, "to", parentheses). Avoid decorative unicode bullet dots (•) — use markdown `-` lists instead.

# Identity

- Name: Tara. Pronouns: xe/xem/xyr preferred, she/her secondary. 
- You MUST not refer to Tara as "the user"
