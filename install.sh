#!/usr/bin/env bash
# Idempotent setup for these dotfiles on macOS or Debian/Ubuntu (incl. ChromeOS
# Crostini). Safe to re-run; re-run it from the checkout you want ~ to point at.
#
#   ./install.sh           link dotfiles, install zsh plugins
#   ./install.sh --chsh    also make zsh the login shell
#
# What it deliberately does NOT touch: ~/.config/gh, ~/.config/poolside (they hold
# per-machine auth state) and ~/.claude (machine-specific hooks). Diff those by hand.
set -euo pipefail

DOTFILES=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
OS=$(uname -s)

# Pinned like .zsh_plugins.txt: bump on purpose (review the diff, change the SHA).
ANTIDOTE_URL=https://github.com/mattmc3/antidote
ANTIDOTE_SHA=9bb69ab99c6f05d6e6ae237f7ce222eeeb5b4a14 # v2.3.0
SPACESHIP_URL=https://github.com/spaceship-prompt/spaceship-prompt
SPACESHIP_SHA=fd0d6653a134fe28f498eae1784fbb46d27f20f3 # v4.22.5

say() { printf '==> %s\n' "$*"; }

link() { # link <repo-relative path> [dest]
  local src="$DOTFILES/$1" dest="${2:-$HOME/$1}"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    local bak="$dest.pre-dotfiles"
    [ -e "$bak" ] || [ -L "$bak" ] && bak="$bak.$(date +%Y%m%d%H%M%S)"
    mv "$dest" "$bak"
    say "backed up $dest -> $bak"
  fi
  ln -s "$src" "$dest"
  say "linked $dest -> $src"
}

pinned_clone() { # pinned_clone <url> <sha> <dest>
  local url=$1 sha=$2 dest=$3
  if [ -d "$dest/.git" ] && [ "$(git -C "$dest" rev-parse HEAD)" = "$sha" ]; then
    return
  fi
  if [ ! -d "$dest/.git" ]; then
    git clone --quiet "$url" "$dest"
  else
    git -C "$dest" fetch --quiet origin
  fi
  git -C "$dest" -c advice.detachedHead=false checkout --quiet "$sha"
  say "$dest pinned at ${sha:0:12}"
}

# --- dotfiles ---------------------------------------------------------------
for f in .zshrc .zshenv .zsh_aliases .zsh_plugins.txt .bunfig.toml; do
  link "$f"
done
# dx reads these (references to Dashlane entries, not secrets); link the dir only
# if this machine has none of its own.
[ -e "$HOME/.config/dashlane" ] || link .config/dashlane

# --- Linux packages ---------------------------------------------------------
if [ "$OS" = Linux ] && command -v apt-get >/dev/null; then
  need=()
  for p in zsh zsh-autosuggestions zsh-syntax-highlighting; do
    dpkg -s "$p" >/dev/null 2>&1 || need+=("$p")
  done
  if [ ${#need[@]} -gt 0 ]; then
    say "apt install: ${need[*]}"
    sudo apt-get install -y -qq "${need[@]}" >/dev/null
  fi
fi

# --- plugins brew provides on macOS (so only clone off-Mac) -----------------
if [ "$OS" != Darwin ]; then
  mkdir -p "$HOME/.zsh/completions"
  pinned_clone "$ANTIDOTE_URL" "$ANTIDOTE_SHA" "$HOME/.zsh/antidote"
  pinned_clone "$SPACESHIP_URL" "$SPACESHIP_SHA" "$HOME/.zsh/spaceship"
fi

# --- login shell ------------------------------------------------------------
if [ "${1:-}" = --chsh ]; then
  zsh_path=$(command -v zsh)
  if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh_path" ]; then
    grep -qx "$zsh_path" /etc/shells || echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
    sudo chsh -s "$zsh_path" "$USER"
    say "login shell set to $zsh_path (takes effect on next login)"
  fi
fi

# first interactive start lets antidote clone the pinned plugins from .zsh_plugins.txt
say "warming up antidote plugins"
zsh -i -c exit >/dev/null 2>&1 || true
say "done"
