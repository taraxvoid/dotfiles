# UV_TOOL_DIR handling in .zshenv: moved into the uv cache only inside Claude's sandbox
setup() {
  command -v zsh >/dev/null || skip "zsh not installed"
  export HOME=$BATS_TEST_TMPDIR/home
  mkdir -p "$HOME"
  unset UV_TOOL_DIR UV_CACHE_DIR SANDBOX_RUNTIME
}

tooldir() {
  ZDOTDIR=$BATS_TEST_DIRNAME/.. zsh -c 'print -r -- "${UV_TOOL_DIR:-unset}"'
}

@test "outside the sandbox UV_TOOL_DIR is left alone" {
  run tooldir
  [ "$output" = unset ]
}

@test "inside the sandbox UV_TOOL_DIR moves into the uv cache" {
  SANDBOX_RUNTIME=1 run tooldir
  [ "$output" = "$HOME/.cache/uv/tools" ]
}

@test "inside the sandbox UV_TOOL_DIR follows UV_CACHE_DIR" {
  SANDBOX_RUNTIME=1 UV_CACHE_DIR=/c/uv run tooldir
  [ "$output" = /c/uv/tools ]
}

@test "an explicit UV_TOOL_DIR wins" {
  SANDBOX_RUNTIME=1 UV_TOOL_DIR=/mine run tooldir
  [ "$output" = /mine ]
}
