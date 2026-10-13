setup() {
  load helpers
  setup_env
}

state_of() { item_for "$1" | jq -r '.state + "|" + .reason'; }

@test "unpushed worktree is orphaned: never pushed" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat)
  run gws --json
  [ "$status" -eq 0 ]
  [ "$(state_of "$wt")" = "orphaned|never pushed" ]
  [ "$(item_for "$wt" | jq -r .repo)" = "personal/app" ]
}

@test "pushed worktree with no PR or issue is orphaned" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat --push)
  gws --json >/dev/null
  [ "$(state_of "$wt")" = "orphaned|pushed, no PR/issue" ]
}

@test "pushed worktree with an open PR is tracked" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat --push)
  set_prs "$main" '[{"headRefName":"worktree-feat","state":"OPEN","headRefOid":"x","number":12}]'
  gws --json >/dev/null
  [ "$(state_of "$wt")" = "tracked|" ]
  [ "$(item_for "$wt" | jq -r .pr)" = 12 ]
}

@test "branch with a slash and an open PR is tracked" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" feat/x --push)
  set_prs "$main" '[{"headRefName":"feat/x","state":"OPEN","headRefOid":"x","number":3}]'
  gws --json >/dev/null
  [ "$(state_of "$wt")" = "tracked|" ]
}

@test "merged PR at HEAD is done even after the remote branch is deleted" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat --push)
  head=$(git -C "$wt" rev-parse HEAD)
  set_prs "$main" "[{\"headRefName\":\"worktree-feat\",\"state\":\"MERGED\",\"headRefOid\":\"$head\",\"number\":5}]"
  git -C "$main" push -q origin --delete worktree-feat
  git -C "$main" fetch -q --prune origin
  gws --json >/dev/null
  [ "$(state_of "$wt")" = "done|" ]
}

@test "new commits after a merged PR are orphaned" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat --push)
  head=$(git -C "$wt" rev-parse HEAD)
  set_prs "$main" "[{\"headRefName\":\"worktree-feat\",\"state\":\"MERGED\",\"headRefOid\":\"$head\",\"number\":5}]"
  git -C "$main" push -q origin --delete worktree-feat
  git -C "$main" fetch -q --prune origin
  git -C "$wt" commit -q --allow-empty -m more
  gws --json >/dev/null
  [ "$(state_of "$wt")" = "orphaned|commits after merged PR" ]
}

@test "pushed worktree-<N>-* with issue N open is tracked" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-7-feat --push)
  set_issue "$main" 7 OPEN
  gws --json >/dev/null
  [ "$(state_of "$wt")" = "tracked|" ]
  [ "$(item_for "$wt" | jq -r .issue)" = 7 ]
}

@test "pushed worktree-<N>-* with issue N closed is orphaned" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-7-feat --push)
  set_issue "$main" 7 CLOSED
  gws --json >/dev/null
  [ "$(state_of "$wt")" = "orphaned|issue #7 closed" ]
}

@test "detached HEAD worktree is orphaned" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat)
  git -C "$wt" checkout -q --detach
  gws --json >/dev/null
  [ "$(state_of "$wt")" = "orphaned|detached HEAD" ]
}

@test "tracked worktree with uncommitted changes notes local changes" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat --push)
  set_prs "$main" '[{"headRefName":"worktree-feat","state":"OPEN","headRefOid":"x","number":12}]'
  touch "$wt/new-file"
  gws --json >/dev/null
  [ "$(item_for "$wt" | jq -r '.state + "|" + (.local_changes|tostring)')" = "tracked|true" ]
}

@test "unpushed branch with no worktree is listed, fully pushed one is not" {
  main=$(make_repo personal/app)
  git -C "$main" branch pushed-already main
  git -C "$main" checkout -q -b local-only
  git -C "$main" commit -q --allow-empty -m wip
  git -C "$main" checkout -q main
  gws --json >/dev/null
  [ "$(jq -r '.items[] | select(.path == "") | .branch + "|" + .reason' "$GWS_CACHE")" = "local-only|never pushed" ]
}

@test "main checkout is not an item" {
  make_repo personal/app >/dev/null
  gws --json >/dev/null
  [ "$(jq '.items | length' "$GWS_CACHE")" = 0 ]
}

@test "repo with no origin remote is unknown" {
  mkdir -p "$GWS_ROOTS/personal/bare"
  git init -q "$GWS_ROOTS/personal/bare"
  gws --json >/dev/null
  [ "$(jq -r '.items[0].state + "|" + .items[0].reason' "$GWS_CACHE")" = "unknown|no origin remote" ]
}

@test "gh failure makes the repo unknown, not skipped" {
  main=$(make_repo personal/app)
  add_worktree "$main" worktree-feat >/dev/null
  touch "$FAKE_GH/app/fail"
  gws --json >/dev/null
  [ "$(jq -r '.items[0].state + "|" + .items[0].reason' "$GWS_CACHE")" = "unknown|gh pr list failed" ]
}

@test "one gh pr list call per repo" {
  main=$(make_repo personal/app)
  add_worktree "$main" a >/dev/null
  add_worktree "$main" b --push >/dev/null
  add_worktree "$main" c --push >/dev/null
  gws --json >/dev/null
  [ "$(gh_calls 'pr list')" = 1 ]
}

@test "worktree whose directory was deleted is still listed" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-gone)
  rm -rf "$wt"
  run gws --json
  [ "$status" -eq 0 ]
  [ "$(state_of "$wt")" = "orphaned|never pushed" ]
}

@test "worktree path with a space works" {
  main=$(make_repo personal/app)
  wt="$BATS_TEST_TMPDIR/with space/feat"
  mkdir -p "$BATS_TEST_TMPDIR/with space"
  git -C "$main" worktree add -q -b worktree-sp "$wt" main
  git -C "$wt" commit -q --allow-empty -m w
  wt=$(cd "$wt" && pwd -P)
  gws --json >/dev/null
  [ "$(state_of "$wt")" = "orphaned|never pushed" ]
}

@test "repos in several tiers are all scanned" {
  a=$(make_repo personal/app)
  b=$(make_repo ravenflight/site)
  add_worktree "$a" x >/dev/null
  add_worktree "$b" y >/dev/null
  gws --json >/dev/null
  [ "$(jq -r '[.items[].repo] | sort | join(",")' "$GWS_CACHE")" = "personal/app,ravenflight/site" ]
  [ "$(jq -r .totals.orphaned "$GWS_CACHE")" = 2 ]
}
