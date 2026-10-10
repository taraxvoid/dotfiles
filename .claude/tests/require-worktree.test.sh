#!/usr/bin/env bash
# Table test for .claude/scripts/require-worktree.sh. Run from a linked worktree
# of this repo: it uses the main checkout as the "blocked" target and the current
# worktree as the "allowed" one. Prints only failures, exits 1 on any.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
S=$here/../scripts/require-worktree.sh
W=$(git -C "$here" rev-parse --show-toplevel)
M=$(dirname "$(git -C "$here" rev-parse --path-format=absolute --git-common-dir)")
[ "$M" != "$W" ] || { echo "run this from a linked worktree, not the main checkout" >&2; exit 1; }
O=$HOME
fail=0

run() { # want tool input-json desc
  local got
  CLAUDE_ALLOW_MAIN_EDITS='' bash "$S" <<<"$2" 2>/dev/null
  got=$?
  if [ "$got" != "$1" ]; then echo "FAIL ($got, want $1): $3"; fail=1; fi
}
bash_case() { # want cwd command
  run "$1" "$(jq -nc --arg d "$2" --arg c "$3" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}')" "Bash in $2: $3"
}
edit_case() { # want path
  run "$1" "$(jq -nc --arg f "$2" '{tool_name:"Edit",tool_input:{file_path:$f}}')" "Edit $2"
}

bash_case 0 "$M" 'ls -la'
bash_case 0 "$M" 'git log --oneline -3'
bash_case 0 "$M" 'for f in a b; do cmp -s "$f" x && echo same; done'
bash_case 0 "$M" 'git stash list'
bash_case 0 "$M" 'git pull --ff-only'
bash_case 0 "$M" "git -C $W commit -m x"
bash_case 0 "$W" 'git commit -m x'
bash_case 0 "$O" 'git commit -m x'
bash_case 2 "$M" 'git commit -m x'
bash_case 2 "$M" 'git add . && git commit -m x'
bash_case 2 "$M" 'git stash push -m x'
bash_case 2 "$M" 'git -c core.x=1 checkout -b foo'
bash_case 2 "$M" 'git status; git push'
bash_case 2 "$O" "git -C $M reset --hard"
bash_case 2 "$O" "cd $M && git rebase main"
edit_case 2 "$M/README.md"
edit_case 0 "$W/README.md"
edit_case 0 "$O/.claude/nope.md"

[ $fail = 0 ] && echo "ok"
exit $fail
