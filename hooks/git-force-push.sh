#!/usr/bin/env bash
# git-force-push.sh
# Denies destructive git history rewrites run via the Bash tool: git push
# --force/-f/--force-with-lease/--mirror/--delete or a "+refspec"; git reset
# --hard; git clean -f; git branch -D on main/master; git checkout -- . .
# Asks for confirmation before any plain push straight to main/master.
# Fails closed on any error, missing jq, or unparsable/empty input. Only
# ever denies or asks; never prints an "allow" decision.
set -euo pipefail

deny() { echo "handrail git-force-push: $1" >&2; exit 2; }
ask() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}

command -v jq >/dev/null 2>&1 || deny "jq is required"

input=$(cat) || deny "could not read stdin"
[ -n "$input" ] || deny "empty stdin"
jq -e . >/dev/null 2>&1 <<<"$input" || deny "stdin is not valid JSON"

tool_name=$(jq -r '.tool_name // empty' <<<"$input") || deny "jq failed"
[ "$tool_name" = "Bash" ] || exit 0

cmd=$(jq -r '.tool_input.command // empty' <<<"$input") || deny "jq failed"
[ -n "$cmd" ] || deny "Bash call with no command"

is_git=0
grep -qE '(^|[^A-Za-z0-9_])git([^A-Za-z0-9_]|$)' <<<"$cmd" && is_git=1
[ "$is_git" = 1 ] || exit 0

if grep -qE '(^|[^A-Za-z0-9_])push([^A-Za-z0-9_]|$)' <<<"$cmd"; then
  if grep -qE -- '--force-with-lease|--force([^-]|$)|(^|[[:space:]])-f([[:space:]]|$)|--mirror([[:space:]]|$)|--delete([[:space:]]|$)|[[:space:]]\+[A-Za-z0-9_./-]+:' <<<"$cmd"; then
    deny "git push with a force/mirror/delete/plus-refspec flag is blocked"
  fi
  if grep -qE '(^|[[:space:]])(main|master)([[:space:]]|$)' <<<"$cmd"; then
    ask "git push targets main/master; confirm before pushing"
  fi
fi

grep -qE '(^|[^A-Za-z0-9_])git[[:space:]].*reset.*--hard' <<<"$cmd" && deny "git reset --hard is blocked"
grep -qE '(^|[^A-Za-z0-9_])git[[:space:]].*clean.*(-[A-Za-z]*f|--force)' <<<"$cmd" && deny "git clean -f is blocked"
grep -qE '(^|[^A-Za-z0-9_])git[[:space:]].*branch.*-D[[:space:]]+(main|master)([[:space:]]|$)' <<<"$cmd" && deny "git branch -D on main/master is blocked"
grep -qE '(^|[^A-Za-z0-9_])git[[:space:]].*checkout[[:space:]]+--[[:space:]]+\.([[:space:]]|$)' <<<"$cmd" && deny "git checkout -- . is blocked"

exit 0
