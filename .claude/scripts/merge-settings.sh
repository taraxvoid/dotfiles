#!/usr/bin/env bash
# merge-settings.sh <fragment.json> <settings.json>
# Merge a tracked settings fragment into a machine's Claude settings.json:
# statusLine is replaced, sandbox.enabled is set (plus allowUnsandboxedCommands=false
# when the fragment asks for strict mode, allowLocalBinding=true when it asks for local
# servers, enableWeakerNetworkIsolation=true when it asks for trustd) and its
# allowlists (excluded commands, write dirs and
# their denied subdirs, domains, credential files by path, env vars by name) are unioned with what is
# there (existing entries win), each hook entry is appended to its event unless one of
# its commands is already registered there (that hook then takes the fragment
# hook's fields, such as a new timeout), permissions.allow, permissions.deny and permissions.ask rules
# missing from settings are appended, the fragment's obsolete.excludedCommands and
# obsolete.allowWrite entries (once added, now unsafe) are removed, and every other
# key is left alone.
# Backs settings.json up to settings.json.bak.<timestamp> before changing it and
# does nothing when it is already up to date, so re-running is safe.
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: ${0##*/} <fragment.json> <settings.json>" >&2; exit 2; }
frag=$1 settings=$2
[ -f "$settings" ] || echo '{}' >"$settings"

new=$(jq --slurpfile f "$frag" '
  $f[0] as $frag
  | (if $frag.statusLine then .statusLine = $frag.statusLine else . end)
  | (if $frag.sandbox then
      def merge($have; $add; f): (($have // []) + [$add[]? | select(. as $x | ($have // []) | all(f != ($x | f)))]);
      .sandbox.enabled = true
      | (if $frag.sandbox.network.allowLocalBinding == true then .sandbox.network.allowLocalBinding = true else . end)
      | (if $frag.sandbox.allowUnsandboxedCommands == false then .sandbox.allowUnsandboxedCommands = false else . end)
      | (if $frag.sandbox.enableWeakerNetworkIsolation == true then .sandbox.enableWeakerNetworkIsolation = true else . end)
      | .sandbox.excludedCommands = merge(.sandbox.excludedCommands; $frag.sandbox.excludedCommands; .)
      | .sandbox.filesystem.allowWrite = merge(.sandbox.filesystem.allowWrite; $frag.sandbox.filesystem.allowWrite; .)
      | .sandbox.filesystem.denyWrite = merge(.sandbox.filesystem.denyWrite; $frag.sandbox.filesystem.denyWrite; .)
      | .sandbox.network.allowedDomains = merge(.sandbox.network.allowedDomains; $frag.sandbox.network.allowedDomains; .)
      | .sandbox.credentials.files = merge(.sandbox.credentials.files; $frag.sandbox.credentials.files; .path)
      | .sandbox.credentials.envVars = merge(.sandbox.credentials.envVars; $frag.sandbox.credentials.envVars; .name)
    else . end)
  # entries an earlier fragment added that are now unsafe; dropped wherever they are
  | (if $frag.obsolete.excludedCommands and .sandbox.excludedCommands then
      .sandbox.excludedCommands -= $frag.obsolete.excludedCommands else . end)
  | (if $frag.obsolete.allowWrite and .sandbox.filesystem.allowWrite then
      .sandbox.filesystem.allowWrite -= $frag.obsolete.allowWrite else . end)
  | reduce ("allow", "deny", "ask") as $k (.; if $frag.permissions[$k] then .permissions[$k] = (reduce $frag.permissions[$k][] as $d
      (.permissions[$k] // []; if any(.[]; . == $d) then . else . + [$d] end)) else . end)
  | .hooks = (reduce (($frag.hooks // {}) | to_entries[]) as $e (.hooks // {};
      # a hook already registered under the same command takes the fragment'"'"'s
      # fields (if, timeout), so a changed timeout reaches machines merged before
      # (keyed by matcher and command: one script can be registered twice, under
      # Edit|Write and under Bash with an `if`)
      ([$e.value[] | (.matcher // "") as $m | .hooks[] | {key: ($m + " " + .command), value: .}]
        | from_entries) as $fh
      | (if .[$e.key] then .[$e.key] |= map((.matcher // "") as $m | if .hooks then .hooks |= map(
          if (.command | type) == "string" and $fh[$m + " " + .command] then . + $fh[$m + " " + .command]
          else . end) else . end)
        else . end)
      | ([.[$e.key][]?.hooks[]?.command]) as $have
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
