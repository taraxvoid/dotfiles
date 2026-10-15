setup() {
  load helpers
  setup_env
  main=$(make_repo personal/app)
  wt=$(add_worktree "$main" worktree-feat)
  c="git commit" # one place, so the strings below stay readable
}

bash_hook() { jq -cn --arg c "$1" --arg d "$2" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' | require-worktree.sh; }
edit_hook() { jq -cn --arg f "$1" '{tool_name: "Edit", tool_input: {file_path: $f}}' | require-worktree.sh; }

@test "blocks a commit in the main checkout" {
  run bash_hook "$c -m x" "$main"
  [ "$status" -eq 2 ]
}

@test "allows a commit in a worktree" {
  run bash_hook "$c -m x" "$wt"
  [ "$status" -eq 0 ]
}

@test "follows cd into a worktree" {
  run bash_hook "cd $wt && $c -m x" "$main"
  [ "$status" -eq 0 ]
}

@test "follows cd into the main checkout" {
  run bash_hook "cd $main && $c -m x" "$wt"
  [ "$status" -eq 2 ]
}

@test "uses the last cd before the commit" {
  run bash_hook "cd $wt; cd $main && $c -m x" "$wt"
  [ "$status" -eq 2 ]
}

@test "follows git -C into a worktree" {
  run bash_hook "git -C $wt commit -m x" "$main"
  [ "$status" -eq 0 ]
}

@test "follows git -C into the main checkout, with other options around it" {
  run bash_hook "git -c core.pager=cat -C $main --no-pager commit -m x" "$wt"
  [ "$status" -eq 2 ]
}

@test "resolves relative and quoted cd and -C paths" {
  run bash_hook "cd '$main' && git -C ../app commit -m x" "$wt"
  [ "$status" -eq 2 ]
  run bash_hook "cd \"$(dirname "$main")\" && git -C app commit -m x" "$wt"
  [ "$status" -eq 2 ]
}

@test "expands ~ and \$HOME" {
  export HOME=$(dirname "$main")
  run bash_hook "cd ~/app && $c -m x" "$wt"
  [ "$status" -eq 2 ]
  run bash_hook "git -C \$HOME/app commit -m x" "$wt"
  [ "$status" -eq 2 ]
}

@test "ignores commands that are not a commit" {
  run bash_hook "git status" "$main"
  [ "$status" -eq 0 ]
  run bash_hook "git log --grep commit" "$main"
  [ "$status" -eq 0 ]
}

@test "blocks edits in the main checkout and allows them in a worktree" {
  run edit_hook "$main/file"
  [ "$status" -eq 2 ]
  run edit_hook "$wt/file"
  [ "$status" -eq 0 ]
}

@test "CLAUDE_ALLOW_MAIN_EDITS=1 lets everything through" {
  CLAUDE_ALLOW_MAIN_EDITS=1 run bash_hook "$c -m x" "$main"
  [ "$status" -eq 0 ]
}
