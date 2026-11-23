setup() {
  load helpers
  setup_env
  export GIT_REMOTE_GUARD_SCRATCH=$BATS_TEST_TMPDIR/scratch
  mkdir -p "$GIT_REMOTE_GUARD_SCRATCH"
  main=$(make_repo personal/r)
}

# guard <cwd> <command>
guard() { jq -cn --arg c "$2" --arg d "$1" '{tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' | git-remote-guard.sh; }

@test "allows push and fetch from a main checkout and a real worktree" {
  run guard "$main" "git push origin main"
  echo "$output"
  [ "$status" -eq 0 ]
  wt=$(add_worktree "$main" feature)
  run guard "$wt" "git fetch origin"
  [ "$status" -eq 0 ]
}

@test "ignores other commands and ls-remote outside a repo" {
  run guard "$main" "git status"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run guard "$BATS_TEST_TMPDIR" "git ls-remote https://example.com/x"
  [ "$status" -eq 0 ]
}

@test "blocks a worktree whose .git file points at a git dir in a scratch dir" {
  wt=$(add_worktree "$main" feature)
  git init -q "$GIT_REMOTE_GUARD_SCRATCH/fake"
  fake=$GIT_REMOTE_GUARD_SCRATCH/fake/.git
  git -C "$fake" config core.sshCommand 'touch /tmp/pwned'
  printf 'gitdir: %s\n' "$fake" >"$wt/.git"
  run guard "$wt" "git push"
  echo "$output"
  [ "$status" -eq 2 ] && [[ $output == *"scratch dir"* ]]
}

@test "blocks a worktree whose commondir points elsewhere" {
  wt=$(add_worktree "$main" feature)
  gd=$(git -C "$wt" rev-parse --path-format=absolute --git-dir)
  other=$GIT_REMOTE_GUARD_SCRATCH/other
  git init -q "$other"
  printf '%s\n' "$other/.git" >"$gd/commondir"
  run guard "$wt" "git push"
  [ "$status" -eq 2 ]
}

@test "blocks config pulled in from an unexpected file" {
  printf '[core]\n\tsshCommand = touch /tmp/pwned\n' >"$BATS_TEST_TMPDIR/evil.cfg"
  git -C "$main" config include.path "$BATS_TEST_TMPDIR/evil.cfg"
  run guard "$main" "git push"
  [ "$status" -eq 2 ] && [[ $output == *evil.cfg* ]]
}

@test "escape hatch" {
  git -C "$main" config include.path "$BATS_TEST_TMPDIR/evil.cfg"
  touch "$BATS_TEST_TMPDIR/evil.cfg"
  CLAUDE_ALLOW_GIT_REMOTE_ANYWHERE=1 run guard "$main" "git push"
  [ "$status" -eq 0 ]
}
