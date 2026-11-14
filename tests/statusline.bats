setup() {
  load helpers
  setup_env
}

line() { jq -cn --arg d "$1" '{workspace: {current_dir: $d}}' | statusline.sh; }
cache() { # cache <path> <state> <reason> <pr|null> <issue|null> <orphans>
  mkdir -p "$(dirname "$GWS_CACHE")"
  jq -n --arg p "$1" --arg s "$2" --arg r "$3" --argjson pr "$4" --argjson is "$5" --argjson o "$6" \
    '{scanned_at: "x", items: [{repo: "personal/app", path: $p, branch: "b", state: $s, reason: $r,
      pr: $pr, issue: $is, local_changes: false}],
      totals: {done: 0, tracked: 0, orphaned: $o, unknown: 0}}' >"$GWS_CACHE"
}

@test "tracked worktree with issue and PR" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-42-feat)
  cache "$wt" tracked "" 20 42 3
  [ "$(line "$wt")" = "app/worktree-42-feat - #42 tracked (PR #20)" ]
}

@test "orphaned worktree shows its reason" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat)
  cache "$wt" orphaned "never pushed" null null 1
  [ "$(line "$wt")" = "app/worktree-feat - orphan: never pushed" ]
}

@test "uncommitted changes are appended" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat)
  cache "$wt" orphaned "never pushed" null null 1
  touch "$wt/x"
  [ "$(line "$wt")" = "app/worktree-feat - orphan: never pushed, local changes" ]
}

@test "main checkout shows just the branch" {
  main=$(make_repo personal/app)
  cache /elsewhere tracked "" null null 2
  [ "$(line "$main")" = "app (main)" ]
}

@test "missing cache says not scanned" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat)
  [ "$(line "$wt")" = "app/worktree-feat - not scanned" ]
}

@test "old cache adds its age" {
  main=$(make_repo personal/app)
  cache /elsewhere tracked "" null null 2
  touch -t 202001010000 "$GWS_CACHE"
  [[ "$(line "$main")" =~ ^"app (main) - scan "[0-9]+"d old"$ ]]
}

@test "empty cache file does not break the line" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat)
  : >"$GWS_CACHE"
  [ "$(line "$wt")" = "app/worktree-feat - not scanned" ]
}

@test "outside git shows the directory" {
  mkdir -p "$BATS_TEST_TMPDIR/plain dir"
  [ "$(line "$BATS_TEST_TMPDIR/plain dir")" = "$BATS_TEST_TMPDIR/plain dir" ]
}

@test "a worktree pushed since the scan is not shown as never pushed" {
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat)
  cache "$wt" orphaned "never pushed" null null 1
  git -C "$wt" push -q -u origin worktree-feat
  [ "$(line "$wt")" = "app/worktree-feat - pushed since scan" ]
}
