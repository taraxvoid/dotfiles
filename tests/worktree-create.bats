setup() {
  load helpers
  setup_env
  main=$(make_repo personal/app)
  export HOME=$BATS_TEST_TMPDIR/home
  mkdir -p "$HOME"
}

create() { jq -cn --arg c "$main" --arg n "$1" '{cwd: $c, name: $n}' | worktree-create.sh; }

@test "creates the worktree on worktree-<name> with no upstream" {
  run create feat
  [ "$status" -eq 0 ]
  [ "$(git -C "$output" branch --show-current)" = worktree-feat ]
  # tracking origin/main would make a plain git push fail under push.default=simple
  run git -C "$output" rev-parse --abbrev-ref '@{upstream}'
  [ "$status" -ne 0 ]
}
