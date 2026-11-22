# uv/bun dirs in .zshenv: moved into sandbox-only caches only inside Claude's sandbox
setup() {
  command -v zsh >/dev/null || skip "zsh not installed"
  export HOME=$BATS_TEST_TMPDIR/home
  mkdir -p "$HOME"
  unset UV_TOOL_DIR UV_CACHE_DIR BUN_INSTALL_CACHE_DIR SANDBOX_RUNTIME
}

zenv() { # <var>: its value in a fresh zsh that read our .zshenv
  ZDOTDIR=$BATS_TEST_DIRNAME/.. zsh -c 'print -r -- "${(P)1:-unset}"' zsh "$1"
}

tooldir() { zenv UV_TOOL_DIR; }

@test "outside the sandbox UV_TOOL_DIR is left alone" {
  run tooldir
  [ "$output" = unset ]
}

@test "inside the sandbox UV_TOOL_DIR moves into the sandbox uv cache" {
  SANDBOX_RUNTIME=1 run tooldir
  [ "$output" = "$HOME/.cache/sandbox/uv/tools" ]
}

@test "inside the sandbox UV_TOOL_DIR follows UV_CACHE_DIR" {
  SANDBOX_RUNTIME=1 UV_CACHE_DIR=/c/uv run tooldir
  [ "$output" = /c/uv/tools ]
}

@test "an explicit UV_TOOL_DIR wins" {
  SANDBOX_RUNTIME=1 UV_TOOL_DIR=/mine run tooldir
  [ "$output" = /mine ]
}

@test "outside the sandbox the uv and bun caches are left alone" {
  run zenv UV_CACHE_DIR
  [ "$output" = unset ]
  run zenv BUN_INSTALL_CACHE_DIR
  [ "$output" = unset ]
}

@test "inside the sandbox uv and bun get caches apart from the shared ones" {
  SANDBOX_RUNTIME=1 run zenv UV_CACHE_DIR
  [ "$output" = "$HOME/.cache/sandbox/uv" ]
  SANDBOX_RUNTIME=1 run zenv BUN_INSTALL_CACHE_DIR
  [ "$output" = "$HOME/.cache/sandbox/bun" ]
}

@test "inside the sandbox an explicit cache dir wins" {
  SANDBOX_RUNTIME=1 BUN_INSTALL_CACHE_DIR=/b run zenv BUN_INSTALL_CACHE_DIR
  [ "$output" = /b ]
}
