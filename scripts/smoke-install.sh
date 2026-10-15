#!/usr/bin/env bash
# Smoke test for install.sh on a fresh machine (CI runs it in a clean Debian
# container and on macOS): run it twice, then start an interactive zsh.
#
#   - the first run must succeed
#   - the second must change nothing: no relinks, backups, installs or pins
#   - the main dotfiles must be links that resolve
#   - an interactive zsh must start with nothing on stderr
#
#   scripts/smoke-install.sh   (destructive to ~: only for a throwaway machine)
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf 'smoke-install: %s\n' "$*" >&2; exit 1; }

echo "--- first run"
./install.sh -y || fail "first run failed"

echo "--- second run"
second=$(./install.sh -y 2>&1) || { printf '%s\n' "$second"; fail "second run failed"; }
printf '%s\n' "$second"
if changed=$(grep -E 'linked |backed up|installing |installed |pinned at|apt install|completion: ' <<<"$second"); then
  fail "second run was not a no-op:"$'\n'"$changed"
fi

echo "--- links"
for f in .zshrc .zshenv .zsh_aliases .gitconfig .ssh/config .config/mise/config.toml .local/bin/gws; do
  [ -L "$HOME/$f" ] || fail "$HOME/$f is not a link"
  [ -e "$HOME/$f" ] || fail "$HOME/$f is a dangling link"
done

echo "--- interactive zsh"
# from $HOME: in this checkout mise would rightly warn that its mise.toml is not
# trusted. Without a terminal, zsh warns that it cannot enable zle; also expected.
cd "$HOME"
err=$(zsh -i -c 'exit' 2>&1 >/dev/null | grep -v "can't change option: zle" || true)
[ -z "$err" ] || fail "zsh startup wrote to stderr:"$'\n'"$err"
zsh -i -c 'whence antidote compinit >/dev/null' 2>/dev/null || fail "antidote or compinit missing in zsh"

echo "smoke-install: ok"
