#!/usr/bin/env bash
# publish-guard.sh
# Asks for confirmation before any Bash command that publishes/releases
# something externally: npm publish, pip upload/twine upload, cargo
# publish, gem push, docker push, gh release create, wrangler deploy,
# vercel --prod, firebase deploy. Denies "npm publish --access public"
# outright unless HANDRAIL_ALLOW_PUBLISH=1 is set in the environment. Fails
# closed on any error, missing jq, or unparsable/empty input. Only ever
# denies or asks; never prints an "allow" decision.
set -euo pipefail

deny() { echo "handrail publish-guard: $1" >&2; exit 2; }
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

if grep -qE '(^|[^A-Za-z0-9_])npm([^A-Za-z0-9_].*)?[[:space:]]publish([[:space:]]|$)' <<<"$cmd"; then
  if grep -qE -- '--access[[:space:]]+public' <<<"$cmd" && [ "${HANDRAIL_ALLOW_PUBLISH:-}" != "1" ]; then
    deny "npm publish --access public requires HANDRAIL_ALLOW_PUBLISH=1"
  fi
  ask "npm publish releases a package publicly"
fi

grep -qiE '(^|[^A-Za-z0-9_])(pip[0-9]?[[:space:]]+.*upload|twine[[:space:]]+upload)([[:space:]]|$)' <<<"$cmd" && ask "pip/twine upload releases a package publicly"
grep -qE '(^|[^A-Za-z0-9_])cargo([^A-Za-z0-9_].*)?[[:space:]]publish([[:space:]]|$)' <<<"$cmd" && ask "cargo publish releases a crate publicly"
grep -qE '(^|[^A-Za-z0-9_])gem([^A-Za-z0-9_].*)?[[:space:]]push([[:space:]]|$)' <<<"$cmd" && ask "gem push releases a gem publicly"
grep -qE '(^|[^A-Za-z0-9_])docker([^A-Za-z0-9_].*)?[[:space:]]push([[:space:]]|$)' <<<"$cmd" && ask "docker push publishes an image"
grep -qE '(^|[^A-Za-z0-9_])gh([^A-Za-z0-9_].*)?[[:space:]]release[[:space:]]+create([[:space:]]|$)' <<<"$cmd" && ask "gh release create publishes a release"
grep -qE '(^|[^A-Za-z0-9_])wrangler([^A-Za-z0-9_].*)?[[:space:]]deploy([[:space:]]|$)' <<<"$cmd" && ask "wrangler deploy ships to production"
grep -qE '(^|[^A-Za-z0-9_])vercel([^A-Za-z0-9_].*)?[[:space:]]--prod([[:space:]]|$)' <<<"$cmd" && ask "vercel --prod ships to production"
grep -qE '(^|[^A-Za-z0-9_])firebase([^A-Za-z0-9_].*)?[[:space:]]deploy([[:space:]]|$)' <<<"$cmd" && ask "firebase deploy ships to production"

exit 0
