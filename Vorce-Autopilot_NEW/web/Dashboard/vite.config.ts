import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import fs from 'fs'
import path from 'path'
import { execSync, spawn } from 'child_process'

let issuesCache: string | null = null;
let issuesCacheTime = 0;
let prsCache: string | null = null;
let prsCacheTime = 0;
const CACHE_TTL = 20000; // 20 seconds cache TTL to avoid hitting GitHub API too frequently

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
              serveFirstJson(res, [
                path.resolve(__dirname, '../../var/db/autopilot-state.json'),
                path.resolve(__dirname, '../../var/db/active-sessions.json'),
              ], {});
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
                    const issuesJson = execSync(
                      `gh issue list --repo ${r} --limit 1000 --state all --json number,title,state,labels,assignees,body,createdAt,updatedAt,url`,
                      { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }
                    );
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
                    const prsJson = execSync(
                      `gh pr list --repo ${r} --limit 1000 --state open --json number,title,state,mergeable,statusCheckRollup,headRefName,baseRefName,updatedAt,url,isDraft`,
                      { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }
                    );
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
                const config = JSON.parse(body);

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

                const configPath = path.resolve(__dirname, '../../var/config/autopilot-config.json');
                const publicConfigPath = path.resolve(__dirname, './public/autopilot-config.json');
                writeJsonFile(configPath, config);
                writeJsonFile(publicConfigPath, config);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'ok', message: 'Autopilot config saved' }));
              } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'error', message: err instanceof Error ? err.message : String(err) }));
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
                const statePath = path.resolve(__dirname, '../../var/db/autopilot-state.json');
                const publicStatePath = path.resolve(__dirname, './public/active-sessions.json');
                const memoryPath = path.resolve(__dirname, '../../var/db/autopilot-memories.json');
                const publicMemoryPath = path.resolve(__dirname, './public/memories.json');
                const readableStatePath = fs.existsSync(statePath) ? statePath : publicStatePath;
                const state = readJsonFile(readableStatePath, { decisions_pending: [] });

                if (!Array.isArray(state.decisions_pending)) state.decisions_pending = [];

                // NEW: Handle "close-alert" action - mark alert as closed with optional comment
                if (payload.action === 'close-alert') {
                  const alert = state.decisions_pending.find((item: any, idx: number) => String(item.id || idx) === String(payload.id));
                  if (alert) {
                    alert.status = 'closed';
                    alert.closed_by = 'user';
                    alert.closed_at = new Date().toISOString();
                    alert.user_comment = payload.comment || 'Manuell geschlossen';
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

                writeJsonFile(statePath, state);
                writeJsonFile(publicStatePath, state);
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
                const statePath = path.resolve(__dirname, '../../var/db/autopilot-state.json');
                const publicStatePath = path.resolve(__dirname, './public/active-sessions.json');
                const readableStatePath = fs.existsSync(statePath) ? statePath : publicStatePath;
                const state = readJsonFile(readableStatePath, {});
                let startOptimizerProcess = false;

                state.optimizer_queue = state.optimizer_queue || [];

                if (payload.action === 'reject') {
                  state.optimizer_queue = state.optimizer_queue.filter((item: any) => item.id !== payload.id);
                } else if (payload.action === 'run-now') {
                  state.run_control = state.run_control || {};
                  state.run_control.force_optimizer = true;
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
                      // Ensure labels exist before creating issue to prevent failures
                      try { execSync(`gh label create "priority: high" --repo "${repo}" --color "CCCCCC" --description "High priority"`, { stdio: 'ignore' }); } catch { /* label already exists */ }
                      try { execSync(`gh label create "bug" --repo "${repo}" --color "CCCCCC" --description "Bug"`, { stdio: 'ignore' }); } catch { /* label already exists */ }
                      try { execSync(`gh label create "agent:gemini_cli" --repo "${repo}" --color "CCCCCC" --description "Gemini CLI agent"`, { stdio: 'ignore' }); } catch { /* label already exists */ }

                      const command = `gh issue create --repo "${repo}" --title "${title.replace(/"/g, '\\"')}" --body "${issueBody.replace(/"/g, '\\"')}" --label "priority: high" --label "bug" --label "agent:gemini_cli"`;
                      const issueUrl = execSync(command, { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();

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

                writeJsonFile(statePath, state);
                writeJsonFile(publicStatePath, state);
                if (startOptimizerProcess) {
                  const autopilotPath = path.resolve(__dirname, '../../autopilot.ps1');
                  const child = spawn('pwsh', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', autopilotPath, '-PlanOnce'], {
                    cwd: path.resolve(__dirname, '../..'),
                    detached: true,
                    stdio: 'ignore',
                    windowsHide: true
                  });
                  child.unref();
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
                const statePath = path.resolve(__dirname, '../../var/db/autopilot-state.json');
                const publicStatePath = path.resolve(__dirname, './public/active-sessions.json');
                const readableStatePath = fs.existsSync(statePath) ? statePath : publicStatePath;
                const state = readJsonFile(readableStatePath, {});

                state.run_control = state.run_control || {};
                if (payload.type === 'planning') {
                  if (payload.action === 'cancel-next') state.run_control.cancel_next_planning = true;
                  if (payload.action === 'uncancel-next') state.run_control.cancel_next_planning = false;
                  if (payload.action === 'note-next') state.run_control.next_planning_note = String(payload.note || '');
                } else if (payload.type === 'monitoring') {
                  if (payload.action === 'cancel-next') state.run_control.cancel_next_monitoring = true;
                  if (payload.action === 'uncancel-next') state.run_control.cancel_next_monitoring = false;
                  if (payload.action === 'note-next') state.run_control.next_monitoring_note = String(payload.note || '');
                } else {
                  throw new Error('Unknown run type');
                }
                state.run_control.updated_at = new Date().toISOString();

                writeJsonFile(statePath, state);
                writeJsonFile(publicStatePath, state);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'ok' }));
              } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'error', message: err instanceof Error ? err.message : String(err) }));
              }
            });
          } else if (req.method === 'POST' && req.url === '/api/trigger-phase') {
            let body = '';
            req.on('data', (chunk: any) => { body += chunk; });
            req.on('end', () => {
              try {
                const payload = JSON.parse(body || '{}');
                const validPhases = ['planning', 'monitoring', 'audit'];
                if (!validPhases.includes(payload.phase)) throw new Error('Invalid phase');

                const scriptPath = path.resolve(__dirname, `../../src/phases/${payload.phase}-wakeup.ps1`);
                if (fs.existsSync(scriptPath)) {
                  const child = spawn('pwsh', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath], {
                    cwd: path.resolve(__dirname, '../..'),
                    detached: true,
                    stdio: 'ignore',
                    windowsHide: true
                  });
                  child.unref();
                }
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'ok', message: `${payload.phase} triggered` }));
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

                const statePath = path.resolve(__dirname, '../../var/db/autopilot-state.json');
                const state = readJsonFile(statePath, {});
                state.manual_plan_queue = state.manual_plan_queue || [];
                if (!state.manual_plan_queue.includes(payload.issue_number)) {
                  state.manual_plan_queue.push(payload.issue_number);
                }
                writeJsonFile(statePath, state);

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
              const statePath = path.resolve(__dirname, '../../var/db/autopilot-state.json');
              const publicStatePath = path.resolve(__dirname, './public/active-sessions.json');
              const readableStatePath = fs.existsSync(statePath) ? statePath : publicStatePath;
              const state = readJsonFile(readableStatePath, {});
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
              writeJsonFile(statePath, state);
              writeJsonFile(publicStatePath, state);
              ensureParentDir(flagPath);
              fs.writeFileSync(flagPath, '', 'utf-8');
              res.writeHead(200, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ status: 'ok', message: 'Alerts cleared' }));
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url === '/api/live-log') {
            try {
              const liveLogPath = path.resolve(__dirname, '../../var/log/autopilot-live.log');
              const content = fs.existsSync(liveLogPath) ? fs.readFileSync(liveLogPath, 'utf-8') : '';
              res.writeHead(200, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ content }));
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err), content: '' }));
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
    proxy: {
      // Proxy für WebSocket-Server auf Port 5174
      '/ws': {
        target: 'ws://localhost:5174',
        ws: true,
        changeOrigin: true,
      }
    },
    // Statische Dateien aus var/ Verzeichnis serven
    fs: {
      allow: ['../../var']
    }
  },
})
