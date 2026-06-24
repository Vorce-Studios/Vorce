import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  ConfigValidationError,
  backupAndWriteConfig,
  buildGitHubIssueCreateArgs,
  buildGitHubIssueListArgs,
  buildGitHubLabelArgs,
  buildGitHubPrListArgs,
  parseGitHubProcessResult,
  validateDashboardConfig,
} from '../web/Dashboard/vite.config.ts';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const factoryRoot = path.resolve(testDir, '..');
const configPath = path.join(factoryRoot, 'var/config/autopilot-config.json');
const viteConfigPath = path.join(factoryRoot, 'web/Dashboard/vite.config.ts');

function loadConfig() {
  return JSON.parse(fs.readFileSync(configPath, 'utf8'));
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function expectConfigError(config, expectedField) {
  assert.throws(
    () => validateDashboardConfig(config),
    error => error instanceof ConfigValidationError && error.fieldPath === expectedField,
  );
}

test('accepts the canonical five-router configuration', () => {
  const config = loadConfig();
  assert.equal(validateDashboardConfig(config), config);
  assert.deepEqual(Object.keys(config.router_rules).sort(), [
    'Audit',
    'CheckAndDoing',
    'MemoryOptimization',
    'Optimizer',
    'Planning',
  ]);
});

test('rejects missing and additional router keys with a field path', () => {
  const missing = loadConfig();
  delete missing.router_rules.Audit;
  expectConfigError(missing, 'router_rules.Audit');

  const extra = loadConfig();
  extra.router_rules.UnsafeRouter = [];
  expectConfigError(extra, 'router_rules.UnsafeRouter');
});

test('rejects unknown conditions and catalog identity changes', () => {
  const condition = loadConfig();
  condition.router_rules.Planning[2].condition = 'Invoke-Expression';
  expectConfigError(condition, 'router_rules.Planning[2].condition');

  const script = loadConfig();
  script.router_rules.Planning[2].script = 'src/runs/attacker.ps1';
  expectConfigError(script, 'router_rules.Planning[2].script');

  const name = loadConfig();
  name.router_rules.Planning[2].name = 'OtherStrategy';
  expectConfigError(name, 'router_rules.Planning[2].name');

  const id = loadConfig();
  id.router_rules.Planning[2].id = '99';
  expectConfigError(id, 'router_rules.Planning[2].id');

  const mode = loadConfig();
  mode.router_rules.Planning[2].mode = 'shell';
  expectConfigError(mode, 'router_rules.Planning[2].mode');

  const wrongSubCondition = loadConfig();
  wrongSubCondition.router_rules.Planning[2].condition = 'has_open_alerts';
  expectConfigError(wrongSubCondition, 'router_rules.Planning[2].condition');
});

test('rejects non-whitelisted and out-of-range numeric settings', () => {
  const outOfRange = loadConfig();
  outOfRange.router_rules.CheckAndDoing[5].condition_settings.interval_minutes = 10_081;
  expectConfigError(outOfRange, 'router_rules.CheckAndDoing[5].condition_settings.interval_minutes');

  const unknownSetting = loadConfig();
  unknownSetting.router_rules.Optimizer[1].condition_settings.shell_command = 1;
  expectConfigError(unknownSetting, 'router_rules.Optimizer[1].condition_settings.shell_command');
});

test('rejects additional top-level and router-entry fields', () => {
  const topLevel = loadConfig();
  topLevel.arbitrary = { command: 'whoami' };
  expectConfigError(topLevel, 'arbitrary');

  const routerField = loadConfig();
  routerField.router_rules.Audit[0].command = 'whoami';
  expectConfigError(routerField, 'router_rules.Audit[0].command');
});

test('creates a backup and atomically replaces config files in a temp directory', t => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'vorce-dashboard-config-'));
  t.after(() => fs.rmSync(tempRoot, { recursive: true, force: true }));

  const target = path.join(tempRoot, 'var/config/autopilot-config.json');
  const publicTarget = path.join(tempRoot, 'web/public/autopilot-config.json');
  const backups = path.join(tempRoot, 'var/config/backups');
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, JSON.stringify({ version: 'old' }), 'utf8');

  const nextConfig = { version: 'new', nested: { value: 1 } };
  const backupPath = backupAndWriteConfig(
    target,
    publicTarget,
    backups,
    nextConfig,
    new Date('2026-06-23T12:34:56.789Z'),
  );

  assert.ok(backupPath);
  assert.equal(path.dirname(backupPath), backups);
  assert.deepEqual(JSON.parse(fs.readFileSync(backupPath, 'utf8')), { version: 'old' });
  assert.deepEqual(JSON.parse(fs.readFileSync(target, 'utf8')), nextConfig);
  assert.deepEqual(JSON.parse(fs.readFileSync(publicTarget, 'utf8')), nextConfig);
  assert.equal(fs.readdirSync(path.dirname(target)).some(name => name.endsWith('.tmp')), false);
});

test('keeps hostile GitHub values as individual arguments', () => {
  const repository = 'owner/repo; echo hacked';
  const title = 'quote " newline\nsemicolon; ampersand& dollar$() backtick`';
  const body = 'line one\nline two; & $(touch nope) `"quoted"`';
  const label = 'priority: high; $(nope)';

  const issueArgs = buildGitHubIssueCreateArgs(repository, title, body, [label, 'bug']);
  assert.equal(issueArgs[issueArgs.indexOf('--repo') + 1], repository);
  assert.equal(issueArgs[issueArgs.indexOf('--title') + 1], title);
  assert.equal(issueArgs[issueArgs.indexOf('--body') + 1], body);
  assert.deepEqual(
    issueArgs.filter((_, index) => index > 0 && issueArgs[index - 1] === '--label'),
    [label, 'bug'],
  );

  assert.equal(buildGitHubIssueListArgs(repository)[3], repository);
  assert.equal(buildGitHubPrListArgs(repository)[3], repository);
  const labelArgs = buildGitHubLabelArgs(repository, label, body);
  assert.equal(labelArgs[labelArgs.indexOf('--repo') + 1], repository);
  assert.equal(labelArgs[labelArgs.indexOf('--description') + 1], body);
});

test('classifies missing gh, non-zero auth failures, and timeouts without starting a process', () => {
  const missing = Object.assign(new Error('spawn gh ENOENT'), { code: 'ENOENT' });
  assert.throws(
    () => parseGitHubProcessResult({ stdout: '', stderr: '', status: null, signal: null, error: missing }),
    /gh failed to start: spawn gh ENOENT/,
  );

  assert.throws(
    () => parseGitHubProcessResult({ stdout: '', stderr: 'authentication required', status: 1, signal: null }),
    /gh exited with code 1: authentication required/,
  );

  const timeout = Object.assign(new Error('timed out'), { code: 'ETIMEDOUT' });
  assert.throws(
    () => parseGitHubProcessResult({ stdout: '', stderr: '', status: null, signal: null, error: timeout }, 1234),
    /gh timed out after 1234ms/,
  );
});

test('contains no execSync or interpolated gh shell command', () => {
  const source = fs.readFileSync(viteConfigPath, 'utf8');
  assert.doesNotMatch(source, /\bexecSync\s*\(/);
  assert.doesNotMatch(source, /\bspawnSync\s*\(\s*`/);
  assert.match(source, /\bspawnSync\s*\(\s*['"]gh['"]/);
});
