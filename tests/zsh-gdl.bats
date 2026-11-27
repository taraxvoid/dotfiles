# gdl from .zsh_aliases, with `gh pending-deploys` stubbed to print $ROWS
setup() {
  command -v zsh >/dev/null || skip "zsh not installed"
}

gd() {
  zsh -fc 'gh() { [[ -n $ROWS ]] && print -r -- "$ROWS"; return 0 }; source "$0"; gdl' \
    "$BATS_TEST_DIRNAME/../.zsh_aliases"
}

@test "gdl says so when nothing is waiting" {
  ROWS= run gd
  [ "$status" -eq 0 ]
  [ "$output" = "No deployments are waiting for review." ]
}

@test "gdl prints waiting rows as they are" {
  ROWS=$'5\tprod\tcan-approve' run gd
  [ "$output" = $'5\tprod\tcan-approve' ]
}
