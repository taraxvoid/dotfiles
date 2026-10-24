# Non-secret environment only. 
# NEVER put API keys or tokens in this file,
# since every process (including package install scripts) inherits it.

# telemetry off
export ORI_TELEMETRY=0
export DO_NOT_TRACK=1

# Claude's Bash sandbox can't write uv's tool dir (~/.local/share/uv/tools), and
# uvx takes a lock and temp file there on every run, even for one-off tools. Point
# it at the writable uv cache instead, so sandboxed tools can't touch the installed
# tool envs that run unsandboxed (the real ones stay on PATH via ~/.local/bin)
[[ -n $SANDBOX_RUNTIME && -z $UV_TOOL_DIR ]] && export UV_TOOL_DIR="${UV_CACHE_DIR:-$HOME/.cache/uv}/tools"

# rustup/cargo (cargo/env is idempotent; it prepends, reordered below)
[[ -r "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# mise shims so non-interactive shells (scripts, tool runners) find mise-managed tools;
# interactive shells get the full `mise activate` in .zshrc, which takes precedence
# mise may come from the vendor installer (~/.local/bin) or brew; .zshrc reuses $_mise_bin
_mise_bin=
for _mise_bin in "$HOME/.local/bin/mise" /opt/homebrew/bin/mise /usr/local/bin/mise /home/linuxbrew/.linuxbrew/bin/mise ""; do
  [[ -x $_mise_bin ]] && break
done
[[ -n $_mise_bin ]] && eval "$("$_mise_bin" activate zsh --shims)"

# PATH order: user-writable tool dirs go after the system dirs so a package that
# drops a fake `git` or `ls` into one of them can't shadow the real binary. mise's
# shims and installs stay first: mise only puts the tools it manages there.
# Applied here for every shell (scripts, Claude's Bash tool) and again at the end
# of .zshrc, after interactive-only setup has prepended more.
_path_user_dirs_last() {
  local -a user_dirs=("$HOME/.local/bin" "$HOME/.bun/bin" "$HOME/.cargo/bin" "$HOME/.turso")
  path=(${path:|user_dirs} $user_dirs)
}
_path_user_dirs_last
