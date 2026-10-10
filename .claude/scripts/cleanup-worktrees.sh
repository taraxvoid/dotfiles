#!/usr/bin/env bash
# Remove git worktrees whose PR is merged or closed. Works on macOS and
# Debian/Ubuntu (bash 3.2+, no GNU-only flags). Needs git and an authed gh.
#
#   cleanup-worktrees.sh [-n] [repo-dir]
#
#   -n, --dry-run   print what would be removed, change nothing
#   repo-dir        any checkout or worktree of the repo (default: cwd)
#
# A worktree is removed only when all of these hold:
#   - it is not the main checkout and has a branch (not detached)
#   - no PR for the branch is open
#   - a merged/closed PR has a head commit equal to the worktree's HEAD, so
#     work added after the merge is never thrown away
#   - the worktree has no uncommitted or untracked files
# Locked worktrees are unlocked first. Branches are left alone.
set -euo pipefail

dry=0
repo=.
while [ $# -gt 0 ]; do
  case $1 in
    -n | --dry-run) dry=1 ;;
    -h | --help) sed -n '2,/^set -/p' "$0" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
    *) repo=$1 ;;
  esac
  shift
done

command -v gh >/dev/null || { echo "gh not found" >&2; exit 1; }
git -C "$repo" rev-parse --git-dir >/dev/null

say() { printf '%s\n' "$*"; }

# main checkout is always the first entry
main=$(git -C "$repo" worktree list --porcelain | awk 'NR==1{sub(/^worktree /,""); print; exit}')

# one record per worktree: path<TAB>branch<TAB>head<TAB>locked(0|1)
records=$(git -C "$repo" worktree list --porcelain | awk '
  function flush() { if (path != "") printf "%s\t%s\t%s\t%d\n", path, branch, head, locked; path = branch = head = ""; locked = 0 }
  /^worktree / { flush(); path = substr($0, 10) }
  /^HEAD /     { head = substr($0, 6) }
  /^branch /   { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
  /^locked/    { locked = 1 }
  END          { flush() }
')

removed=0
while IFS=$'\t' read -r -u 3 path branch head locked; do
  [ "$path" = "$main" ] && continue
  if [ -z "$branch" ]; then say "skip   $path (detached HEAD)"; continue; fi

  prs=$(cd "$main" && gh pr list --head "$branch" --state all --limit 50 \
    --json state,headRefOid --jq '.[] | "\(.state) \(.headRefOid)"')
  if [ -z "$prs" ]; then say "skip   $path ($branch: no PR)"; continue; fi
  if printf '%s\n' "$prs" | grep -q '^OPEN '; then say "skip   $path ($branch: PR open)"; continue; fi
  if ! printf '%s\n' "$prs" | grep -q " $head\$"; then
    say "skip   $path ($branch: HEAD differs from every PR head, unmerged commits?)"; continue
  fi
  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
    say "skip   $path ($branch: uncommitted changes)"; continue
  fi

  if [ "$dry" = 1 ]; then say "would remove $path ($branch)"; continue; fi
  if [ "$locked" = 1 ]; then git -C "$main" worktree unlock "$path"; fi
  git -C "$main" worktree remove "$path"
  say "removed $path ($branch)"
  removed=$((removed + 1))
done 3<<<"$records" # fd 3: gh/git would otherwise eat the loop's stdin

if [ "$dry" = 0 ]; then
  git -C "$main" worktree prune
  say "$removed worktree(s) removed"
fi
