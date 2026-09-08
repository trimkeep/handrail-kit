#!/usr/bin/env bash
# prod-guard.sh
# Asks for confirmation on any Bash command that touches production: a
# PROD/PRODUCTION-valued env var (NODE_ENV=production, RAILS_ENV=production,
# ENV=prod, ...), kubectl/terraform apply, a --prod/--production flag, or a
# migration run against a URL containing "prod". Denies terraform destroy
# and kubectl delete namespace outright. Fails closed on any error, missing
# jq, or unparsable/empty input. Only ever denies or asks; never prints an
# "allow" decision.
set -euo pipefail

deny() { echo "handrail prod-guard: $1" >&2; exit 2; }
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

if grep -qiE '(^|[^A-Za-z0-9_])terraform([^A-Za-z0-9_].*)?[[:space:]]destroy([[:space:]]|$)' <<<"$cmd"; then
  deny "terraform destroy is blocked"
fi
if grep -qiE '(^|[^A-Za-z0-9_])kubectl([^A-Za-z0-9_].*)?[[:space:]]delete[[:space:]]+namespace([[:space:]]|$)' <<<"$cmd"; then
  deny "kubectl delete namespace is blocked"
fi

if grep -qiE '(^|[^A-Za-z0-9_])(NODE_ENV|RAILS_ENV|APP_ENV|ENV|DJANGO_SETTINGS_MODULE|STAGE)=["'"'"']?(production|prod)["'"'"']?([^A-Za-z0-9_]|$)' <<<"$cmd"; then
  ask "command sets a production environment variable"
fi
if grep -qiE '(^|[^A-Za-z0-9_])(kubectl|terraform)([^A-Za-z0-9_].*)?[[:space:]]apply([[:space:]]|$)' <<<"$cmd"; then
  ask "kubectl/terraform apply can change production infrastructure"
fi
if grep -qE -- '--prod([^A-Za-z0-9_-]|$)|--production([^A-Za-z0-9_-]|$)' <<<"$cmd"; then
  ask "command passes --prod/--production"
fi
if grep -qiE '(migrat[a-z]*)' <<<"$cmd" && grep -qiE '(^|[^A-Za-z0-9_.-])[a-z]+://[^[:space:]]*prod[^[:space:]]*' <<<"$cmd"; then
  ask "migration appears to target a production URL"
fi

exit 0
