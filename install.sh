#!/usr/bin/env bash
# Idempotent setup for these dotfiles on macOS or Debian/Ubuntu (incl. ChromeOS
# Crostini). Safe to re-run; re-run it from the checkout you want ~ to point at.
#
#   ./install.sh           link dotfiles, install zsh plugins
#   ./install.sh --chsh    also make zsh the login shell
#   ./install.sh -y        answer yes to every prompt (also: --yes)
#
# It asks (default no) before linking the Claude files in .claude/ into ~/.claude;
# anything already there is moved aside to <name>.pre-dotfiles first. With no
# terminal on stdin it assumes no unless -y is given.
#
# What it deliberately does NOT touch: ~/.config/gh/hosts.yml, ~/.config/poolside
# (they hold per-machine auth state) and the rest of ~/.claude (settings.json and
# hooks are machine-specific). Diff those by hand. ~/.config/gh/config.yml has no
# secrets, so it is linked.
#
# Stays bash (not POSIX sh) for arrays and [[ ]]; keep it bash 3.2 compatible,
# that is what macOS ships.
set -euo pipefail

DOTFILES=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
OS=$(uname -s)

# Pinned like .zsh_plugins.txt: bump on purpose (review the diff, change the SHA).
ANTIDOTE_URL=https://github.com/mattmc3/antidote
ANTIDOTE_SHA=9bb69ab99c6f05d6e6ae237f7ce222eeeb5b4a14 # v2.3.0
# starship is a Rust binary, not a zsh plugin, so antidote can't provide it.
# brew on macOS; on Linux a checksummed release tarball goes in ~/.local/bin.
STARSHIP_VERSION=1.26.0
# shellcheck disable=SC2034 # indirect expansion via sha_var
STARSHIP_SHA256_x86_64=b7c232b0e8249d8e55a40beb79c5c43a7d370f3f9408bd215deb0170daeaadf3
# shellcheck disable=SC2034 # indirect expansion via sha_var
STARSHIP_SHA256_aarch64=dc30189378d2f2e287384e8a692d3f95ad1df64cf0e8c36aa9201516028aed6b
NERDFONT_VERSION=3.5.1
NERDFONT_SHA256=04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf # JetBrainsMono.tar.xz

CHSH=0
YES=0
for arg in "$@"; do
  case $arg in
    --chsh) CHSH=1 ;;
    -y | --yes) YES=1 ;;
    *) echo "usage: $0 [--chsh] [-y|--yes]" >&2; exit 2 ;;
  esac
done

say() { printf '==> %s\n' "$*"; }

ask() { # ask <question>: default no; -y answers yes; no tty means no
  [ "$YES" = 1 ] && return 0
  [ -t 0 ] || return 1
  local reply
  read -r -p "$1 [y/N] " reply
  [[ $reply == [yY] || $reply == [yY][eE][sS] ]]
}

link() { # link <repo-relative path> [dest]
  local src="$DOTFILES/$1" dest="${2:-$HOME/$1}" cur bak
  mkdir -p "$(dirname "$dest")"
  cur=$(readlink "$dest" 2>/dev/null || true)
  [ "$cur" = "$src" ] && return
  if [ -n "$cur" ] && [[ $cur == */"$1" ]]; then
    # points into another checkout of this repo: nothing to keep, just repoint
    ln -sfn "$src" "$dest"
    say "relinked $dest -> $src"
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    bak="$dest.pre-dotfiles"
    if [ -e "$bak" ] || [ -L "$bak" ]; then bak="$bak.$(date +%Y%m%d%H%M%S)"; fi
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
for f in .zshrc .zshenv .zsh_aliases .zsh_plugins.txt .bunfig.toml .gitconfig .config/git/ignore .config/starship.toml .config/gh/config.yml; do
  link "$f"
done
# dx reads these (references to Dashlane entries, not secrets); link the dir only
# if this machine has none of its own.
[ -e "$HOME/.config/dashlane" ] || link .config/dashlane

# --- Claude files (opt-in) --------------------------------------------------
# link() backs up whatever is already at the destination. Scripts are linked one
# by one so other scripts in ~/.claude/scripts (e.g. hooks) are left alone.
if ask "Link Claude files (.claude/CLAUDE.md, .claude/scripts/*) into ~/.claude?"; then
  link .claude/CLAUDE.md
  for f in .claude/scripts/*.sh; do link "$f"; done
else
  say "skipping ~/.claude (pass -y to link it)"
fi

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
fi

# --- starship + Nerd Font ---------------------------------------------------
fetch_verified() { # fetch_verified <url> <sha256> <dest>
  curl -fsSL "$1" -o "$3"
  echo "$2  $3" | sha256sum -c --quiet - || { echo "checksum mismatch: $1" >&2; exit 1; }
}

if [ "$OS" = Darwin ]; then
  if command -v brew >/dev/null; then
    command -v starship >/dev/null || brew install --quiet starship
    brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1 \
      || brew install --quiet --cask font-jetbrains-mono-nerd-font
  fi
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  if ! command -v starship >/dev/null || [ "$(starship --version | awk 'NR==1{print $2}')" != "$STARSHIP_VERSION" ]; then
    arch=$(uname -m)
    sha_var=STARSHIP_SHA256_$arch
    [ -n "${!sha_var:-}" ] || { echo "no pinned starship checksum for $arch" >&2; exit 1; }
    say "installing starship $STARSHIP_VERSION"
    fetch_verified "https://github.com/starship/starship/releases/download/v$STARSHIP_VERSION/starship-$arch-unknown-linux-musl.tar.gz" \
      "${!sha_var}" "$tmp/starship.tar.gz"
    mkdir -p "$HOME/.local/bin"
    tar -xzf "$tmp/starship.tar.gz" -C "$HOME/.local/bin" starship
  fi
  fontdir=$HOME/.local/share/fonts/JetBrainsMonoNerd
  if [ ! -e "$fontdir/.v$NERDFONT_VERSION" ]; then
    say "installing JetBrainsMono Nerd Font $NERDFONT_VERSION"
    fetch_verified "https://github.com/ryanoasis/nerd-fonts/releases/download/v$NERDFONT_VERSION/JetBrainsMono.tar.xz" \
      "$NERDFONT_SHA256" "$tmp/font.tar.xz"
    rm -rf "$fontdir"; mkdir -p "$fontdir"
    tar -xJf "$tmp/font.tar.xz" -C "$fontdir" --wildcards '*.ttf'
    touch "$fontdir/.v$NERDFONT_VERSION"
    command -v fc-cache >/dev/null && fc-cache -f "$fontdir"
  fi
fi

# --- login shell ------------------------------------------------------------
if [ "$CHSH" = 1 ]; then
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
