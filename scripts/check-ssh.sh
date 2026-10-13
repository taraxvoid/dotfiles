#!/usr/bin/env bash
# Guard for the tracked ssh config. The repo is public and auth config raises the
# stakes of a leak, so this is an allowlist, not a pattern scan (gitleaks does that):
#
#   - .ssh/config is the only file allowed under .ssh/ (no keys, known_hosts, etc.)
#   - no private key or certificate material anywhere in it
#   - only allowlisted directives; anything else (ProxyCommand, LocalCommand,
#     SetEnv, ...) can carry tokens or run commands, so it fails until added
#     here on purpose
#   - IdentityFile/CertificateFile must be a path under ~/.ssh/, never a .pub
#     key or a file inside this repo
#
#   scripts/check-ssh.sh                  check every tracked file under .ssh/ (CI)
#   scripts/check-ssh.sh --staged FILE..  check the staged (index) copies (lefthook)
set -euo pipefail

ALLOWED='host|match|hostname|user|port|include|identityfile|identitiesonly|certificatefile|addkeystoagent|serveraliveinterval|serveralivecountmax|tcpkeepalive|controlmaster|controlpath|controlpersist|forwardagent|stricthostkeychecking|updatehostkeys|hashknownhosts|preferredauthentications|compression|connecttimeout|loglevel'

staged=0
if [ "${1:-}" = --staged ]; then
  staged=1
  shift
fi
cd "$(git rev-parse --show-toplevel)"
if [ $# -eq 0 ]; then
  files=()
  while IFS= read -r f; do files+=("$f"); done < <(git ls-files -- .ssh)
  set -- ${files[@]+"${files[@]}"}
fi

fail=0
err() { printf 'check-ssh: %s\n' "$*" >&2; fail=1; }

content() { # content <path>: staged blob or working-tree file
  if [ "$staged" = 1 ]; then git show ":$1"; else cat -- "$1"; fi
}

for f in "$@"; do
  case $f in
    .ssh/config) ;;
    *) err "$f: only .ssh/config may be committed under .ssh/"; continue ;;
  esac
  # a deletion is staged with no blob; nothing to check
  if [ "$staged" = 1 ] && ! git cat-file -e ":$f" 2>/dev/null; then continue; fi

  body=$(content "$f")
  if grep -qE -- '-----BEGIN [A-Z ]*(PRIVATE KEY|CERTIFICATE)|ssh-(rsa|ed25519|dss)-cert-v01|PuTTY-User-Key-File' <<<"$body"; then
    err "$f: contains key or certificate material"
  fi

  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line=${line%%#*}
    # keyword is separated from its value by whitespace and/or one '='
    read -r kw rest <<<"${line//=/ }" || true
    [ -n "${kw:-}" ] || continue
    lc=$(printf '%s' "$kw" | tr '[:upper:]' '[:lower:]')
    if ! grep -qxE "$ALLOWED" <<<"$lc"; then
      err "$f:$n: directive '$kw' is not allowlisted (edit ALLOWED in $0 if it is safe)"
      continue
    fi
    case $lc in
      identityfile | certificatefile)
        case $rest in
          *.pub) err "$f:$n: $kw must name a private key path, not a .pub file" ;;
          \~/.ssh/*[!/]) ;; # a literal ~ (ssh expands it, this check must not)
          *) err "$f:$n: $kw must be a path under ~/.ssh/ (got '$rest')" ;;
        esac
        ;;
    esac
  done <<<"$body"
done

exit "$fail"
