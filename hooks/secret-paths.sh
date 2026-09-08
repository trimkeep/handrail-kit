#!/usr/bin/env bash
# secret-paths.sh
# Denies reading or writing secret-shaped paths (.env / .env.*, *.pem,
# *.key, id_rsa*/id_ed25519*, any **/secrets/** path, ~/.aws/credentials,
# ~/.ssh/*) whether referenced by a Bash command or targeted by
# Edit/Write/MultiEdit's file_path, and denies writing content that looks
# like a live credential (sk-ant-..., sk_live_..., AKIA..., ghp_/gho_...,
# xai-..., a PEM private-key block). Fails closed on any error, missing jq,
# or unparsable/empty input. Only ever denies; never prints an "allow".
set -euo pipefail

deny() { echo "handrail secret-paths: $1" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || deny "jq is required"

input=$(cat) || deny "could not read stdin"
[ -n "$input" ] || deny "empty stdin"
jq -e . >/dev/null 2>&1 <<<"$input" || deny "stdin is not valid JSON"

tool_name=$(jq -r '.tool_name // empty' <<<"$input") || deny "jq failed"

path_re='(^|[/[:space:]"'"'"'])\.env(\.[A-Za-z0-9_-]+)?([/[:space:]"'"'"']|$)|\.pem([/[:space:]"'"'"']|$)|\.key([/[:space:]"'"'"']|$)|id_rsa[A-Za-z0-9_.-]*|id_ed25519[A-Za-z0-9_.-]*|(^|/)secrets(/|$)|\.aws/credentials|\.ssh/[A-Za-z0-9_.-]+'
content_re='sk-ant-[A-Za-z0-9_-]+|sk_live_[A-Za-z0-9]+|AKIA[A-Z0-9]{8,}|gh[po]_[A-Za-z0-9]+|xai-[A-Za-z0-9_-]+|-----BEGIN[A-Za-z0-9 ]*PRIVATE KEY-----'

case "$tool_name" in
  Bash)
    cmd=$(jq -r '.tool_input.command // empty' <<<"$input") || deny "jq failed"
    [ -n "$cmd" ] || deny "Bash call with no command"
    grep -qE "$path_re" <<<"$cmd" && deny "command references a secret-shaped path"
    grep -qE "$content_re" <<<"$cmd" && deny "command contains a credential-shaped string"
    ;;
  Edit|Write|MultiEdit)
    fp=$(jq -r '.tool_input.file_path // empty' <<<"$input") || deny "jq failed"
    [ -n "$fp" ] || deny "no file_path in tool_input"
    grep -qE "$path_re" <<<"$fp" && deny "file_path is a secret-shaped path"
    content=$(jq -r '[.tool_input.content, .tool_input.new_string, ((.tool_input.edits // []) | map(.new_string // "") | join("\n"))] | map(select(. != null)) | join("\n")' <<<"$input") || deny "jq failed"
    grep -qE "$content_re" <<<"$content" && deny "written content contains a credential-shaped string"
    ;;
  *)
    exit 0
    ;;
esac

exit 0
