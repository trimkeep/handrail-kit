// test/hooks.test.js
// node --test suite for the Handrail hook pack. No dependencies: node:test,
// node:assert, node:child_process, node:fs, node:os, node:path only.
//
// Covers, per the project spec:
//  (i)   >=6 dangerous fixtures per hook are denied (exit 2) or asked
//        (JSON hookSpecificOutput.permissionDecision === "ask")
//  (ii)  >=4 benign fixtures per hook are allowed (exit 0, no stdout)
//  (iii) fail-closed: empty stdin / non-JSON stdin / JSON without
//        tool_input / PATH with jq removed all produce exit 2
//  (iv)  only-tightens: no hook ever prints permissionDecision "allow"
//  (v)   install.sh produces a valid settings.json with all six hooks and
//        is idempotent; uninstall.sh restores the pre-install state
import { test, describe, before } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const HOOKS_DIR = path.join(ROOT, 'hooks');
const FIXTURES_DIR = path.join(__dirname, 'fixtures');
const INSTALL_SH = path.join(ROOT, 'install.sh');
const UNINSTALL_SH = path.join(ROOT, 'uninstall.sh');

const HOOK_NAMES = [
  'destructive-shell',
  'git-force-push',
  'secret-paths',
  'prod-guard',
  'publish-guard',
  'remote-exec',
];

// --- a PATH that has every core utility a hook needs (bash, cat, grep) but
// not jq, for the "missing jq" fail-closed case. Built once, reused.
let NO_JQ_PATH;
before(() => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'handrail-nojq-'));
  for (const bin of ['bash', 'cat', 'grep', 'sh']) {
    const found = spawnSync('/usr/bin/which', [bin], { encoding: 'utf8' });
    const real = found.status === 0 ? found.stdout.trim() : `/bin/${bin}`;
    fs.symlinkSync(real, path.join(dir, bin));
  }
  NO_JQ_PATH = dir;
});

function runHook(hookName, input, { env } = {}) {
  const scriptPath = path.join(HOOKS_DIR, `${hookName}.sh`);
  const stdin = typeof input === 'string' ? input : JSON.stringify(input);
  return spawnSync(scriptPath, [], {
    input: stdin,
    encoding: 'utf8',
    env: env ?? process.env,
    timeout: 10_000,
  });
}

function loadFixtures(hookName) {
  return JSON.parse(fs.readFileSync(path.join(FIXTURES_DIR, `${hookName}.json`), 'utf8'));
}

// A hook must never emit permissionDecision "allow" — deny (exit 2, no
// stdout JSON) or ask (JSON) are the only shapes it may produce.
function assertOnlyTightens(result) {
  const out = result.stdout ?? '';
  assert.doesNotMatch(out, /"permissionDecision"\s*:\s*"allow"/, 'hook must never print permissionDecision: allow');
  if (out.trim() !== '') {
    let parsed;
    try {
      parsed = JSON.parse(out);
    } catch {
      parsed = null;
    }
    if (parsed?.hookSpecificOutput) {
      assert.notEqual(parsed.hookSpecificOutput.permissionDecision, 'allow');
    }
  }
}

for (const hookName of HOOK_NAMES) {
  describe(`hooks/${hookName}.sh`, () => {
    const fixtures = loadFixtures(hookName);

    for (const c of fixtures.deny ?? []) {
      test(`denies: ${c.name}`, () => {
        const r = runHook(hookName, c.input);
        assertOnlyTightens(r);
        assert.equal(r.status, 2, `expected exit 2, got ${r.status}\nstderr: ${r.stderr}`);
        assert.equal(r.stdout.trim(), '', 'a deny must not print stdout JSON');
        assert.ok(r.stderr.trim().length > 0, 'a deny must print a one-line reason to stderr');
      });
    }

    for (const c of fixtures.ask ?? []) {
      test(`asks: ${c.name}`, () => {
        const r = runHook(hookName, c.input);
        assertOnlyTightens(r);
        assert.equal(r.status, 0, `expected exit 0, got ${r.status}\nstderr: ${r.stderr}`);
        const out = JSON.parse(r.stdout);
        assert.equal(out.hookSpecificOutput.hookEventName, 'PreToolUse');
        assert.equal(out.hookSpecificOutput.permissionDecision, 'ask');
        assert.ok(
          typeof out.hookSpecificOutput.permissionDecisionReason === 'string' &&
            out.hookSpecificOutput.permissionDecisionReason.length > 0,
          'ask must carry a non-empty reason'
        );
      });
    }

    for (const c of fixtures.allow ?? []) {
      test(`allows: ${c.name}`, () => {
        const r = runHook(hookName, c.input);
        assertOnlyTightens(r);
        assert.equal(r.status, 0, `expected exit 0, got ${r.status}\nstderr: ${r.stderr}`);
        assert.equal(r.stdout.trim(), '', 'a benign input must produce no stdout');
      });
    }
  });
}

describe('fail-closed behaviour (every hook)', () => {
  for (const hookName of HOOK_NAMES) {
    test(`${hookName}.sh: empty stdin denies`, () => {
      const r = runHook(hookName, '');
      assertOnlyTightens(r);
      assert.equal(r.status, 2);
    });

    test(`${hookName}.sh: non-JSON stdin denies`, () => {
      const r = runHook(hookName, 'this is not json');
      assertOnlyTightens(r);
      assert.equal(r.status, 2);
    });

    test(`${hookName}.sh: JSON without tool_input denies`, () => {
      const r = runHook(hookName, { tool_name: 'Bash' });
      assertOnlyTightens(r);
      assert.equal(r.status, 2);
    });

    test(`${hookName}.sh: PATH with jq removed denies`, () => {
      const r = runHook(
        hookName,
        { tool_name: 'Bash', tool_input: { command: 'ls -la' } },
        { env: { PATH: NO_JQ_PATH } }
      );
      assertOnlyTightens(r);
      assert.equal(r.status, 2);
    });
  }
});

describe('only-tightens: full fixture sweep', () => {
  test('no hook prints permissionDecision "allow" for any shipped fixture', () => {
    for (const hookName of HOOK_NAMES) {
      const fixtures = loadFixtures(hookName);
      for (const bucket of ['deny', 'ask', 'allow']) {
        for (const c of fixtures[bucket] ?? []) {
          const r = runHook(hookName, c.input);
          assertOnlyTightens(r);
        }
      }
    }
  });
});

describe('publish-guard.sh: HANDRAIL_ALLOW_PUBLISH override', () => {
  test('npm publish --access public without the env var is denied', () => {
    const r = runHook('publish-guard', {
      tool_name: 'Bash',
      tool_input: { command: 'npm publish --access public' },
    });
    assert.equal(r.status, 2);
  });

  test('npm publish --access public with HANDRAIL_ALLOW_PUBLISH=1 falls through to ask, not deny', () => {
    const r = runHook(
      'publish-guard',
      { tool_name: 'Bash', tool_input: { command: 'npm publish --access public' } },
      { env: { ...process.env, HANDRAIL_ALLOW_PUBLISH: '1' } }
    );
    assertOnlyTightens(r);
    assert.equal(r.status, 0);
    const out = JSON.parse(r.stdout);
    assert.equal(out.hookSpecificOutput.permissionDecision, 'ask');
  });
});

describe('bash -n syntax check', () => {
  for (const hookName of HOOK_NAMES) {
    test(`${hookName}.sh has valid bash syntax`, () => {
      const r = spawnSync('bash', ['-n', path.join(HOOKS_DIR, `${hookName}.sh`)], { encoding: 'utf8' });
      assert.equal(r.status, 0, r.stderr);
    });
  }
  for (const script of ['install.sh', 'uninstall.sh']) {
    test(`${script} has valid bash syntax`, () => {
      const r = spawnSync('bash', ['-n', path.join(ROOT, script)], { encoding: 'utf8' });
      assert.equal(r.status, 0, r.stderr);
    });
  }
});

// ---------------------------------------------------------------------------
// install.sh / uninstall.sh
// ---------------------------------------------------------------------------

function mkTmpProject() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'handrail-project-'));
}

function readSettings(projectDir) {
  return JSON.parse(fs.readFileSync(path.join(projectDir, '.claude', 'settings.json'), 'utf8'));
}

function bashMatcherCommands(settings) {
  const group = settings.hooks.PreToolUse.find((g) => g.matcher === 'Bash');
  return group ? group.hooks.map((h) => h.command) : [];
}

describe('install.sh on a fresh project (no existing settings.json)', () => {
  const tmp = mkTmpProject();

  test('creates a valid settings.json wiring all six hooks', () => {
    const r = spawnSync(INSTALL_SH, [tmp], { encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);

    const settings = readSettings(tmp);
    const bashCommands = bashMatcherCommands(settings);
    for (const name of HOOK_NAMES) {
      assert.ok(
        bashCommands.some((c) => c.includes(`handrail/${name}.sh`)),
        `Bash matcher is missing ${name}.sh`
      );
    }
    const ewmGroup = settings.hooks.PreToolUse.find((g) => g.matcher === 'Edit|Write|MultiEdit');
    assert.ok(ewmGroup, 'Edit|Write|MultiEdit matcher group is missing');
    assert.ok(ewmGroup.hooks.some((h) => h.command.includes('secret-paths.sh')));

    for (const name of HOOK_NAMES) {
      const scriptPath = path.join(tmp, '.claude', 'hooks', 'handrail', `${name}.sh`);
      assert.ok(fs.existsSync(scriptPath), `${name}.sh was not copied`);
      const mode = fs.statSync(scriptPath).mode;
      assert.ok(mode & 0o111, `${name}.sh is not executable`);
    }
  });

  test('is idempotent: a second run changes nothing and creates no backup', () => {
    const settingsPath = path.join(tmp, '.claude', 'settings.json');
    const before = fs.readFileSync(settingsPath, 'utf8');

    const r = spawnSync(INSTALL_SH, [tmp], { encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);

    const after = fs.readFileSync(settingsPath, 'utf8');
    assert.equal(after, before, 'settings.json content changed on a repeat install');

    const claudeFiles = fs.readdirSync(path.join(tmp, '.claude'));
    assert.ok(
      !claudeFiles.some((f) => f.startsWith('settings.json.bak-')),
      'a backup was created even though nothing needed to change'
    );
  });

  test('uninstall removes the hook scripts and strips the hooks block (no backup existed)', () => {
    const r = spawnSync(UNINSTALL_SH, [tmp], { encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);
    assert.ok(!fs.existsSync(path.join(tmp, '.claude', 'hooks', 'handrail')));

    const settings = readSettings(tmp);
    assert.deepEqual(settings, {}, 'settings.json should be back to empty since install created it from nothing');
  });
});

describe('install.sh merging into an existing settings.json', () => {
  const tmp = mkTmpProject();
  const original = {
    env: { SOME_VAR: '1' },
    permissions: { allow: ['Bash(npm test)'] },
    hooks: {
      PreToolUse: [{ matcher: 'Bash', hooks: [{ type: 'command', command: './my-existing-hook.sh' }] }],
    },
  };

  before(() => {
    fs.mkdirSync(path.join(tmp, '.claude'), { recursive: true });
    fs.writeFileSync(path.join(tmp, '.claude', 'settings.json'), JSON.stringify(original, null, 2));
  });

  test('preserves existing keys and entries, adds Handrail hooks, and backs up first', () => {
    const r = spawnSync(INSTALL_SH, [tmp], { encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);

    const settings = readSettings(tmp);
    assert.deepEqual(settings.env, original.env);
    assert.deepEqual(settings.permissions, original.permissions);

    const bashCommands = bashMatcherCommands(settings);
    assert.ok(bashCommands.includes('./my-existing-hook.sh'), 'pre-existing hook entry was lost');
    for (const name of HOOK_NAMES) {
      assert.ok(bashCommands.some((c) => c.includes(`handrail/${name}.sh`)));
    }

    const backups = fs.readdirSync(path.join(tmp, '.claude')).filter((f) => f.startsWith('settings.json.bak-'));
    assert.equal(backups.length, 1, 'expected exactly one backup file');
    const backedUp = JSON.parse(fs.readFileSync(path.join(tmp, '.claude', backups[0]), 'utf8'));
    assert.deepEqual(backedUp, original);
  });

  test('is idempotent and does not create a second backup', () => {
    const settingsPath = path.join(tmp, '.claude', 'settings.json');
    const before = fs.readFileSync(settingsPath, 'utf8');

    const r = spawnSync(INSTALL_SH, [tmp], { encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);

    assert.equal(fs.readFileSync(settingsPath, 'utf8'), before);
    const backups = fs.readdirSync(path.join(tmp, '.claude')).filter((f) => f.startsWith('settings.json.bak-'));
    assert.equal(backups.length, 1, 'a repeat install created an extra backup');
  });

  test('uninstall restores the original settings.json from the backup', () => {
    const r = spawnSync(UNINSTALL_SH, [tmp], { encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);
    assert.ok(!fs.existsSync(path.join(tmp, '.claude', 'hooks', 'handrail')));

    const restored = readSettings(tmp);
    assert.deepEqual(restored, original);
  });
});

describe('install.sh / uninstall.sh error handling', () => {
  test('install.sh fails closed with no arguments', () => {
    const r = spawnSync(INSTALL_SH, [], { encoding: 'utf8' });
    assert.notEqual(r.status, 0);
  });

  test('install.sh fails closed on a non-existent target directory', () => {
    const r = spawnSync(INSTALL_SH, ['/no/such/directory/handrail-test'], { encoding: 'utf8' });
    assert.notEqual(r.status, 0);
  });

  test('install.sh leaves a corrupt settings.json untouched rather than overwriting it', () => {
    const tmp = mkTmpProject();
    fs.mkdirSync(path.join(tmp, '.claude'), { recursive: true });
    const settingsPath = path.join(tmp, '.claude', 'settings.json');
    fs.writeFileSync(settingsPath, '{not valid json');

    const r = spawnSync(INSTALL_SH, [tmp], { encoding: 'utf8' });
    assert.notEqual(r.status, 0);
    assert.equal(fs.readFileSync(settingsPath, 'utf8'), '{not valid json');
  });
});
