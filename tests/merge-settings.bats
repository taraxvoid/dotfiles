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

@test "prints usage and exits 2 without both arguments" {
  run merge-settings.sh "$frag"
  [ "$status" -eq 2 ]
  [[ "$output" == usage:* ]]
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

@test "turns the sandbox on and adds its allowlists to a fresh file" {
  echo '{}' >"$s"
  merge-settings.sh "$frag" "$s"
  [ "$(jq .sandbox.enabled "$s")" = true ]
  [ "$(jq '.sandbox.network.allowedDomains | index("github.com") != null' "$s")" = true ]
  [ "$(jq '.sandbox.filesystem.allowWrite | index("~/.claude/plans") != null' "$s")" = true ]
  [ "$(jq '.sandbox.filesystem.allowWrite | index("~/Library/Preferences/.wrangler") != null' "$s")" = true ]
  [ "$(jq '.sandbox.filesystem.allowWrite | index("~/Library/pnpm") != null' "$s")" = true ]
  [ "$(jq '.sandbox.filesystem.allowWrite | index("~/.local/share/aube") != null' "$s")" = true ]
  [ "$(jq .sandbox.network.allowLocalBinding "$s")" = true ]
  [ "$(jq -r '.sandbox.credentials.files[] | select(.path == "~/.ssh") | .mode' "$s")" = deny ]
  [ "$(jq -r '.sandbox.credentials.envVars[] | select(.name == "GITHUB_TOKEN") | .mode' "$s")" = deny ]
}

@test "allowLocalBinding is set without dropping existing network keys" {
  echo '{"sandbox":{"network":{"allowedDomains":["example.com"],"httpProxyPort":8080}}}' >"$s"
  merge-settings.sh "$frag" "$s"
  [ "$(jq .sandbox.network.allowLocalBinding "$s")" = true ]
  [ "$(jq .sandbox.network.httpProxyPort "$s")" = 8080 ]
}

@test "sandbox lists are unioned once and other sandbox keys are kept" {
  echo '{"sandbox":{"enabled":false,"allowUnsandboxedCommands":false,"network":{"allowedDomains":["example.com","github.com"]},"credentials":{"files":[{"path":"~/.ssh","mode":"mask"}]}}}' >"$s"
  merge-settings.sh "$frag" "$s"
  [ "$(jq .sandbox.enabled "$s")" = true ]
  [ "$(jq .sandbox.allowUnsandboxedCommands "$s")" = false ]
  [ "$(jq -r '.sandbox.network.allowedDomains[0]' "$s")" = example.com ]
  [ "$(jq '[.sandbox.network.allowedDomains[] | select(. == "github.com")] | length' "$s")" = 1 ]
  [ "$(jq '[.sandbox.credentials.files[] | select(.path == "~/.ssh")] | length' "$s")" = 1 ]
  [ "$(jq -r '.sandbox.credentials.files[] | select(.path == "~/.ssh") | .mode' "$s")" = mask ]
}
