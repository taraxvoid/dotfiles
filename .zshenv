# Non-secret environment only. 
# NEVER put API keys or tokens in this file,
# since every process (including package install scripts) inherits it.

# telemetry off
export ORI_TELEMETRY=0
export DO_NOT_TRACK=1

# rustup/cargo (cargo/env is idempotent; interactive shells re-order it in .zshrc)
[[ -r "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
