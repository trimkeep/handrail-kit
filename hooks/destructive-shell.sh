#!/usr/bin/env bash
# destructive-shell.sh
# Blocks destructive shell commands passed to the Bash tool: rm -rf/-fr in
# any flag order (bare, chained with &&/;/|, inside subshells, or sudo
# -prefixed), mkfs, dd writing to a block device, shred, redirecting into
# /dev/sd*, chmod -R 777 /, and the classic fork bomb. Fails closed on any
# error, missing jq, or unparsable/empty input. Only ever denies; never
# prints an "allow" decision.
set -euo pipefail

deny() { echo "handrail destructive-shell: $1" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || deny "jq is required"

input=$(cat) || deny "could not read stdin"
[ -n "$input" ] || deny "empty stdin"
jq -e . >/dev/null 2>&1 <<<"$input" || deny "stdin is not valid JSON"

tool_name=$(jq -r '.tool_name // empty' <<<"$input") || deny "jq failed"
[ "$tool_name" = "Bash" ] || exit 0

cmd=$(jq -r '.tool_input.command // empty' <<<"$input") || deny "jq failed"
[ -n "$cmd" ] || deny "Bash call with no command"

# "rm" as a whole word anywhere in the command (subshells/chains/sudo do not
# hide it, since we search the raw text, not a parsed AST).
has_rm=0
grep -qE '(^|[^A-Za-z0-9_])rm([^A-Za-z0-9_]|$)' <<<"$cmd" && has_rm=1
# a combined short flag containing both r and f (-rf, -fr, -Rf, -vrf, ...),
# or the long forms, or -r/-R and -f as separate tokens.
has_combo=0
grep -qE -- '(^|[[:space:]])-[A-Za-z]*[rR][A-Za-z]*f[A-Za-z]*([[:space:]]|$)|(^|[[:space:]])-[A-Za-z]*f[A-Za-z]*[rR][A-Za-z]*([[:space:]]|$)' <<<"$cmd" && has_combo=1
has_r=0
grep -qE -- '(^|[[:space:]])-[A-Za-z]*[rR][A-Za-z]*([[:space:]]|$)|--recursive([[:space:]]|$)' <<<"$cmd" && has_r=1
has_f=0
grep -qE -- '(^|[[:space:]])-[A-Za-z]*f[A-Za-z]*([[:space:]]|$)|--force([[:space:]]|$)' <<<"$cmd" && has_f=1

if [ "$has_rm" = 1 ] && { [ "$has_combo" = 1 ] || { [ "$has_r" = 1 ] && [ "$has_f" = 1 ]; }; }; then
  deny "rm -rf/-fr style recursive-force delete is blocked"
fi

grep -qiE '(^|[^A-Za-z0-9_])mkfs(\.[A-Za-z0-9]+)?([^A-Za-z0-9_]|$)' <<<"$cmd" && deny "mkfs is blocked"
grep -qiE '(^|[^A-Za-z0-9_])dd([^A-Za-z0-9_].*)?[[:space:]]of=/dev/' <<<"$cmd" && deny "dd writing to a device is blocked"
grep -qiE '(^|[^A-Za-z0-9_])shred([^A-Za-z0-9_]|$)' <<<"$cmd" && deny "shred is blocked"
grep -qE '>[[:space:]]*/dev/sd[a-z0-9]*' <<<"$cmd" && deny "redirecting into /dev/sd* is blocked"
grep -qE 'chmod[[:space:]]+(-R|--recursive)[[:space:]]+[0-7]*777[[:space:]]+/([[:space:]]|$)' <<<"$cmd" && deny "chmod -R 777 / is blocked"
grep -qE ':\(\)[[:space:]]*\{[[:space:]]*:\|:&[[:space:]]*\};[[:space:]]*:' <<<"$cmd" && deny "fork bomb pattern is blocked"

exit 0
