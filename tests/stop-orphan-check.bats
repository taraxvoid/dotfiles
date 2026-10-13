setup() {
  load helpers
  setup_env
}

hook() { jq -cn --arg cwd "$1" --argjson active "${2:-false}" '{cwd: $cwd, stop_hook_active: $active}' | stop-orphan-check.sh; }

@test "blocks once for an orphan holding unpushed commits" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat)
  run hook "$wt"
  [ "$status" -eq 0 ]
  [ "$(jq -r .decision <<<"$output")" = block ]
  [[ "$(jq -r .reason <<<"$output")" == "gws: worktree-feat: orphaned (never pushed)."* ]]
  run hook "$wt"
  [ -z "$output" ]
}

@test "a new commit nudges again" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat)
  hook "$wt" >/dev/null
  git -C "$wt" commit -q --allow-empty -m more
  run hook "$wt"
  [ "$(jq -r .decision <<<"$output")" = block ]
}

@test "passes when stop_hook_active" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat)
  run hook "$wt" true
  [ -z "$output" ]
}

@test "passes for a tracked worktree with unpushed commits" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat --push)
  set_prs "$main" '[{"headRefName":"worktree-feat","state":"OPEN","headRefOid":"x","number":4}]'
  git -C "$wt" commit -q --allow-empty -m more
  run hook "$wt"
  [ -z "$output" ]
}

@test "passes when nothing is at risk (no commits off the remotes)" {
  main=$(make_repo personal/app)
  wt=$BATS_TEST_TMPDIR/fresh
  git -C "$main" worktree add -q -b worktree-fresh "$wt" main
  touch "$wt/scratch"
  run hook "$wt"
  [ -z "$output" ]
}

@test "passes in a main checkout and outside git" {
  main=$(make_repo personal/app)
  git -C "$main" commit -q --allow-empty -m local
  run hook "$main"
  [ -z "$output" ]
  run hook "$BATS_TEST_TMPDIR"
  [ -z "$output" ]
}

@test "passes when gh fails" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat --push)
  git -C "$wt" commit -q --allow-empty -m more
  touch "$FAKE_GH/app/fail"
  run hook "$wt"
  [ -z "$output" ]
}
