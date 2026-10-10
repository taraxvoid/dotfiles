#!/usr/bin/env bash
# Claude Code WorktreeRemove hook. Deliberately a no-op: worktrees are never
# removed by Claude. Use cleanup-worktrees.sh (removes only merged/closed PRs).
echo "worktree-remove: leaving worktree in place (use cleanup-worktrees.sh)" >&2
exit 0
