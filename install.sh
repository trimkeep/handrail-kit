#!/usr/bin/env bash
# install.sh — install the Handrail hook pack into a target project.
#
# Usage: ./install.sh <path-to-target-project>
#
# Copies hooks/*.sh into <target>/.claude/hooks/handrail/, chmod +x's them,
# and merges the Handrail hooks block into <target>/.claude/settings.json
# (creating the file if it is absent, preserving every existing entry,
# backing up any existing settings.json to
# .claude/settings.json.bak-<timestamp> first). Idempotent: running it again
# makes no further changes. Fails closed: aborts on the first error and
# never leaves a half-written settings.json — all writes happen to a temp
# file that is only moved into place after it validates as JSON.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "handrail install: $1" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required"
[ $# -eq 1 ] || die "usage: ./install.sh <path-to-target-project>"

TARGET="$1"
[ -d "$TARGET" ] || die "target directory does not exist: $TARGET"
[ -d "$SCRIPT_DIR/hooks" ] || die "hooks/ not found next to install.sh"

CLAUDE_DIR="$TARGET/.claude"
HOOKS_DEST="$CLAUDE_DIR/hooks/handrail"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$HOOKS_DEST"
for f in "$SCRIPT_DIR"/hooks/*.sh; do
  cp "$f" "$HOOKS_DEST/"
done
chmod +x "$HOOKS_DEST"/*.sh
echo "handrail install: copied $(ls "$SCRIPT_DIR"/hooks/*.sh | wc -l | tr -d ' ') hook scripts to $HOOKS_DEST"

handrail_block=$(jq '.hooks.PreToolUse' "$SCRIPT_DIR/settings.example.json") \
  || die "could not read settings.example.json"

if [ -f "$SETTINGS" ]; then
  jq -e . "$SETTINGS" >/dev/null 2>&1 || die "existing settings.json is not valid JSON, aborting"
  existing=$(cat "$SETTINGS")
else
  existing='{}'
fi

merged=$(jq --argjson handrail "$handrail_block" '
  .hooks = (.hooks // {}) |
  .hooks.PreToolUse = (.hooks.PreToolUse // []) |
  reduce $handrail[] as $hg (.;
    ((.hooks.PreToolUse | map(.matcher) | index($hg.matcher))) as $idx |
    if $idx == null then
      .hooks.PreToolUse += [$hg]
    else
      .hooks.PreToolUse[$idx].hooks = (
        (.hooks.PreToolUse[$idx].hooks // []) as $existing2 |
        $existing2 + ($hg.hooks | map(select(. as $h | ($existing2 | map(.command) | index($h.command)) == null)))
      )
    end
  )
' <<<"$existing") || die "failed to merge hooks block"

jq -e . >/dev/null 2>&1 <<<"$merged" || die "merged settings failed JSON validation, aborting without writing"

if [ -f "$SETTINGS" ] && diff -q <(jq -S . "$SETTINGS") <(jq -S . <<<"$merged") >/dev/null 2>&1; then
  echo "handrail install: $SETTINGS already has the Handrail hooks, nothing to change"
  exit 0
fi

mkdir -p "$CLAUDE_DIR"
if [ -f "$SETTINGS" ]; then
  backup="$CLAUDE_DIR/settings.json.bak-$(date +%Y%m%dT%H%M%S)"
  cp "$SETTINGS" "$backup" || die "could not create backup, aborting"
  echo "handrail install: backed up existing settings.json to $backup"
fi

tmpfile="$CLAUDE_DIR/.settings.json.handrail-tmp.$$"
printf '%s\n' "$merged" | jq . > "$tmpfile" || die "failed to write temp settings file"
jq -e . "$tmpfile" >/dev/null 2>&1 || { rm -f "$tmpfile"; die "temp settings file failed validation, aborting"; }
mv "$tmpfile" "$SETTINGS" || die "failed to move temp settings file into place"

echo "handrail install: wrote $SETTINGS with all Handrail hooks wired"
