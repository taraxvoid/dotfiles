setup() {
  load helpers
  setup_env
  # a scratch HOME with a clone of this repo as its main checkout and one worktree
  export HOME=$BATS_TEST_TMPDIR/home
  mkdir -p "$HOME"
  repo=$HOME/projects/personal/dotfiles
  git clone -q "$BATS_TEST_DIRNAME/.." "$repo"
  repo=$(cd "$repo" && pwd -P)
  wt=$HOME/worktrees/personal/dotfiles/feat
  git -C "$repo" worktree add -q -b worktree-feat "$wt"
  wt=$(cd "$wt" && pwd -P)
  # stage the working-tree install.sh in both, so the test runs the code under test
  cp "$BATS_TEST_DIRNAME/../install.sh" "$repo/install.sh"
  cp "$BATS_TEST_DIRNAME/../install.sh" "$wt/install.sh"
}

@test "links go through ~/.dotfiles to the main checkout, even when run from a worktree" {
  run "$wt/install.sh" --link-only
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.dotfiles")" = "$repo" ]
  [ "$(readlink "$HOME/.zshrc")" = "$HOME/.dotfiles/.zshrc" ]
  [ "$(readlink "$HOME/.config/mise/config.toml")" = "$HOME/.dotfiles/.config/mise-global.toml" ]
  [ -r "$HOME/.zshrc" ]
}

@test "mise bootstrap config lists the same links install.sh makes" {
  command -v mise >/dev/null || skip "mise not installed"
  "$wt/install.sh" --link-only >/dev/null
  [ "$(readlink "$HOME/.config/mise/conf.d/dotfiles.toml")" = "$HOME/.dotfiles/.config/mise-bootstrap.toml" ]
  # every [dotfiles] entry is in place after the plain link pass, so nothing drifts.
  # -C: from the test's cwd mise would walk up into the real ~/.config/mise
  run env XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" \
    mise -C "$HOME" dot status --json
  [ "$status" -eq 0 ]
  [ "$(jq '.files | length' <<<"$output")" -gt 0 ]
  [ "$(jq -r '[.files[] | select(.state != "applied") | .target] | join(" ")' <<<"$output")" = "" ]
}

@test "--from-here backs ~ with the worktree, and a plain run switches back" {
  "$wt/install.sh" --link-only --from-here >/dev/null
  [ "$(readlink "$HOME/.dotfiles")" = "$wt" ]
  "$wt/install.sh" --link-only >/dev/null
  [ "$(readlink "$HOME/.dotfiles")" = "$repo" ]
}

@test "old direct links into a checkout are repointed through ~/.dotfiles" {
  ln -s "$wt/.gitconfig" "$HOME/.gitconfig"
  "$repo/install.sh" --link-only >/dev/null
  [ "$(readlink "$HOME/.gitconfig")" = "$HOME/.dotfiles/.gitconfig" ]
  [ ! -e "$HOME/.gitconfig.pre-dotfiles" ]
}

@test "a real file is backed up before linking" {
  echo mine >"$HOME/.zshenv"
  "$repo/install.sh" --link-only >/dev/null
  [ "$(cat "$HOME/.zshenv.pre-dotfiles")" = mine ]
}

@test "refuses when ~/.dotfiles is a real directory" {
  mkdir "$HOME/.dotfiles"
  run "$repo/install.sh" --link-only
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a symlink"* ]]
}

@test "cleanup-worktrees skips the worktree ~/.dotfiles points at" {
  git -C "$wt" checkout -q -- install.sh # clean, so only the link guard can skip it
  mkdir -p "$FAKE_GH/dotfiles"
  head=$(git -C "$wt" rev-parse HEAD)
  printf '[{"headRefName":"worktree-feat","state":"MERGED","headRefOid":"%s"}]\n' "$head" >"$FAKE_GH/dotfiles/prs.json"
  ln -s "$wt" "$HOME/.dotfiles"
  run cleanup-worktrees.sh -n "$repo"
  [[ "$output" == *"~/.dotfiles points here"* ]]
  rm "$HOME/.dotfiles"
  run cleanup-worktrees.sh -n "$repo"
  [[ "$output" == *"would remove $wt"* ]]
}
