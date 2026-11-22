setup() {
  load helpers
  setup_env
  frag=$BATS_TEST_DIRNAME/../.claude/settings.fragment.json
  s=$BATS_TEST_TMPDIR/settings.json
}

@test "every host sbx allows for untrusted code is also in the fragment allowlist" {
  # sbx keeps its own, stricter list on purpose; this only catches a registry
  # added to sbx but forgotten in the fragment
  sbx=$BATS_TEST_DIRNAME/../.local/bin/sbx
  doms=$(sed -n 's/^ *doms="\(.*\) \${SBX_DOMAINS:-}"$/\1/p' "$sbx")
  [ -n "$doms" ]
  for d in $doms; do
    run jq -e --arg d "$d" '.sandbox.network.allowedDomains | index($d) != null' "$frag"
    [ "$status" -eq 0 ] || { echo "missing from fragment: $d"; return 1; }
  done
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
  [ "$(jq '.hooks.PreToolUse | length' "$s")" = 7 ]
  [ "$(jq -r '.hooks.PreToolUse[1].hooks[0].if' "$s")" = 'Bash(git commit*)' ]
  [ "$(jq -r '.hooks.PreToolUse[2].hooks[0].command' "$s")" = '$HOME/.claude/scripts/gh-aw-frontmatter-guard.sh' ]
  [ "$(jq -r '.hooks.PreToolUse[3].hooks[0].command' "$s")" = '$HOME/.claude/scripts/gh-aw-pre-push.sh' ]
  [ "$(jq -r '.hooks.PreToolUse[4].hooks[0].command' "$s")" = '$HOME/.claude/scripts/git-push-no-verify.sh' ]
  [ "$(jq -r '.hooks.PreToolUse[5].hooks[0].command' "$s")" = '$HOME/.claude/scripts/git-remote-guard.sh' ]
  [ "$(jq -r '.hooks.PreToolUse[6].hooks[0].command' "$s")" = '$HOME/.claude/scripts/gh-api-guard.sh' ]
  [ "$(jq -r '.hooks.WorktreeCreate[0].hooks[0].command' "$s")" = '$HOME/.claude/scripts/worktree-create.sh' ]
  [ "$(jq '.hooks.WorktreeRemove | length' "$s")" = 1 ]
  [ "$(jq -r '.permissions.deny[0]' "$s")" = 'Bash(git worktree remove*)' ]
}

@test "deny rules are appended once, keeping existing ones and their order" {
  echo '{"permissions":{"deny":["Bash(curl*)","Bash(git worktree prune*)"],"allow":["Read"]}}' >"$s"
  merge-settings.sh "$frag" "$s"
  merge-settings.sh "$frag" "$s"
  # existing rules first, then the fragment's in its order, each rule once
  want=$(jq -c '["Bash(curl*)","Bash(git worktree prune*)"] as $old
    | reduce .permissions.deny[] as $d ($old; if index([$d]) then . else . + [$d] end)' "$frag")
  [ "$(jq -c '.permissions.deny' "$s")" = "$want" ]
  [ "$(jq '.permissions.deny | length' "$s")" = "$(jq '.permissions.deny | unique | length' "$s")" ]
  [ "$(jq -r '.permissions.deny[2]' "$s")" = 'Bash(git worktree remove*)' ]
  # allow rules merge the same way: existing first, fragment's appended once
  [ "$(jq -r '.permissions.allow[0]' "$s")" = Read ]
  [ "$(jq '.permissions.allow | index("Bash(gh api repos/*)") != null' "$s")" = true ]
  [ "$(jq '.permissions.allow | length' "$s")" = "$(jq '.permissions.allow | unique | length' "$s")" ]
}

@test "a machine that already wired the hooks by hand gets no duplicates" {
  jq '{hooks: {PreToolUse: .hooks.PreToolUse, WorktreeCreate: .hooks.WorktreeCreate}}' "$frag" >"$s"
  merge-settings.sh "$frag" "$s"
  [ "$(jq '.hooks.PreToolUse | length' "$s")" = 7 ]
  [ "$(jq '.hooks.WorktreeCreate | length' "$s")" = 1 ]
}

@test "obsolete sandbox entries from an earlier merge are removed, the rest kept" {
  echo '{"sandbox":{"excludedCommands":["git pull *","mine *"],"filesystem":{"allowWrite":["~/.local/share/mise","~/mine"]}}}' >"$s"
  merge-settings.sh "$frag" "$s"
  [ "$(jq '.sandbox.excludedCommands | index("git pull *")' "$s")" = null ]
  [ "$(jq '.sandbox.excludedCommands | index("mine *") != null' "$s")" = true ]
  [ "$(jq '.sandbox.filesystem.allowWrite | index("~/.local/share/mise")' "$s")" = null ]
  [ "$(jq '.sandbox.filesystem.allowWrite | index("~/mine") != null' "$s")" = true ]
  # the fragment never lists what it marks obsolete
  [ "$(jq '[.obsolete.excludedCommands[] as $x | .sandbox.excludedCommands | index($x)] | all(. == null)' "$frag")" = true ]
  [ "$(jq '[.obsolete.allowWrite[] as $x | .sandbox.filesystem.allowWrite | index($x)] | all(. == null)' "$frag")" = true ]
}

@test "the fragment denies the gh and push spellings that escape the sandbox" {
  for r in 'Bash(gh auth status*--show-token*)' 'Bash(gh alias set*)' 'Bash(gh extension *)' \
    'Bash(gh config set*)' 'Bash(gh pr checkout*)' 'Bash(gh repo clone*)' \
    'Bash(git push *refs/heads/main*)' 'Bash(git push *--mirror*)' 'Bash(git push *:master)'; do
    [ "$(jq --arg r "$r" '.permissions.deny | index($r) != null' "$frag")" = true ]
  done
  [ "$(jq '.permissions.ask | index("Edit(**/.github/workflows/**)") != null' "$frag")" = true ]
  [ "$(jq '.permissions.ask | index("Bash(gh pr create*--repo*)") != null' "$frag")" = true ]
  [ "$(jq '.permissions.ask | index("Bash(gh gist *)") != null' "$frag")" = true ]
  for v in GH_TOKEN CF_TOKEN_ADMIN; do
    [ "$(jq --arg v "$v" '[.sandbox.credentials.envVars[].name] | index($v) != null' "$frag")" = true ]
  done
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
  # mise installs run unsandboxed (gh among them), so the sandbox must not write them
  [ "$(jq '.sandbox.filesystem.allowWrite | index("~/.local/share/mise") == null' "$s")" = true ]
  # the dotfiles main checkout is live config behind ~/.dotfiles
  [ "$(jq '.sandbox.filesystem.denyWrite | index("~/projects/personal/dotfiles/.claude") != null' "$s")" = true ]
  # pull merges in the unsandboxed process, running post-merge/post-checkout hooks
  [ "$(jq '.sandbox.excludedCommands | index("git pull *") == null' "$s")" = true ]
  # the session's own worktree is added by Claude Code; other sessions' stay read-only
  [ "$(jq '.sandbox.filesystem.allowWrite | index("~/worktrees") == null' "$s")" = true ]
  # uv/bun caches the sandbox writes are its own (.zshenv), not the ones used unsandboxed
  [ "$(jq '.sandbox.filesystem.allowWrite | index("~/.cache/sandbox") != null' "$s")" = true ]
  [ "$(jq '.sandbox.filesystem.allowWrite | index("~/.cache/uv") == null' "$s")" = true ]
  [ "$(jq '.sandbox.filesystem.denyWrite | index("~/**/.zshenv") != null' "$s")" = true ]
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
