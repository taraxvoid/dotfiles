#!/usr/bin/env bash
# Claude Code PreToolUse hook. Blocks file edits (Edit|Write|NotebookEdit) and
# `git commit` (Bash) when the target is a repo's main checkout, so Claude must
# EnterWorktree first. Other Bash commands and paths outside git repos are
# allowed. Escape hatch: CLAUDE_ALLOW_MAIN_EDITS=1.
set -uo pipefail
[ "${CLAUDE_ALLOW_MAIN_EDITS:-}" = 1 ] && exit 0

# resolve <base> <path>: path with quotes stripped, ~ and $HOME expanded, made
# absolute against base
resolve() {
  local p=$2
  p=${p#[\"\']} p=${p%[\"\']}
  case $p in
    \~ | \$HOME | \$\{HOME\}) p=$HOME ;;
    \~/* | \$HOME/* | \$\{HOME\}/*) p=$HOME/${p#*/} ;;
  esac
  case $p in /*) printf '%s' "$p" ;; *) printf '%s/%s' "$1" "$p" ;; esac
}

input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input")
case $tool in
  Edit | Write) target=$(jq -r '.tool_input.file_path // empty' <<<"$input") ;;
  NotebookEdit) target=$(jq -r '.tool_input.notebook_path // empty' <<<"$input") ;;
  Bash)
    # Only `git commit` is gated; read-only commands run anywhere. Checked here as
    # well as by the settings.json `if` filter, which doesn't reliably narrow it.
    cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
    # git, its global options (-C <dir>, -c <k=v>, --flags), then commit
    re='(^|[;&|(]|[[:space:]])git(([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*)[[:space:]]+commit([[:space:]]|$)'
    [[ $cmd =~ $re ]] || exit 0
    opts=${BASH_REMATCH[2]} before=${cmd%%"${BASH_REMATCH[0]}"*}
    # the commit runs where the last `cd <dir>` before it went, else the cwd...
    target=$(jq -r '.cwd // empty' <<<"$input")
    re_cd='(^|[;&|(])[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+)'
    while [[ $before =~ $re_cd ]]; do
      target=$(resolve "$target" "${BASH_REMATCH[2]}")
      before=${before#*"${BASH_REMATCH[0]}"}
    done
    # ...then each git -C <dir> applies on top
    read -r -a words <<<"$opts"
    for ((i = 0; i < ${#words[@]}; i++)); do
      if [ "${words[i]}" = -C ] && [ $((i + 1)) -lt ${#words[@]} ]; then
        target=$(resolve "$target" "${words[i + 1]}")
      fi
    done
    ;;
  *) exit 0 ;;
esac
[ -n "$target" ] || exit 0

dir=$target
[ "$tool" = Bash ] || dir=$(dirname "$target")
while [ ! -d "$dir" ] && [ "$dir" != / ]; do dir=$(dirname "$dir"); done

gitdir=$(git -C "$dir" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
[ "$gitdir" = "$common" ] || exit 0

cat >&2 <<MSG
Blocked: $target is in a repo's main checkout. Call EnterWorktree (short
kebab-case name) first, make changes there, and commit freely on the worktree
branch. Set CLAUDE_ALLOW_MAIN_EDITS=1 only if Tara explicitly asks for edits in place.
MSG
exit 2
