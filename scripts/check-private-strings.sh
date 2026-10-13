#!/usr/bin/env bash
# Pre-commit guard against linking identities: fails if a staged change adds any
# string listed (one per line, case-insensitive, fixed strings) in
# ~/.config/dotfiles/private-strings. That list is per-machine and never
# committed, since publishing it would leak exactly what it protects. CI has no
# copy, so this only runs locally.
#
#   scripts/check-private-strings.sh   scan added lines and paths of the staged diff
set -euo pipefail

list=${DOTFILES_PRIVATE_STRINGS:-$HOME/.config/dotfiles/private-strings}
[ -s "$list" ] || exit 0

patterns=$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$list" || true)
[ -n "$patterns" ] || exit 0

fail=0
# names of staged files whose path or added lines match (the match is not printed)
while IFS= read -r f; do
  if printf '%s\n' "$f" | grep -qiF -- "$patterns" \
    || git diff --cached --no-color -U0 -- "$f" | grep '^+' | grep -qiF -- "$patterns"; then
    echo "check-private-strings: $f adds a string listed in $list" >&2
    fail=1
  fi
done < <(git diff --cached --name-only --diff-filter=d)
exit "$fail"
