# _gh_pr_cmd and the PR shortcuts built on it (gpv, gpw, ...), with gh, the picker and
# the current-PR lookup stubbed. Calls land in $HOME/gh-calls; stdout is faked as a tty.
setup() {
  command -v zsh >/dev/null || skip "zsh not installed"
  export HOME=$BATS_TEST_TMPDIR/home
  mkdir -p "$HOME"
}

zc() {
  : >"$HOME/gh-calls"
  zsh -fc '
    source "$0"
    gh() { print -r -- "gh $*" >>"$HOME/gh-calls" }
    _gh_pr_current() { [[ -n ${PR-} ]] && print -r -- $PR }
    _gh_pr_pick() { print 9 }
    commands[fzf]=/usr/bin/true
    functions[_gh_pr_cmd]=${functions[_gh_pr_cmd]/"[[ -t 1 ]]"/true}
    '"$1" "$BATS_TEST_DIRNAME/../.zsh_aliases"
}

@test "bare shortcut on a branch with a PR passes through, no picker" {
  PR=7 run zc 'gpv'
  [ "$(cat "$HOME/gh-calls")" = "gh pr view" ]
}

@test "bare shortcut with no PR on the branch runs on the picked PR" {
  run zc 'gpv'
  [ "$(cat "$HOME/gh-calls")" = "gh pr view 9" ]
}

@test "flag-only call gets the picked number first, subcommand flags kept" {
  run zc 'gpw'
  [ "$(cat "$HOME/gh-calls")" = "gh pr checks --watch 9" ]
  run zc 'gpv --web'
  [ "$(cat "$HOME/gh-calls")" = "gh pr view 9 --web" ]
}

@test "an explicit PR or -R passes straight through" {
  run zc 'gpv 12'
  [ "$(cat "$HOME/gh-calls")" = "gh pr view 12" ]
  run zc 'gpv -R a/b'
  [ "$(cat "$HOME/gh-calls")" = "gh pr view -R a/b" ]
}

@test "attached -R, help and a selector after flags all skip the picker" {
  run zc 'gpv -Ra/b'
  [ "$(cat "$HOME/gh-calls")" = "gh pr view -Ra/b" ]
  run zc 'gpv --help'
  [ "$(cat "$HOME/gh-calls")" = "gh pr view --help" ]
  run zc 'gpv --web 12'
  [ "$(cat "$HOME/gh-calls")" = "gh pr view --web 12" ]
}

@test "on a terminal without fzf it is plain gh" {
  run zc 'unset "commands[fzf]"; gpv'
  [ "$(cat "$HOME/gh-calls")" = "gh pr view" ]
}

@test "without a terminal it is plain gh" {
  run zsh -fc '
    source "$0"
    gh() { print -r -- "gh $*" }
    _gh_pr_pick() { print 9 }
    gpdn' "$BATS_TEST_DIRNAME/../.zsh_aliases"
  [ "$output" = "gh pr diff --name-only" ]
}
