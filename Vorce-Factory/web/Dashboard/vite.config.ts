import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import fs from 'fs'
import path from 'path'
import { spawn, spawnSync } from 'child_process'
import { fileURLToPath } from 'url'
import { getRunHierarchy as buildRunHierarchy } from './src/runHierarchy.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url));
let issuesCache: string | null = null;
let issuesCacheTime = 0;
let prsCache: string | null = null;
let prsCacheTime = 0;
const CACHE_TTL = 20000; // 20 seconds cache TTL to avoid hitting GitHub API too frequently
const VORCE_ROOT = path.resolve(__dirname, '../..');
const GLOBAL_STATE_PATH = path.join(VORCE_ROOT, 'var/db/global-state.json');
const DASHBOARD_STATE_PATH = path.join(VORCE_ROOT, 'var/db/dashboard-state.json');
const CONFIG_PATH = path.join(VORCE_ROOT, 'var/config/autopilot-config.json');
const RUN_STATES_DIR = path.join(VORCE_ROOT, 'var/run-states');
const RUN_HISTORY_DIR = path.join(VORCE_ROOT, 'var/run-history');
const CONFIG_BACKUP_DIR = path.join(VORCE_ROOT, 'var/config/backups');
const GH_TIMEOUT_MS = 30_000;
const GH_MAX_BUFFER = 10 * 1024 * 1024;
const MAIN_RUNS = [
  { name: 'MAIN-RUN-01_Planning', label: 'Planning', routerKey: 'Planning', intervalKey: 'planning_minutes' },
  { name: 'MAIN-RUN-02_CheckAndDoing', label: 'Check & Doing', routerKey: 'CheckAndDoing', intervalKey: 'check_and_doing_minutes' },
  { name: 'MAIN-RUN-03_Audit', label: 'Audit', routerKey: 'Audit', intervalKey: 'audit_minutes' },
  { name: 'MAIN-RUN-04_Optimizer', label: 'Optimizer', routerKey: 'Optimizer', intervalKey: 'optimizer_minutes' },
  { name: 'MAIN-RUN-05_MemoryOptimization', label: 'Memory Optimization', routerKey: 'MemoryOptimization', intervalKey: 'memory_optimization_minutes' },
] as const;
const MAIN_RUN_NAMES = new Set(MAIN_RUNS.map(run => run.name));

type RouterKey = typeof MAIN_RUNS[number]['routerKey'];
type RouterMode = 'always' | 'automatic' | 'manual_only';
type RouterCondition =
  | 'always'
  | 'pipeline_below_limit'
  | 'has_untriaged_issues'
  | 'has_approved_proposals'
  | 'has_active_jules_delegations'
  | 'has_active_local_agent_sessions'
  | 'has_open_prs_requiring_review'
  | 'jules_capacity_available'
  | 'housekeeping_due'
  | 'has_new_audit_inputs'
  | 'has_open_alerts'
  | 'optimizer_has_sufficient_samples'
  | 'optimizer_has_findings'
  | 'optimizer_has_approved_changes'
  | 'optimizer_has_changes_to_evaluate'
  | 'memory_maintenance_due'
  | 'memory_has_candidates'
  | 'master_issue_context_changed';

interface NumericSettingDefinition {
  label: string;
  min: number;
  max: number;
  step: number;
  default: number;
}

interface RouterCatalogEntry {
  id: string;
  name: string;
  script: string;
  defaultMode: RouterMode;
  defaultCondition: RouterCondition;
  allowedConditions: readonly RouterCondition[];
  dashboardEditable: boolean;
}

export const ROUTER_MODE_WHITELIST = ['always', 'automatic', 'manual_only'] as const;
export const ROUTER_CONDITION_WHITELIST = [
  'always',
  'pipeline_below_limit',
  'has_untriaged_issues',
  'has_approved_proposals',
  'has_active_jules_delegations',
  'has_active_local_agent_sessions',
  'has_open_prs_requiring_review',
  'jules_capacity_available',
  'housekeeping_due',
  'has_new_audit_inputs',
  'has_open_alerts',
  'optimizer_has_sufficient_samples',
  'optimizer_has_findings',
  'optimizer_has_approved_changes',
  'optimizer_has_changes_to_evaluate',
  'memory_maintenance_due',
  'memory_has_candidates',
  'master_issue_context_changed',
] as const;

export const CONDITION_SETTING_CATALOG: Partial<Record<RouterCondition, Record<string, NumericSettingDefinition>>> = {
  housekeeping_due: {
    interval_minutes: { label: 'Intervall (Minuten)', min: 15, max: 10_080, step: 15, default: 1_440 },
  },
  has_new_audit_inputs: {
    max_interval_minutes: { label: 'Max. Intervall (Minuten)', min: 15, max: 43_200, step: 15, default: 1_440 },
  },
  optimizer_has_sufficient_samples: {
    minimum_samples: { label: 'Mindest-Samples', min: 1, max: 1_000, step: 1, default: 3 },
  },
  memory_maintenance_due: {
    interval_minutes: { label: 'Intervall (Minuten)', min: 15, max: 10_080, step: 15, default: 60 },
  },
};

const entry = (
  id: string,
  name: string,
  script: string,
  defaultMode: RouterMode,
  defaultCondition: RouterCondition,
  allowedConditions: readonly RouterCondition[] = [defaultCondition],
): RouterCatalogEntry => ({
  id,
  name,
  script,
  defaultMode,
  defaultCondition,
  allowedConditions,
  dashboardEditable: true,
});

export const ROUTER_CATALOG: Record<RouterKey, readonly RouterCatalogEntry[]> = {
  Planning: [
    entry('01', 'DataSync', 'src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-01_MR-01_Planning__DataSync/SUB-RUN-01_MR-01_Planning__DataSync.ps1', 'always', 'always'),
    entry('02', 'Triage', 'src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-02_MR-01_Planning__Triage/SUB-RUN-02_MR-01_Planning__Triage.ps1', 'automatic', 'has_untriaged_issues', ['has_untriaged_issues', 'always']),
    entry('03', 'Strategy', 'src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-03_MR-01_Planning__Strategy/SUB-RUN-03_MR-01_Planning__Strategy.ps1', 'automatic', 'pipeline_below_limit', ['pipeline_below_limit', 'always']),
    entry('04', 'Delegation', 'src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-04_MR-01_Planning__Delegation/SUB-RUN-04_MR-01_Planning__Delegation.ps1', 'automatic', 'has_approved_proposals', ['has_approved_proposals', 'always']),
  ],
  CheckAndDoing: [
    entry('01', 'SessionSync', 'src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-01_MR-02_CheckAndDoing__SessionSync/SUB-RUN-01_MR-02_CheckAndDoing__SessionSync.ps1', 'always', 'always'),
    entry('02', 'JulesCheck', 'src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-02_MR-02_CheckAndDoing__JulesCheck/SUB-RUN-02_MR-02_CheckAndDoing__JulesCheck.ps1', 'automatic', 'has_active_jules_delegations', ['has_active_jules_delegations', 'always']),
    entry('03', 'LocalAgentCheck', 'src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-03_MR-02_CheckAndDoing__LocalAgentCheck/SUB-RUN-03_MR-02_CheckAndDoing__LocalAgentCheck.ps1', 'automatic', 'has_active_local_agent_sessions', ['has_active_local_agent_sessions', 'always']),
    entry('04', 'ReviewDispatch', 'src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-04_MR-02_CheckAndDoing__ReviewDispatch/SUB-RUN-04_MR-02_CheckAndDoing__ReviewDispatch.ps1', 'automatic', 'has_open_prs_requiring_review', ['has_open_prs_requiring_review', 'always']),
    entry('05', 'JulesRefill', 'src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-05_MR-02_CheckAndDoing__JulesRefill/SUB-RUN-05_MR-02_CheckAndDoing__JulesRefill.ps1', 'automatic', 'jules_capacity_available', ['jules_capacity_available', 'always']),
    entry('06', 'Housekeeping', 'src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-06_MR-02_CheckAndDoing__Housekeeping/SUB-RUN-06_MR-02_CheckAndDoing__Housekeeping.ps1', 'automatic', 'housekeeping_due', ['housekeeping_due', 'always']),
  ],
  Audit: [
    entry('01', 'DataSync', 'src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-01_MR-03_Audit__DataSync/SUB-RUN-01_MR-03_Audit__DataSync.ps1', 'always', 'always'),
    entry('02', 'ComplianceCheck', 'src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-02_MR-03_Audit__ComplianceCheck/SUB-RUN-02_MR-03_Audit__ComplianceCheck.ps1', 'automatic', 'has_new_audit_inputs', ['has_new_audit_inputs', 'always']),
    entry('03', 'JulesSupervision', 'src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-03_MR-03_Audit__JulesSupervision/SUB-RUN-03_MR-03_Audit__JulesSupervision.ps1', 'automatic', 'has_active_jules_delegations', ['has_active_jules_delegations', 'always']),
    entry('04', 'AlertDisposition', 'src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-04_MR-03_Audit__AlertDisposition/SUB-RUN-04_MR-03_Audit__AlertDisposition.ps1', 'automatic', 'has_open_alerts', ['has_open_alerts', 'always']),
  ],
  Optimizer: [
    entry('01', 'PerformanceDataCollection', 'src/runs/MAIN-RUN-04_Optimizer/SUB-RUNS/SUB-RUN-01_MR-04_Optimizer__PerformanceDataCollection/SUB-RUN-01_MR-04_Optimizer__PerformanceDataCollection.ps1', 'always', 'always'),
    entry('02', 'SystemAnalysis', 'src/runs/MAIN-RUN-04_Optimizer/SUB-RUNS/SUB-RUN-02_MR-04_Optimizer__SystemAnalysis/SUB-RUN-02_MR-04_Optimizer__SystemAnalysis.ps1', 'automatic', 'optimizer_has_sufficient_samples', ['optimizer_has_sufficient_samples', 'always']),
  ],
  MemoryOptimization: [
    entry('01', 'MemoryMaintenance', 'src/runs/MAIN-RUN-05_MemoryOptimization/SUB-RUNS/SUB-RUN-01_MR-05_MemoryOptimization__MemoryMaintenance/SUB-RUN-01_MR-05_MemoryOptimization__MemoryMaintenance.ps1', 'automatic', 'memory_maintenance_due', ['memory_maintenance_due', 'always']),
  ],
};

const ROUTER_KEYS = Object.keys(ROUTER_CATALOG) as RouterKey[];
const ROUTER_RULE_KEYS = ['id', 'name', 'script', 'enabled', 'mode', 'condition', 'condition_settings', 'dashboard_editable'];
const ALLOWED_CONFIG_KEYS = new Set([
  'debug_mode',
  'repository',
  'wake_intervals',
  'gemini_worktree_path',
  'issue_filters',
  'max_issues_per_planning_cycle',
  'working_sessions',
  'jules',
  'router_rules',
  'dual_ceo',
  'run_settings',
  'prompts',
]);

export class ConfigValidationError extends Error {
  readonly fieldPath: string;

  constructor(fieldPath: string, message: string) {
    super(message);
    this.name = 'ConfigValidationError';
    this.fieldPath = fieldPath;
  }
}

function isRecord(value: unknown): value is Record<string, any> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function assertExactKeys(value: Record<string, any>, expected: readonly string[], fieldPath: string): void {
  const actual = Object.keys(value);
  const missing = expected.find(key => !actual.includes(key));
  if (missing) throw new ConfigValidationError(`${fieldPath}.${missing}`, 'Pflichtfeld fehlt.');
  const extra = actual.find(key => !expected.includes(key));
  if (extra) throw new ConfigValidationError(`${fieldPath}.${extra}`, 'Feld ist nicht erlaubt.');
}

export function validateDashboardConfig(payload: unknown): Record<string, any> {
  if (!isRecord(payload)) throw new ConfigValidationError('$', 'Konfiguration muss ein JSON-Objekt sein.');
  const unknownTopLevelKey = Object.keys(payload).find(key => !ALLOWED_CONFIG_KEYS.has(key));
  if (unknownTopLevelKey) throw new ConfigValidationError(unknownTopLevelKey, 'Unbekannter Konfigurationsschluessel.');
  if (!isRecord(payload.router_rules)) {
    throw new ConfigValidationError('router_rules', 'Router-Regeln muessen ein Objekt sein.');
  }

  assertExactKeys(payload.router_rules, ROUTER_KEYS, 'router_rules');
  for (const routerKey of ROUTER_KEYS) {
    const rules = payload.router_rules[routerKey];
    const catalog = ROUTER_CATALOG[routerKey];
    const rulesPath = `router_rules.${routerKey}`;
    if (!Array.isArray(rules)) throw new ConfigValidationError(rulesPath, 'Router-Regeln muessen ein Array sein.');
    if (rules.length !== catalog.length) {
      throw new ConfigValidationError(rulesPath, `Exakt ${catalog.length} katalogisierte Eintraege erforderlich.`);
    }

    const seenIds = new Set<string>();
    rules.forEach((rule, index) => {
      const rulePath = `${rulesPath}[${index}]`;
      if (!isRecord(rule)) throw new ConfigValidationError(rulePath, 'Router-Eintrag muss ein Objekt sein.');
      assertExactKeys(rule, ROUTER_RULE_KEYS, rulePath);
      if (typeof rule.id !== 'string') throw new ConfigValidationError(`${rulePath}.id`, 'ID muss ein String sein.');
      if (seenIds.has(rule.id)) throw new ConfigValidationError(`${rulePath}.id`, 'ID ist doppelt vorhanden.');
      seenIds.add(rule.id);

      const canonical = catalog.find(candidate => candidate.id === rule.id);
      if (!canonical) throw new ConfigValidationError(`${rulePath}.id`, 'ID ist nicht im Run-Katalog enthalten.');
      if (rule.name !== canonical.name) throw new ConfigValidationError(`${rulePath}.name`, `Erwartet: ${canonical.name}.`);
      if (rule.script !== canonical.script) throw new ConfigValidationError(`${rulePath}.script`, `Erwartet: ${canonical.script}.`);
      if (typeof rule.enabled !== 'boolean') throw new ConfigValidationError(`${rulePath}.enabled`, 'Aktiv muss boolesch sein.');
      if (!ROUTER_MODE_WHITELIST.includes(rule.mode)) {
        throw new ConfigValidationError(`${rulePath}.mode`, 'Mode ist nicht erlaubt.');
      }
      if (!ROUTER_CONDITION_WHITELIST.includes(rule.condition)) {
        throw new ConfigValidationError(`${rulePath}.condition`, 'Condition ist nicht erlaubt.');
      }
      const condition = rule.condition as RouterCondition;
      if (!canonical.allowedConditions.includes(condition)) {
        throw new ConfigValidationError(`${rulePath}.condition`, 'Condition ist fuer diesen SUB-RUN nicht erlaubt.');
      }
      if (rule.dashboard_editable !== canonical.dashboardEditable) {
        throw new ConfigValidationError(`${rulePath}.dashboard_editable`, 'Katalogwert darf nicht geaendert werden.');
      }
      if (!isRecord(rule.condition_settings)) {
        throw new ConfigValidationError(`${rulePath}.condition_settings`, 'Condition-Settings muessen ein Objekt sein.');
      }

      const settingCatalog = CONDITION_SETTING_CATALOG[condition] || {};
      const unknownSetting = Object.keys(rule.condition_settings).find(key => !(key in settingCatalog));
      if (unknownSetting) {
        throw new ConfigValidationError(`${rulePath}.condition_settings.${unknownSetting}`, 'Zahlenfeld ist fuer diese Condition nicht erlaubt.');
      }
      for (const [settingKey, definition] of Object.entries(settingCatalog)) {
        if (!(settingKey in rule.condition_settings)) {
          throw new ConfigValidationError(`${rulePath}.condition_settings.${settingKey}`, 'Pflichtfeld fehlt.');
        }
        const value = rule.condition_settings[settingKey];
        if (!Number.isInteger(value) || value < definition.min || value > definition.max) {
          throw new ConfigValidationError(
            `${rulePath}.condition_settings.${settingKey}`,
            `Ganzzahl zwischen ${definition.min} und ${definition.max} erforderlich.`,
          );
        }
      }
    });
  }

  return payload;
}

function timestampForFile(date = new Date()): string {
  return date.toISOString().replace(/[-:.]/g, '');
}

export function writeJsonFileAtomic(filePath: string, data: unknown): void {
  ensureParentDir(filePath);
  const tempPath = path.join(
    path.dirname(filePath),
    `.${path.basename(filePath)}.${process.pid}.${Date.now()}.${Math.random().toString(16).slice(2)}.tmp`,
  );
  try {
    fs.writeFileSync(tempPath, `${JSON.stringify(data, null, 2)}\n`, { encoding: 'utf-8', flag: 'wx' });
    fs.renameSync(tempPath, filePath);
  } finally {
    if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath);
  }
}

export function backupAndWriteConfig(
  configPath: string,
  publicConfigPath: string,
  backupDir: string,
  config: unknown,
  now = new Date(),
): string | null {
  let backupPath: string | null = null;
  if (fs.existsSync(configPath)) {
    fs.mkdirSync(backupDir, { recursive: true });
    backupPath = path.join(backupDir, `autopilot-config-${timestampForFile(now)}.json`);
    fs.copyFileSync(configPath, backupPath, fs.constants.COPYFILE_EXCL);
  }
  writeJsonFileAtomic(configPath, config);
  writeJsonFileAtomic(publicConfigPath, config);
  return backupPath;
}

export function buildGitHubIssueListArgs(repository: string): string[] {
  return ['issue', 'list', '--repo', repository, '--limit', '1000', '--state', 'all', '--json', 'number,title,state,labels,assignees,body,createdAt,updatedAt,url'];
}

export function buildGitHubPrListArgs(repository: string): string[] {
  return ['pr', 'list', '--repo', repository, '--limit', '1000', '--state', 'open', '--json', 'number,title,state,mergeable,statusCheckRollup,headRefName,baseRefName,updatedAt,url,isDraft'];
}

export function buildGitHubLabelArgs(repository: string, label: string, description: string): string[] {
  return ['label', 'create', label, '--repo', repository, '--color', 'CCCCCC', '--description', description, '--force'];
}

export function buildGitHubIssueCreateArgs(repository: string, title: string, body: string, labels: readonly string[]): string[] {
  return [
    'issue',
    'create',
    '--repo',
    repository,
    '--title',
    title,
    '--body',
    body,
    ...labels.flatMap(label => ['--label', label]),
  ];
}

interface GitHubProcessResult {
  stdout: string | null;
  stderr: string | null;
  status: number | null;
  signal: NodeJS.Signals | null;
  error?: Error;
}

export function parseGitHubProcessResult(result: GitHubProcessResult, timeoutMs = GH_TIMEOUT_MS): string {
  const stdout = result.stdout || '';
  const stderr = result.stderr || '';
  if (result.error) {
    const timedOut = (result.error as NodeJS.ErrnoException).code === 'ETIMEDOUT';
    throw new Error(timedOut ? `gh timed out after ${timeoutMs}ms` : `gh failed to start: ${result.error.message}`);
  }
  if (result.signal) throw new Error(`gh terminated by signal ${result.signal}: ${stderr.trim()}`);
  if (result.status !== 0) throw new Error(`gh exited with code ${result.status}: ${stderr.trim() || stdout.trim()}`);
  return stdout;
}

function runGitHub(args: readonly string[]): string {
  const result = spawnSync('gh', [...args], {
    encoding: 'utf-8',
    windowsHide: true,
    timeout: GH_TIMEOUT_MS,
    maxBuffer: GH_MAX_BUFFER,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return parseGitHubProcessResult(result);
}

function ensureParentDir(filePath: string): void {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function writeJsonFile(filePath: string, data: unknown): void {
  ensureParentDir(filePath);
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf-8');
}

function readJsonFile(filePath: string, fallback: any = null): any {
  if (!fs.existsSync(filePath)) return fallback;
  return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
}

function parseRunName(actualName: string): string {
  return actualName.split('__').pop()?.replace(/^SUB-RUN-\d+_MR-\d+_/, '').replace(/^PART-RUN-\d+_MR-\d+_/, '') || actualName;
}

function firstCommentLine(filePath: string): string {
  if (!fs.existsSync(filePath)) return '';
  const line = fs.readFileSync(filePath, 'utf-8')
    .split(/\r?\n/)
    .find(item => item.trim().startsWith('#') && !item.includes('ps1'));
  return line ? line.replace(/^#\s*/, '').trim() : '';
}

function getRunCatalog(): any {
  const config = readJsonFile(CONFIG_PATH, {});
  const promptsDir = path.join(VORCE_ROOT, 'var/prompts');
  const promptRegistry = getPromptRegistry(promptsDir);
  const promptEntries = Object.entries(promptRegistry).map(([key, metadata]) => ({
    key,
    path: metadata.path.replace(/\\/g, '/'),
    content: fs.existsSync(path.resolve(promptsDir, metadata.path))
      ? fs.readFileSync(path.resolve(promptsDir, metadata.path), 'utf-8')
      : '',
  }));
  const promptForPath = (matcher: (entry: { key: string; path: string; content: string }) => boolean) =>
    promptEntries.find(matcher) || null;
  const runsRoot = path.join(VORCE_ROOT, 'src/runs');
  return {
    main_runs: MAIN_RUNS.map(definition => {
      const mainDir = path.join(runsRoot, definition.name);
      const mainPrompt = promptForPath(entry =>
        entry.path.startsWith(`runs/${definition.name}/MAIN-RUN-PROMPT`)
      );
      const configuredById = new Map<string, any>(
        (Array.isArray(config.router_rules?.[definition.routerKey]) ? config.router_rules[definition.routerKey] : [])
          .map((rule: any): [string, any] => [String(rule.id), rule]),
      );
      const subRuns = ROUTER_CATALOG[definition.routerKey].map(canonicalRule => {
        const configuredRule = configuredById.get(canonicalRule.id) || {};
        const rule = {
          ...configuredRule,
          id: canonicalRule.id,
          name: canonicalRule.name,
          script: canonicalRule.script,
          enabled: configuredRule.enabled !== false,
          mode: ROUTER_MODE_WHITELIST.includes(configuredRule.mode) ? configuredRule.mode : canonicalRule.defaultMode,
          condition: canonicalRule.allowedConditions.includes(configuredRule.condition)
            ? configuredRule.condition
            : canonicalRule.defaultCondition,
          condition_settings: isRecord(configuredRule.condition_settings) ? configuredRule.condition_settings : {},
          dashboard_editable: canonicalRule.dashboardEditable,
        };
        const ruleCondition = rule.condition as RouterCondition;
        const scriptPath = path.join(VORCE_ROOT, rule.script || '');
        const subDir = path.dirname(scriptPath);
        const actualName = path.basename(subDir);
        const partsDir = path.join(subDir, 'PART-RUNS');
        const partRuns = fs.existsSync(partsDir)
          ? fs.readdirSync(partsDir)
            .filter(file => file.endsWith('.ps1'))
            .sort()
            .map(file => {
              const partName = path.basename(file, '.ps1');
              const partPath = path.join(partsDir, file);
              const partOrdinal = partName.match(/^PART-RUN-(\d+)_/)?.[1] || '';
              const partPrompt = promptForPath(entry =>
                entry.path.includes(`/${actualName}/`) &&
                entry.path.includes(`PART-RUN-PROMPT-${partOrdinal}_`)
              );
              return {
                name: partName,
                label: parseRunName(partName),
                script: path.relative(VORCE_ROOT, partPath).replace(/\\/g, '/'),
                description: firstCommentLine(partPath),
                prompt_key: partPrompt?.key || '',
                system_prompt: partPrompt?.content || '',
              };
            })
          : [];

        return {
          id: rule.id,
          name: actualName,
          label: rule.name || parseRunName(actualName),
          script: rule.script,
          enabled: rule.enabled !== false,
          mode: rule.mode,
          condition: rule.condition,
          condition_settings: rule.condition_settings,
          dashboard_editable: rule.dashboard_editable,
          allowed_conditions: canonicalRule.allowedConditions,
          condition_settings_schema: CONDITION_SETTING_CATALOG[ruleCondition] || {},
          condition_settings_schemas: Object.fromEntries(
            canonicalRule.allowedConditions.map(condition => [condition, CONDITION_SETTING_CATALOG[condition] || {}]),
          ),
          description: firstCommentLine(scriptPath),
          system_prompt: `Koordiniere ${rule.name || parseRunName(actualName)}. Fuehre die aktivierten PART-RUNs in der definierten Reihenfolge aus und liefere nur Status, Ergebnis und naechste Aktion zurueck.`,
          part_runs: partRuns,
        };
      });

      return {
        ...definition,
        actualName: definition.name,
        path: path.relative(VORCE_ROOT, mainDir).replace(/\\/g, '/'),
        interval_minutes: Number(config.wake_intervals?.[definition.intervalKey] || 0),
        description: firstCommentLine(path.join(mainDir, `${definition.routerKey}-Router.ps1`)),
        prompt_key: mainPrompt?.key || '',
        system_prompt: mainPrompt?.content || '',
        sub_runs: subRuns,
        part_run_count: subRuns.reduce((sum: number, sub: any) => sum + sub.part_runs.length, 0),
      };
    }),
  };
}

function getRunHierarchy(): any {
  return buildRunHierarchy({
    vorceRoot: VORCE_ROOT,
    configPath: CONFIG_PATH,
    runStatesDir: RUN_STATES_DIR,
  });
}

function getRunSummary(limit = 10): any {
  const boundedLimit = Math.max(1, Math.min(100, Math.trunc(limit) || 10));
  const listJsonFiles = (directory: string): string[] => {
    if (!fs.existsSync(directory)) return [];
    return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
      const entryPath = path.join(directory, entry.name);
      if (entry.isDirectory()) return listJsonFiles(entryPath);
      return entry.isFile() && entry.name.endsWith('.json') ? [entryPath] : [];
    });
  };
  const historyFiles = listJsonFiles(RUN_HISTORY_DIR);

  const mainRuns = historyFiles
    .map(file => {
      try {
        const state = readJsonFile(file, null);
        return state && state.type === 'MAIN' ? state : null;
      } catch {
        return null;
      }
    })
    .filter(Boolean)
    .sort((a: any, b: any) => new Date(b.completed_at || b.started_at).getTime() - new Date(a.completed_at || a.started_at).getTime());

  const descendants = (state: any): any[] => {
    const nodes: any[] = [];
    const visit = (node: any) => {
      if (!node || typeof node !== 'object') return;
      nodes.push(node);
      for (const property of ['results', 'parts']) {
        for (const child of Array.isArray(node[property]) ? node[property] : []) visit(child);
      }
    };
    visit(state);
    return nodes;
  };
  const metricsFor = (state: any) => {
    const nodes = descendants(state);
    const attempts = new Map<string, any>();
    let fallbacks = 0;
    for (const node of nodes) {
      const nodeAttempts = Array.isArray(node.attempts) ? node.attempts : [];
      fallbacks += Math.max(0, nodeAttempts.length - 1);
      nodeAttempts.forEach((attempt: any, index: number) => {
        const key = String(attempt?.attempt_id || `${attempt?.provider || ''}|${attempt?.model || ''}|${attempt?.started_at || ''}|${attempt?.exit_code ?? ''}|${index}`);
        if (!attempts.has(key)) attempts.set(key, attempt);
      });
    }
    const attemptList = [...attempts.values()];
    const errorClasses = [
      ...nodes.filter(node => !Array.isArray(node.attempts) || node.attempts.length === 0).map(node => node.error_class).filter(Boolean),
      ...attemptList.map(attempt => attempt.error_class).filter(Boolean),
    ];
    const numberFrom = (value: unknown) => Number.isFinite(Number(value)) ? Number(value) : 0;
    return {
      provider_attempts: attemptList.length,
      fallbacks,
      timeout_errors: errorClasses.filter(value => value === 'timeout').length,
      rate_limit_errors: errorClasses.filter(value => value === 'rate_limited' || value === 'quota_exhausted').length,
      auth_errors: errorClasses.filter(value => value === 'auth_missing').length,
      estimated_cost_usd: attemptList.reduce((sum, attempt) => sum + numberFrom(attempt.estimated_cost_usd ?? attempt.usage?.estimated_cost_usd ?? attempt.cost_usd), 0),
      input_tokens: attemptList.reduce((sum, attempt) => sum + numberFrom(attempt.input_tokens ?? attempt.usage?.input_tokens), 0),
      output_tokens: attemptList.reduce((sum, attempt) => sum + numberFrom(attempt.output_tokens ?? attempt.usage?.output_tokens), 0),
      resume_count: numberFrom(state.resume_count ?? state.resume?.resume_count ?? state.metadata?.resume_count),
      no_work: nodes.filter(node =>
        node.status === 'no_work'
        || node.outcome === 'no_work'
        || node.result_status === 'no_work'
        || node.metadata?.outcome === 'no_work'
      ).length,
    };
  };
  const primaryError = (state: any): string | null => {
    if (state.error) return String(state.error);
    const failed = descendants(state).find(node => node.status === 'failed' && node.error);
    return failed ? String(failed.error) : null;
  };
  const resultSummary = (state: any): string => {
    const metrics = metricsFor(state);
    const text = String(
      state.metadata?.result_summary
      || state.result_summary
      || `Sub-Runs: ${(state.results || []).length}, Attempts: ${metrics.provider_attempts}, Fallbacks: ${metrics.fallbacks}, Reused: ${descendants(state).filter(node => node.status === 'reused').length}`
    );
    return text.length > 160 ? `${text.slice(0, 157)}...` : text;
  };

  const summarizeWindow = (days: number) => {
    const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;
    const selected = mainRuns.filter((state: any) => new Date(state.completed_at || state.started_at).getTime() >= cutoff);
    const durations = selected
      .map((state: any) => {
        const started = new Date(state.started_at || 0).getTime();
        const completed = new Date(state.completed_at || state.started_at || 0).getTime();
        return Math.max(0, completed - started);
      })
      .filter((value: number) => value > 0)
      .sort((a: number, b: number) => a - b);
    const allResults = selected.flatMap((state: any) => state.results || []);
    const allParts = selected.flatMap((state: any) => (state.results || []).flatMap((result: any) => result.parts || []));
    const metrics = selected.map(metricsFor);
    const p95Index = durations.length ? Math.min(durations.length - 1, Math.ceil(durations.length * 0.95) - 1) : -1;
    const sumMetric = (key: keyof ReturnType<typeof metricsFor>) =>
      metrics.reduce((sum, item) => sum + Number(item[key] || 0), 0);

    return {
      runs_started: selected.length,
      runs_completed: selected.filter((state: any) => state.status === 'completed').length,
      runs_failed: selected.filter((state: any) => state.status === 'failed').length,
      runs_waiting_provider: selected.filter((state: any) => state.status === 'waiting_provider').length,
      success_rate: selected.length ? selected.filter((state: any) => state.status === 'completed').length / selected.length : 0,
      avg_duration_ms: durations.length ? Math.round(durations.reduce((sum: number, value: number) => sum + value, 0) / durations.length) : 0,
      p95_duration_ms: p95Index >= 0 ? durations[p95Index] : 0,
      sub_runs_completed: allResults.filter((result: any) => result.status === 'completed').length,
      sub_runs_failed: allResults.filter((result: any) => result.status === 'failed').length,
      sub_runs_skipped: allResults.filter((result: any) => result.status === 'skipped').length,
      sub_runs_reused: allResults.filter((result: any) => result.status === 'reused').length,
      part_runs_completed: allParts.filter((part: any) => part.status === 'completed').length,
      part_runs_failed: allParts.filter((part: any) => part.status === 'failed').length,
      part_runs_skipped: allParts.filter((part: any) => part.status === 'skipped').length,
      part_runs_reused: allParts.filter((part: any) => part.status === 'reused').length,
      provider_attempts: sumMetric('provider_attempts'),
      fallbacks: sumMetric('fallbacks'),
      timeout_errors: sumMetric('timeout_errors'),
      rate_limit_errors: sumMetric('rate_limit_errors'),
      auth_errors: sumMetric('auth_errors'),
      estimated_cost_usd: sumMetric('estimated_cost_usd'),
      input_tokens: sumMetric('input_tokens'),
      output_tokens: sumMetric('output_tokens'),
      resume_count: sumMetric('resume_count'),
      no_work: sumMetric('no_work'),
    };
  };

  return {
    generated_at: new Date().toISOString(),
    recent_runs: mainRuns.slice(0, boundedLimit).map((state: any) => {
      const metrics = metricsFor(state);
      const subRuns = Array.isArray(state.results) ? state.results : [];
      const parts = subRuns.flatMap((result: any) => Array.isArray(result.parts) ? result.parts : []);
      return {
        run_id: state.id,
        main_run: state.name,
        status: state.status,
        started_at: state.started_at,
        completed_at: state.completed_at,
        duration_ms: state.duration_ms || 0,
        sub_runs: {
          completed: subRuns.filter((result: any) => result.status === 'completed').length,
          failed: subRuns.filter((result: any) => result.status === 'failed').length,
          skipped: subRuns.filter((result: any) => result.status === 'skipped').length,
          reused: subRuns.filter((result: any) => result.status === 'reused').length,
        },
        part_runs: {
          completed: parts.filter((part: any) => part.status === 'completed').length,
          failed: parts.filter((part: any) => part.status === 'failed').length,
          skipped: parts.filter((part: any) => part.status === 'skipped').length,
          reused: parts.filter((part: any) => part.status === 'reused').length,
        },
        ...metrics,
        result_summary: resultSummary(state),
        primary_error: primaryError(state),
      };
    }),
    stats_24h: summarizeWindow(1),
    stats_7d: summarizeWindow(7),
  };
}

function readRuntimeState(): any {
  const globalState = readJsonFile(GLOBAL_STATE_PATH, {});
  const dashboardState = readJsonFile(DASHBOARD_STATE_PATH, {});
  const config = readJsonFile(CONFIG_PATH, {});
  const runStates = fs.existsSync(RUN_STATES_DIR)
    ? fs.readdirSync(RUN_STATES_DIR)
      .filter(file => file.endsWith('.json') && !file.includes('_VALIDATE-'))
      .map(file => {
        try {
          return readJsonFile(path.join(RUN_STATES_DIR, file), null);
        } catch {
          return null;
        }
      })
      .filter(Boolean)
    : [];
  const now = Date.now();
  const mainRuns = MAIN_RUNS.map(definition => {
    const intervalMinutes = Number(config.wake_intervals?.[definition.intervalKey] ?? 0);
    const lastRunAt = globalState.last_runs?.[definition.name] || null;
    const nextRunTimestamp = lastRunAt
      ? new Date(lastRunAt).getTime() + intervalMinutes * 60_000
      : now;
    const latestState = runStates.find(state => state.type === 'MAIN' && state.name === definition.name) || null;
    const subRunNames = (config.router_rules?.[definition.routerKey] || []).map((rule: any) => rule.name);
    const subRuns = subRunNames.map((name: string) =>
      runStates.find(state =>
        (state.type === 'SUB' && (state.name === name || state.name?.endsWith(`__${name}`)))
        || state.sub_run?.endsWith(`__${name}`)
      )
      || { name, type: 'SUB', status: 'not_started' }
    );
    const control = dashboardState.run_control?.main_runs?.[definition.name] || {};

    return {
      ...definition,
      interval_minutes: intervalMinutes,
      last_run_at: lastRunAt,
      next_run_at: new Date(nextRunTimestamp).toISOString(),
      next_run_in_seconds: Math.max(0, Math.round((nextRunTimestamp - now) / 1000)),
      status: latestState?.status || 'not_started',
      summary: latestState
        ? `${latestState.results?.length || 0} Sub-Runs, Status: ${latestState.status}`
        : 'Noch kein Lauf dokumentiert.',
      latest_state: latestState,
      sub_runs: subRuns,
      control,
    };
  });

  return {
    schema_version: 3,
    session_id: 'vorce-autopilot-3',
    started_at: globalState.started_at || globalState.last_run || '',
    last_heartbeat: globalState.last_run || '',
    ...globalState,
    ...dashboardState,
    decisions_pending: dashboardState.decisions_pending || globalState.escalated_issues || [],
    active_delegations: globalState.active_delegations || [],
    review_queue: globalState.review_queue || [],
    autopilot_created_issues: dashboardState.autopilot_created_issues || globalState.autopilot_created_issues || [],
    completed_this_session: dashboardState.completed_this_session || globalState.completed_this_session || [],
    run_control: dashboardState.run_control || { main_runs: {} },
    main_runs: mainRuns,
    run_states: runStates,
  };
}

function readDashboardState(): any {
  return readJsonFile(DASHBOARD_STATE_PATH, {});
}

function writeDashboardState(state: any): void {
  writeJsonFile(DASHBOARD_STATE_PATH, state);
}

function startMainRun(mainRun: string): void {
  if (!MAIN_RUN_NAMES.has(mainRun as any)) throw new Error('Invalid MAIN-RUN');
  const autopilotPath = path.join(VORCE_ROOT, 'autopilot.ps1');
  const child = spawn('pwsh', [
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', autopilotPath,
    '-RunOnce',
    '-ForceMainRun', mainRun,
  ], {
    cwd: VORCE_ROOT,
    stdio: 'ignore',
    windowsHide: true,
  });
  child.on('error', error => {
    console.error(`[API] Failed to start ${mainRun}:`, error);
  });
}

function serveFirstJson(res: any, candidates: string[], fallback: unknown): void {
  const filePath = candidates.find(candidate => fs.existsSync(candidate));
  const data = filePath ? readJsonFile(filePath, fallback) : fallback;
  res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(data, null, 2));
}

function getRepository(): string {
  try {
    const configPath = path.resolve(__dirname, '../../var/config/autopilot-config.json');
    if (fs.existsSync(configPath)) {
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
      if (config && config.repository) {
        return config.repository;
      }
    }
  } catch {
    // Use the configured fallback below.
  }
  return 'Vorce-Studios/Vorce';
}

function getPromptRegistry(promptsDir: string): Record<string, { path: string }> {
  return readJsonFile(path.join(promptsDir, 'prompt-registry.json'), { prompts: {} }).prompts || {};
}

function loadRegisteredPrompts(promptsDir: string): Record<string, string> {
  const prompts: Record<string, string> = {};
  for (const [key, metadata] of Object.entries(getPromptRegistry(promptsDir))) {
    const promptPath = path.resolve(promptsDir, metadata.path);
    if (fs.existsSync(promptPath)) {
      prompts[key] = fs.readFileSync(promptPath, 'utf-8');
    }
  }
  return prompts;
}

export default defineConfig({
  root: __dirname,
  plugins: [
    react(),
    {
      name: 'api-middleware',
      configureServer(server) {
        server.middlewares.use((req: any, res: any, next: any) => {
          if (req.method === 'GET' && req.url === '/api/health') {
            res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
            res.end(JSON.stringify({ service: 'vorce-autopilot-dashboard', root: path.resolve(__dirname, '../..'), schema: 2 }));
          } else if (req.method === 'GET' && req.url === '/active-sessions.json') {
            try {
              const state = readRuntimeState();
              res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
              res.end(JSON.stringify(state, null, 2));
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url === '/autopilot-config.json') {
            try {
              const configPath = path.resolve(__dirname, '../../var/config/autopilot-config.json');
              if (fs.existsSync(configPath)) {
                const configContent = fs.readFileSync(configPath, 'utf-8');
                const config = JSON.parse(configContent);

                const promptsDir = path.resolve(__dirname, '../../var/prompts');
                config.prompts = loadRegisteredPrompts(promptsDir);

                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify(config, null, 2));
              } else {
                res.writeHead(404, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'autopilot-config.json not found' }));
              }
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url === '/run-catalog.json') {
            try {
              const catalog = getRunCatalog();
              res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
              res.end(JSON.stringify(catalog, null, 2));
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url?.startsWith('/run-summary.json')) {
            try {
              const url = new URL(req.url, 'http://localhost');
              const limit = Number(url.searchParams.get('limit') || '10');
              const summary = getRunSummary(Number.isFinite(limit) && limit > 0 ? limit : 10);
              res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
              res.end(JSON.stringify(summary, null, 2));
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url === '/run-hierarchy.json') {
            try {
              const hierarchy = getRunHierarchy();
              res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
              res.end(JSON.stringify(hierarchy, null, 2));
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && (req.url === '/registry.json' || req.url === '/quota-registry.json')) {
            try {
              serveFirstJson(res, [
                path.resolve(__dirname, '../../var/db/registry.json'),
                path.resolve(__dirname, '../../var/db/quota-registry.json'),
                path.resolve(__dirname, '../../var/config/quota-registry.json'),
              ], {});
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url === '/jules-sessions.json') {
            try {
              serveFirstJson(res, [
                path.resolve(__dirname, '../../var/db/jules-sessions.json'),
                path.resolve(__dirname, './jules-sessions.json'),
              ], []);
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url === '/project-items.json') {
            try {
              serveFirstJson(res, [
                path.resolve(__dirname, '../../var/db/project-items.json'),
                path.resolve(__dirname, './project-items.json'),
              ], { items: [] });
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url === '/data.json') {
            try {
              serveFirstJson(res, [
                path.resolve(__dirname, '../../var/db/data.json'),
                path.resolve(__dirname, './data.json'),
              ], []);
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url === '/audit-result.json') {
            try {
              serveFirstJson(res, [
                path.resolve(__dirname, '../../var/db/beta-audit-result.json'),
                path.resolve(__dirname, './audit-result.json'),
              ], null);
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url === '/live-log.json') {
            try {
              const logPath = path.resolve(__dirname, '../../var/log/autopilot-live.log');
              const content = fs.existsSync(logPath) ? fs.readFileSync(logPath, 'utf-8') : '';
              res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
              res.end(JSON.stringify({ content }));
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url === '/github-issues.json') {
            const now = Date.now();
            if (issuesCache && (now - issuesCacheTime < CACHE_TTL)) {
              res.writeHead(200, { 'Content-Type': 'application/json' });
              res.end(issuesCache);
            } else {
              try {
                const repos = [getRepository()];
                if (repos[0] === 'Vorce-Studios/Vorce') {
                  repos.push('MrLongNight/MapFlow');
                }
                let allIssues: any[] = [];
                let successfulRepos = 0;
                for (const r of repos) {
                  try {
                    const issuesJson = runGitHub(buildGitHubIssueListArgs(r));
                    const parsed = JSON.parse(issuesJson);
                    if (Array.isArray(parsed)) {
                      successfulRepos++;
                      parsed.forEach((issue: any) => issue.repo = r);
                      allIssues = allIssues.concat(parsed);
                    }
                  } catch {
                    // Skip repositories that cannot be queried.
                  }
                }
                if (successfulRepos === 0) throw new Error('No GitHub issue source was available');
                const responseJson = JSON.stringify(allIssues);
                issuesCache = responseJson;
                issuesCacheTime = now;
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(responseJson);
              } catch {
                // Fallback to static public file if GH command fails
                const fallbackPath = [
                  path.resolve(__dirname, '../../var/db/github-issues.json'),
                  path.resolve(__dirname, './github-issues.json'),
                  path.resolve(__dirname, './public/github-issues.json'),
                ].find(candidate => fs.existsSync(candidate));
                if (fallbackPath) {
                  const fallbackContent = fs.readFileSync(fallbackPath, 'utf-8');
                  res.writeHead(200, { 'Content-Type': 'application/json' });
                  res.end(fallbackContent);
                } else {
                  res.writeHead(500, { 'Content-Type': 'application/json' });
                  res.end(JSON.stringify({ error: 'Failed to fetch issues and no fallback found' }));
                }
              }
            }
          } else if (req.method === 'GET' && req.url === '/pull-requests.json') {
            const now = Date.now();
            if (prsCache && (now - prsCacheTime < CACHE_TTL)) {
              res.writeHead(200, { 'Content-Type': 'application/json' });
              res.end(prsCache);
            } else {
              try {
                const repos = [getRepository()];
                if (repos[0] === 'Vorce-Studios/Vorce') {
                  repos.push('MrLongNight/MapFlow');
                }
                let allPRs: any[] = [];
                let successfulRepos = 0;
                for (const r of repos) {
                  try {
                    const prsJson = runGitHub(buildGitHubPrListArgs(r));
                    const parsed = JSON.parse(prsJson);
                    if (Array.isArray(parsed)) {
                      successfulRepos++;
                      parsed.forEach((pr: any) => pr.repo = r);
                      allPRs = allPRs.concat(parsed);
                    }
                  } catch {
                    // Skip repositories that cannot be queried.
                  }
                }
                if (successfulRepos === 0) throw new Error('No GitHub PR source was available');
                const responseJson = JSON.stringify(allPRs);
                prsCache = responseJson;
                prsCacheTime = now;
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(responseJson);
              } catch {
                // Fallback to static public file if GH command fails
                const fallbackPath = [
                  path.resolve(__dirname, '../../var/db/pull-requests.json'),
                  path.resolve(__dirname, './pull-requests.json'),
                  path.resolve(__dirname, './public/pull-requests.json'),
                ].find(candidate => fs.existsSync(candidate));
                if (fallbackPath) {
                  const fallbackContent = fs.readFileSync(fallbackPath, 'utf-8');
                  res.writeHead(200, { 'Content-Type': 'application/json' });
                  res.end(fallbackContent);
                } else {
                  res.writeHead(500, { 'Content-Type': 'application/json' });
                  res.end(JSON.stringify({ error: 'Failed to fetch PRs and no fallback found' }));
                }
              }
            }
          } else if (req.method === 'POST' && req.url === '/api/config') {
            let body = '';
            req.on('data', (chunk: any) => { body += chunk; });
            req.on('end', () => {
              try {
                const config = validateDashboardConfig(JSON.parse(body));

                // Write modified prompts back to their respective markdown files
                if (config.prompts) {
                  const promptsDir = path.resolve(__dirname, '../../var/prompts');
                  const registry = getPromptRegistry(promptsDir);
                  const findPromptFile = (key: string) =>
                    registry[key]?.path ? path.resolve(promptsDir, registry[key].path) : null;

                  for (const key of Object.keys(config.prompts)) {
                    const promptFile = findPromptFile(key);
                    if (promptFile) {
                      fs.writeFileSync(promptFile, config.prompts[key], 'utf-8');
                      delete config.prompts[key]; // Do not store dynamically resolved prompts in JSON
                    }
                  }
                  if (Object.keys(config.prompts).length === 0) {
                    delete config.prompts;
                  }
                }

                const configPath = CONFIG_PATH;
                const publicConfigPath = path.resolve(__dirname, './public/autopilot-config.json');
                const backupPath = backupAndWriteConfig(
                  configPath,
                  publicConfigPath,
                  CONFIG_BACKUP_DIR,
                  config,
                );
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'ok', message: 'Autopilot config saved', backup_path: backupPath }));
              } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({
                  status: 'error',
                  field: err instanceof ConfigValidationError ? err.fieldPath : '$',
                  message: err instanceof Error ? err.message : String(err),
                }));
              }
            });
          } else if (req.method === 'POST' && req.url === '/api/quota') {
            let body = '';
            req.on('data', (chunk: any) => { body += chunk; });
            req.on('end', () => {
              try {
                const quota = JSON.parse(body);
                const quotaPath = path.resolve(__dirname, '../../var/db/quota-registry.json');
                const publicRegistryPath = path.resolve(__dirname, './public/registry.json');
                const publicDataPath = path.resolve(__dirname, './public/data.json');
                writeJsonFile(quotaPath, quota);
                writeJsonFile(publicRegistryPath, quota);
                writeJsonFile(publicDataPath, quota);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'ok', message: 'Quota registry saved' }));
              } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'error', message: err instanceof Error ? err.message : String(err) }));
              }
            });
          } else if (req.method === 'GET' && req.url === '/memories.json') {
            try {
              const memoryPath = path.resolve(__dirname, '../../var/db/autopilot-memories.json');
              // Initialize from template memories.json if not present
              if (!fs.existsSync(memoryPath)) {
                const defaultMemoriesPath = path.resolve(__dirname, './memories.json');
                if (fs.existsSync(defaultMemoriesPath)) {
                  ensureParentDir(memoryPath);
                  fs.copyFileSync(defaultMemoriesPath, memoryPath);
                }
              }
              if (fs.existsSync(memoryPath)) {
                const memoryContent = fs.readFileSync(memoryPath, 'utf-8');
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(memoryContent);
              } else {
                const defaultStore = { schema_version: 1, memories: [] };
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify(defaultStore));
              }
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'POST' && req.url === '/api/memories') {
            let body = '';
            req.on('data', (chunk: any) => { body += chunk; });
            req.on('end', () => {
              try {
                const payload = JSON.parse(body);
                const memoryPath = path.resolve(__dirname, '../../var/db/autopilot-memories.json');
                const publicMemoryPath = path.resolve(__dirname, './public/memories.json');

                let store = { schema_version: 1, memories: [] as any[] };
                if (fs.existsSync(memoryPath)) {
                  store = JSON.parse(fs.readFileSync(memoryPath, 'utf-8'));
                }

                if (payload.action === 'add') {
                  const newEntry = {
                    id: `mem-${Date.now()}-${Math.random().toString(36).substr(2, 4)}`,
                    text: payload.entry.text,
                    type: payload.entry.type || 'temporary',
                    priority: payload.entry.priority || 'medium',
                    created_at: new Date().toISOString(),
                    source: payload.entry.source || 'dashboard'
                  };

                  if (store.memories.length >= 30) {
                    throw new Error('Maximum von 30 Erinnerungen erreicht. Loeschen Sie alte Eintraege zuerst.');
                  }

                  store.memories.push(newEntry);
                } else if (payload.action === 'remove') {
                  store.memories = store.memories.filter((m: any) => m.id !== payload.id);
                } else {
                  throw new Error('Ungueltige Aktion.');
                }

                const storeStr = JSON.stringify(store, null, 2);
                ensureParentDir(memoryPath);
                ensureParentDir(publicMemoryPath);
                fs.writeFileSync(memoryPath, storeStr, 'utf-8');
                fs.writeFileSync(publicMemoryPath, storeStr, 'utf-8');

                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'ok', message: 'Memories updated successfully' }));
              } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'error', message: err instanceof Error ? err.message : String(err) }));
              }
            });
          } else if (req.method === 'POST' && req.url === '/api/alerts') {
            let body = '';
            req.on('data', (chunk: any) => { body += chunk; });
            req.on('end', () => {
              try {
                const payload = JSON.parse(body || '{}');
                const memoryPath = path.resolve(__dirname, '../../var/db/autopilot-memories.json');
                const publicMemoryPath = path.resolve(__dirname, './public/memories.json');
                const state = readDashboardState();

                if (!Array.isArray(state.decisions_pending)) state.decisions_pending = [];

                // NEW: Handle "close-alert" action - mark alert as closed with optional comment
                if (payload.action === 'close-alert') {
                  const alert = state.decisions_pending.find((item: any, idx: number) => String(item.id || idx) === String(payload.id));
                  if (alert) {
                    alert.status = 'closed';
                    alert.closed_by = 'user';
                    alert.closed_at = new Date().toISOString();
                    alert.user_comment = payload.comment || 'Manuell geschlossen';
                    writeDashboardState(state);
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ status: 'ok', message: 'Alert geschlossen', alert }));
                    return;
                  }
                }

                // NEW: Handle "ignore-alert" action - mark alert as ignored and create memory
                if (payload.action === 'ignore-alert') {
                  const alert = state.decisions_pending.find((item: any, idx: number) => String(item.id || idx) === String(payload.id));
                  if (alert) {
                    alert.status = 'ignored';
                    alert.closed_by = 'user';
                    alert.closed_at = new Date().toISOString();
                    alert.user_comment = payload.comment || 'Ignoriert (repeat-accept)';

                    // Create memory for this alert so it won't reappear
                    let memoryCreated = false;
                    try {
                      let store = { schema_version: 1, memories: [] as any[] };
                      if (fs.existsSync(memoryPath)) {
                        store = JSON.parse(fs.readFileSync(memoryPath, 'utf-8'));
                      }

                      const memoryEntry = {
                        id: `mem-${Date.now()}-${Math.random().toString(36).substr(2, 4)}`,
                        text: `IGNORE_ALERT: ${alert.topic}\nDetails: ${alert.context}\nUser-Kommentar: ${alert.user_comment}`,
                        type: 'temporary',
                        priority: 'medium',
                        created_at: new Date().toISOString(),
                        source: 'dashboard_alert_ignore'
                      };

                      if (store.memories.length >= 30) {
                        // Remove oldest non-critical memory
                        const nonCritical = store.memories.filter((m: any) => m.priority !== 'critical');
                        if (nonCritical.length > 0) {
                          const oldest = nonCritical.sort((a: any, b: any) =>
                            new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
                          )[0];
                          store.memories = store.memories.filter((m: any) => m.id !== oldest.id);
                        }
                      }

                      store.memories.push(memoryEntry);
                      fs.writeFileSync(memoryPath, JSON.stringify(store, null, 2), 'utf-8');
                      fs.writeFileSync(publicMemoryPath, JSON.stringify(store, null, 2), 'utf-8');
                      memoryCreated = true;
                      console.log(`[API] Memory created for ignored alert: ${alert.topic}`);
                    } catch (memErr) {
                      console.error(`[API] Failed to create memory:`, memErr);
                    }

                    writeDashboardState(state);
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({
                      status: 'ok',
                      message: 'Alert ignoriert und Memory erstellt',
                      alert,
                      memory_created: memoryCreated
                    }));
                    return;
                  }
                }

                if (payload.action === 'clear') {
                  state.decisions_pending = [];
                } else if (payload.action === 'remove') {
                  state.decisions_pending = state.decisions_pending.filter((alert: any, idx: number) => String(alert.id || idx) !== String(payload.id));
                } else if (payload.action === 'escalate-user') {
                  const alert = state.decisions_pending.find((item: any, idx: number) => String(item.id || idx) === String(payload.id));
                  if (alert) {
                    alert.owner = 'user';
                    alert.status = 'awaiting_user';
                    alert.process_stage = 'user_decision';
                    alert.escalation_level = 'user';
                    alert.user_escalation_reason = payload.response || 'CEO Sondersession konnte die Ursache nicht beheben. Deine Entscheidung ist erforderlich.';
                    alert.user_escalated_at = new Date().toISOString();
                  }
                }

                writeDashboardState(state);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'ok' }));
              } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'error', message: err instanceof Error ? err.message : String(err) }));
              }
            });
          } else if (req.method === 'POST' && req.url === '/api/optimizer') {
            let body = '';
            req.on('data', (chunk: any) => { body += chunk; });
            req.on('end', () => {
              try {
                const payload = JSON.parse(body || '{}');
                const state = readDashboardState();
                let startOptimizerProcess = false;

                state.optimizer_queue = state.optimizer_queue || [];

                if (payload.action === 'reject') {
                  state.optimizer_queue = state.optimizer_queue.filter((item: any) => item.id !== payload.id);
                } else if (payload.action === 'run-now') {
                  state.run_control = state.run_control || { main_runs: {} };
                  state.run_control.force_optimizer_requested_at = new Date().toISOString();
                  startOptimizerProcess = true;
                } else if (payload.action === 'approve') {
                  const item = state.optimizer_queue.find((i: any) => i.id === payload.id);
                  if (item) {
                    // Create GitHub issue using gh CLI following naming conventions: __MF-SubI_Optimizer-[Title]
                    const cleanTitle = item.title.replace(/[^a-zA-Z0-9\s_-]/g, '').trim().replace(/\s+/g, '-');
                    const title = `__MF-SubI_Optimizer-${cleanTitle}`;
                    const issueBody = `Vorgeschlagene Optimierung aus der Optimizer-Session:\n\n**Beschreibung:**\n${item.description}\n\n**Auswirkung:**\n${item.impact}\n\n**Vorgeschlagene Aktion:**\n${item.proposed_action}`;

                    try {
                      const repo = getRepository();
                      const labels = [
                        ['priority: high', 'High priority'],
                        ['bug', 'Bug'],
                        ['agent:gemini_cli', 'Gemini CLI agent'],
                      ] as const;
                      for (const [label, description] of labels) {
                        runGitHub(buildGitHubLabelArgs(repo, label, description));
                      }
                      const issueUrl = runGitHub(
                        buildGitHubIssueCreateArgs(repo, title, issueBody, labels.map(([label]) => label)),
                      ).trim();

                      const match = issueUrl.match(/\/issues\/(\d+)/);
                      if (match) {
                        const issueNum = parseInt(match[1]);
                        // Add to working queue
                        state.working_queue = state.working_queue || [];
                        state.working_queue.push({
                          id: `work-${issueNum}-${Date.now()}`,
                          issue_number: issueNum,
                          issue_title: title,
                          agent_provider: "gemini_cli",
                          status: "QUEUED",
                          queued_at: new Date().toISOString()
                        });
                      }
                    } catch (e) {
                      throw new Error(`Fehler beim Erstellen des GitHub Issues: ${(e as any).message}`);
                    }

                    state.optimizer_last_run = state.optimizer_last_run || {};
                    state.optimizer_last_run.approved_changes = Array.isArray(state.optimizer_last_run.approved_changes) ? state.optimizer_last_run.approved_changes : [];
                    state.optimizer_last_run.approved_changes.push({
                      id: item.id,
                      title: item.title,
                      description: item.description,
                      impact: item.impact,
                      proposed_action: item.proposed_action,
                      approved_at: new Date().toISOString()
                    });
                    state.optimizer_last_run.approved_changes = state.optimizer_last_run.approved_changes.slice(-10);
                    // Remove from optimizer queue
                    state.optimizer_queue = state.optimizer_queue.filter((i: any) => i.id !== payload.id);
                  }
                }

                writeDashboardState(state);
                if (startOptimizerProcess) {
                  startMainRun('MAIN-RUN-04_Optimizer');
                }
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'ok' }));
              } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'error', message: err instanceof Error ? err.message : String(err) }));
              }
            });
          } else if (req.method === 'POST' && req.url === '/api/run-control') {
            let body = '';
            req.on('data', (chunk: any) => { body += chunk; });
            req.on('end', () => {
              try {
                const payload = JSON.parse(body || '{}');
                const state = readDashboardState();
                const mainRun = String(payload.main_run || payload.type || '');
                if (!MAIN_RUN_NAMES.has(mainRun as any)) throw new Error('Unknown MAIN-RUN');

                state.run_control = state.run_control || {};
                state.run_control.main_runs = state.run_control.main_runs || {};
                const control = state.run_control.main_runs[mainRun] || {};
                if (payload.action === 'cancel-next') control.cancel_next = true;
                else if (payload.action === 'uncancel-next') control.cancel_next = false;
                else if (payload.action === 'note-next') control.note = String(payload.note || '');
                else throw new Error('Unknown run-control action');
                control.updated_at = new Date().toISOString();
                state.run_control.main_runs[mainRun] = control;
                state.run_control.updated_at = control.updated_at;

                writeDashboardState(state);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'ok' }));
              } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'error', message: err instanceof Error ? err.message : String(err) }));
              }
            });
          } else if (req.method === 'POST' && (req.url === '/api/trigger-main-run' || req.url === '/api/trigger-phase')) {
            let body = '';
            req.on('data', (chunk: any) => { body += chunk; });
            req.on('end', () => {
              try {
                const payload = JSON.parse(body || '{}');
                const legacyPhases: Record<string, string> = {
                  planning: 'MAIN-RUN-01_Planning',
                  monitoring: 'MAIN-RUN-02_CheckAndDoing',
                  audit: 'MAIN-RUN-03_Audit',
                  optimizer: 'MAIN-RUN-04_Optimizer',
                  memory: 'MAIN-RUN-05_MemoryOptimization',
                };
                const mainRun = String(payload.main_run || legacyPhases[payload.phase] || '');
                startMainRun(mainRun);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'ok', message: `${mainRun} triggered` }));
              } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'error', message: err instanceof Error ? err.message : String(err) }));
              }
            });
          } else if (req.method === 'POST' && req.url === '/api/replan-issue') {
            let body = '';
            req.on('data', (chunk: any) => { body += chunk; });
            req.on('end', () => {
              try {
                const payload = JSON.parse(body || '{}');
                if (!payload.issue_number) throw new Error('issue_number is required');

                const state = readDashboardState();
                state.manual_plan_queue = state.manual_plan_queue || [];
                if (!state.manual_plan_queue.includes(payload.issue_number)) {
                  state.manual_plan_queue.push(payload.issue_number);
                }
                writeDashboardState(state);

                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'ok', message: `Issue ${payload.issue_number} queued for replan` }));
              } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'error', message: err instanceof Error ? err.message : String(err) }));
              }
            });
          } else if (req.method === 'POST' && req.url === '/api/clear-alerts') {
            try {
              const flagPath = path.resolve(__dirname, '../../var/db/clear-alerts.flag');
              const state = readDashboardState();
              if (Array.isArray(state.decisions_pending)) {
                state.decisions_pending.forEach((alert: any) => {
                  if (alert.status !== 'closed' && alert.status !== 'ignored') {
                    alert.status = 'closed';
                    alert.closed_by = 'user';
                    alert.closed_at = new Date().toISOString();
                    alert.user_comment = 'Alle gelöscht';
                  }
                });
              }
              writeDashboardState(state);
              ensureParentDir(flagPath);
              fs.writeFileSync(flagPath, '', 'utf-8');
              res.writeHead(200, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ status: 'ok', message: 'Alerts cleared' }));
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else {
            next();
          }
        });
      }
    }
  ],
  server: {
    port: 5173,
    open: true,
    hmr: false,
    // Statische Dateien aus var/ Verzeichnis serven
    fs: {
      allow: [
        path.resolve(__dirname),
        path.resolve(__dirname, '../../var'),
      ]
    }
  },
})
