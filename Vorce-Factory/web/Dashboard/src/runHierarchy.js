import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const MODULE_DIR = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_MANIFEST_PATH = path.join(MODULE_DIR, 'run-topology.manifest.json');

function readJsonFile(filePath, fallback) {
  if (!fs.existsSync(filePath)) return fallback;
  return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
}

function canonicalPath(filePath) {
  return filePath.replace(/\\/g, '/');
}

function parseRunLabel(name) {
  return name.split('__').pop()?.replace(/^SUB-RUN-\d+_MR-\d+_/, '').replace(/^PART-RUN-\d+_MR-\d+_/, '') || name;
}

function loadManifest(manifestPath) {
  return readJsonFile(manifestPath, { schema_version: 1, main_runs: [] });
}

function loadRuntimeStates(runStatesDir) {
  if (!fs.existsSync(runStatesDir)) return [];

  return fs.readdirSync(runStatesDir)
    .filter(file => file.endsWith('.json') && !file.includes('_VALIDATE-'))
    .map(file => {
      try {
        const state = readJsonFile(path.join(runStatesDir, file), {});
        return { ...state, source_file: file };
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

function normalizeName(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function collectStateNamesFromResults(results) {
  if (!Array.isArray(results)) return [];
  return results.flatMap(entry => {
    if (!entry || typeof entry !== 'object') return [];
    return [entry.name, entry.sub_run, entry.script, entry.id]
      .map(normalizeName)
      .filter(Boolean);
  });
}

function latestByTimestamp(items) {
  if (items.length === 0) return null;
  return items.reduce((latest, current) => {
    if (!latest) return current;
    const currentTime = Date.parse(String(current.completed_at || current.started_at || 0));
    const latestTime = Date.parse(String(latest.completed_at || latest.started_at || 0));
    return currentTime >= latestTime ? current : latest;
  }, items[0] ?? null);
}

function isCanonicalStateRecord(state, manifest) {
  const fileStem = path.basename(state.source_file, '.json');
  const mainStateStems = new Set(manifest.main_runs.map(main => `MAIN_${main.name}`));
  const subStateStems = new Set(manifest.main_runs.flatMap(main => main.sub_runs.map(sub => `SUB_${path.basename(sub.script, '.ps1')}`)));
  const partStateStems = new Set(manifest.main_runs.flatMap(main => main.sub_runs.flatMap(sub => sub.parts.map(part => `PART_${path.basename(part.script, '.ps1')}`))));

  if (mainStateStems.has(fileStem)) return true;
  if (subStateStems.has(fileStem)) return true;
  if (partStateStems.has(fileStem)) return true;
  return false;
}

function getConfiguredSubRuns(config, routerKey) {
  const routerRules = config.router_rules || {};
  const rules = routerRules[routerKey] || [];
  return Array.isArray(rules) ? rules : [];
}

function findMainState(states, mainName) {
  return latestByTimestamp(states.filter(state => normalizeName(state.type).toUpperCase() === 'MAIN' && normalizeName(state.name) === mainName));
}

function findSubState(states, subName) {
  const matches = states.filter(state => {
    const type = normalizeName(state.type).toUpperCase();
    const name = normalizeName(state.name);
    const subRun = normalizeName(state.sub_run);
    const sourceStem = path.basename(state.source_file, '.json');
    return type === 'SUB' && (
      name === subName ||
      name.endsWith(`__${subName}`) ||
      subRun === subName ||
      subRun.endsWith(`__${subName}`) ||
      sourceStem === `SUB_${subName}` ||
      sourceStem.endsWith(`__${subName}`)
    );
  });
  return latestByTimestamp(matches);
}

function findPartState(states, partName) {
  const matches = states.filter(state => {
    const type = normalizeName(state.type).toUpperCase();
    const name = normalizeName(state.name);
    const sourceStem = path.basename(state.source_file, '.json');
    return type === 'PART' && (
      name === partName ||
      name.endsWith(`__${partName}`) ||
      sourceStem === `PART_${partName}` ||
      sourceStem.endsWith(`__${partName}`)
    );
  });
  return latestByTimestamp(matches);
}

function buildRouterDecision(main, latestMainState, activeSubRunsFromLastRun, configuredSubRuns) {
  return {
    configured_sub_runs: configuredSubRuns.map(rule => ({
      id: rule.id,
      name: rule.name,
      script: rule.script,
      configured_enabled: rule.enabled !== false,
      active: activeSubRunsFromLastRun.some(activeName => activeName === rule.name || activeName.endsWith(`__${rule.name}`) || activeName.endsWith(rule.name)),
      reason: rule.enabled === false
        ? 'disabled_in_config'
        : (activeSubRunsFromLastRun.some(activeName => activeName === rule.name || activeName.endsWith(`__${rule.name}`))
          ? 'active_by_router'
          : 'skipped_by_router_condition')
    })),
    active_sub_runs: activeSubRunsFromLastRun.map(name => ({ name, active: true })),
    inactive_sub_runs: configuredSubRuns
      .filter(rule => !activeSubRunsFromLastRun.some(activeName => activeName === rule.name || activeName.endsWith(`__${rule.name}`)))
      .map(rule => ({
        id: rule.id,
        name: rule.name,
        script: rule.script,
        active: false,
        reason: rule.enabled === false ? 'disabled_in_config' : 'skipped_by_router_condition'
      })),
    router_key: main.router_key,
    decision_timestamp: latestMainState?.completed_at || latestMainState?.started_at || null
  };
}

function buildPartNode(vorceRoot, runStatesDir, main, sub, part, states, activePartNames) {
  const partState = findPartState(states, part.name);
  const isActive = activePartNames.some(name => name === part.name || name.endsWith(`__${part.name}`));

  return {
    id: part.id,
    name: part.name,
    label: parseRunLabel(part.name),
    script: canonicalPath(part.script),
    parent_main_name: main.name,
    parent_sub_name: sub.name,
    configured_enabled: true,
    runtime_status: normalizeName(partState?.status) || (isActive ? 'completed' : 'not_started'),
    activation_reason: isActive ? 'activated_in_last_run' : 'not_activated_in_last_run',
    inactive_reason: normalizeName(partState?.skip_reason) || null,
    latest_state_path: partState ? canonicalPath(path.relative(vorceRoot, path.join(runStatesDir, partState.source_file))) : null,
    timestamp: normalizeName(partState?.completed_at) || normalizeName(partState?.started_at) || normalizeName(partState?.timestamp) || null
  };
}

function buildSubNode(vorceRoot, runStatesDir, main, sub, configRules, states, latestMainState, activeSubRunsFromLastRun) {
  const configRule = configRules.find(rule => rule.id === sub.id || rule.name === sub.name || canonicalPath(rule.script) === canonicalPath(sub.script)) || null;
  const subState = findSubState(states, sub.name);
  const activeFromLastRun = activeSubRunsFromLastRun.some(name => name === sub.name || name.endsWith(`__${sub.name}`));
  const activePartNames = collectStateNamesFromResults(
    latestMainState?.results?.find(result => {
      if (!result || typeof result !== 'object') return false;
      const resultName = normalizeName(result.sub_run) || normalizeName(result.name);
      return resultName === sub.name || resultName.endsWith(`__${sub.name}`);
    })?.parts
  );

  const partRuns = sub.parts.map(part => buildPartNode(vorceRoot, runStatesDir, main, sub, part, states, activePartNames));
  const runtimeStatus = normalizeName(subState?.status) || (activeFromLastRun ? 'completed' : 'not_started');

  return {
    id: sub.id,
    name: sub.name,
    label: configRule?.name || parseRunLabel(sub.name),
    script: canonicalPath(sub.script),
    parent_main_name: main.name,
    configured_enabled: configRule?.enabled !== false,
    runtime_status: runtimeStatus,
    activation_reason: activeFromLastRun || runtimeStatus !== 'not_started' ? 'activated_in_last_run' : 'not_activated_in_last_run',
    inactive_reason: normalizeName(subState?.skip_reason) || (configRule?.enabled === false ? 'disabled_in_config' : (runtimeStatus === 'skipped' ? 'skipped_by_router_condition' : null)),
    router_active_last_run: activeFromLastRun,
    latest_state_path: subState ? canonicalPath(path.relative(vorceRoot, path.join(runStatesDir, subState.source_file))) : null,
    part_runs: partRuns
  };
}

function collectActiveSubRuns(latestMainState) {
  const routerDecision = latestMainState?.metadata && typeof latestMainState.metadata === 'object'
    ? latestMainState.metadata.router_decision
    : null;
  const fromRouterDecision = routerDecision && typeof routerDecision === 'object'
    ? collectStateNamesFromResults(routerDecision.active_sub_runs)
    : [];
  if (fromRouterDecision.length > 0) return fromRouterDecision;
  return collectStateNamesFromResults(latestMainState?.results);
}

export function getRunTopologyManifest(manifestPath = DEFAULT_MANIFEST_PATH) {
  return loadManifest(manifestPath);
}

export function getRunHierarchy(options = {}) {
  const vorceRoot = options.vorceRoot ?? path.resolve(MODULE_DIR, '../..');
  const configPath = options.configPath ?? path.join(vorceRoot, 'var/config/autopilot-config.json');
  const runStatesDir = options.runStatesDir ?? path.join(vorceRoot, 'var/run-states');
  const manifest = loadManifest(options.manifestPath ?? DEFAULT_MANIFEST_PATH);
  const config = readJsonFile(configPath, {});
  const states = loadRuntimeStates(runStatesDir);

  const hierarchy = manifest.main_runs.map(main => {
    const latestMainState = findMainState(states, main.name);
    const configuredSubRuns = getConfiguredSubRuns(config, main.router_key);
    const activeSubRunsFromLastRun = collectActiveSubRuns(latestMainState);
    const subRuns = main.sub_runs.map(sub => buildSubNode(vorceRoot, runStatesDir, main, sub, configuredSubRuns, states, latestMainState, activeSubRunsFromLastRun));
    const routerDecision = buildRouterDecision(main, latestMainState, activeSubRunsFromLastRun, configuredSubRuns);

    return {
      name: main.name,
      label: main.label,
      router_key: main.router_key,
      interval_key: main.interval_key,
      configured_sub_runs: main.sub_runs.length,
      active_sub_runs_last_run: activeSubRunsFromLastRun.length,
      latest_state_path: latestMainState ? canonicalPath(path.relative(vorceRoot, path.join(runStatesDir, latestMainState.source_file))) : null,
      latest_state_status: normalizeName(latestMainState?.status) || 'not_started',
      last_run_timestamp: normalizeName(latestMainState?.completed_at) || normalizeName(latestMainState?.started_at) || normalizeName(latestMainState?.timestamp) || null,
      router_decision: routerDecision,
      sub_runs: subRuns
    };
  });

  const legacyOrphanStates = states
    .filter(state => !isCanonicalStateRecord(state, manifest))
    .map(state => ({
      source_file: state.source_file,
      type: normalizeName(state.type) || null,
      name: normalizeName(state.name) || null,
      timestamp: normalizeName(state.completed_at) || normalizeName(state.started_at) || normalizeName(state.timestamp) || null
    }));

  return {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    main_runs: hierarchy,
    legacy_orphan_states: legacyOrphanStates
  };
}
