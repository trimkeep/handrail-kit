#!/usr/bin/env bash
# remote-exec.sh
# Denies piping a remote download straight into an interpreter: curl|bash,
# wget|sh, bash <(curl ...), python -c "$(curl ...)", eval "$(curl ...)",
# and npx/pnpm dlx of a package pulled from a bare URL instead of a
# registry. Asks before "npx <pkg>" (or pnpm dlx) when the package is not
# pinned to an explicit @version. Fails closed on any error, missing jq, or
# unparsable/empty input. Only ever denies or asks; never prints an "allow".
set -euo pipefail

deny() { echo "handrail remote-exec: $1" >&2; exit 2; }
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

if grep -qE '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh|python[0-9.]*)([[:space:]]|$)' <<<"$cmd"; then
  deny "piping a remote download into an interpreter is blocked"
fi
if grep -qE '(bash|sh|zsh)[[:space:]]+<\([[:space:]]*(curl|wget)' <<<"$cmd"; then
  deny "running a process-substituted remote download is blocked"
fi
if grep -qE '(python[0-9.]*[[:space:]]+-c|eval)[[:space:]]+"?\$\([[:space:]]*(curl|wget)' <<<"$cmd"; then
  deny "evaluating a remote download's output is blocked"
fi
if grep -qE '(^|[^A-Za-z0-9_])(npx|pnpm[[:space:]]+dlx)([^A-Za-z0-9_].*)?[[:space:]](https?://|git\+)[^[:space:]]+' <<<"$cmd"; then
  deny "npx/dlx of a bare URL instead of a registry package is blocked"
fi

if grep -qE '(^|[^A-Za-z0-9_])npx[[:space:]]+(-y[[:space:]]+|--yes[[:space:]]+)?([A-Za-z0-9@][A-Za-z0-9._/-]*)([[:space:]]|$)' <<<"$cmd"; then
  if ! grep -qE '(^|[^A-Za-z0-9_])npx[[:space:]]+(-y[[:space:]]+|--yes[[:space:]]+)?[A-Za-z0-9@][A-Za-z0-9._/-]*@[A-Za-z0-9.^~-]+([[:space:]]|$)' <<<"$cmd"; then
    ask "npx package is not pinned to an explicit @version"
  fi
fi
if grep -qE '(^|[^A-Za-z0-9_])pnpm[[:space:]]+dlx[[:space:]]+([A-Za-z0-9@][A-Za-z0-9._/-]*)([[:space:]]|$)' <<<"$cmd"; then
  if ! grep -qE '(^|[^A-Za-z0-9_])pnpm[[:space:]]+dlx[[:space:]]+[A-Za-z0-9@][A-Za-z0-9._/-]*@[A-Za-z0-9.^~-]+([[:space:]]|$)' <<<"$cmd"; then
    ask "pnpm dlx package is not pinned to an explicit @version"
  fi
fi

exit 0
