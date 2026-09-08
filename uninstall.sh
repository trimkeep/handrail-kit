#!/usr/bin/env bash
# uninstall.sh — remove the Handrail hook pack from a target project.
#
# Usage: ./uninstall.sh <path-to-target-project>
#
# Removes <target>/.claude/hooks/handrail/ and reverses the settings.json
# edit made by install.sh: if a .claude/settings.json.bak-<timestamp> exists
# it restores the newest one verbatim; otherwise it surgically strips only
# the Handrail hook entries out of settings.json with jq, leaving every
# other entry untouched. Fails closed: aborts on the first error and never
# leaves a half-written settings.json.
set -euo pipefail

die() { echo "handrail uninstall: $1" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required"
[ $# -eq 1 ] || die "usage: ./uninstall.sh <path-to-target-project>"

TARGET="$1"
[ -d "$TARGET" ] || die "target directory does not exist: $TARGET"

CLAUDE_DIR="$TARGET/.claude"
HOOKS_DEST="$CLAUDE_DIR/hooks/handrail"
SETTINGS="$CLAUDE_DIR/settings.json"

if [ -d "$HOOKS_DEST" ]; then
  rm -rf "$HOOKS_DEST"
  echo "handrail uninstall: removed $HOOKS_DEST"
else
  echo "handrail uninstall: $HOOKS_DEST not present, nothing to remove there"
fi

latest_backup=""
if compgen -G "$CLAUDE_DIR/settings.json.bak-*" >/dev/null 2>&1; then
  latest_backup=$(ls -1 "$CLAUDE_DIR"/settings.json.bak-* | sort | tail -n1)
fi

if [ -n "$latest_backup" ]; then
  jq -e . "$latest_backup" >/dev/null 2>&1 || die "backup $latest_backup is not valid JSON, aborting"
  tmpfile="$CLAUDE_DIR/.settings.json.handrail-tmp.$$"
  cp "$latest_backup" "$tmpfile" || die "failed to stage restored settings"
  jq -e . "$tmpfile" >/dev/null 2>&1 || { rm -f "$tmpfile"; die "staged settings failed validation, aborting"; }
  mv "$tmpfile" "$SETTINGS" || die "failed to move restored settings into place"
  echo "handrail uninstall: restored $SETTINGS from $latest_backup"
elif [ -f "$SETTINGS" ]; then
  jq -e . "$SETTINGS" >/dev/null 2>&1 || die "existing settings.json is not valid JSON, aborting"
  stripped=$(jq '
    if (.hooks.PreToolUse? // empty) == null then . else
      .hooks.PreToolUse = [
        .hooks.PreToolUse[] |
        .hooks = [ .hooks[] | select(.command | test("/.claude/hooks/handrail/") | not) ] |
        select((.hooks | length) > 0)
      ] |
      (if (.hooks.PreToolUse | length) == 0 then .hooks |= del(.PreToolUse) else . end) |
      (if (.hooks | length) == 0 then del(.hooks) else . end)
    end
  ' "$SETTINGS") || die "failed to strip Handrail hooks from settings.json"
  jq -e . >/dev/null 2>&1 <<<"$stripped" || die "stripped settings failed validation, aborting"
  tmpfile="$CLAUDE_DIR/.settings.json.handrail-tmp.$$"
  printf '%s\n' "$stripped" | jq . > "$tmpfile" || die "failed to write temp settings file"
  jq -e . "$tmpfile" >/dev/null 2>&1 || { rm -f "$tmpfile"; die "temp settings file failed validation, aborting"; }
  mv "$tmpfile" "$SETTINGS" || die "failed to move temp settings file into place"
  echo "handrail uninstall: no backup found, stripped Handrail entries from $SETTINGS directly"
else
  echo "handrail uninstall: no settings.json and no backup found, nothing to restore"
fi
