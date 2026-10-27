# the history_cwd autosuggest strategy in .zshrc: cd suggestions only for dirs that exist from $PWD
setup() {
  command -v zsh >/dev/null || skip "zsh not installed"
  export HOME=$BATS_TEST_TMPDIR/home
  mkdir -p "$HOME/repo/docs"
  # fc -R in a non-interactive zsh drops the file's last line, hence the trailing filler
  printf '%s\n' 'cd docs' 'cd src/content/blog' 'ls -la' 'cd ~' 'cd src/content/x' 'cd ~/repo' 'true' >"$BATS_TEST_TMPDIR/hist"
}

# suggest <buffer>: the suggestion for <buffer>, run from ~/repo with the fake history
suggest() {
  cd "$HOME/repo" && HISTFILE=$BATS_TEST_TMPDIR/hist zsh -fc '
    _zsh_autosuggest_strategy_history() { typeset -g suggestion="${history[(r)$1*]}"; }
    eval "$(sed -n "/^_zsh_autosuggest_strategy_history_cwd()/,/^}/p" "$0")"
    fc -R
    _zsh_autosuggest_strategy_history_cwd "$1"
    print -r -- "$suggestion"' "$BATS_TEST_DIRNAME/../.zshrc" "$1"
}

@test "cd skips history entries whose dir does not exist here" {
  run suggest 'cd s'
  [ "$output" = "" ]
}

@test "cd suggests the newest entry that exists here" {
  run suggest 'cd '
  [ "$output" = "cd ~/repo" ]
  run suggest 'cd d'
  [ "$output" = "cd docs" ]
}

@test "other commands use the plain history strategy" {
  run suggest 'ls'
  [ "$output" = "ls -la" ]
}
