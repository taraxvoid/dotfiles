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

# gwl_cache_repo: a repo with one worktree on branch feat, cwd inside it
gwl_cache_repo() {
  r=$BATS_TEST_TMPDIR/repo
  git init -q -b main "$r"
  git -C "$r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  git -C "$r" worktree add -q -b feat "$BATS_TEST_TMPDIR/wt"
  cd "$BATS_TEST_TMPDIR/wt"
  export XDG_CACHE_HOME=$BATS_TEST_TMPDIR/cache GWL_CALLS=$BATS_TEST_TMPDIR/calls
}

# gh stub: counts calls, answers "open" lists with PR #7 on feat, "all" lists with nothing
gwl_gh_stub='gh() {
  print x >>"$GWL_CALLS"
  case "$*" in
    *"--state open"*) print -r -- "[{\"number\":7,\"title\":\"t\",\"author\":{\"login\":\"x\"},\"headRefName\":\"feat\",\"headRefOid\":\"abc\",\"state\":\"OPEN\",\"isDraft\":true,\"updatedAt\":\"2026-01-01T00:00:00Z\"}]" ;;
    *) print -r -- "[]" ;;
  esac
}'

@test "gwl caches the PR lookup: a second run within the TTL makes no gh call, -r refetches" {
  gwl_cache_repo
  run zsh -fc "$gwl_gh_stub"'; source "$0"; gwl; wc -l <"$GWL_CALLS"' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  [[ "$output" == *"#7"*draft* ]]
  [[ "${lines[${#lines[@]}-1]}" -eq 2 ]]
  run zsh -fc "$gwl_gh_stub"'; source "$0"; gwl; wc -l <"$GWL_CALLS"' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [[ "$output" == *"#7"*draft* ]]
  [[ "${lines[${#lines[@]}-1]}" -eq 2 ]]
  run zsh -fc "$gwl_gh_stub"'; source "$0"; gwl -r; wc -l <"$GWL_CALLS"' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [[ "${lines[${#lines[@]}-1]}" -eq 4 ]]
}

@test "gwl serves a stale cache at once and refreshes it in the background" {
  gwl_cache_repo
  run zsh -fc "$gwl_gh_stub"'; source "$0"; gwl >/dev/null' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  f=$(echo "$XDG_CACHE_HOME"/zsh/gwl-*.json)
  touch -t 200001010000 "$f"
  run zsh -fc "$gwl_gh_stub"'; source "$0"; gwl' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [[ "$output" == *"#7"*draft* ]]
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(wc -l <"$GWL_CALLS")" -ge 4 ] && [ "$(find "$f" -newermt 2001-01-01 | wc -l)" -eq 1 ] && [ ! -e "$f.lock" ] && break
    sleep 0.2
  done
  [ "$(wc -l <"$GWL_CALLS")" -eq 4 ]
  [ -z "$(find "$f.lock" 2>/dev/null)" ]
}

@test "gwl reports dirty files, ahead and behind from one status call per worktree" {
  gwl_cache_repo
  echo x >f
  run zsh -fc 'gh() { return 1 }; source "$0"; gwl' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [[ "${lines[1]}" == *"1 dirty"* ]]
  git add f
  git -c user.name=t -c user.email=t@t commit -q -m c
  git branch -q --set-upstream-to=main
  run zsh -fc 'gh() { return 1 }; source "$0"; gwl' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [[ "${lines[1]}" == *"ahead 1"* && "${lines[1]}" != *dirty* ]]
}

@test "fdsd replaces a literal string in files matching the glob, hidden ones only with --hidden" {
  command -v fd >/dev/null && command -v sd >/dev/null || skip "fd and sd not installed"
  d=$BATS_TEST_TMPDIR/proj; mkdir -p "$d/.hid"
  echo 'a: foo.x' >"$d/one.yaml"; echo 'a: foo.x' >"$d/.hid/two.yaml"; echo 'a: foo.x' >"$d/three.txt"
  cd "$d"
  run zsh -fc 'source "$0"; fdsd foo.x bar "*yaml"' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  [ "$(cat one.yaml)" = "a: bar" ]
  [ "$(cat .hid/two.yaml)" = "a: foo.x" ]
  # eval parses after the sourcing, so the noglob alias keeps *yaml from expanding
  run zsh -fc 'source "$0"; eval "fdsd foo.x bar *yaml --hidden"' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  [ "$(cat .hid/two.yaml)" = "a: bar" ]
  [ "$(cat three.txt)" = "a: foo.x" ]
}

@test "fdsd -a replaces in every non-hidden file, hidden ones too with --hidden" {
  command -v fd >/dev/null && command -v sd >/dev/null || skip "fd and sd not installed"
  d=$BATS_TEST_TMPDIR/proj; mkdir -p "$d/.hid" "$d/sub"
  echo 'foo' >"$d/one.yaml"; echo 'foo' >"$d/sub/two.txt"; echo 'foo' >"$d/.hid/three"; echo 'foo' >"$d/.dot"
  cd "$d"
  run zsh -fc 'source "$0"; fdsd foo bar -a' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  [ "$(cat one.yaml)" = "bar" ]
  [ "$(cat sub/two.txt)" = "bar" ]
  [ "$(cat .hid/three)" = "foo" ]
  [ "$(cat .dot)" = "foo" ]
  run zsh -fc 'source "$0"; fdsd --hidden foo bar --all' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  [ "$(cat .hid/three)" = "bar" ]
  [ "$(cat .dot)" = "bar" ]
}

@test "fdsd needs exactly one of a glob or -a" {
  run zsh -fc 'source "$0"; fdsd foo bar' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 2 ]
  run zsh -fc 'source "$0"; fdsd foo bar "*yaml" -a' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 2 ]
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

# stub_yazi <body>: a yazi on PATH that y's guard sees; $1 is the dir, $2 --cwd-file=<f>
stub_yazi() {
  mkdir -p "$HOME/bin"
  printf '#!/bin/sh\n%s\n' "$1" >"$HOME/bin/yazi"
  chmod +x "$HOME/bin/yazi"
}

@test "y cds to the dir yazi was left in" {
  mkdir -p "$HOME/there"
  stub_yazi 'printf %s "$1" >"${2#--cwd-file=}"'
  run env PATH="$HOME/bin:$PATH" zsh -fc 'source "$0"; cd /; y "$1"; print -r -- $PWD' "$BATS_TEST_DIRNAME/../.zsh_aliases" "$HOME/there"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/there" ]
}

@test "y stays put when yazi quits without writing a cwd (Q)" {
  stub_yazi ':'
  run env PATH="$HOME/bin:$PATH" zsh -fc 'source "$0"; cd /; y; print -r -- $PWD' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$output" = / ]
}

@test "git shortcut aliases are defined" {
  run zsh -fc 'source "$0"; for a in gs gb gd gl ga gci gma; do print -r -- "$a=$aliases[$a]"; done' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "gs=git status" ]
  [ "${lines[3]}" = "gl=git log -5" ]
  [ "${lines[6]}" = "gma=git merge --abort" ]
}

# zb <code>: run code in zsh with the aliases loaded, on branch $BRANCH (default
# worktree-12-x) whose open PR is $PR (none if unset). gh calls go to
# $HOME/gh-calls; fzf prints "picker" and cancels. tty_gpd is gpd as if stdout
# were a terminal.
zb() {
  : >"$HOME/gh-calls"
  zsh -fc '
    source "$0"
    gh() {
      print -r -- "gh $*" >>"$HOME/gh-calls"
      case "$1 $2" in
        "pr view") [[ -n ${PR-} ]] && print -r -- $PR || return 1 ;;
        "api user") print me ;;
        "pr list") print "[]" ;;
      esac
    }
    git() { [[ $1 == branch ]] && print -r -- "${BRANCH-worktree-12-x}" }
    fzf() { print -u2 picker; return 1 }
    commands[fzf]=/usr/bin/true
    _page() { cat }
    functions[tty_gpd]=${functions[gpd]/"[[ ! -t 1 ]]"/false}
    '"$1" "$BATS_TEST_DIRNAME/../.zsh_aliases"
}

@test "bare gpd pages the current branch's PR diff without a picker" {
  PR=7 run zb 'tty_gpd'
  [ "$status" -eq 0 ]
  [[ "$output" != *picker* ]]
  [ "$(tail -1 "$HOME/gh-calls")" = "gh pr diff --color=always" ]
}

@test "gpd opens the picker when the branch has no PR, or with -p" {
  run zb 'tty_gpd'
  [[ "$output" == *picker* ]]
  PR=7 run zb 'tty_gpd -p'
  [[ "$output" == *picker* ]]
  run grep -c 'pr diff' "$HOME/gh-calls"
  [ "$output" = 0 ]
}

@test "gpx asks before closing the current branch's PR, default no; -y skips it" {
  PR=7 run zb 'gpx </dev/null'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Close #7 and delete its branch?"* ]]
  run grep -c 'pr close' "$HOME/gh-calls"
  [ "$output" = 0 ]
  PR=7 run zb 'gpx -y; cat "$HOME/gh-calls"'
  [[ "$output" == *"gh pr close 7 --delete-branch"* ]]
  run zb 'gpx --yes -c bye 9; cat "$HOME/gh-calls"'
  [[ "$output" == *"gh pr close 9 --delete-branch -c bye"* ]]
  run zb 'gpx -y'
  [ "$status" -eq 1 ]
  [[ "$output" == *"no open PR"* ]]
}

# zm <code>: like zb for gpm. The branch's open PR is 7 ($STATE is its merge
# state, default BLOCKED); the repo allows auto-merge when $AUTO is true. gh
# calls go to $HOME/gh-calls.
zm() {
  : >"$HOME/gh-calls"
  zsh -fc '
    source "$0"
    gh() {
      print -r -- "gh $*" >>"$HOME/gh-calls"
      case "$1 $2" in
        "pr view") [[ $* == *mergeStateStatus* ]] \
          && print -r -- "https://github.com/o/r/pull/7	${STATE-BLOCKED}" || print 7 ;;
        "api repos/o/r") print -r -- "${AUTO-false}" ;;
      esac
    }
    '"$1" "$BATS_TEST_DIRNAME/../.zsh_aliases"
}

@test "gpm enables auto-merge without asking when the repo allows it and the PR is blocked" {
  AUTO=true run zm 'gpm </dev/null; cat "$HOME/gh-calls"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Enabling auto-merge for #7 (merge state BLOCKED)"* ]]
  [[ "$output" == *"gh pr merge 7 --squash --auto"* ]]
  [[ "$output" != *"[y/N]"* ]]
  AUTO=true STATE=BEHIND run zm 'gpm -R o/r 7 </dev/null; cat "$HOME/gh-calls"'
  [[ "$output" == *"gh pr view 7 -R o/r --json url,mergeStateStatus"* ]]
  [[ "$output" == *"gh pr merge 7 --squash --auto -R o/r"* ]]
}

@test "gpm falls back to a confirmed merge when auto-merge is off, the PR is mergeable, or --no-auto/--admin" {
  for case in false:BLOCKED true:CLEAN true:DIRTY; do
    AUTO=${case%:*} STATE=${case#*:} run zm 'gpm </dev/null'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Squash-merge #7?"* ]]
    run grep -c 'pr merge' "$HOME/gh-calls"
    [ "$output" = 0 ]
  done
  AUTO=true run zm 'gpm -y --no-auto; cat "$HOME/gh-calls"'
  [[ "$output" == *"gh pr merge 7 --squash"* ]]
  [[ "$output" != *"--auto"* ]]
  [[ "$output" != *mergeStateStatus* ]]
  AUTO=true run zm 'gpm -y --admin; cat "$HOME/gh-calls"'
  [[ "$output" == *"gh pr merge 7 --squash --admin"* ]]
  [[ "$output" != *"--auto"* ]]
}

@test "gpm --auto passes through without asking or probing" {
  run zm 'gpm --auto; cat "$HOME/gh-calls"'
  [[ "$output" == *"gh pr merge 7 --squash --auto"* ]]
  [[ "$output" != *mergeStateStatus* ]]
}

@test "bare giv and gicm use the worktree-<N> branch's issue, else (or with -p) pick" {
  run zb 'giv; gicm; cat "$HOME/gh-calls"'
  [[ "$output" == *"gh issue view 12"* ]]
  [[ "$output" == *"gh issue comment 12"* ]]
  BRANCH=main run zb 'giv'
  [[ "$output" == *picker* ]]
  run zb 'giv -p'
  [[ "$output" == *picker* ]]
}

@test "bare gic asks before closing the branch's issue, -y skips it, a number does not ask" {
  run zb 'gic </dev/null'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Close #12"* ]]
  run zb 'gic -y; gic 4; cat "$HOME/gh-calls"'
  [[ "$output" == *"gh issue close 12"* ]]
  [[ "$output" == *"gh issue close 4"* ]]
  [[ "$output" != *"[y/N]"* ]]
}

@test "every git/gh shortcut has a #: line for ghelp" {
  run zsh -fc 'source "$0"
    setopt extendedglob
    documented=(${${(M)${(f)"$(<$0)"}:#\#: *}//(#b)\#: ([^ ]##)*/$match[1]})
    for a in ${(k)aliases}; do
      [[ $a == g* && $aliases[$a] == (git|gh|_gh)* ]] && (( ! ${documented[(Ie)$a]} )) && print -r -- "undocumented alias $a"
    done
    for f in ${(k)functions}; do
      [[ $f == g[a-z]## ]] && (( ! ${documented[(Ie)$f]} )) && print -r -- "undocumented function $f"
    done
    true' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "ghelp lists usage and description, and filters by word" {
  run zsh -fc 'source "$0"; ghelp' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gpv [pr]"*"view a PR"* ]]
  [ "${#lines[@]}" -gt 50 ]
  run zsh -fc 'source "$0"; ghelp MERGE' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [[ "$output" == *"gpm [pr]"* ]]
  [[ "$output" != *"gpv [pr]"* ]]
}
