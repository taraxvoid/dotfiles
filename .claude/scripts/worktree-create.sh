#!/usr/bin/env bash
# Claude Code WorktreeCreate hook. Reads {"cwd","name",...} JSON on stdin,
# creates ~/worktrees/<tier>/<repo>/<name> on branch worktree-<name> and prints
# its absolute path (and nothing else) on stdout. <tier> is the repo's dir
# under ~/projects (personal, ravenflight, untrusted). Idempotent.
set -euo pipefail

input=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$input")
name=$(jq -r '.name // empty' <<<"$input")
[ -n "$cwd" ] && [ -n "$name" ] || { echo "worktree-create: missing cwd or name" >&2; exit 1; }
name=${name//\//-}

common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir)
main=$(dirname "$common")
repo=$(basename "$main")
rel=${main#"$HOME/projects/"}
if [ "$rel" != "$main" ]; then tier=${rel%%/*}; else tier=other; fi

dest="$HOME/worktrees/$tier/$repo/$name"
branch="worktree-$name"

if [ ! -e "$dest" ]; then
  mkdir -p "$(dirname "$dest")"
  git -C "$main" fetch -q origin >/dev/null 2>&1 || true
  base=$(git -C "$main" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -z "$base" ]; then
    for b in origin/main origin/master; do
      git -C "$main" rev-parse -q --verify "$b" >/dev/null && { base=$b; break; }
    done
  fi
  base=${base:-HEAD}
  if git -C "$main" rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
    git -C "$main" worktree add -q "$dest" "$branch" >&2
  else
    git -C "$main" worktree add -q -b "$branch" "$dest" "$base" >&2
  fi
fi

printf '%s\n' "$dest"
