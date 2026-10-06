# Non-secret environment only. 
# NEVER put API keys or tokens in this file,
# since every process (including package install scripts) inherits it.

# telemetry off
export ORI_TELEMETRY=0
export DO_NOT_TRACK=1

# rustup/cargo (cargo/env is idempotent; interactive shells re-order it in .zshrc)
[[ -r "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# mise shims so non-interactive shells (scripts, tool runners) find mise-managed tools;
# interactive shells get the full `mise activate` in .zshrc, which takes precedence
[[ -x "$HOME/.local/bin/mise" ]] && eval "$("$HOME/.local/bin/mise" activate zsh --shims)"
