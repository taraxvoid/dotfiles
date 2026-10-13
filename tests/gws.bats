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
@test "table lists orphans and a totals line, hides tracked without -a" {
  main=$(make_repo personal/app)
  add_worktree "$main" lost >/dev/null
  add_worktree "$main" kept --push >/dev/null
  set_prs "$main" '[{"headRefName":"kept","state":"OPEN","headRefOid":"x","number":1}]'
  run gws
  [ "$status" -eq 0 ]
  [[ "$output" == *"lost"*"never pushed"* ]]
  [[ "$output" != *"kept"* ]]
  [[ "$output" == *"1 orphaned, 0 unknown, 1 tracked, 0 done"* ]]
  run gws -a
  [[ "$output" == *"kept"* ]]
}

@test "table suggests cleanup-worktrees.sh when items are done" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" fin --push)
  set_prs "$main" "[{\"headRefName\":\"fin\",\"state\":\"MERGED\",\"headRefOid\":\"$(git -C "$wt" rev-parse HEAD)\",\"number\":2}]"
  run gws
  [[ "$output" == *"cleanup-worktrees.sh"* ]]
}

@test "no repos gives zero totals" {
  run gws --json
  [ "$status" -eq 0 ]
  [ "$(jq -c .totals "$GWS_CACHE")" = '{"done":0,"tracked":0,"orphaned":0,"unknown":0}' ]
}

@test "--refresh writes the cache quietly and skips a fresh one" {
  main=$(make_repo personal/app)
  add_worktree "$main" a >/dev/null
  run gws --refresh
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$GWS_CACHE" ]
  [ "$(gh_calls 'pr list')" = 1 ]
  gws --refresh
  [ "$(gh_calls 'pr list')" = 1 ]
  gws --refresh -f
  [ "$(gh_calls 'pr list')" = 2 ]
}

@test "--refresh exits quietly while another scan holds the lock" {
  make_repo personal/app >/dev/null
  mkdir -p "$GWS_CACHE.lock"
  run gws --refresh -f
  [ "$status" -eq 0 ]
  [ ! -f "$GWS_CACHE" ]
}

@test "--refresh takes over a stale lock" {
  make_repo personal/app >/dev/null
  mkdir -p "$GWS_CACHE.lock"
  touch -t 202001010000 "$GWS_CACHE.lock"
  run gws --refresh -f
  [ "$status" -eq 0 ]
  [ -f "$GWS_CACHE" ]
  [ ! -d "$GWS_CACHE.lock" ]
}

@test "--refresh --bg returns at once and the scan lands" {
  make_repo personal/app >/dev/null
  run gws --refresh --bg
  [ "$status" -eq 0 ]
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$GWS_CACHE" ] && break; sleep 0.5; done
  [ -f "$GWS_CACHE" ]
}

@test "unknown argument exits 64" {
  run gws --nope
  [ "$status" -eq 64 ]
}
@test "--here on an orphan prints the reason and exits 2" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat)
  run gws --here "$wt"
  [ "$status" -eq 2 ]
  [ "$output" = "worktree-feat: orphaned (never pushed)" ]
}

@test "--here on a tracked worktree exits 0" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat --push)
  set_prs "$main" '[{"headRefName":"worktree-feat","state":"OPEN","headRefOid":"x","number":4}]'
  run gws --here "$wt"
  [ "$status" -eq 0 ]
  [ "$output" = "worktree-feat: tracked" ]
}

@test "--here defaults to the current directory" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat)
  cd "$wt"
  run gws --here
  [ "$status" -eq 2 ]
}

@test "--here in a main checkout exits 0" {
  main=$(make_repo personal/app)
  run gws --here "$main"
  [ "$status" -eq 0 ]
  [ "$output" = "main checkout" ]
}

@test "--here outside git exits 0 silently" {
  run gws --here "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--here fails open when gh fails" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat --push)
  touch "$FAKE_GH/app/fail"
  run gws --here "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown"* ]]
}

@test "--here handles a path with a space" {
  main=$(make_repo personal/app)
  wt="$BATS_TEST_TMPDIR/with space/feat"
  mkdir -p "$BATS_TEST_TMPDIR/with space"
  git -C "$main" worktree add -q -b worktree-sp "$wt" main
  git -C "$wt" commit -q --allow-empty -m w
  run gws --here "$wt"
  [ "$status" -eq 2 ]
  [ "$output" = "worktree-sp: orphaned (never pushed)" ]
}
