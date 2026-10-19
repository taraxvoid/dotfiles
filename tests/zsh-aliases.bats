# gwc and gpo from .zsh_aliases, run in zsh with gh and the worktree hook stubbed
setup() {
  load helpers
  setup_env
  command -v zsh >/dev/null || skip "zsh not installed"
  export HOME=$BATS_TEST_TMPDIR/home
  mkdir -p "$HOME/.claude/scripts"
  HOME=$(cd "$HOME" && pwd -P)
  # stub hook: records its input, makes the dir, prints it
  cat >"$HOME/.claude/scripts/worktree-create.sh" <<'EOF'
#!/usr/bin/env bash
in=$(cat); printf '%s\n' "$in" >"$HOME/hook-input"
d=$HOME/worktrees/personal/app/$(jq -r .name <<<"$in"); mkdir -p "$d"; printf '%s\n' "$d"
EOF
  chmod +x "$HOME/.claude/scripts/worktree-create.sh"
}

# z <code>: run code in zsh with the aliases loaded and gh/git stubbed
z() {
  zsh -fc '
    gh() {
      case "$1 $2" in
        "issue view") print -r -- "$GH_TITLE" ;;
        "pr view") print -r -- "feat-branch	$GH_AUTHOR" ;;
        "pr checkout") print -r -- "checked out $3" ;;
        "api user") print -r -- me ;;
      esac
    }
    source "$0"
    git() { case $1 in push) return 0 ;; branch) print worktree-x ;; rev-parse) print -r -- "$GIT_TOP" ;; worktree) ;; esac }
    '"$1" "$BATS_TEST_DIRNAME/../.zsh_aliases"
}

@test "gwc names the worktree <N>-<slug of the issue title>" {
  GH_TITLE='Fix: the "sbx" sandbox, again!!' run z 'gwc 42 && print -r -- $PWD'
  [ "$status" -eq 0 ]
  [ "$(jq -r .name "$HOME/hook-input")" = "42-fix-the-sbx-sandbox-again" ]
  [[ "$output" == *"$HOME/worktrees/personal/app/42-fix-the-sbx-sandbox-again" ]]
}

@test "gwc caps the slug at 40 chars without a trailing dash" {
  # the 40th char is the dash after the d's
  GH_TITLE='aaaaaaaaaa bbbbbbbbbb cccccccccc dddddd eeeeeeeeee' run z 'gwc "#7"'
  [ "$status" -eq 0 ]
  [ "$(jq -r .name "$HOME/hook-input")" = "7-aaaaaaaaaa-bbbbbbbbbb-cccccccccc-dddddd" ]
}

@test "gwc takes an explicit slug and rejects a non-number" {
  run z 'gwc 9 My-Slug'
  [ "$(jq -r .name "$HOME/hook-input")" = "9-my-slug" ]
  run z 'gwc abc'
  [ "$status" -eq 2 ]
}

@test "gpo asks before checking out someone else's PR in a trusted tree, default no" {
  GIT_TOP=$HOME/projects/personal/app GH_AUTHOR=stranger run z 'gpo 5 </dev/null'
  [ "$status" -eq 1 ]
  [[ "$output" == *"#5 is by stranger"* ]]
  [[ "$output" != *"checked out"* ]]
}

@test "gpo checks out your own PR, or any PR outside the trusted tiers, without asking" {
  GIT_TOP=$HOME/projects/personal/app GH_AUTHOR=me run z 'gpo 5'
  [[ "$output" == *"checked out 5"* ]]
  GIT_TOP=$HOME/projects/untrusted/app GH_AUTHOR=stranger run z 'gpo 5'
  [[ "$output" == *"checked out 5"* ]]
}

@test "fdsd replaces a literal string in files matching the glob, hidden ones only with -a" {
  command -v fd >/dev/null && command -v sd >/dev/null || skip "fd and sd not installed"
  d=$BATS_TEST_TMPDIR/proj; mkdir -p "$d/.hid"
  echo 'a: foo.x' >"$d/one.yaml"; echo 'a: foo.x' >"$d/.hid/two.yaml"; echo 'a: foo.x' >"$d/three.txt"
  cd "$d"
  run zsh -fc 'source "$0"; fdsd foo.x bar "*yaml"' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  [ "$(cat one.yaml)" = "a: bar" ]
  [ "$(cat .hid/two.yaml)" = "a: foo.x" ]
  # eval parses after the sourcing, so the noglob alias keeps *yaml from expanding
  run zsh -fc 'source "$0"; eval "fdsd foo.x bar *yaml -a"' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  [ "$(cat .hid/two.yaml)" = "a: bar" ]
  [ "$(cat three.txt)" = "a: foo.x" ]
}

@test "re-sourcing .zsh_aliases (sz) does not trip over the fdsd alias" {
  run zsh -fc 'source "$0"; source "$0"' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [[ "$output" != *"parse error"* ]]
}
