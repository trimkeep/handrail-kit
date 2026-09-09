// test/plugin.test.js
// The plugin manifest and hooks.json must stay consistent with the shipped scripts:
// every command in hooks/hooks.json points at an existing, executable hook, and the
// plugin hooks cover exactly the same six scripts install.sh writes into settings.json.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const HOOK_NAMES = ['destructive-shell', 'git-force-push', 'secret-paths', 'prod-guard', 'publish-guard', 'remote-exec'];

test('plugin.json carries the fields the plugin manager needs', () => {
  const p = JSON.parse(fs.readFileSync(path.join(ROOT, '.claude-plugin/plugin.json'), 'utf8'));
  assert.equal(p.name, 'handrail');
  assert.match(p.version, /^\d+\.\d+\.\d+$/);
  assert.ok(p.description.length > 20);
  assert.equal(p.license, 'MIT');
  assert.equal(p.author.name, 'Trimkeep');
});

test('hooks.json references only shipped, executable scripts and covers all six', () => {
  const h = JSON.parse(fs.readFileSync(path.join(ROOT, 'hooks/hooks.json'), 'utf8'));
  const commands = h.hooks.PreToolUse.flatMap((m) => m.hooks.map((x) => x.command));
  assert.ok(commands.length >= HOOK_NAMES.length);
  const seen = new Set();
  for (const cmd of commands) {
    const m = cmd.match(/\$\{CLAUDE_PLUGIN_ROOT\}"?\/hooks\/([a-z-]+)\.sh$/);
    assert.ok(m, `command must resolve under \${CLAUDE_PLUGIN_ROOT}/hooks: ${cmd}`);
    const file = path.join(ROOT, 'hooks', `${m[1]}.sh`);
    assert.ok(fs.existsSync(file), `missing hook script ${file}`);
    fs.accessSync(file, fs.constants.X_OK);
    seen.add(m[1]);
  }
  assert.deepEqual([...seen].sort(), [...HOOK_NAMES].sort());
  for (const matcher of h.hooks.PreToolUse) {
    for (const x of matcher.hooks) assert.equal(x.type, 'command');
  }
});

test('the Bash matcher runs every hook; the edit matcher runs secret-paths', () => {
  const h = JSON.parse(fs.readFileSync(path.join(ROOT, 'hooks/hooks.json'), 'utf8'));
  const bash = h.hooks.PreToolUse.find((m) => m.matcher === 'Bash');
  const edit = h.hooks.PreToolUse.find((m) => m.matcher === 'Edit|Write|MultiEdit');
  assert.equal(bash.hooks.length, 6);
  assert.equal(edit.hooks.length, 1);
  assert.match(edit.hooks[0].command, /secret-paths\.sh$/);
});
