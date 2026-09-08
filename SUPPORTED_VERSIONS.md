# Supported versions

Handrail hooks are plain POSIX-ish bash + jq, invoked the way Claude Code
invokes a `PreToolUse` command hook: the hook script is run with the tool
call's JSON on stdin, and its exit code (plus, for an "ask", a JSON line on
stdout) is the decision.

- **Claude Code**: 2.1.x — tested against the hook contract this pack relies
  on (stdin JSON with `session_id`, `cwd`, `hook_event_name`, `tool_name`,
  `tool_input`; exit 0 = allow; exit 2 = block with stderr shown to the
  model; a `{"hookSpecificOutput": {...}}` JSON line on stdout with exit 0 to
  force a user prompt).
- **bash**: >= 3.2 (macOS's shipped `/bin/bash`) and >= 5 (typical Linux).
  No bash 4+-only features are used (no associative arrays, no `mapfile`).
- **jq**: >= 1.6.

Every hook fails closed if `jq` is missing, so an unmet `jq` requirement is
self-reporting rather than silent.

## Untested, likely compatible

Any other agent CLI that wires up a shell-command hook receiving the same
stdin-JSON shape (`tool_name` / `tool_input`) and honors the same exit-code
contract (0 = allow, 2 = deny, plus a JSON `permissionDecision` on stdout for
"ask") should work unmodified. This has not been verified against any CLI
other than Claude Code — if you wire Handrail into another agent's hook
system, please treat it as untested until you've run the pack's own
`npm test` fixtures through your CLI's actual hook invocation path.
