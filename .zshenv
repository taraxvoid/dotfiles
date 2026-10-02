# Non-secret environment only. Secrets live in Dashlane (see `dx` in ~/.zsh_aliases
# and ~/.config/dashlane/*.env); never put API keys or tokens in this file,
# since every process (including package install scripts) inherits it.

# telemetry off
export ORI_TELEMETRY=0
export DO_NOT_TRACK=1

. $HOME/.cargo/env
