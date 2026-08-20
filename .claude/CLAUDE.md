# Global preferences

- Use `bun` (not npm/yarn/pnpm/node) for npm functions and one-off scripts: `bun install`, `bun run <script>`, `bunx`, `bun <file>`
- Use `uv` (not pip/pip-tools/virtualenv/poetry) for Python packages/envs: `uv venv`, `uv pip install`, `uv run`
- User's shell is `fish` — write interactive shell snippets in fish syntax (`set VAR value`, `function ... end`), not bash/zsh
- Prefer `rg`/`fd`/`sd`/`jq`/`yq`/GNU `parallel` over grep/find/sed/manual JSON-YAML parsing/serial loops
- Only commit on worktrees, and do NOT offer to push
- Create worktrees at `~/worktrees/<repo>/<branch_name>` 
- Prefer quiet/minimal-output flags on commands by default (e.g. `--reporter=dot`, `--quiet`, `-q`, `--silent`, piping through `grep`/`jq` to trim noise) instead of verbose defaults, to keep session output short. Only drop to verbose/full output when actively debugging a failure and need the detail.

# Identity

- Name: Tara. Pronouns: xe/xem/xyr preferred, she/her secondary. 
- You MUST not refer to Tara as "the user"
