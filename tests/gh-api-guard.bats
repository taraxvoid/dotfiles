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

rewritten() { jq -r '.hookSpecificOutput.updatedInput.command // empty' <<<"$output"; }

@test "quotes bare {owner}/{repo} placeholders so the sandbox exclusion still matches" {
  run guard "gh api repos/{owner}/{repo}/pulls -q '.[0].number'"
  [ "$status" -eq 0 ]
  [ "$(rewritten)" = "gh api 'repos/{owner}/{repo}/pulls' -q '.[0].number'" ]
}

@test "leaves already-quoted placeholders and literal repos alone" {
  run guard "gh api 'repos/{owner}/{repo}/pulls' -q '.[0].number'"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run guard "gh api repos/o/r/pulls -q '.[0].number'"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "does not rewrite placeholders outside gh api" {
  run guard "echo repos/{owner}/{repo}"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "keeps the graphql ask when it also rewrites" {
  run guard "gh api graphql -f query='{viewer{login}}' -f o={owner}"
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$output")" = ask ]
  [ "$(rewritten)" = "gh api graphql -f query='{viewer{login}}' -f 'o={owner}'" ]
}

@test "CLAUDE_ALLOW_GH_API_WRITES=1 lifts the block" {
  CLAUDE_ALLOW_GH_API_WRITES=1 run guard "gh api repos/o/r -X POST"
  [ "$status" -eq 0 ]
}

@test "leaves the reply-thread and resolve-thread aliases alone" {
  run guard "gh reply-thread 12 345 'looks fixed in abc123'"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run guard "gh resolve-thread PRRT_kwDOabc"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "the review-thread aliases are allowed in the fragment and defined in gh config" {
  frag="$BATS_TEST_DIRNAME/../.claude/settings.fragment.json"
  cfg="$BATS_TEST_DIRNAME/../.config/gh/config.yml"
  for a in reply-thread resolve-thread; do
    [ "$(jq --arg r "Bash(gh $a *)" '.permissions.allow | index($r) != null' "$frag")" = true ]
    [ "$(yq ".aliases.\"$a\" | test(\"^!.*gh api \")" "$cfg")" = true ]
  done
  # the graphql alias is pinned to the one resolve mutation
  [ "$(yq '.aliases."resolve-thread" | test("resolveReviewThread")' "$cfg")" = true ]
}

# alias_run <alias> args...: run the alias body the way gh does (sh -c body -- args)
# with a stub gh that records its argv, one per line, in $BATS_TEST_TMPDIR/argv
alias_run() {
  local a=$1 body
  shift
  body=$(yq ".aliases.\"$a\"" "$BATS_TEST_DIRNAME/../.config/gh/config.yml")
  body=${body#!}
  mkdir -p "$BATS_TEST_TMPDIR/stub"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/argv"\n' "$BATS_TEST_TMPDIR" >"$BATS_TEST_TMPDIR/stub/gh"
  chmod +x "$BATS_TEST_TMPDIR/stub/gh"
  rm -f "$BATS_TEST_TMPDIR/argv"
  PATH=$BATS_TEST_TMPDIR/stub:$PATH run sh -c "$body" -- "$@"
}

@test "reply-thread posts to the reply endpoint with numeric ids" {
  alias_run reply-thread 12 345 'looks fixed'
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$BATS_TEST_TMPDIR/argv")" = api ]
  [ "$(sed -n 2p "$BATS_TEST_TMPDIR/argv")" = 'repos/{owner}/{repo}/pulls/12/comments/345/replies' ]
  rg -qx 'body=looks fixed' "$BATS_TEST_TMPDIR/argv"
}

@test "reply-thread refuses ids that could reroute the request" {
  for bad in '123/reviews#' '1?x=2' '12/../3' '' 'abc' '1 2'; do
    alias_run reply-thread "$bad" 345 body
    [ "$status" -eq 2 ]
    [ ! -e "$BATS_TEST_TMPDIR/argv" ]
    alias_run reply-thread 12 "$bad" body
    [ "$status" -eq 2 ]
    [ ! -e "$BATS_TEST_TMPDIR/argv" ]
  done
}

@test "resolve-thread sends the fixed mutation with the id as a variable" {
  alias_run resolve-thread PRRT_kwDOabc
  [ "$status" -eq 0 ]
  rg -qx 'id=PRRT_kwDOabc' "$BATS_TEST_TMPDIR/argv"
  rg -q 'resolveReviewThread\(input:\{threadId:\$id\}\)' "$BATS_TEST_TMPDIR/argv"
}
