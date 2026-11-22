#!/usr/bin/env bash
# Claude Code PreToolUse hook for Bash `git push`. `git push` is a sandbox-excluded
# command (it needs real credentials), and git runs the repo's pre-push hook in
# that same unsandboxed process. lefthook's pre-push reads lefthook.yml and
# lefthook-local.yml from the worktree and runs project code (tests, node_modules),
# all of which sandboxed commands can write, so letting the hook run would run
# sandbox-written code outside the sandbox. This hook rewrites a bare
# `git push ...` to `git push --no-verify ...` (via updatedInput) so no git hook
# runs there. Run pre-push checks sandboxed first instead: `lefthook run pre-push`.
# Only a lone `git push` is rewritten: anything chained or prefixed does not match
# the sandbox exclusion anyway, so it runs sandboxed and cannot push.
# Escape hatch: CLAUDE_ALLOW_PUSH_HOOKS=1.
set -uo pipefail
[ "${CLAUDE_ALLOW_PUSH_HOOKS:-}" = 1 ] && exit 0

input=$(cat)
[ "$(jq -r '.tool_name // empty' <<<"$input")" = Bash ] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")

# leading whitespace, `git push`, then end or whitespace
re='^([[:space:]]*git[[:space:]]+push)([[:space:]]|$)(.*)$'
[[ $cmd =~ $re ]] || exit 0
rest=${BASH_REMATCH[2]}${BASH_REMATCH[3]}
# already skipping hooks (push has no short form: its -n is --dry-run)
[[ " $rest " == *[[:space:]]--no-verify[[:space:]]* ]] && exit 0

# Insert right after `git push` so deny rules anchored on the tail
# (`git push * main`, `git push * --force*`) still match.
fixed="git push --no-verify$rest"
jq -cn --arg c "$fixed" --argjson i "$(jq -c '.tool_input' <<<"$input")" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: ($i + {command: $c})
  }
}'
exit 0
