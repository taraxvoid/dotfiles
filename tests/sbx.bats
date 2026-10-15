setup() {
  load helpers
  setup_env
  if ! command -v bwrap >/dev/null || ! bwrap --ro-bind / / true 2>/dev/null; then
    skip "bubblewrap unavailable or blocked here"
  fi
  export HOME=$BATS_TEST_TMPDIR/home
  mkdir -p "$HOME/projects/untrusted" "$HOME/worktrees/untrusted"
  HOME=$(cd "$HOME" && pwd -P)
  repo=$HOME/projects/untrusted/app
  other=$HOME/projects/untrusted/other
  git init -q "$repo"
  git -C "$repo" commit -q --allow-empty -m init
  git init -q "$other"
  sbx=$BATS_TEST_DIRNAME/../.local/bin/sbx
}

@test "the repo is writable but its .git is not" {
  cd "$repo"
  run "$sbx" sh -c 'touch "$PWD/ok" && echo "[core] fsmonitor = evil" >>.git/config'
  [ "$status" -ne 0 ]
  [ -e "$repo/ok" ]
  ! grep -q evil "$repo/.git/config"
}

@test "hooks cannot be planted" {
  cd "$repo"
  run "$sbx" sh -c 'echo evil >.git/hooks/post-checkout'
  [ "$status" -ne 0 ]
  [ ! -e "$repo/.git/hooks/post-checkout" ]
}

@test "other untrusted repos are not visible" {
  cd "$repo"
  run "$sbx" sh -c "ls '$other'"
  [ "$status" -ne 0 ]
}

@test "a worktree's shared git dir is read-only too" {
  wt=$HOME/worktrees/untrusted/app/feat
  mkdir -p "$(dirname "$wt")"
  git -C "$repo" worktree add -q -b feat "$wt"
  cd "$wt"
  run "$sbx" sh -c "echo x >>'$repo/.git/config'"
  [ "$status" -ne 0 ]
  run "$sbx" sh -c 'touch "$PWD/ok"'
  [ "$status" -eq 0 ]
}

@test "--rw-git allows writing .git" {
  cd "$repo"
  run "$sbx" --rw-git sh -c 'touch .git/rw-ok'
  [ "$status" -eq 0 ]
  [ -e "$repo/.git/rw-ok" ]
}

@test "each repo gets its own HOME" {
  cd "$repo"
  "$sbx" sh -c 'touch "$HOME/planted"'
  cd "$other"
  run "$sbx" sh -c 'test -e "$HOME/planted"'
  [ "$status" -ne 0 ]
}

@test "refuses outside the untrusted trees" {
  cd "$BATS_TEST_TMPDIR"
  run "$sbx" true
  [ "$status" -eq 1 ]
}
