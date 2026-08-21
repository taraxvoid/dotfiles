export PATH="$HOME/.local/bin:/Users/kitsune/.bun/bin:$PATH"
export HOMEBREW_NO_ENV_HINTS=1
fpath+=(~/.config/hcloud/completion/zsh)
eval "$(zoxide init zsh)"
source ~/.zsh_aliases
# source antidote
source /opt/homebrew/opt/antidote/share/antidote/antidote.zsh
# fuzzy finder
source <(fzf --zsh)

zstyle ':completion:*' matcher-list 'r:|?=**' 'l:|=* r:|=*'

# initialize plugins statically with ${ZDOTDIR:-$HOME}/.zsh_plugins.txt
antidote load

autoload -Uz compinit && compinit
