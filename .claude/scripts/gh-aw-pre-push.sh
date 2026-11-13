#!/usr/bin/env bash
# Claude Code PreToolUse hook for Bash `git push`. In a repo with gh aw workflow
# sources (.github/workflows/*.md), runs `gh aw compile --strict` first and blocks
# (exit 2) the push when compile fails or rewrites a lock file, so CI does not
# turn red on a stale or invalid *.lock.yml. Repos without gh aw sources are
# untouched. Escape hatch: CLAUDE_SKIP_GH_AW_PUSH_CHECK=1.
set -uo pipefail
[ "${CLAUDE_SKIP_GH_AW_PUSH_CHECK:-}" = 1 ] && exit 0

input=$(cat)
[ "$(jq -r '.tool_name // empty' <<<"$input")" = Bash ] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
re='(^|[;&|(]|[[:space:]])git[[:space:]]+push([[:space:]]|$)'
[[ $cmd =~ $re ]] || exit 0

cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0
top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$top" || exit 0
# gh aw only counts .md files whose first line is the frontmatter opener; compile
# errors out when it finds none, so skip repos without such a file
found=0
for f in .github/workflows/*.md; do
  [ -f "$f" ] && [ "$(head -n 1 "$f")" = '---' ] && found=1 && break
done
[ "$found" = 1 ] || exit 0

before=$(git status --porcelain -- '.github/workflows/*.lock.yml')
if ! out=$(gh aw compile --strict 2>&1); then
  {
    echo "Blocked push: gh aw compile --strict failed."
    tail -n 20 <<<"$out"
  } >&2
  exit 2
fi
after=$(git status --porcelain -- '.github/workflows/*.lock.yml')
if [ "$before" != "$after" ]; then
  {
    echo "Blocked push: gh aw compile --strict changed lock files. Review, commit them, then push."
    echo "$after"
  } >&2
  exit 2
fi
exit 0
