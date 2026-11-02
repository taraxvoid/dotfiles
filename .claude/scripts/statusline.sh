#!/usr/bin/env bash
# Claude Code status line: repo/worktree - this worktree's gws state - orphan
# count. Reads only local git and the gws cache and never calls gh, so it stays
# fast. Plain text on purpose: the count is a fact, not an alarm.
set -o pipefail

input=$(cat)
cwd=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input" 2>/dev/null)
cwd=${cwd:-$PWD}
cache=${GWS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/gws.json}
valid=0
if [ -s "$cache" ] && jq -e .totals "$cache" >/dev/null 2>&1; then valid=1; fi

parts=()
if top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
  main=$(dirname "$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir)")
  if [ "$top" = "$main" ]; then
    parts+=("$(basename "$main") ($(git -C "$top" symbolic-ref -q --short HEAD || echo detached))")
  else
    parts+=("$(basename "$main")/$(basename "$top")")
    st=
    if [ "$valid" = 1 ]; then
      st=$(jq -r --arg p "$top" 'first(.items[] | select(.path == $p))
        | if .state == "tracked" then
            (if .issue then "#\(.issue) " else "" end) + "tracked" + (if .pr then " (PR #\(.pr))" else "" end)
          elif .state == "orphaned" then "orphan: \(.reason)"
          else .state end' "$cache")
    fi
    st=${st:-not scanned}
    # the cache only refreshes at session start; a push since then shows here
    if [ "$st" = "orphan: never pushed" ] && b=$(git -C "$top" symbolic-ref -q --short HEAD) &&
      git -C "$top" rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null; then
      st="pushed since scan"
    fi
    if [ -n "$(git -C "$top" status --porcelain 2>/dev/null | head -1)" ]; then st="$st, local changes"; fi
    parts+=("$st")
  fi
else
  tilde='~'
  case $cwd in
    "$HOME"/*) parts+=("$tilde${cwd#"$HOME"}") ;;
    *) parts+=("$cwd") ;;
  esac
fi

if [ "$valid" = 1 ]; then
  n=$(jq -r '.totals.orphaned // 0' "$cache")
  case $n in
    0 | '' | *[!0-9]*) ;;
    1) parts+=("1 orphan") ;;
    *) parts+=("$n orphans") ;;
  esac
  age=$((($(date +%s) - $(date -r "$cache" +%s)) / 86400))
  if [ "$age" -ge 1 ]; then parts+=("scan ${age}d old"); fi
fi

out=${parts[0]}
for p in "${parts[@]:1}"; do out="$out - $p"; done
printf '%s' "$out"
