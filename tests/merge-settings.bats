setup() {
  load helpers
  setup_env
  frag=$BATS_TEST_DIRNAME/../.claude/settings.fragment.json
  s=$BATS_TEST_TMPDIR/settings.json
}

@test "fills an empty settings file" {
  echo '{}' >"$s"
  run merge-settings.sh "$frag" "$s"
  [ "$status" -eq 0 ]
  [ "$(jq -r .statusLine.command "$s")" = '$HOME/.claude/scripts/statusline.sh' ]
  [ "$(jq '.hooks.SessionStart | length' "$s")" = 1 ]
  [ "$(jq '.hooks.Stop[0].hooks[0].timeout' "$s")" = 20 ]
}

@test "keeps unrelated keys and hooks" {
  echo '{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"other"}]}],"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"p"}]}]}}' >"$s"
  merge-settings.sh "$frag" "$s"
  [ "$(jq -r .model "$s")" = x ]
  [ "$(jq '.hooks.Stop | length' "$s")" = 2 ]
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$s")" = p ]
}

@test "second run changes nothing and makes no backup" {
  echo '{}' >"$s"
  merge-settings.sh "$frag" "$s"
  before=$(cat "$s")
  rm -f "$s".bak.*
  run merge-settings.sh "$frag" "$s"
  [[ "$output" == *"already up to date"* ]]
  [ "$(cat "$s")" = "$before" ]
  [ -z "$(ls "$s".bak.* 2>/dev/null)" ]
}

@test "backs up before changing and replaces statusLine" {
  echo '{"statusLine":{"type":"command","command":"old"}}' >"$s"
  merge-settings.sh "$frag" "$s"
  [ "$(jq -r .statusLine.command "$s")" = '$HOME/.claude/scripts/statusline.sh' ]
  [ "$(jq -r .statusLine.command "$s".bak.*)" = old ]
}

@test "creates a missing settings file" {
  merge-settings.sh "$frag" "$s"
  [ "$(jq '.hooks.Stop | length' "$s")" = 1 ]
}

@test "adds every guardrail hook and the worktree deny rules to a fresh file" {
  echo '{}' >"$s"
  merge-settings.sh "$frag" "$s"
  [ "$(jq '.hooks.PreToolUse | length' "$s")" = 2 ]
  [ "$(jq -r '.hooks.PreToolUse[1].hooks[0].if' "$s")" = 'Bash(git commit*)' ]
  [ "$(jq -r '.hooks.WorktreeCreate[0].hooks[0].command' "$s")" = '$HOME/.claude/scripts/worktree-create.sh' ]
  [ "$(jq '.hooks.WorktreeRemove | length' "$s")" = 1 ]
  [ "$(jq -r '.permissions.deny[0]' "$s")" = 'Bash(git worktree remove*)' ]
}

@test "deny rules are appended once, keeping existing ones and their order" {
  echo '{"permissions":{"deny":["Bash(curl*)","Bash(git worktree prune*)"],"allow":["Read"]}}' >"$s"
  merge-settings.sh "$frag" "$s"
  merge-settings.sh "$frag" "$s"
  [ "$(jq -c '.permissions.deny' "$s")" = '["Bash(curl*)","Bash(git worktree prune*)","Bash(git worktree remove*)","Bash(rm -rf ~/worktrees*)"]' ]
  [ "$(jq -c '.permissions.allow' "$s")" = '["Read"]' ]
}

@test "a machine that already wired the hooks by hand gets no duplicates" {
  jq '{hooks: {PreToolUse: .hooks.PreToolUse, WorktreeCreate: .hooks.WorktreeCreate}}' "$frag" >"$s"
  merge-settings.sh "$frag" "$s"
  [ "$(jq '.hooks.PreToolUse | length' "$s")" = 2 ]
  [ "$(jq '.hooks.WorktreeCreate | length' "$s")" = 1 ]
}
