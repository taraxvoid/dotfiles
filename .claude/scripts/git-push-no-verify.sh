#!/usr/bin/env bash
# Claude Code PreToolUse hook for Bash `git push`. `git push` is a sandbox-excluded
# command (it needs real credentials), and git runs the repo's pre-push hook in
# that same unsandboxed process. The hook (lefthook, husky, a plain script) and
# everything it runs (lefthook.yml, tests, node_modules) are files sandboxed
# commands can write, so letting git run it would run sandbox-written code outside
# the sandbox.
#
# So this hook runs the repo's pre-push hook itself, inside `srt` (sandbox-runtime)
# with the same network allowlist, write dirs and credential denies as Claude's own
# Bash sandbox (read from ~/.claude/settings.json), writable worktree, a fresh
# TMPDIR, and git's usual hook arguments and stdin. If it fails, the push is
# blocked (exit 2) with its output. If it passes (or there is no pre-push hook),
# the command is rewritten to `git push --no-verify ...` (via updatedInput) so git
# does not run it a second time, unsandboxed.
#
# Only a lone `git push` is handled: anything chained or prefixed does not match
# the sandbox exclusion anyway, so it runs sandboxed and cannot push. A push that
# already says --no-verify is not rewritten but still checked, unless the same
# commit already passed for the same remote branch: auto mode makes Claude re-issue
# the rewritten call, and that second call should not run the checks again. Passes
# are recorded in CLAUDE_PUSH_CHECK_DIR (default ~/.cache/claude-push-checks),
# which sandboxed commands can't write.
# Escape hatch: CLAUDE_ALLOW_PUSH_HOOKS=1 (git runs the hook itself, unsandboxed).
# Overrides, for tests: CLAUDE_SETTINGS (settings file), SRT_BIN (srt binary).
set -uo pipefail
[ "${CLAUDE_ALLOW_PUSH_HOOKS:-}" = 1 ] && exit 0

input=$(cat)
[ "$(jq -r '.tool_name // empty' <<<"$input")" = Bash ] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")

# leading whitespace, `git push`, then end or whitespace
re='^([[:space:]]*git[[:space:]]+push)([[:space:]]|$)(.*)$'
[[ $cmd =~ $re ]] || exit 0
rest=${BASH_REMATCH[2]}${BASH_REMATCH[3]}
# already skipping hooks (push has no short form: its -n is --dry-run)
noverify=0
[[ " $rest " == *[[:space:]]--no-verify[[:space:]]* ]] && noverify=1

block() { echo "Blocked push: $1" >&2; exit 2; }

# run_pre_push: run the repo's pre-push hook sandboxed; returns when there is none
# or it passed, blocks otherwise
run_pre_push() {
  local cwd top gitdir hooks hook branch remote url dst lsha rsha
  cwd=$(jq -r '.cwd // empty' <<<"$input")
  [ -n "$cwd" ] && cd "$cwd" 2>/dev/null || return 0
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  gitdir=$(git rev-parse --path-format=absolute --git-dir) || return 0
  hooks=$(git config core.hooksPath) || hooks=
  if [ -n "$hooks" ]; then
    case $hooks in /*) ;; "~"/*) hooks=$HOME/${hooks#"~/"} ;; *) hooks=$top/$hooks ;; esac
  else
    hooks=$(git rev-parse --path-format=absolute --git-path hooks)
  fi
  hook=$hooks/pre-push
  [ -f "$hook" ] && [ -x "$hook" ] || return 0

  # git's hook arguments (<remote> <url>) and stdin (<local ref> <local sha>
  # <remote ref> <remote sha>), for the usual `git push [opts] [remote [branch]]`
  local -a pos=() words=()
  local w
  read -r -a words <<<"$rest"
  for w in ${words[@]+"${words[@]}"}; do [[ $w == -* ]] || pos+=("$w"); done
  branch=$(git symbolic-ref -q --short HEAD) || branch=
  remote=${pos[0]:-}
  if [ -z "$remote" ]; then
    remote=$(git config "branch.$branch.pushRemote" || git config remote.pushDefault ||
      git config "branch.$branch.remote" || echo origin)
  fi
  url=$(git remote get-url --push "$remote" 2>/dev/null) || url=$remote
  local src=${pos[1]:-$branch}
  src=${src#+}
  dst=${src#*:} src=${src%%:*}
  [ -n "$src" ] || return 0 # a delete; nothing local to check
  lsha=$(git rev-parse --verify -q "$src^{commit}") || return 0
  [[ $src == refs/* ]] || src=refs/heads/$src
  [[ $dst == refs/* ]] || dst=refs/heads/$dst
  rsha=$(git rev-parse --verify -q "refs/remotes/$remote/${dst#refs/heads/}") ||
    rsha=0000000000000000000000000000000000000000

  local stamps=${CLAUDE_PUSH_CHECK_DIR:-$HOME/.cache/claude-push-checks} stamp
  stamp=$stamps/$(printf '%s\n' "$top" "$lsha" "$remote" "$dst" "$(git hash-object "$hook")" |
    git hash-object --stdin)
  [ -e "$stamp" ] && return 0

  local srt=${SRT_BIN:-srt} settings=${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}
  command -v "$srt" >/dev/null ||
    block "srt (sandbox-runtime) not found, so the pre-push hook can't run sandboxed. Install it (mise use -g npm:@anthropic-ai/sandbox-runtime) or set CLAUDE_ALLOW_PUSH_HOOKS=1."
  local cfgdir tmp cfg
  cfgdir=$(mktemp -d) tmp=$(mktemp -d)
  # shellcheck disable=SC2064 # expand now: the dirs are fixed
  trap "rm -rf '$cfgdir' '$tmp'" EXIT
  cfg=$cfgdir/srt.json
  jq --arg top "$top" --arg gitdir "$gitdir" --arg tmp "$tmp" '(.sandbox // {}) as $s | {
      network: {
        allowedDomains: ($s.network.allowedDomains // []),
        deniedDomains: ($s.network.deniedDomains // []),
        allowLocalBinding: ($s.network.allowLocalBinding // false)
      },
      filesystem: {
        denyRead: ($s.filesystem.denyRead // []),
        allowRead: ($s.filesystem.allowRead // []),
        allowWrite: (($s.filesystem.allowWrite // []) + [$top, $gitdir, $tmp]),
        denyWrite: ($s.filesystem.denyWrite // [])
      },
      credentials: ($s.credentials // {}),
      enableWeakerNetworkIsolation: ($s.enableWeakerNetworkIsolation // false)
    }' "$settings" 2>/dev/null >"$cfg" || echo '{}' | jq --arg top "$top" --arg gitdir "$gitdir" --arg tmp "$tmp" '{
      network: {allowedDomains: [], deniedDomains: []},
      filesystem: {denyRead: [], allowWrite: [$top, $gitdir, $tmp], denyWrite: []}
    }' >"$cfg"

  # zsh, so .zshenv points package caches at ~/.cache/sandbox as in Claude's sandbox.
  # srt sets the child's TMPDIR from CLAUDE_CODE_TMPDIR (else /tmp/claude), and
  # Claude's own value (/tmp/claude-<uid>) is not writable under this config. Claude
  # also exports TMPPREFIX=/tmp/claude-<uid>/zsh, which zsh uses for heredoc and
  # =(...) temp files, so the zsh above fails there too unless it is moved as well.
  local sh inner out rc
  sh=$(command -v zsh || command -v bash)
  inner=$(printf '%q ' "$hook" "$remote" "$url")
  out=$(cd "$top" && printf '%s %s %s %s\n' "$src" "$lsha" "$dst" "$rsha" |
    TMPDIR=$tmp TMPPREFIX=$tmp/zsh CLAUDE_CODE_TMPDIR=$tmp CLAUDE_TMPDIR=$tmp SANDBOX_RUNTIME=1 "$srt" -s "$cfg" -c "$(printf '%q -c %q' "$sh" "$inner")" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    mkdir -p "$stamps" && touch "$stamp"
    return 0
  fi
  {
    echo "Blocked push: the pre-push hook failed (exit $rc), run sandboxed via srt. Fix what it reports and push again:"
    tail -n 40 <<<"$out"
  } >&2
  exit 2
}
# In a subshell: an unexpected failure in there (exit 1, an unset variable) must
# block the push, not let it run with git's own, unsandboxed hook
(run_pre_push)
rc=$?
[ "$rc" -eq 0 ] || { [ "$rc" -eq 2 ] || echo "Blocked push: ${0##*/} failed (exit $rc) checking the pre-push hook." >&2; exit 2; }
[ "$noverify" = 1 ] && exit 0

# Insert right after `git push` so deny rules anchored on the tail
# (`git push * main`, `git push * --force*`) still match.
fixed="git push --no-verify$rest"
jq -cn --arg c "$fixed" --argjson i "$(jq -c '.tool_input' <<<"$input")" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: ($i + {command: $c})
  }
}'
exit 0
