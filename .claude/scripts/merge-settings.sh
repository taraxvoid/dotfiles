#!/usr/bin/env bash
# merge-settings.sh <fragment.json> <settings.json>
# Merge a tracked settings fragment into a machine's Claude settings.json:
# statusLine is replaced, sandbox.enabled is set and its allowlists (write dirs and
# their denied subdirs, domains, credential files by path, env vars by name) are unioned with what is
# there (existing entries win), each hook entry is appended to its event unless one of
# its commands is already registered there, permissions.deny rules missing from
# settings are appended, and every other key is left alone.
# Backs settings.json up to settings.json.bak.<timestamp> before changing it and
# does nothing when it is already up to date, so re-running is safe.
set -euo pipefail

frag=$1 settings=$2
[ -f "$settings" ] || echo '{}' >"$settings"

new=$(jq --slurpfile f "$frag" '
  $f[0] as $frag
  | (if $frag.statusLine then .statusLine = $frag.statusLine else . end)
  | (if $frag.sandbox then
      def merge($have; $add; f): (($have // []) + [$add[]? | select(. as $x | ($have // []) | all(f != ($x | f)))]);
      .sandbox.enabled = true
      | .sandbox.filesystem.allowWrite = merge(.sandbox.filesystem.allowWrite; $frag.sandbox.filesystem.allowWrite; .)
      | .sandbox.filesystem.denyWrite = merge(.sandbox.filesystem.denyWrite; $frag.sandbox.filesystem.denyWrite; .)
      | .sandbox.network.allowedDomains = merge(.sandbox.network.allowedDomains; $frag.sandbox.network.allowedDomains; .)
      | .sandbox.credentials.files = merge(.sandbox.credentials.files; $frag.sandbox.credentials.files; .path)
      | .sandbox.credentials.envVars = merge(.sandbox.credentials.envVars; $frag.sandbox.credentials.envVars; .name)
    else . end)
  | (if $frag.permissions.deny then .permissions.deny = (reduce $frag.permissions.deny[] as $d
      (.permissions.deny // []; if any(.[]; . == $d) then . else . + [$d] end)) else . end)
  | .hooks = (reduce (($frag.hooks // {}) | to_entries[]) as $e (.hooks // {};
      ([.[$e.key][]?.hooks[]?.command]) as $have
      | .[$e.key] = ((.[$e.key] // []) + [$e.value[]
          | select(all(.hooks[].command; . as $c | ($have | any(.[]; . == $c)) | not))])))
' "$settings")

if [ "$(jq -S . "$settings")" = "$(jq -S . <<<"$new")" ]; then
  echo "$settings already up to date"
  exit 0
fi
cp "$settings" "$settings.bak.$(date +%Y%m%d%H%M%S)"
printf '%s\n' "$new" >"$settings.tmp"
mv "$settings.tmp" "$settings"
echo "merged $frag into $settings"
