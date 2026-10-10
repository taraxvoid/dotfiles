#!/usr/bin/env bash
# Claude Code PreToolUse hook. Blocks file edits (Edit|Write|NotebookEdit) and
# git commands that change repo state (Bash) when the target is a repo's main
# checkout, so Claude must EnterWorktree first. Other Bash commands (reads,
# builds, tests) and paths outside git repos are allowed. `git pull` is allowed
# so main can be fast-forwarded after a merge. Escape hatch:
# CLAUDE_ALLOW_MAIN_EDITS=1.
set -uo pipefail
[ "${CLAUDE_ALLOW_MAIN_EDITS:-}" = 1 ] && exit 0

# Exit 2 (block) if $1 is inside a repo's main checkout; return otherwise.
check() {
  local target=$1 dir=$2 gitdir common
  while [ ! -d "$dir" ] && [ "$dir" != / ]; do dir=$(dirname "$dir"); done
  gitdir=$(git -C "$dir" rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 0
  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  [ "$gitdir" = "$common" ] || return 0
  cat >&2 <<MSG
Blocked: $target is in a repo's main checkout. Call EnterWorktree (short
kebab-case name) first, make changes there, and commit freely on the worktree
branch. Set CLAUDE_ALLOW_MAIN_EDITS=1 only if Tara explicitly asks for edits in place.
MSG
  exit 2
}

input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input")
case $tool in
  Edit | Write) target=$(jq -r '.tool_input.file_path // empty' <<<"$input") ;;
  NotebookEdit) target=$(jq -r '.tool_input.notebook_path // empty' <<<"$input") ;;
  Bash) ;;
  *) exit 0 ;;
esac

if [ "$tool" != Bash ]; then
  [ -n "$target" ] && check "$target" "$(dirname "$target")"
  exit 0
fi

cwd=$(jq -r '.cwd // empty' <<<"$input")
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[ -n "$cmd" ] || exit 0

# A leading `cd DIR &&` moves where the rest of the command runs.
if [[ $cmd =~ ^[[:space:]]*cd[[:space:]]+([^[:space:];&|]+) ]]; then
  d=${BASH_REMATCH[1]/#\~/$HOME}
  [[ $d = /* ]] || d=$cwd/$d
  cwd=$d
fi

# Each git invocation (optionally with -C DIR / -c k=v) running a subcommand that
# writes commits, refs, the index or the working tree. `stash list|show` is a read.
sep='(^|[;&|(`[:space:]])'
writes='commit|merge|rebase|reset|cherry-pick|revert|stash|checkout|switch|push|add|am|restore|rm|mv|clean'
re="${sep}git(([[:space:]]+-C[[:space:]]+([^[:space:];&|]+))|([[:space:]]+-c[[:space:]]+[^[:space:];&|]+))*[[:space:]]+($writes)([[:space:]]+([^[:space:];&|]+))?"
rest=$cmd
while [[ $rest =~ $re ]]; do
  rest=${rest#*"${BASH_REMATCH[0]}"}
  sub=${BASH_REMATCH[6]} arg=${BASH_REMATCH[8]}
  [ "$sub" = stash ] && [[ $arg = list || $arg = show ]] && continue
  dir=$cwd
  if [ -n "${BASH_REMATCH[4]}" ]; then
    dir=${BASH_REMATCH[4]/#\~/$HOME}
    [[ $dir = /* ]] || dir=$cwd/$dir
  fi
  [ -n "$dir" ] && check "$dir (git $sub)" "$dir"
done
exit 0
