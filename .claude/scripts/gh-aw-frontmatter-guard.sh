#!/usr/bin/env bash
# Claude Code PreToolUse hook for Edit|Write. Stops Claude widening a gh aw
# workflow's own privileges unnoticed: for .github/workflows/*.md it asks when the
# edit would change a privilege-bearing frontmatter key (permissions, tools,
# network, safe-outputs, engine, imports) compared with origin/main, or when the
# file is new on this branch. Prompt-body edits and other keys pass silently, so
# the permissions rules decide. The permission rules cover the *.yml workflows.
set -uo pipefail

keys='permissions tools network safe-outputs engine imports'

input=$(cat)
[ "$(jq -r '.tool_name // empty' <<<"$input")" = Edit ] ||
  [ "$(jq -r '.tool_name // empty' <<<"$input")" = Write ] || exit 0
file=$(jq -r '.tool_input.file_path // empty' <<<"$input")
case $file in */.github/workflows/*.md) ;; *) exit 0 ;; esac

ask() {
  jq -cn --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
  exit 0
}

# sensitive <text on stdin>: JSON of the privilege-bearing frontmatter keys
sensitive() {
  local fm
  fm=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } NR > 1 { print }')
  [ -n "$fm" ] || { echo '{}'; return; }
  local sel='' k
  for k in $keys; do sel+="\"$k\": .\"$k\","; done
  yq -o=json -I=0 "{${sel%,}}" <<<"$fm" 2>/dev/null || echo 'unparsable'
}

if [ "$(jq -r '.tool_name' <<<"$input")" = Write ]; then
  new=$(jq -r '.tool_input.content // empty' <<<"$input")
else
  [ -f "$file" ] || exit 0
  # apply the replacement in jq so the text is matched literally
  new=$(jq -rn --rawfile cur "$file" --argjson i "$(jq -c .tool_input <<<"$input")" '
    ($i.old_string) as $o | ($i.new_string) as $n |
    if $o == "" then $cur
    elif ($i.replace_all // false) then $cur | split($o) | join($n)
    else ($cur | index($o)) as $p | if $p == null then $cur else $cur[:$p] + $n + $cur[$p + ($o | length):] end
    end')
fi

dir=$(dirname "$file")
rel=$(git -C "$dir" ls-files --full-name --error-unmatch -- "$file" 2>/dev/null) || rel=''
if [ -z "$rel" ]; then
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
  rel=${file#"$top"/}
fi
base=$(git -C "$dir" show "origin/main:$rel" 2>/dev/null) ||
  ask "New gh aw workflow source $rel: review its permissions, tools, network and safe-outputs."

old=$(sensitive <<<"$base")
now=$(sensitive <<<"$new")
if [ "$old" != "$now" ] || [ "$now" = unparsable ]; then
  ask "This edit changes privilege-bearing frontmatter in $rel (permissions, tools, network, safe-outputs, engine or imports) or leaves it unparsable."
fi
exit 0
