#!/usr/bin/env bash
# Claude Code Stop hook. Stop fires at the end of every turn, so this only acts
# when work is at risk: the session's cwd is a non-main worktree whose HEAD has
# commits on no remote, and `gws --here` calls it orphaned. Then it blocks the
# stop once per worktree HEAD so Claude pushes it with a PR or linked issue, or
# says why it should stay local. Fails open: any error or a check slower than
# GWS_HOOK_TIMEOUT seconds (default 8) lets the stop through.
set -o pipefail

input=$(cat)
[ "$(jq -r '.stop_hook_active // false' <<<"$input" 2>/dev/null)" = true ] && exit 0
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
[ -n "$cwd" ] || exit 0
gws=$(command -v gws || echo "$HOME/.local/bin/gws")
[ -x "$gws" ] || exit 0

top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
main=$(dirname "$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")
[ "$top" != "$main" ] || exit 0
[ "$(git -C "$top" rev-list --count HEAD --not --remotes 2>/dev/null)" != 0 ] || exit 0

head=$(git -C "$top" rev-parse HEAD) || exit 0
marks=${XDG_CACHE_HOME:-$HOME/.cache}/gws-nudged
mark=$marks/$(printf '%s' "$top" | tr '/ ' '%_')
[ "$(cat "$mark" 2>/dev/null)" != "$head" ] || exit 0

# Mark first, so a check that hangs or fails is not retried every turn at this HEAD
mkdir -p "$marks" && printf '%s\n' "$head" >"$mark" || exit 0
# gh can hang (offline); cut gws off well before Claude Code's hook timeout.
# Background job plus a sleeping killer, since macOS has no timeout(1). Job
# control (set -m) puts each in its own process group so the kill reaches gws's
# whole tree: a bare kill of gws is deferred by its EXIT trap until the hung gh
# child finishes.
out=$marks/.out.$$
set -m
"$gws" --here "$top" >"$out" 2>/dev/null &
pid=$!
(sleep "${GWS_HOOK_TIMEOUT:-8}"; kill -- "-$pid" 2>/dev/null) >/dev/null 2>&1 &
killer=$!
# disown so bash does not print a "Terminated" job notice (it would land on stderr)
disown "$killer" 2>/dev/null
wait "$pid" 2>/dev/null
rc=$?
kill -- "-$killer" 2>/dev/null
set +m
line=$(cat "$out" 2>/dev/null)
rm -f "$out"
[ "$rc" = 2 ] || exit 0
jq -cn --arg l "$line" '{decision: "block", reason: ("gws: " + $l
  + ". Push it and open a PR, or link an issue (branch worktree-<N>-<slug>, renamed before its first push), or tell Tara why it should stay local.")}'
exit 0
