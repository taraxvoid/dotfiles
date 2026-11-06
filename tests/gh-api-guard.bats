setup() {
  load helpers
  setup_env
}

guard() { jq -cn --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | gh-api-guard.sh; }

@test "ignores commands that are not gh api" {
  run guard "gh pr view 3"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run guard "curl -X POST https://example.com -f"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "ignores non-Bash tools" {
  run bash -c 'echo "{\"tool_name\":\"Edit\"}" | gh-api-guard.sh'
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "lets plain reads through silently" {
  run guard "gh api repos/o/r/pulls/1/comments --paginate --jq '.[].body'"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run guard "gh api -H 'Accept: application/vnd.github+json' repos/o/r"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "allows an explicit GET in any spelling" {
  for c in "-X GET" "-XGET" "--method GET" "--method=get"; do
    run guard "gh api $c repos/o/r"
    [ "$status" -eq 0 ]
  done
}

@test "denies non-GET methods in every spelling" {
  for c in "-X POST" "-XPOST" "-X DELETE" "--method PATCH" "--method=PUT"; do
    run guard "gh api repos/o/r $c"
    [ "$status" -eq 2 ]
    run guard "gh api $c repos/o/r"
    [ "$status" -eq 2 ]
  done
}

@test "denies body flags, which turn the call into a POST" {
  for c in "-f a=b" "-fa=b" "-F a=@file" "--field a=b" "--field=a=b" "--raw-field a=b" "--input body.json"; do
    run guard "gh api repos/o/r/issues $c"
    [ "$status" -eq 2 ]
    run guard "gh api $c repos/o/r/issues"
    [ "$status" -eq 2 ]
  done
}

@test "asks for graphql instead of denying its -f query" {
  run guard "gh api graphql -f query='{viewer{login}}'"
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$output")" = ask ]
}

@test "finds gh api after other commands and on later lines" {
  run guard "cd x && gh api repos/o/r -X POST"
  [ "$status" -eq 2 ]
  run guard $'echo hi\ngh api repos/o/r --input b.json'
  [ "$status" -eq 2 ]
}

@test "checks every gh api in a chain" {
  run guard "gh api repos/o/r; gh api repos/o/r -f a=b"
  [ "$status" -eq 2 ]
}

@test "does not blame flags that belong to another command" {
  run guard "gh api repos/o/r; git commit -F msg.txt"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "CLAUDE_ALLOW_GH_API_WRITES=1 lifts the block" {
  CLAUDE_ALLOW_GH_API_WRITES=1 run guard "gh api repos/o/r -X POST"
  [ "$status" -eq 0 ]
}
