# Global preferences

- Use `bun` (not npm/yarn/pnpm/node) for npm functions and one-off scripts: `bun install`, `bun run <script>`, `bunx`, `bun <file>`
- Use `uv` (not pip/pip-tools/virtualenv/poetry) for Python packages/envs: `uv venv`, `uv pip install`, `uv run`
- Prefer `rg`/`fd`/`jq`/`yq`/GNU `parallel` over grep/find/manual JSON-YAML parsing/serial loops
- All changes to a git repo happen in a worktree: before the first edit or commit in a main checkout, call `EnterWorktree` with a short kebab-case name without asking (a hook blocks edits and commits there). Files outside git repos (`~/.claude`, scratchpad, memory) are exempt.
- Worktrees live at `~/worktrees/<tier>/<repo>/<name>` (`<tier>`: personal, ravenflight or untrusted, the repo's dir under `~/projects`), placed by WorktreeCreate/Remove hooks. Branches are `worktree-<name>`.
- Commit on worktrees without asking: small logical commits as work progresses, and always before finishing a task. Pushing and opening PRs is allowed without asking. Never commit or push to main/master, never force-push.
- Never remove or prune worktrees (denied in settings). When work is done and its PR is open, `ExitWorktree` with `keep` and `git worktree unlock <path>` if locked. Don't touch the main checkout's branch/state to "tidy up".
- git-branchless is installed (global mise): in repos where `git branchless init` has already run, `git sl` shows the smartlog and `git restack`/`git amend`/`git move`/`git absorb` manage stacked commits. Don't run `git branchless init` yourself. `git submit` pushes internally but is not sandbox-excluded, so its push fails; push with `git push` and open PRs with `gh pr create` instead.
- Bash runs in a strict sandbox. `gh`, `git push/fetch/pull/ls-remote` are excluded and run with real credentials, but only when the whole call matches: run each as its own Bash call from inside the repo, with no pipe, `&&`/`;` chain, `cd`, redirect to a file, `VAR=x` prefix, `git -C <dir>` or `git -c ...`, or backticks/`$(...)` anywhere in the arguments (use `--body-file`, `--jq`/`-q`, `-L`). A keyring/TLS/`~/.ssh` error from these means the call didn't match; fix the call shape, don't swap remotes, credential helpers or skip hooks. Push and open PRs yourself; never hand `! git push`/`gh pr create` to Tara unless the sandbox blocks it for another reason, and then say which.
- Prefer quiet/minimal-output flags on commands by default (e.g. `--reporter=dot`, `--quiet`, `-q`, `--silent`, piping through `rg`/`jq` to trim noise). Drop to verbose output only when debugging a failure.
- Writing style: avoid stock filler words like "genuinely" and similar hedging/intensifier cruft. Never use em dashes (U+2014), en dashes (U+2013), middle dots (U+00B7), bullet dots (U+2022) or unicode arrows (U+2192 and friends), in prose, code, comments, UI strings or separators. Use plain ASCII instead: commas, parentheses, "to", a hyphen, or markdown `-` lists. Never put a period or other punctuation directly after text meant to be copied (commands, URLs, paths, flags). Reword or use a code block so the copyable text stays clean.

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

# PR follow-up (reviews and CI)

Bots in CI (CodeRabbit, Codacy) / Tara may review PRs

- After opening a PR, check it once immediately (`gh pr checks`, then reviews and inline comments via `gh pr view --comments` and `gh api` with `--jq`), then schedule a re-check about 10 minutes later (`ScheduleWakeup` when running under `/loop`, otherwise `CronCreate` with `recurring: false`). Scheduled re-checks only fire while the session stays open, so tell Tara the re-check is pending and will not run if the session is closed.
- Each check: fix failing CI, and address review comments. Apply the `superpowers:receiving-code-review` approach: verify each finding, apply the valid ones, and reply on the thread with a short reason when declining a wrong or noisy one. Commit, push, and resolve the threads you addressed.
- If a check pushed changes, schedule one more check about 10 minutes later (new pushes retrigger the bots). If a follow-up check (not the initial one) finds no new comments, no new reviews and CI green (or still pending with no failures), stop: do not schedule another, and say the PR is quiet.
- Never loop indefinitely: stop after 3 max follow-up rounds even if comments keep arriving, and tell Tara what remains. When stopping, cancel any pending schedule: `ScheduleWakeup` with `stop: true` under `/loop`, or `CronDelete` for a PR-specific cron job.
- Keep every `gh` call a bare call (see Bash sandbox note above): no pipes, chains, or shell loops around it.
- Do not merge the PR; that stays Tara's call.

# Identity

- Name: Tara. Pronouns: xe/xem/xyr preferred, she/her secondary.
- Never refer to Tara as "the user".
