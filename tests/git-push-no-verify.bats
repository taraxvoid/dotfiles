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

in_repo() { jq -cn --arg c "$1" --arg d "$2" '{tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' | git-push-no-verify.sh; }

# repo_with_hook <exit code>: worktree whose pre-push hook logs its args and stdin
repo_with_hook() {
  local main wt
  main=$(make_repo personal/p)
  wt=$(add_worktree "$main" feat --push)
  git -C "$wt" commit -q --allow-empty -m more
  printf '#!/usr/bin/env bash\necho "args $*" >"%s/hook.log"\ncat >>"%s/hook.log"\necho "$TMPDIR" >"%s/hook.tmpdir"\necho hook-says-no\nexit %s\n' \
    "$FAKE_SRT_DIR" "$FAKE_SRT_DIR" "$FAKE_SRT_DIR" "$1" >"$main/.git/hooks/pre-push"
  chmod +x "$main/.git/hooks/pre-push"
  printf '%s\n' "$wt"
}

setup_srt() {
  export FAKE_SRT_DIR=$BATS_TEST_TMPDIR/srt SRT_BIN=$BATS_TEST_DIRNAME/fake-srt/srt
  export ZDOTDIR=$BATS_TEST_TMPDIR CLAUDE_SETTINGS=$BATS_TEST_TMPDIR/settings.json
  export CLAUDE_PUSH_CHECK_DIR=$BATS_TEST_TMPDIR/stamps
  mkdir -p "$FAKE_SRT_DIR"
  echo '{"sandbox":{"network":{"allowedDomains":["github.com"]},"filesystem":{"allowWrite":["~/.cache/sandbox"],"denyWrite":["~/x"]},"credentials":{"envVars":[{"name":"GH_TOKEN","mode":"deny"}]},"enableWeakerNetworkIsolation":true}}' >"$CLAUDE_SETTINGS"
}

@test "runs the pre-push hook through srt with git's args and stdin, then rewrites" {
  setup_srt
  wt=$(repo_with_hook 0)
  run in_repo "git push" "$wt"
  [ "$status" -eq 0 ] && [ "$(rewritten)" = "git push --no-verify" ]
  head -n 1 "$FAKE_SRT_DIR/hook.log" | grep -q "^args origin .*/origins/personal/p.git$"
  sha=$(git -C "$wt" rev-parse HEAD) rsha=$(git -C "$wt" rev-parse origin/feat)
  [ "$(sed -n 2p "$FAKE_SRT_DIR/hook.log")" = "refs/heads/feat $sha refs/heads/feat $rsha" ]
}

@test "srt gets the Claude sandbox's rules plus the worktree, git dir and a fresh TMPDIR" {
  setup_srt
  wt=$(repo_with_hook 0)
  run in_repo "git push -u origin feat" "$wt"
  [ "$status" -eq 0 ]
  c=$FAKE_SRT_DIR/cfg.json tmp=$(sed -n 1p "$FAKE_SRT_DIR/env")
  [ "$(jq -r '.network.allowedDomains[0]' "$c")" = github.com ]
  [ "$(jq -r '.filesystem.denyWrite[0]' "$c")" = "~/x" ]
  [ "$(jq -r '.credentials.envVars[0].name' "$c")" = GH_TOKEN ]
  [ "$(jq '.enableWeakerNetworkIsolation' "$c")" = true ]
  [ "$(jq --arg w "$wt" '.filesystem.allowWrite | index($w) != null' "$c")" = true ]
  [ "$(jq --arg t "$tmp" '.filesystem.allowWrite | index($t) != null' "$c")" = true ]
  [ "$(sed -n 2p "$FAKE_SRT_DIR/env")" = 1 ]
  # srt hands the child CLAUDE_CODE_TMPDIR as TMPDIR; it must be the fresh dir
  [ "$(cat "$FAKE_SRT_DIR/hook.tmpdir")" = "$tmp" ]
  [ ! -e "$tmp" ]
}

@test "a failing pre-push hook blocks the push with its output" {
  setup_srt
  wt=$(repo_with_hook 1)
  run in_repo "git push" "$wt"
  [ "$status" -eq 2 ] && [[ $output == *"pre-push hook failed"* ]] && [[ $output == *hook-says-no* ]]
}

@test "no pre-push hook: rewrites without running srt" {
  setup_srt
  main=$(make_repo personal/q)
  run in_repo "git push" "$main"
  [ "$status" -eq 0 ] && [ "$(rewritten)" = "git push --no-verify" ] && [ ! -e "$FAKE_SRT_DIR/cfg.json" ]
}

@test "an explicit --no-verify is still checked, and not rewritten" {
  setup_srt
  wt=$(repo_with_hook 1)
  run in_repo "git push --no-verify" "$wt"
  [ "$status" -eq 2 ] && [[ $output == *hook-says-no* ]]
}

@test "a commit that already passed is not checked again (auto mode re-issue)" {
  setup_srt
  wt=$(repo_with_hook 0)
  run in_repo "git push" "$wt"
  [ "$status" -eq 0 ] && [ -e "$FAKE_SRT_DIR/hook.log" ]
  rm "$FAKE_SRT_DIR/hook.log"
  run in_repo "git push --no-verify" "$wt"
  [ "$status" -eq 0 ] && [ -z "$output" ] && [ ! -e "$FAKE_SRT_DIR/hook.log" ]
  # a new commit is checked again
  git -C "$wt" commit -q --allow-empty -m again
  run in_repo "git push --no-verify" "$wt"
  [ "$status" -eq 0 ] && [ -e "$FAKE_SRT_DIR/hook.log" ]
}

@test "blocks when srt is missing and a hook exists" {
  setup_srt
  wt=$(repo_with_hook 0)
  SRT_BIN=no-such-srt run in_repo "git push" "$wt"
  [ "$status" -eq 2 ] && [[ $output == *"srt (sandbox-runtime) not found"* ]]
}

@test "escape hatch" {
  CLAUDE_ALLOW_PUSH_HOOKS=1 run hook "git push"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}
