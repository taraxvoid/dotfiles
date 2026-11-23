setup() {
  load helpers
  setup_env
}

hook() { jq -cn --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c, description: "d"}}' | git-push-no-verify.sh; }
rewritten() { jq -r '.hookSpecificOutput.updatedInput.command' <<<"$output"; }

@test "adds --no-verify right after git push" {
  run hook "git push"
  [ "$status" -eq 0 ] && [ "$(rewritten)" = "git push --no-verify" ]
  run hook "git push -u origin worktree-1-x"
  [ "$(rewritten)" = "git push --no-verify -u origin worktree-1-x" ]
}

@test "keeps the other tool_input fields" {
  run hook "git push"
  [ "$(jq -r '.hookSpecificOutput.updatedInput.description' <<<"$output")" = d ]
}

@test "keeps tail-anchored deny patterns matching" {
  run hook "git push origin main"
  [[ $(rewritten) == "git push "*" main" ]]
}

@test "leaves a push that already skips hooks alone" {
  run hook "git push --no-verify origin x"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run hook "git push origin x --no-verify"
  [ -z "$output" ]
}

@test "ignores other commands and tools" {
  for c in "git status" "git pushx" "echo git push" "cd x && git push"; do
    run hook "$c"
    [ "$status" -eq 0 ] && [ -z "$output" ]
  done
  run bash -c 'echo "{\"tool_name\":\"Edit\"}" | git-push-no-verify.sh'
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "escape hatch" {
  CLAUDE_ALLOW_PUSH_HOOKS=1 run hook "git push"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}
