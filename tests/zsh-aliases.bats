# gwc, gpo and the gwl/gwo rows from .zsh_aliases, run in zsh with gh and the worktree hook stubbed
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

@test "bare gpo checks out the PR picked in the gps picker, no action menu" {
  GIT_TOP=$HOME/projects/untrusted/app run z '_gh_pr_pick() { print -u2 "prompt: $1"; print 5 }; _gh_pr_act() { print menu }; gpo'
  [[ "$output" == *"prompt: PR checkout> "* ]]
  [[ "$output" == *"checked out 5"* ]]
  [[ "$output" != *menu* ]]
}

@test "_gh_pr_pick prints the picked PR number, yours sorted first" {
  run zsh -fc '
    gh() { case "$1 $2" in
      "api user") print me ;;
      "pr list") print -r -- "[{\"number\":3,\"title\":\"t\",\"author\":{\"login\":\"x\"},\"updatedAt\":\"2026-01-01T00:00:00Z\"},{\"number\":8,\"title\":\"u\",\"author\":{\"login\":\"me\"},\"updatedAt\":\"2026-01-01T00:00:00Z\"}]" ;;
    esac }
    fzf() { head -1 }
    source "$0"; _gh_pr_pick "PR> " ""' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  [ "$output" = 8 ]
}

@test "_gw_rows feeds gwl and gwo: path and branch, then gwl's colored row" {
  r=$BATS_TEST_TMPDIR/repo
  git init -q -b main "$r"
  git -C "$r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  git -C "$r" worktree add -q -b feat "$BATS_TEST_TMPDIR/wt"
  echo x >"$BATS_TEST_TMPDIR/wt/f"
  cd "$BATS_TEST_TMPDIR/wt"
  run zsh -fc 'gh() { return 1 }; source "$0"; _gw_rows' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  wt=$(pwd -P)
  [[ "${lines[1]}" == "$wt"$'\t'feat$'\t'"* "*feat*"1 dirty"*"no PR"* ]]
  run zsh -fc 'gh() { return 1 }; source "$0"; gwl' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [[ "${lines[1]}" == "* "*feat* ]]
  [[ "${lines[1]}" != *$'\t'* ]]
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

# _gh_me with a gh stub that counts its `api user` calls in $HOME/calls
gh_me() {
  zsh -fc '
    gh() { print x >>"$HOME/calls"; print -r -- "${GH_LOGIN-me}"; [[ -n ${GH_FAIL-} ]] && return 1 || return 0 }
    source "$0"
    '"$1" "$BATS_TEST_DIRNAME/../.zsh_aliases"
}

@test "_gh_me asks gh once, then answers from the cache" {
  run gh_me '_gh_me; _gh_me'
  [ "$status" -eq 0 ]
  [ "$output" = $'me\nme' ]
  [ "$(wc -l <"$HOME/calls")" -eq 1 ]
}

@test "_gh_me refetches when gh's hosts.yml is newer than the cache" {
  export GH_CONFIG_DIR="$HOME/ghcfg" # CI may set XDG_CONFIG_HOME, which moves hosts.yml
  gh_me '_gh_me' >/dev/null
  mkdir -p "$GH_CONFIG_DIR"
  touch -t 203001010000 "$GH_CONFIG_DIR/hosts.yml"
  GH_LOGIN=other run gh_me '_gh_me'
  [ "$output" = other ]
  [ "$(wc -l <"$HOME/calls")" -eq 2 ]
}

@test "_gh_me caches nothing when the lookup fails" {
  GH_FAIL=1 run gh_me '_gh_me'
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.cache/zsh/gh-login" ]
}

@test "lg launches lazygit" {
  run zsh -fc 'source "$0"; lazygit() { print -r -- "lazygit $*"; }; eval "lg -p /x"' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  [ "$output" = "lazygit -p /x" ]
}

@test "git shortcut aliases are defined" {
  run zsh -fc 'source "$0"; for a in gs gb gd gl ga gci gma; do print -r -- "$a=$aliases[$a]"; done' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "gs=git status" ]
  [ "${lines[3]}" = "gl=git log -5" ]
  [ "${lines[6]}" = "gma=git merge --abort" ]
}
