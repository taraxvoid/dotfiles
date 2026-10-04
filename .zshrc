# Cross-platform (macOS + Debian/Ubuntu/ChromeOS Crostini): detect what exists
# instead of branching on OS. Every macOS path below is still tried first.
source "${ZDOTDIR:-$HOME}/.zsh_aliases"

# colima (macOS) exposes docker on a per-user socket; only point at it if present
[[ -S "$HOME/.colima/default/docker.sock" ]] && export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"

# helper: set REPLY to the first readable candidate path (macOS brew paths come
# first, then Linux package/clone locations)
_zfind() { local f; for f in "$@"; do [[ -r $f ]] && { REPLY=$f; return 0 } done; return 1 }
_brew=${HOMEBREW_PREFIX:-/opt/homebrew}

# HISTFILE is only preset by macOS's /etc/zshrc, not on Debian/Ubuntu
: ${HISTFILE:=$HOME/.zsh_history}

# dedupe PATH entries (zsh ties $path to $PATH)
typeset -U path PATH

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

fpath=( "$HOME/.zsh/completions" $fpath )

# full compinit (with its slow security audit) at most once a day; otherwise
# trust the cached ~/.zcompdump with -C. Delete ~/.zcompdump to force a rebuild
# after adding completions.
autoload -Uz compinit
if [[ -n ${HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

# This forces word navigation/deletion to respect slashes, periods, etc.
autoload -U select-word-style
select-word-style bash

(( $+commands[mise] )) && eval "$(mise activate zsh)"

# zoxide: `j <part of dir>` jumps to the best frecent match, `ji` is an fzf picker
(( $+commands[zoxide] )) && eval "$(zoxide init zsh --cmd j)"

# fzf defaults: fd respects .gitignore and is much faster than find.
# Debian/Ubuntu ship fd as `fdfind` and bat as `batcat`; fzf runs these strings in
# a subshell where aliases don't exist, so resolve the real binary names here.
_fd=${${commands[fd]:+fd}:-${commands[fdfind]:+fdfind}}
_bat=${${commands[bat]:+bat}:-${commands[batcat]:+batcat}}
if [[ -n $_fd ]]; then
  export FZF_DEFAULT_COMMAND="$_fd --type f --hidden --follow --exclude .git"
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND="$_fd --type d --hidden --follow --exclude .git"
fi
[[ -n $_bat ]] && export FZF_CTRL_T_OPTS="--preview '$_bat --color=always --style=numbers --line-range=:200 {}'"
(( $+commands[eza] )) && export FZF_ALT_C_OPTS="--preview 'eza --tree --level=1 --color=always {}'"
if (( $+commands[fzf] )); then
  if fzf --zsh &>/dev/null; then
    source <(fzf --zsh)
  else
    # fzf < 0.48 (older Ubuntu/Debian) has no --zsh; use the packaged scripts
    for f in /usr/share/doc/fzf/examples/{key-bindings,completion}.zsh(N); do source $f; done
    unset f
  fi
fi
command -v flux >/dev/null && . <(flux completion zsh)
# just completion: recipe names only, see ~/.zsh/completions/_just

# Order of elements shown on the prompt line
SPACESHIP_PROMPT_ORDER=(
  dir           # Current directory
  git           # Git status (branch, delivery status)
  char          # Prompt character (usually ➜)
)

# load antidote (zsh plugins): brew on macOS, pinned clone from install.sh on Linux
_zfind "$_brew/opt/antidote/share/antidote/antidote.zsh" "$HOME/.zsh/antidote/antidote.zsh" && source $REPLY

# Bind Up and Down arrow keys for Fish-like history searching. Terminals in
# application mode (Crostini, ghostty, tmux) send ^[OA/^[OB instead of ^[[A/^[[B.
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
[[ -n $terminfo[kcuu1] ]] && bindkey "$terminfo[kcuu1]" history-substring-search-up
[[ -n $terminfo[kcud1] ]] && bindkey "$terminfo[kcud1]" history-substring-search-down

# fzf-tab: case-insensitive + partial-path matching (e.g. proj/syn<TAB> finds
# projects/synthomaha), with a directory preview for cd
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._/-]=* r:|=*'
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -1 --color=always $realpath'
zstyle ':fzf-tab:complete:__zoxide_j:*' fzf-preview 'ls -1 --color=always $realpath'
zstyle ':fzf-tab:*' switch-group '<' '>'

(( $+functions[antidote] )) && antidote load

# brew (macOS) / apt + pinned clone (Linux) plugins. Order matters: autosuggestions
# must come after fzf-tab (loaded by antidote above) and syntax-highlighting must
# be sourced last.
_zfind "$_brew/opt/spaceship/spaceship.zsh" "$HOME/.zsh/spaceship/spaceship.zsh" && source $REPLY
_zfind "$_brew/share/zsh-autosuggestions/zsh-autosuggestions.zsh" /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh && source $REPLY
_zfind "$_brew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh && source $REPLY
unset _brew

# sentry
fpath=("$HOME/.local/share/zsh/site-functions" $fpath)

# re-prioritize custom completions (e.g. _just) over anything brew shellenv/antidote
# prepended to fpath above, since zsh autoloads from whichever fpath dir it finds first
fpath=( "$HOME/.zsh/completions" $fpath )

[[ -r "$HOME/.turso/env" ]] && . "$HOME/.turso/env"

# PATH order: user-writable tool dirs go after the system dirs so a package that
# drops a fake `git` or `ls` into one of them can't shadow the real binary.
# (Runs after the rustup/turso env files above, which prepend their own dirs.)
() {
  local -a user_dirs=("$HOME/.local/bin" "$HOME/.bun/bin" "$HOME/.cargo/bin" "$HOME/.turso")
  path=(${path:|user_dirs} $user_dirs)
}
#compdef cf
compdef _cf cf

# zsh completion for cf -*- shell-script -*-

__cf_debug() {
    local file="$BASH_COMP_DEBUG_FILE"
    if [[ -n ${file} ]]; then
        echo "$*" >> "${file}"
    fi
}

_cf() {
    local shellCompDirectiveError=1
    local shellCompDirectiveNoSpace=2
    local shellCompDirectiveNoFileComp=4
    local shellCompDirectiveFilterFileExt=8
    local shellCompDirectiveFilterDirs=16
    local shellCompDirectiveKeepOrder=32

    local lastParam lastChar flagPrefix requestComp out directive comp lastComp noSpace keepOrder
    local -a completions

    __cf_debug "\n========= starting completion logic =========="
    __cf_debug "CURRENT: ${CURRENT}, words[*]: ${words[*]}"

    # The user could have moved the cursor backwards on the command-line.
    # We need to trigger completion from the $CURRENT location, so we need
    # to truncate the command-line ($words) up to the $CURRENT location.
    # (We cannot use $CURSOR as its value does not work when a command is an alias.)
    words=( "${=words[1,CURRENT]}" )
    __cf_debug "Truncated words[*]: ${words[*]},"

    lastParam=${words[-1]}
    lastChar=${lastParam[-1]}
    __cf_debug "lastParam: ${lastParam}, lastChar: ${lastChar}"

    # For zsh, when completing a flag with an = (e.g., cf -n=<TAB>)
    # completions must be prefixed with the flag
    setopt local_options BASH_REMATCH
    if [[ "${lastParam}" =~ '-.*=' ]]; then
        # We are dealing with a flag with an =
        flagPrefix="-P ${BASH_REMATCH}"
    fi

    # Prepare the command to obtain completions, ensuring arguments are quoted for eval
    local -a args_to_quote=("${(@)words[2,-1]}")
    if [ "${lastChar}" = "" ]; then
        # If the last parameter is complete (there is a space following it)
        # We add an extra empty parameter so we can indicate this to the go completion code.
        __cf_debug "Adding extra empty parameter"
        args_to_quote+=("")
    fi

    # Use Zsh's (q) flag to quote each argument safely for eval
    local quoted_args=("${(@q)args_to_quote}")

    # Join the main command and the quoted arguments into a single string for eval
    requestComp="cf complete -- ${quoted_args[*]}"

    __cf_debug "About to call: eval ${requestComp}"

    # Use eval to handle any environment variables and such
    out=$(eval ${requestComp} 2>/dev/null)
    __cf_debug "completion output: ${out}"

    # Extract the directive integer following a : from the last line
    local lastLine
    while IFS='
' read -r line; do
        lastLine=${line}
    done < <(printf "%s
" "${out[@]}")
    __cf_debug "last line: ${lastLine}"

    if [ "${lastLine[1]}" = : ]; then
        directive=${lastLine[2,-1]}
        # Remove the directive including the : and the newline
        local suffix
        (( suffix=${#lastLine}+2))
        out=${out[1,-$suffix]}
    else
        # There is no directive specified.  Leave $out as is.
        __cf_debug "No directive found.  Setting to default"
        directive=0
    fi

    __cf_debug "directive: ${directive}"
    __cf_debug "completions: ${out}"
    __cf_debug "flagPrefix: ${flagPrefix}"

    if [ $((directive & shellCompDirectiveError)) -ne 0 ]; then
        __cf_debug "Completion received error. Ignoring completions."
        return
    fi

    local activeHelpMarker="%"
    local endIndex=${#activeHelpMarker}
    local startIndex=$((${#activeHelpMarker}+1))
    local hasActiveHelp=0
    while IFS='
' read -r comp; do
        # Check if this is an activeHelp statement (i.e., prefixed with $activeHelpMarker)
        if [ "${comp[1,$endIndex]}" = "$activeHelpMarker" ];then
            __cf_debug "ActiveHelp found: $comp"
            comp="${comp[$startIndex,-1]}"
            if [ -n "$comp" ]; then
                compadd -x "${comp}"
                __cf_debug "ActiveHelp will need delimiter"
                hasActiveHelp=1
            fi
            continue
        fi

        if [ -n "$comp" ]; then
            # If requested, completions are returned with a description.
            # The description is preceded by a TAB character.
            # For zsh's _describe, we need to use a : instead of a TAB.
            # We first need to escape any : as part of the completion itself.
            comp=${comp//:/\:}

            local tab="$(printf '\t')"
            comp=${comp//$tab/:}

            __cf_debug "Adding completion: ${comp}"
            completions+=${comp}
            lastComp=$comp
        fi
    done < <(printf "%s
" "${out[@]}")

    # Add a delimiter after the activeHelp statements, but only if:
    # - there are completions following the activeHelp statements, or
    # - file completion will be performed (so there will be choices after the activeHelp)
    if [ $hasActiveHelp -eq 1 ]; then
        if [ ${#completions} -ne 0 ] || [ $((directive & shellCompDirectiveNoFileComp)) -eq 0 ]; then
            __cf_debug "Adding activeHelp delimiter"
            compadd -x "--"
            hasActiveHelp=0
        fi
    fi

    if [ $((directive & shellCompDirectiveNoSpace)) -ne 0 ]; then
        __cf_debug "Activating nospace."
        noSpace="-S ''"
    fi

    if [ $((directive & shellCompDirectiveKeepOrder)) -ne 0 ]; then
        __cf_debug "Activating keep order."
        keepOrder="-V"
    fi

    if [ $((directive & shellCompDirectiveFilterFileExt)) -ne 0 ]; then
        # File extension filtering
        local filteringCmd
        filteringCmd='_files'
        for filter in ${completions[@]}; do
            if [ ${filter[1]} != '*' ]; then
                # zsh requires a glob pattern to do file filtering
                filter="\*.$filter"
            fi
            filteringCmd+=" -g $filter"
        done
        filteringCmd+=" ${flagPrefix}"

        __cf_debug "File filtering command: $filteringCmd"
        _arguments '*:filename:'"$filteringCmd"
    elif [ $((directive & shellCompDirectiveFilterDirs)) -ne 0 ]; then
        # File completion for directories only
        local subdir
        subdir="${completions[1]}"
        if [ -n "$subdir" ]; then
            __cf_debug "Listing directories in $subdir"
            pushd "${subdir}" >/dev/null 2>&1
        else
            __cf_debug "Listing directories in ."
        fi

        local result
        _arguments '*:dirname:_files -/'" ${flagPrefix}"
        result=$?
        if [ -n "$subdir" ]; then
            popd >/dev/null 2>&1
        fi
        return $result
    else
        __cf_debug "Calling _describe"
        if eval _describe $keepOrder "completions" completions -Q ${flagPrefix} ${noSpace}; then
            __cf_debug "_describe found some completions"

            # Return the success of having called _describe
            return 0
        else
            __cf_debug "_describe did not find completions."
            __cf_debug "Checking if we should do file completion."
            if [ $((directive & shellCompDirectiveNoFileComp)) -ne 0 ]; then
                __cf_debug "deactivating file completion"

                # Return 0 to indicate completion is finished and prevent zsh from
                # trying other completion algorithms (which could cause hanging).
                # We use NoFileComp directive to explicitly disable file completion.
                return 0
            else
                # Perform file completion
                __cf_debug "Activating file completion"

                # We must return the result of this command, so it must be the
                # last command, or else we must store its result to return it.
                _arguments '*:filename:_files'" ${flagPrefix}"
            fi
        fi
    fi
}

# don't run the completion function when being sourced or eval-ed
if [ "${funcstack[1]}" = "_cf" ]; then
    _cf
fi

