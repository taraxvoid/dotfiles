#!/usr/bin/env bash
# Idempotent setup for these dotfiles on macOS or Debian/Ubuntu (incl. ChromeOS
# Crostini). Safe to re-run; re-run it from the checkout you want ~ to point at.
#
#   ./install.sh           link dotfiles, install zsh plugins, generate completions
#   ./install.sh --chsh    also make zsh the login shell
#   ./install.sh -y        answer yes to every prompt (also: --yes)
#
# It asks (default no) before linking the Claude files in .claude/ into ~/.claude;
# anything already there is moved aside to <name>.pre-dotfiles first. With no
# terminal on stdin it assumes no unless -y is given.
#
# What it deliberately does NOT touch: ~/.config/gh/hosts.yml, ~/.config/poolside
# (they hold per-machine auth state) and the rest of ~/.claude. settings.json is
# machine-specific; the Claude step only merges .claude/settings.fragment.json
# into it (backed up first). ~/.config/gh/config.yml has no secrets, so it is
# linked.
#
# Stays bash (not POSIX sh) for arrays and [[ ]]; keep it bash 3.2 compatible,
# that is what macOS ships.
set -euo pipefail

DOTFILES=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
OS=$(uname -s)

# Pinned like .zsh_plugins.txt: bump on purpose (review the diff, change the SHA).
ANTIDOTE_URL=https://github.com/mattmc3/antidote
ANTIDOTE_SHA=9bb69ab99c6f05d6e6ae237f7ce222eeeb5b4a14 # v2.3.0
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
# ssh refuses a config that others can write; ~/.ssh itself must be private.
# Other accounts and private hosts go in the untracked ~/.ssh/config.local.
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
link .ssh/config
# dx reads these (references to Dashlane entries, not secrets); link the dir only
# if this machine has none of its own.
[ -e "$HOME/.config/dashlane" ] || link .config/dashlane

# --- dev tiers: sandbox, mise trust, git hooks, auto-fetch -------------------
# Repos live in ~/projects/{personal,ravenflight,untrusted} (worktrees mirror that
# under ~/worktrees). personal and ravenflight are trusted: mise auto-trusts their
# mise.toml and lefthook hooks install themselves. untrusted gets neither; use sbx.
link .config/mise-global.toml "$HOME/.config/mise/config.toml"
link .local/bin/sbx
link .local/bin/git-autofetch
link .local/bin/gws
mkdir -p "$HOME"/projects/{personal,ravenflight,untrusted} "$HOME"/worktrees/{personal,ravenflight,untrusted}

# --- mise, uv, bun, and the CLI tools mise provides --------------------------
# mise, uv and bun come from their vendors and update themselves (`mise self-update`,
# `uv self update`, `bun upgrade`), so they are installed only when missing. They are
# deliberately not in the global mise config: a mise copy of uv/bun would shadow the
# vendor one and hide unpinned-version mistakes in projects. Everything else
# (neovim, fzf, rg, zoxide, just, yq, starship) is pinned in
# .config/mise-global.toml and installed by `mise install` (aqua backend, which
# verifies release checksums), because Debian's apt versions are years old.
# eza is the exception: the author's apt repo (Linux) or brew (macOS) is used
# because the release binary ships no zsh completion and the packages do.
if [ "$OS" = Darwin ] && command -v brew >/dev/null; then
  command -v mise >/dev/null || brew install --quiet mise
  command -v uv >/dev/null || brew install --quiet uv
  command -v bun >/dev/null || brew install --quiet oven-sh/bun/bun
  command -v eza >/dev/null || brew install --quiet eza
else
  PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
  if ! command -v mise >/dev/null; then
    say "installing mise"
    curl -fsSL https://mise.run | sh >/dev/null
  fi
  if ! command -v uv >/dev/null; then
    say "installing uv"
    curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh >/dev/null
  fi
  if ! command -v bun >/dev/null; then
    say "installing bun"
    curl -fsSL https://bun.sh/install | SHELL=/bin/sh bash >/dev/null
  fi
fi
if command -v mise >/dev/null; then
  say "mise install (global tools)"
  mise install --yes --quiet || echo "warning: mise install failed; re-run after fixing" >&2
  mise reshim
fi

# --- release cooldowns -------------------------------------------------------
# Every package manager refuses releases younger than 3 days, which blunts
# "publish a poisoned version and wait for installs" attacks: bun via the linked
# ~/.bunfig.toml, uv via ~/.config/uv/uv.toml, mise via its global config, npm
# and pnpm via their user config files here (~/.npmrc also holds the npm login
# token, so it is set in place rather than linked).
link .config/uv/uv.toml
PATH="$HOME/.local/share/mise/shims:$PATH"
if command -v npm >/dev/null && [ "$(npm config get min-release-age 2>/dev/null)" != 3 ]; then
  npm config set min-release-age 3 --location=user && say "npm: min-release-age 3 (days)"
fi
if command -v pnpm >/dev/null && [ "$(pnpm config get minimum-release-age 2>/dev/null)" != 4320 ]; then
  pnpm config set minimum-release-age 4320 --global >/dev/null && say "pnpm: minimum-release-age 4320 (minutes)"
fi

# post-checkout is copied, not linked: git copies it into every new repo's .git/hooks,
# and a link into a checkout of this repo would dangle when that checkout goes away.
# Only files carrying the managed-by marker are overwritten.
copy_hook() { # copy_hook <dest>
  local dest=$1
  if [ -e "$dest" ] && ! grep -q 'managed-by: dotfiles' "$dest"; then
    say "leaving $dest alone (not managed by dotfiles)"
    return
  fi
  cmp -s "$DOTFILES/.config/git/template/hooks/post-checkout" "$dest" 2>/dev/null && return
  mkdir -p "$(dirname "$dest")"
  cp "$DOTFILES/.config/git/template/hooks/post-checkout" "$dest"
  say "installed $dest"
}
copy_hook "$HOME/.config/git/template/hooks/post-checkout"
for d in "$HOME"/projects/personal/*/ "$HOME"/projects/ravenflight/*/; do
  [ -e "$d/.git" ] || continue
  # a repo with core.hooksPath (husky) never runs .git/hooks, so leave it alone
  [ -z "$(git -C "$d" config core.hooksPath)" ] || continue
  copy_hook "$(git -C "$d" rev-parse --path-format=absolute --git-common-dir)/hooks/post-checkout"
done

if [ "$OS" = Linux ] && systemctl --user show-environment >/dev/null 2>&1; then
  link .config/systemd/user/git-autofetch.service
  link .config/systemd/user/git-autofetch.timer
  systemctl --user daemon-reload
  systemctl --user enable --now git-autofetch.timer >/dev/null 2>&1 || say "could not enable git-autofetch.timer"
fi

# --- Claude files (opt-in) --------------------------------------------------
# link() backs up whatever is already at the destination. Scripts are linked one
# by one so other scripts in ~/.claude/scripts (e.g. hooks) are left alone.
# settings.json stays a per-machine file: only the tracked fragment (status line,
# gws hooks) is merged into it, with a backup first.
if ask "Link Claude files (.claude/CLAUDE.md, .claude/scripts/*) and merge .claude/settings.fragment.json into ~/.claude/settings.json?"; then
  link .claude/CLAUDE.md
  for f in .claude/scripts/*.sh; do link "$f"; done
  say "$("$DOTFILES/.claude/scripts/merge-settings.sh" "$DOTFILES/.claude/settings.fragment.json" "$HOME/.claude/settings.json")"
else
  say "skipping ~/.claude (pass -y to link it)"
fi

# --- Linux packages ---------------------------------------------------------
if [ "$OS" = Linux ] && command -v apt-get >/dev/null; then
  need=()
  for p in zsh zsh-autosuggestions zsh-syntax-highlighting; do
    dpkg -s "$p" >/dev/null 2>&1 || need+=("$p")
  done
  # eza's own apt repo (https://github.com/eza-community/eza/blob/main/INSTALL.md)
  if [ ! -e /etc/apt/sources.list.d/gierens.list ]; then
    say "adding eza apt repo"
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
      | sudo gpg --dearmor --yes -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] https://deb.gierens.de stable main" \
      | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    sudo apt-get update -qq >/dev/null
  elif grep -q 'http://deb.gierens.de' /etc/apt/sources.list.d/gierens.list; then
    # plain HTTP gets intercepted by filtering proxies, which apt reports as "not signed"
    say "switching eza apt repo to https"
    sudo sed -i 's|http://deb.gierens.de|https://deb.gierens.de|' /etc/apt/sources.list.d/gierens.list
    sudo apt-get update -qq >/dev/null
  fi
  dpkg -s eza >/dev/null 2>&1 || need+=(eza)
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

# --- Nerd Font ---------------------------------------------------
fetch_verified() { # fetch_verified <url> <sha256> <dest>
  curl -fsSL "$1" -o "$3"
  echo "$2  $3" | sha256sum -c --quiet - || { echo "checksum mismatch: $1" >&2; exit 1; }
}

if [ "$OS" = Darwin ]; then
  if command -v brew >/dev/null; then
    brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1 \
      || brew install --quiet --cask font-jetbrains-mono-nerd-font
  fi
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
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
    say "completion: $name"
  fi
}
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
# (mise's completions call `usage` at tab time; it is pinned in the global mise
# config and installed by `mise install` above)
# .zshrc trusts the cached ~/.zcompdump for a day and only notices fpath string
# changes, not completions added or removed (apt/brew installs, deleted files), so
# always drop it; the next shell rebuilds it.
rm -f "$HOME"/.zcompdump*

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
