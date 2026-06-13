#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

function findGeminiCoreBundle() {
  const appData = process.env.APPDATA;
  if (!appData) {
    throw new Error('APPDATA is not set; cannot locate the global Gemini CLI install.');
  }

  const bundleDir = path.join(appData, 'npm', 'node_modules', '@google', 'gemini-cli', 'bundle');
  const candidates = fs.readdirSync(bundleDir)
    .filter((name) => /^core-[A-Z0-9]+\.js$/i.test(name))
    .map((name) => {
      const fullPath = path.join(bundleDir, name);
      return { fullPath, mtimeMs: fs.statSync(fullPath).mtimeMs };
    })
    .sort((a, b) => b.mtimeMs - a.mtimeMs);

  if (candidates.length === 0) {
    throw new Error(`No Gemini CLI core bundle found in ${bundleDir}`);
  }

  return candidates[0].fullPath;
}

function parseArgs(argv) {
  const args = {
    cwd: process.cwd(),
    model: undefined
  };

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--cwd' && argv[i + 1]) {
      args.cwd = path.resolve(argv[i + 1]);
      i += 1;
    } else if (arg === '--model' && argv[i + 1]) {
      args.model = argv[i + 1];
      i += 1;
    }
  }

  return args;
}

function computeBucket(bucket) {
  const fraction = Number(bucket.remainingFraction);
  if (!Number.isFinite(fraction)) {
    return null;
  }

  let remaining;
  let limit;
  if (bucket.remainingAmount !== undefined && bucket.remainingAmount !== null && `${bucket.remainingAmount}` !== '') {
    remaining = Number.parseInt(`${bucket.remainingAmount}`, 10);
    limit = fraction > 0 ? Math.round(remaining / fraction) : undefined;
  } else {
    limit = 100;
    remaining = Math.round(fraction * limit);
  }

  if (!Number.isFinite(remaining) || !Number.isFinite(limit) || limit <= 0) {
    return null;
  }

  const used = Math.max(0, Math.min(limit, limit - remaining));
  return {
    model_id: bucket.modelId,
    remaining,
    limit,
    used,
    used_percent: Math.round((used / limit) * 1000) / 10,
    remaining_fraction: fraction,
    resets_at: bucket.resetTime ?? null
  };
}

async function main() {
  const args = parseArgs(process.argv);
  const originalConsole = {
    log: console.log,
    info: console.info,
    warn: console.warn,
    error: console.error,
    stdoutWrite: process.stdout.write.bind(process.stdout),
    stderrWrite: process.stderr.write.bind(process.stderr)
  };

  try {
    process.env.NO_COLOR = process.env.NO_COLOR || '1';
    const corePath = findGeminiCoreBundle();

    // The Gemini core bundle logs auth and experiment details during quota setup.
    // Suppress those logs so stdout remains machine-readable JSON.
    console.log = () => {};
    console.info = () => {};
    console.warn = () => {};
    console.error = () => {};
    process.stdout.write = () => true;
    process.stderr.write = () => true;

    const core = await import(pathToFileURL(corePath).href);
    const model = args.model || core.DEFAULT_GEMINI_MODEL_AUTO || 'gemini-3-pro-preview';
    const cfg = new core.Config({
      sessionId: core.createSessionId?.() ?? `quota-${Date.now()}`,
      clientName: 'cli-command',
      clientVersion: 'autopilot-quota',
      model,
      embeddingModel: 'gemini-embedding-001',
      targetDir: args.cwd,
      cwd: args.cwd,
      interactive: false,
      mcpEnabled: false,
      extensionsEnabled: false,
      telemetry: { enabled: false },
      usageStatisticsEnabled: false,
      includeDirectoryTree: false,
      fileFiltering: {
        respectGitIgnore: false,
        respectGeminiIgnore: false,
        enableFileWatcher: false,
        enableRecursiveFileSearch: false,
        enableFuzzySearch: false
      },
      plan: false,
      skillsSupport: false,
      enableAgents: false,
      enableEventDrivenScheduler: false,
      enableHooks: false,
      approvalMode: 'default',
      output: { format: 'json' }
    });

    await cfg.refreshAuth(core.AuthType.LOGIN_WITH_GOOGLE);
    const quota = await cfg.refreshUserQuota();
    const buckets = (quota?.buckets ?? [])
      .map(computeBucket)
      .filter(Boolean);

    const remaining = Number(cfg.getQuotaRemaining?.());
    const limit = Number(cfg.getQuotaLimit?.());
    const pooled = Number.isFinite(remaining) && Number.isFinite(limit) && limit > 0
      ? {
          remaining,
          limit,
          used: Math.max(0, Math.min(limit, limit - remaining)),
          used_percent: Math.round(((limit - remaining) / limit) * 1000) / 10,
          resets_at: cfg.getQuotaResetTime?.() ?? null
        }
      : null;

    console.log = originalConsole.log;
    console.info = originalConsole.info;
    console.warn = originalConsole.warn;
    console.error = originalConsole.error;
    process.stdout.write = originalConsole.stdoutWrite;
    process.stderr.write = originalConsole.stderrWrite;
    originalConsole.stdoutWrite(`${JSON.stringify({
      ok: true,
      source: 'gemini-cli-retrieveUserQuota',
      model,
      fetched_at: new Date().toISOString(),
      pooled,
      buckets
    })}\n`);
  } catch (error) {
    console.log = originalConsole.log;
    console.info = originalConsole.info;
    console.warn = originalConsole.warn;
    console.error = originalConsole.error;
    process.stdout.write = originalConsole.stdoutWrite;
    process.stderr.write = originalConsole.stderrWrite;
    originalConsole.stdoutWrite(`${JSON.stringify({
      ok: false,
      source: 'gemini-cli-retrieveUserQuota',
      fetched_at: new Date().toISOString(),
      error: error instanceof Error ? error.message : String(error)
    })}\n`);
    process.exitCode = 1;
  }
}

await main();
