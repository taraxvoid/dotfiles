# Merge the shared settings ($shared) into a local ~/.claude/settings.json (.).
# Run: jq --slurpfile shared settings.shared.json --arg home "$HOME" -f settings-merge.jq
#
# - "@HOME@" in shared strings becomes $home (permission rules match literally).
# - Hooks: a local hook entry that runs any command the shared file also runs is
#   dropped, then the shared entries are appended, so edits to a shared hook
#   (matcher, timeout, `if`) replace the old copy instead of duplicating it.
# - Arrays elsewhere (permissions.allow/deny/ask, ...) are unioned, local first.
# - Objects merge recursively; for scalars the shared value wins.
# Idempotent: merging the result again changes nothing.

def subst: walk(if type == "string" then gsub("@HOME@"; $home) else . end);

def merge($a; $b):
  if ($a | type) == "object" and ($b | type) == "object" then
    reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = merge($a[$k]; $b[$k]))
  elif ($a | type) == "array" and ($b | type) == "array" then
    $a + [$b[] | select(. as $x | any($a[]; . == $x) | not)]
  elif $b == null then $a
  else $b
  end;

($shared[0] | subst) as $s
| [$s.hooks // {} | .[][] | .hooks[].command] as $cmds
| .hooks = ((.hooks // {}) | with_entries(
    .value |= map(select(any(.hooks[]?; .command as $c | any($cmds[]; . == $c)) | not))
  ))
| merge(.; $s)
| .hooks |= with_entries(select(.value != []))
