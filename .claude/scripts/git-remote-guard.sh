#!/usr/bin/env bash
# Claude Code PreToolUse hook for Bash `git push|fetch|ls-remote`. Those run outside
# the sandbox, and git reads its config (core.sshCommand, credential helpers,
# url.*.insteadOf, remote.*.receivepack, core.hooksPath, ...) from the repo's git
# dir. The sandbox protects .git/config and .git/hooks, but a worktree finds its git
# dir through files the sandbox can write: the worktree's `.git` file and the
# gitdir's `commondir`. Repointing either at a git dir under $TMPDIR would hand
# that config to the unsandboxed git. So before the call runs, this checks that:
#   - the common dir is a repo's own .git directory (not a file, not under a
#     sandbox-writable scratch dir), and the git dir is it or <common>/worktrees/*;
#   - every config file git reads is one of the expected ones (system, global,
#     ~/.gitconfig.local, <common>/config), so no include or config.worktree
#     pulls in a writable file.
# Otherwise it blocks (exit 2). Escape hatch: CLAUDE_ALLOW_GIT_REMOTE_ANYWHERE=1.
set -uo pipefail
[ "${CLAUDE_ALLOW_GIT_REMOTE_ANYWHERE:-}" = 1 ] && exit 0

input=$(cat)
[ "$(jq -r '.tool_name // empty' <<<"$input")" = Bash ] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
re='^[[:space:]]*git[[:space:]]+(push|fetch|ls-remote)([[:space:]]|$)'
[[ $cmd =~ $re ]] || exit 0

block() { echo "Blocked: $1. Unsandboxed git would read config from it." >&2; exit 2; }

cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0
# outside a repo (ls-remote <url>) there is no repo config to worry about
gitdir=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
gitdir=$(cd "$gitdir" && pwd -P) common=$(cd "$common" && pwd -P)

case $common in
  */.git) ;;
  *) block "git common dir $common is not a repo's .git directory" ;;
esac
# GIT_REMOTE_GUARD_SCRATCH (space-separated) overrides the list, for tests
read -r -a scratches <<<"${GIT_REMOTE_GUARD_SCRATCH:-${TMPDIR:-/tmp} /tmp /private/tmp /var/folders /private/var/folders}"
for scratch in "${scratches[@]}"; do
  scratch=$(cd "$scratch" 2>/dev/null && pwd -P) || continue
  case $common/ in "$scratch"/*) block "git common dir $common is in a scratch dir" ;; esac
done
case $gitdir in
  "$common" | "$common"/worktrees/*) ;;
  *) block "git dir $gitdir is not $common or one of its worktrees" ;;
esac

# every config file git reads must be an expected one
home=$(cd "$HOME" && pwd -P)
# realpath of a file's directory plus its name (keeps a symlinked file's own name)
realfile() { (cd "$(dirname "$1")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$1")") || printf '%s' "$1"; }
global=/nonexistent
[ -n "${GIT_CONFIG_GLOBAL:-}" ] && global=$(realfile "$GIT_CONFIG_GLOBAL")
while IFS= read -r origin; do
  case $origin in
    command\ line:* | "" ) continue ;;
    file:*) f=${origin#file:} ;;
    *) block "git config origin $origin is unexpected" ;;
  esac
  case $f in /*) ;; *) f=$PWD/$f ;; esac
  real=$(realfile "$f")
  case $real in
    /etc/gitconfig | /private/etc/gitconfig | /opt/homebrew/etc/gitconfig | /usr/local/etc/gitconfig) ;;
    /Library/Developer/CommandLineTools/* | /Applications/Xcode*.app/*) ;;
    "$home"/.gitconfig | "$home"/.gitconfig.local | "$home"/.config/git/config) ;;
    "$global") ;;
    # ~/.gitconfig links into the dotfiles checkout (sandbox denyWrite)
    "$home"/projects/personal/dotfiles/.gitconfig) ;;
    "$common"/config) ;;
    *) block "git reads config from $real" ;;
  esac
done < <(git config --list --show-origin --name-only 2>/dev/null | cut -f1 | sort -u)
exit 0
