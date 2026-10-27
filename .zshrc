# Cross-platform (macOS + Debian/Ubuntu/ChromeOS Crostini): detect what exists
# instead of branching on OS. Every macOS path below is still tried first.
source "${ZDOTDIR:-$HOME}/.zsh_aliases"

# colima (macOS) exposes docker on a per-user socket; only point at it if present
[[ -S "$HOME/.colima/default/docker.sock" ]] && export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"

# helper: set REPLY to the first readable candidate path (macOS brew paths come
# first, then Linux package/clone locations)
_zfind() { local f; for f in "$@"; do [[ -r $f ]] && { REPLY=$f; return 0 } done; return 1 }
_brew=${HOMEBREW_PREFIX:-/opt/homebrew}

# helper: _cache_eval <name> <cmd...> sources what <cmd...> prints, cached in
# ~/.cache/zsh/<name>.zsh and regenerated when the tool's binary changes (new
# path or newer mtime). Saves a process spawn per tool on every shell start.
# Only for init scripts that print the same text each time (mise's embeds $PATH).
_cache_eval() {
  local name=$1 bin=${commands[$2]} f=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/$1.zsh first
  shift
  [[ -n $bin ]] || return 1
  [[ -r $f ]] && read -r first <$f
  if [[ $first != "# $bin" || $bin -nt $f ]]; then
    mkdir -p ${f:h}
    { print -r -- "# $bin"; "$@" } >| $f 2>/dev/null || { rm -f $f; return 1 }
  fi
  source $f
}

# ssh keys: keychain reuses one long-lived ssh-agent across shells and loads every
# private key in ~/.ssh (prompting once per boot for passphrases). Not installed
# on macOS, which has its own launchd agent. Exports SSH_AUTH_SOCK via the env file.
# keychain itself is slow (~130ms), so it only runs when no agent answers yet; a
# key missing from a live agent is added on first use (AddKeysToAgent in ~/.ssh/config).
if [[ -o interactive ]] && (( $+commands[keychain] )); then
  [[ -r ~/.keychain/${HOST}-sh ]] && source ~/.keychain/${HOST}-sh
  ssh-add -l &>/dev/null
  if (( $? == 2 )); then
    # `~` (glob exclusion) only works with extendedglob, which is off by default
    () {
      setopt local_options extendedglob
      keychain --quiet --agents ssh --ignore-missing ~/.ssh/id*~*.pub(N) 2>/dev/null
    }
    [[ -r ~/.keychain/${HOST}-sh ]] && source ~/.keychain/${HOST}-sh
  fi
fi

# HISTFILE is only preset by macOS's /etc/zshrc, not on Debian/Ubuntu
: ${HISTFILE:=$HOME/.zsh_history}

# dedupe PATH and fpath entries (zsh ties $path to $PATH; first occurrence wins)
typeset -U path PATH fpath

# Maximum lines kept in memory
export HISTSIZE=100000
# Maximum lines saved to $HISTFILE
export SAVEHIST=100000
# Like INC_APPEND_HISTORY + re-read history whenever accessing it
setopt SHARE_HISTORY

# only show latest cmd if it's a dupe
setopt HIST_IGNORE_ALL_DUPS

# commands starting with a space aren't saved (handy for one-off secrets)
setopt HIST_IGNORE_SPACE
# collapse runs of blanks before saving
setopt HIST_REDUCE_BLANKS

# macOS only: GNU unix utils such as timeout (installed as gtimeout)
[[ -d "$_brew/opt/coreutils/libexec/gnubin" ]] && PATH="$_brew/opt/coreutils/libexec/gnubin:$PATH"
# user-writable tool dirs (~/.local/bin, ~/.bun/bin, ~/.cargo/bin, ~/.turso) are
# moved after the system dirs at the end of this file; see "PATH order" below

export HOMEBREW_NO_ENV_HINTS=1

# every completion dir goes on fpath *before* compinit, or its completions never
# register (a dir added afterwards is ignored until the next rebuild).
# sentry-cli installs its completion into ~/.local/share/zsh/site-functions.
fpath=( "$HOME/.zsh/completions" "$HOME/.local/share/zsh/site-functions" $fpath )

# antidote (zsh plugins): brew on macOS, pinned clone from install.sh on Linux.
# Only sourced here (defines the function); `antidote load` runs after compinit.
_zfind "$_brew/opt/antidote/share/antidote/antidote.zsh" "$HOME/.zsh/antidote/antidote.zsh" && source $REPLY
# zsh-completions, from antidote's clone. Look in its cache dirs (Linux, macOS)
# directly; `antidote path` costs ~35ms and is only the fallback on a first run.
(( $+functions[antidote] )) && () {
  local d
  for d in ${ANTIDOTE_HOME:-} ~/.cache/antidote ~/Library/Caches/antidote; do
    [[ -d $d/github.com/zsh-users/zsh-completions/src ]] && { fpath=("$d/github.com/zsh-users/zsh-completions/src" $fpath); return }
  done
  d=$(antidote path zsh-users/zsh-completions 2>/dev/null)
  [[ -d $d/src ]] && fpath=("$d/src" $fpath)
}

# full compinit (with its slow security audit) when the cache is over a day old or
# fpath changed (e.g. a plugin was just cloned); otherwise trust the cached
# ~/.zcompdump with -C. The (#qN.mh+24) glob qualifier is only evaluated with
# extendedglob; without it the test is always true and the cache is never used.
autoload -Uz compinit
() {
  setopt local_options extendedglob
  local sig=$HOME/.zcompdump.fpath
  if [[ -n ${HOME}/.zcompdump(#qN.mh+24) || ! -r $sig || $(<$sig) != "$fpath" ]]; then
    compinit
    print -r -- "$fpath" >| $sig
  else
    compinit -C
  fi
}

# This forces word navigation/deletion to respect slashes, periods, etc.
autoload -U select-word-style
select-word-style bash

# absolute path ($_mise_bin, found in .zshenv): ~/.local/bin isn't on PATH yet here
[[ -n $_mise_bin ]] && eval "$("$_mise_bin" activate zsh)"

# zoxide: `j <part of dir>` jumps to the best frecent match, `ji` is an fzf picker
_cache_eval zoxide zoxide init zsh --cmd j

# fzf defaults: fd respects .gitignore and is much faster than find.
# Debian/Ubuntu ship fd as `fdfind` and bat as `batcat`; fzf runs these strings in
# a subshell where aliases don't exist, so resolve the real binary names here.
_fd=${${commands[fd]:+fd}:-${commands[fdfind]:+fdfind}}
_bat=${${commands[bat]:+bat}:-${commands[batcat]:+batcat}}
# Top-down list with the cursor on the first item, and up/down wrap around.
export FZF_DEFAULT_OPTS="--layout=reverse --cycle"
if [[ -n $_fd ]]; then
  export FZF_DEFAULT_COMMAND="$_fd --type f --hidden --follow --exclude .git"
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND="$_fd --type d --hidden --follow --exclude .git"
fi
[[ -n $_bat ]] && export FZF_CTRL_T_OPTS="--preview '$_bat --color=always --style=numbers --line-range=:200 {}'"
(( $+commands[eza] )) && export FZF_ALT_C_OPTS="--preview 'eza --tree --level=1 --color=always {}'"
if (( $+commands[fzf] )); then
  if ! _cache_eval fzf fzf --zsh; then
    # fzf < 0.48 (older Ubuntu/Debian) has no --zsh; use the packaged scripts
    for f in /usr/share/doc/fzf/examples/{key-bindings,completion}.zsh(N); do source $f; done
    unset f
  fi
fi
_cache_eval flux flux completion zsh
# tool completions (just, mise, uv, bun, cf, ...) are generated into ~/.zsh/completions by install.sh

# emacs keymap. zsh picks vi mode by itself when $EDITOR or $VISUAL contains "vi".
bindkey -e

# Bind Up and Down arrow keys for Fish-like history searching. Terminals in
# application mode (Crostini, ghostty, tmux) send ^[OA/^[OB instead of ^[[A/^[[B.
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
[[ -n $terminfo[kcuu1] ]] && bindkey "$terminfo[kcuu1]" history-substring-search-up
[[ -n $terminfo[kcud1] ]] && bindkey "$terminfo[kcud1]" history-substring-search-down

# Word navigation: ctrl+arrows (^[[1;5), alt+arrows (^[[1;3 xterm/ghostty, ^[^[[ and
# ^[[1;9 for some macOS terminals), in both normal and application cursor mode.
# select-word-style bash (above) makes backward-word/forward-word stop at / . etc.
for _m in 5 3 9; do
  bindkey "^[[1;${_m}D" backward-word
  bindkey "^[[1;${_m}C" forward-word
done
bindkey '^[^[[D' backward-word
bindkey '^[^[[C' forward-word
bindkey '^[^[OD' backward-word
bindkey '^[^[OC' forward-word
bindkey '^[b' backward-word
bindkey '^[f' forward-word
# Home/End/Delete (xterm, application mode, and terminfo variants)
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[OH' beginning-of-line
bindkey '^[OF' end-of-line
bindkey '^[[3~' delete-char
[[ -n $terminfo[khome] ]] && bindkey "$terminfo[khome]" beginning-of-line
[[ -n $terminfo[kend] ]] && bindkey "$terminfo[kend]" end-of-line
unset _m

# fzf-tab: case-insensitive + partial-path matching (e.g. proj/syn<TAB> finds
# projects/synthomaha), with a directory preview for cd. The leading '' tries an
# exact-case match first so --d<TAB> doesn't get case-folded to --dR.
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._/-]=* r:|=*'
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -1 --color=always $realpath'
zstyle ':fzf-tab:complete:__zoxide_j:*' fzf-preview 'ls -1 --color=always $realpath'
zstyle ':fzf-tab:*' switch-group '<' '>'

(( $+functions[antidote] )) && antidote load

# brew (macOS) / apt + pinned clone (Linux) plugins. Order matters: autosuggestions
# must come after fzf-tab (loaded by antidote above) and syntax-highlighting must
# be sourced last.
_zfind "$_brew/share/zsh-autosuggestions/zsh-autosuggestions.zsh" /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh && source $REPLY
_zfind "$_brew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh && source $REPLY
unset _brew

# prompt: starship (binary from brew / install.sh), config in ~/.config/starship.toml
# Re-sourcing (sz) makes starship wrap its own zle-keymap-select widget, which then
# calls itself until FUNCNEST. Drop the old widget so init binds a fresh one.
[[ ${widgets[zle-keymap-select]-} == user:starship_* ]] && zle -D zle-keymap-select
_cache_eval starship starship init zsh --print-full-init

# re-prioritize custom completions (e.g. _just) over anything brew shellenv/antidote
# prepended to fpath above, since zsh autoloads from whichever fpath dir it finds
# first (typeset -U keeps this first copy and drops the later duplicate)
fpath=( "$HOME/.zsh/completions" $fpath )

[[ -r "$HOME/.turso/env" ]] && . "$HOME/.turso/env"

# PATH order: user-writable tool dirs go after the system dirs (see .zshenv). Again
# here because the rustup/turso env files and mise activate above prepend.
(( $+functions[_path_user_dirs_last] )) && _path_user_dirs_last
