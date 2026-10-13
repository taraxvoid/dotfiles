# Shared bats setup: real git repos under a temp roots dir, a fake gh first on
# PATH, and the repo's own scripts on PATH.

setup_env() {
  mkdir -p "$BATS_TEST_TMPDIR/projects" "$BATS_TEST_TMPDIR/gh" "$BATS_TEST_TMPDIR/cache"
  touch "$BATS_TEST_TMPDIR/gh/calls"
  GWS_ROOTS=$(cd "$BATS_TEST_TMPDIR/projects" && pwd -P)
  export GWS_ROOTS
  export XDG_CACHE_HOME=$BATS_TEST_TMPDIR/cache
  export GWS_CACHE=$XDG_CACHE_HOME/gws.json
  export FAKE_GH=$BATS_TEST_TMPDIR/gh
  export PATH=$BATS_TEST_DIRNAME/fake-gh:$BATS_TEST_DIRNAME/../.local/bin:$BATS_TEST_DIRNAME/../.claude/scripts:$PATH
  export GIT_CONFIG_GLOBAL=$BATS_TEST_TMPDIR/gitconfig GIT_CONFIG_NOSYSTEM=1
  git config --global user.name test
  git config --global user.email test@example.com
  git config --global init.defaultBranch main
  git config --global advice.detachedHead false
}

# make_repo <tier/name>: bare origin plus a main checkout with one pushed commit
make_repo() {
  local main=$GWS_ROOTS/$1 origin=$BATS_TEST_TMPDIR/origins/$1.git
  mkdir -p "$main" "$origin"
  git init -q --bare "$origin"
  git init -q "$main"
  git -C "$main" commit -q --allow-empty -m init
  git -C "$main" remote add origin "$origin"
  git -C "$main" push -q -u origin main
  mkdir -p "$FAKE_GH/$(basename "$main")"
  printf '%s\n' "$main"
}

# add_worktree <main> <branch> [--push]: worktree with one commit beyond main
add_worktree() {
  local main=$1 branch=$2 wt
  wt=$BATS_TEST_TMPDIR/wt/$(basename "$main")/${branch//\//-}
  mkdir -p "$(dirname "$wt")"
  git -C "$main" worktree add -q -b "$branch" "$wt" main
  git -C "$wt" commit -q --allow-empty -m "work on $branch"
  if [ "${3:-}" = --push ]; then git -C "$wt" push -q -u origin "$branch"; fi
  (cd "$wt" && pwd -P)
}

set_prs() { printf '%s\n' "$2" >"$FAKE_GH/$(basename "$1")/prs.json"; }
set_issue() { printf '%s\n' "$3" >"$FAKE_GH/$(basename "$1")/issue-$2"; }
item_for() { jq -c --arg p "$1" 'first(.items[] | select(.path == $p))' "$GWS_CACHE"; }
gh_calls() { grep -c -- "${1:-.}" "$FAKE_GH/calls" || true; }
