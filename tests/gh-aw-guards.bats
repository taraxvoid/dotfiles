setup() {
  load helpers
  setup_env
  main=$(make_repo personal/awrepo)
  mkdir -p "$main/.github/workflows"
  printf -- '---\non: workflow_dispatch\npermissions:\n  contents: read\nengine: copilot\n---\n# Hello\n\nSay hello.\n' \
    >"$main/.github/workflows/hello.md"
  git -C "$main" add -A
  git -C "$main" commit -q -m wf
  git -C "$main" push -q origin main
  wf=$main/.github/workflows/hello.md
}

fm() {
  jq -cn --arg t "$1" --arg f "$2" --arg a "$3" --arg b "$4" \
    '{tool_name: $t, tool_input: ($t | if . == "Write" then {file_path: $f, content: $a} else {file_path: $f, old_string: $a, new_string: $b} end)}' |
    gh-aw-frontmatter-guard.sh
}

@test "frontmatter: ignores files that are not workflow sources" {
  run fm Write "$main/README.md" "x" ""
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "frontmatter: prompt-body edit passes silently" {
  run fm Edit "$wf" "Say hello." "Say goodbye."
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "frontmatter: other keys pass silently" {
  run fm Edit "$wf" "on: workflow_dispatch" "on: push"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "frontmatter: asks when permissions change" {
  run fm Edit "$wf" "contents: read" "contents: write"
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$output")" = ask ]
}

@test "frontmatter: asks when a sensitive key is added" {
  run fm Edit "$wf" "engine: copilot" $'engine: copilot\nnetwork: defaults\nsafe-outputs:\n  create-issue:'
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$output")" = ask ]
}

@test "frontmatter: Write that changes engine asks, same frontmatter does not" {
  run fm Write "$wf" $'---\non: workflow_dispatch\npermissions:\n  contents: read\nengine: claude\n---\nhi\n' ""
  [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$output")" = ask ]
  run fm Write "$wf" $'---\non: workflow_dispatch\npermissions:\n  contents: read\nengine: copilot\n---\nhi\n' ""
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "frontmatter: asks for a workflow source new on this branch" {
  run fm Write "$main/.github/workflows/new.md" $'---\non: push\n---\nhi\n' ""
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$output")" = ask ]
}

# stub gh: `gh aw compile` fails (FAKE_AW=fail) or rewrites a lock file (FAKE_AW=dirty)
stub_gh() {
  mkdir -p "$BATS_TEST_TMPDIR/stub"
  cat >"$BATS_TEST_TMPDIR/stub/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$STUB_LOG"
case ${FAKE_AW:-ok} in
  fail) echo "error: bad frontmatter" >&2; exit 1 ;;
  dirty) echo changed >.github/workflows/hello.lock.yml ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/stub/gh"
  export PATH=$BATS_TEST_TMPDIR/stub:$PATH STUB_LOG=$BATS_TEST_TMPDIR/stub.log
  : >"$STUB_LOG"
}

push() {
  jq -cn --arg c "$1" --arg d "$main" '{tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' | gh-aw-pre-push.sh
}

@test "pre-push: ignores commands other than git push" {
  stub_gh
  run push "git status"
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
}

@test "pre-push: skips repos without workflow sources" {
  stub_gh
  rm "$wf"
  run push "git push -u origin HEAD"
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
}

@test "pre-push: runs compile --strict and allows a clean result" {
  stub_gh
  run push "git push -u origin HEAD"
  [ "$status" -eq 0 ]
  grep -q "aw compile --strict" "$STUB_LOG"
}

@test "pre-push: blocks when compile fails" {
  stub_gh
  FAKE_AW=fail run push "git push"
  [ "$status" -eq 2 ]
  [[ $output == *"bad frontmatter"* ]]
}

@test "pre-push: blocks when compile rewrites a lock file" {
  stub_gh
  FAKE_AW=dirty run push "git push"
  [ "$status" -eq 2 ]
  [[ $output == *"lock files"* ]]
}

@test "pre-push: escape hatch skips the check" {
  stub_gh
  FAKE_AW=fail CLAUDE_SKIP_GH_AW_PUSH_CHECK=1 run push "git push"
  [ "$status" -eq 0 ]
}
