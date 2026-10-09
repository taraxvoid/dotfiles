#!/usr/bin/env bash
# Idempotent setup for these dotfiles on macOS or Debian/Ubuntu (incl. ChromeOS
# Crostini). Safe to re-run; re-run it from the checkout you want ~ to point at.
#
#   ./install.sh           link dotfiles, install zsh plugins, generate completions
#   ./install.sh --chsh    also make zsh the login shell
#
# What it deliberately does NOT touch: ~/.config/gh/hosts.yml, ~/.config/poolside
# (they hold per-machine auth state) and ~/.claude (machine-specific hooks). Diff
# those by hand. ~/.config/gh/config.yml has no secrets, so it is linked.
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
for f in .zshrc .zshenv .zsh_aliases .zsh_plugins.txt .bunfig.toml .config/starship.toml .config/gh/config.yml; do
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

# --- completions -----------------------------------------------------------
# Generated once here instead of `eval "$(tool completion zsh)"` in .zshrc, which
# costs a process spawn per tool on every shell start. Written to ~/.zsh/completions
# (first on fpath in .zshrc). Tools whose package already ships a completion (gh,
# rg, fd, eza, zoxide via apt/brew) are left alone. Re-run after upgrading a tool.
# Not covered: wrangler, astro, biome, vitest, playwright (per-project or no zsh
# generator), claude (none), flux (sourced in .zshrc when installed).
comp_dir=$HOME/.zsh/completions
mkdir -p "$comp_dir"
# install.sh runs under bash, so put the user tool dirs on PATH the way .zshenv does
PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$PATH"

# gen_completion <name> <command...>: write _name if the tool exists and its
# output looks like a zsh completion; keep the old file if generation fails.
gen_completion() {
  local name=$1; shift
  command -v "$1" >/dev/null || return 0
  local out
  out=$(cd "$DOTFILES" && "$@" 2>/dev/null) || return 0
  case $out in "#compdef"*) ;; *) return 0 ;; esac
  if [ "$out" != "$(cat "$comp_dir/_$name" 2>/dev/null)" ]; then
    printf '%s\n' "$out" >"$comp_dir/_$name"
    comps_changed=1
    say "completion: $name"
  fi
}
comps_changed=0
gen_completion mise mise completion zsh
gen_completion uv uv generate-shell-completion zsh
gen_completion uvx uvx --generate-shell-completion zsh
gen_completion bun env SHELL=zsh bun completions
gen_completion pnpm pnpm completion zsh
gen_completion just just --completions zsh
gen_completion lefthook lefthook completion zsh
gen_completion gitleaks gitleaks completion zsh
gen_completion typst typst completions zsh
gen_completion yq yq completion zsh
gen_completion starship starship completions zsh
gen_completion rustup rustup completions zsh rustup
gen_completion cargo rustup completions zsh cargo
# mise's completions call out to `usage` at tab time
if command -v mise >/dev/null && ! command -v usage >/dev/null; then
  say "note: mise completions need the usage CLI (mise use -g usage)"
fi
# .zshrc trusts the cached ~/.zcompdump for a day, so drop it to pick up changes
[ "$comps_changed" = 1 ] && rm -f "$HOME"/.zcompdump*

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
