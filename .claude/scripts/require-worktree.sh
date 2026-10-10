#!/usr/bin/env bash
# Claude Code PreToolUse hook. Blocks file edits (Edit|Write|NotebookEdit) and
# `git commit` (Bash) when the target is a repo's main checkout, so Claude must
# EnterWorktree first. Paths outside git repos are allowed. Escape hatch:
# CLAUDE_ALLOW_MAIN_EDITS=1.
set -uo pipefail
[ "${CLAUDE_ALLOW_MAIN_EDITS:-}" = 1 ] && exit 0

input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input")
case $tool in
  Edit | Write) target=$(jq -r '.tool_input.file_path // empty' <<<"$input") ;;
  NotebookEdit) target=$(jq -r '.tool_input.notebook_path // empty' <<<"$input") ;;
  Bash) target=$(jq -r '.cwd // empty' <<<"$input") ;;
  *) exit 0 ;;
esac
[ -n "$target" ] || exit 0

dir=$target
[ "$tool" = Bash ] || dir=$(dirname "$target")
while [ ! -d "$dir" ] && [ "$dir" != / ]; do dir=$(dirname "$dir"); done

gitdir=$(git -C "$dir" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
[ "$gitdir" = "$common" ] || exit 0

cat >&2 <<MSG
Blocked: $target is in a repo's main checkout. Call EnterWorktree (short
kebab-case name) first, make changes there, and commit freely on the worktree
branch. Set CLAUDE_ALLOW_MAIN_EDITS=1 only if Tara explicitly asks for edits in place.
MSG
exit 2
