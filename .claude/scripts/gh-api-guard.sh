#!/usr/bin/env bash
# Claude Code PreToolUse hook for Bash. Keeps `gh api` read-only:
#   - denies (exit 2) any call that writes: -X/--method other than GET, -f/-F/
#     --field/--raw-field (they turn the call into a POST), or --input;
#   - asks for `gh api graphql` (always a POST, and it takes -f query=...);
#   - says nothing otherwise, so the permissions.allow/deny rules in
#     settings.fragment.json decide.
# Unlike glob rules it copes with -XPOST, --method=POST, -fname=x and flags
# placed before the endpoint. Escape hatch: CLAUDE_ALLOW_GH_API_WRITES=1.
set -uo pipefail
[ "${CLAUDE_ALLOW_GH_API_WRITES:-}" = 1 ] && exit 0

input=$(cat)
[ "$(jq -r '.tool_name // empty' <<<"$input")" = Bash ] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
cmd=${cmd//$'\n'/ }

re='(^|[;&|(]|[[:space:]])gh[[:space:]]+api([[:space:]]+|$)'
deny=() ask=()

# scan <args after "gh api">: sets deny/ask reasons
scan() {
  local -a t
  local i=0 a m endpoint='' bad=()
  read -r -a t <<<"$1"
  while ((i < ${#t[@]})); do
    a=${t[i]}
    # the next invocation is handled by the caller's loop
    if [ "$a" = gh ] && [ "${t[i + 1]:-}" = api ]; then break; fi
    case $a in
      -X | --method)
        m=$(tr "[:lower:]" "[:upper:]" <<<"${t[i + 1]:-}")
        [ "$m" = GET ] || bad+=("$a ${t[i + 1]:-} sets a non-GET method")
        ((i += 2))
        ;;
      -X?* | --method=*)
        m=$(tr "[:lower:]" "[:upper:]" <<<"${a#-X}")
        m=${m#--METHOD=}
        [ "$m" = GET ] || bad+=("$a sets a non-GET method")
        ((i += 1))
        ;;
      -f | -F | --field | --raw-field | --input)
        bad+=("$a sends a request body")
        ((i += 2))
        ;;
      -f?* | -F?* | --field=* | --raw-field=* | --input=*)
        bad+=("$a sends a request body")
        ((i += 1))
        ;;
      -H | --header | -q | --jq | -t | --template | --cache | --hostname | -p | --preview)
        ((i += 2))
        ;;
      -*) ((i += 1)) ;;
      *)
        a=${a//[\"\']/}
        endpoint=${endpoint:-$a}
        ((i += 1))
        ;;
    esac
    # stop at the end of this command (`;`, `&&`, `||`)
    case $a in *\; | '&&' | '||') break ;; esac
  done
  # graphql needs -f query=..., so its body flags are asked about, not denied
  if [ "${endpoint#/}" = graphql ]; then
    ask+=("gh api graphql is a POST and can mutate")
  elif [ ${#bad[@]} -gt 0 ]; then
    deny+=("${bad[0]}")
  fi
}

rest=$cmd
while [[ $rest =~ $re ]]; do
  rest=${rest#*"${BASH_REMATCH[0]}"}
  scan "$rest"
done

if [ ${#deny[@]} -gt 0 ]; then
  {
    echo "Blocked: gh api must stay read-only (${deny[0]})."
    echo "Use a dedicated gh subcommand for writes (gh pr create, gh issue comment, ...)."
    echo "Set CLAUDE_ALLOW_GH_API_WRITES=1 only if Tara explicitly asks for a write via gh api."
  } >&2
  exit 2
fi
if [ ${#ask[@]} -gt 0 ]; then
  jq -cn --arg r "${ask[0]}" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
fi
exit 0
