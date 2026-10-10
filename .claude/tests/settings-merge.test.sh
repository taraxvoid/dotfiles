#!/usr/bin/env bash
# Tests for .claude/settings-merge.jq. Prints only failures, exits 1 on any.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
m() { jq --slurpfile shared "$here/../settings.shared.json" --arg home /h -f "$here/../settings-merge.jq"; }
fail=0
expect() { # desc jq-filter-that-must-be-true json
  jq -e "$2" >/dev/null <<<"$3" || { echo "FAIL: $1"; fail=1; }
}

# A local file like the one this replaced: an old Bash entry with `if`, a local
# allow list, an unrelated user hook, and one shared deny rule already present.
local_json='{
  "model": "opus",
  "permissions": {"allow": ["Bash(ls*)"], "deny": ["Bash(git worktree prune*)", "Bash(sudo*)"]},
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "$HOME/.claude/scripts/require-worktree.sh", "if": "Bash(git commit*)"}]},
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "my-logger"}]}
    ],
    "Stop": [{"hooks": [{"type": "command", "command": "notify"}]}]
  }
}'

once=$(m <<<"$local_json")
twice=$(m <<<"$once")
[ "$once" = "$twice" ] || { echo "FAIL: not idempotent"; fail=1; }

expect "local scalar kept" '.model == "opus"' "$once"
expect "local allow kept" '.permissions.allow == ["Bash(ls*)"]' "$once"
expect "deny unioned, local first, no dupes" \
  '.permissions.deny == ["Bash(git worktree prune*)", "Bash(sudo*)", "Bash(git worktree remove*)", "Bash(rm -rf ~/worktrees*)", "Bash(rm -rf /h/worktrees*)"]' "$once"
expect "old guard entry (with if) replaced" \
  '[.hooks.PreToolUse[].hooks[] | select(.command | test("require-worktree"))] | length == 2 and all(has("if") | not)' "$once"
expect "unrelated user hooks kept" \
  '([.hooks.PreToolUse[].hooks[].command] | index("my-logger")) and .hooks.Stop[0].hooks[0].command == "notify"' "$once"
expect "worktree hooks added" '.hooks.WorktreeCreate[0].hooks[0].timeout == 60 and (.hooks.WorktreeRemove | length) == 1' "$once"
expect "\$HOME left literal in hook commands" '.hooks.WorktreeRemove[0].hooks[0].command | startswith("$HOME/")' "$once"

empty=$(m <<<'{}')
expect "from empty" '(.hooks | keys) == ["PreToolUse","WorktreeCreate","WorktreeRemove"] and (.permissions.deny | length) == 4' "$empty"

# install.sh's merge_claude_settings, against a throwaway HOME.
repo=$(cd "$here/../.." && pwd -P)
fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
mkdir -p "$fake/.claude"
echo '{"model": "opus"}' >"$fake/.claude/settings.json"
chmod 644 "$fake/.claude/settings.json"
eval "$(sed -n '/^say()/p;/^merge_claude_settings()/,/^}/p' "$repo/install.sh")"
out=$(HOME=$fake DOTFILES=$repo merge_claude_settings; HOME=$fake DOTFILES=$repo merge_claude_settings)
[ "$(grep -c merged <<<"$out")" = 1 ] || { echo "FAIL: install merge should report once, got: $out"; fail=1; }
[ -e "$fake/.claude/settings.json.pre-dotfiles" ] || { echo "FAIL: install merge left no backup"; fail=1; }
[ "$(stat -c %a "$fake/.claude/settings.json" 2>/dev/null || stat -f %Lp "$fake/.claude/settings.json")" = 644 ] ||
  { echo "FAIL: install merge changed file mode"; fail=1; }
expect "install merge result" ".model == \"opus\" and (.permissions.deny | index(\"Bash(rm -rf $fake/worktrees*)\"))" \
  "$(cat "$fake/.claude/settings.json")"
[ -z "$(find "$fake/.claude" -name 'settings.json.??????')" ] || { echo "FAIL: temp file left behind"; fail=1; }

[ $fail = 0 ] && echo "ok"
exit $fail
