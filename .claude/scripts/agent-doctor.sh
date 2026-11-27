#!/usr/bin/env bash
# agent-doctor: say loudly when the agent setup is quietly broken.
#
# Silent when everything is fine. Otherwise prints one line per problem, which
# a SessionStart hook puts in front of Claude (and so in front of Tara).
#
#   agent-doctor.sh            links + hooks + chore health
#   agent-doctor.sh --links    links + hooks only (install.sh uses this; no network)
#
# Checks:
# - $HOME/.dotfiles resolves, and not into $HOME/worktrees (a cleaned worktree would
#   take every linked hook with it)
# - $HOME/.claude/CLAUDE.md resolves to a file
# - $HOME/.claude/agents resolves to a directory with at least one persona
# - every symlink in $HOME/.claude/scripts resolves
# - every hook command in $HOME/.claude/settings.json that names a path exists
# - no open gh-aw failure issues ("[aw] ...") in AGENT_DOCTOR_REPOS
#   (default taraxvoid/voidlife), cached for 6 hours
set -uo pipefail
# shellcheck disable=SC2088 # "$HOME/..." in messages is display text, meant literally

problems=()
warn() { problems+=("$1"); }

dot=$(readlink "$HOME/.dotfiles" 2>/dev/null || true)
if [ ! -d "$HOME/.dotfiles" ]; then
  warn "$HOME/.dotfiles does not resolve${dot:+ (points at $dot)}: every linked hook and script is broken"
elif [[ $dot == "$HOME"/worktrees/* ]]; then
  warn "$HOME/.dotfiles points at a worktree ($dot); cleaning it breaks every hook. Repoint: ln -sfn $HOME/projects/personal/dotfiles $HOME/.dotfiles"
fi

[ -f "$HOME/.claude/CLAUDE.md" ] ||
  warn "$HOME/.claude/CLAUDE.md missing: global preferences are not loading. Fix: ln -s $HOME/.dotfiles/.claude/CLAUDE.md $HOME/.claude/CLAUDE.md"

if [ ! -d "$HOME/.claude/agents" ]; then
  warn "$HOME/.claude/agents missing: rookery personas are not available. Fix: ln -s $HOME/projects/personal/rookery/agents $HOME/.claude/agents"
elif ! compgen -G "$HOME/.claude/agents/*.md" >/dev/null; then
  warn "$HOME/.claude/agents has no personas ($(readlink "$HOME/.claude/agents" 2>/dev/null))"
fi

for f in "$HOME"/.claude/scripts/*; do
  [ -L "$f" ] && [ ! -e "$f" ] && warn "broken link: $f -> $(readlink "$f")"
done

if command -v jq >/dev/null && [ -f "$HOME/.claude/settings.json" ]; then
  while IFS= read -r cmd; do
    path=${cmd%% *}
    path=${path//\$HOME/$HOME}
    path=${path#\'}; path=${path%\'}
    [[ $path == /* ]] || continue
    [ -e "$path" ] || warn "hook command not found: $path"
  done < <(jq -r '.hooks // {} | .[][] | .hooks[]? | .command' "$HOME/.claude/settings.json" 2>/dev/null |
    sed -E "s/^bash '([^']+)'.*/\1/")
fi

if [ "${1:-}" != "--links" ] && command -v gh >/dev/null; then
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/agent-doctor/chores"
  mkdir -p "$(dirname "$cache")"
  if [ ! -f "$cache" ] || [ -n "$(find "$cache" -mmin +360 2>/dev/null)" ]; then
    : >"$cache.tmp"
    for repo in ${AGENT_DOCTOR_REPOS:-taraxvoid/voidlife}; do
      gh issue list -R "$repo" --state open --label agentic-workflows \
        --search '"[aw]" in:title' --json number,title \
        --jq ".[] | select(.title | test(\"Detection Runs\") | not) | \"$repo#\(.number) \(.title)\"" \
        >>"$cache.tmp" 2>/dev/null || true # "[aw] Detection Runs" is a standing tracker, not a failure
    done
    mv "$cache.tmp" "$cache"
  fi
  while IFS= read -r line; do
    [ -n "$line" ] && warn "agent chore failing: $line"
  done <"$cache"
fi

if [ ${#problems[@]} -gt 0 ]; then
  echo "agent-doctor found ${#problems[@]} problem(s) with the agent setup. Tell Tara before starting work:"
  printf -- '- %s\n' "${problems[@]}"
  [ "${1:-}" = "--links" ] && exit 1
fi
exit 0
