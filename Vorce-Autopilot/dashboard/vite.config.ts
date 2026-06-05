import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import fs from 'fs'
import path from 'path'
import { execSync } from 'child_process'

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

function getRepository(): string {
  try {
    const configPath = path.resolve(__dirname, '../config/autopilot-config.json');
    if (fs.existsSync(configPath)) {
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
      if (config && config.repository) {
        return config.repository;
      }
    }
  } catch (e) {}
  return 'Vorce-Studios/Vorce';
}

export default defineConfig({
  plugins: [
    react(),
    {
      name: 'api-middleware',
      configureServer(server) {
        server.middlewares.use((req: any, res: any, next: any) => {
          if (req.method === 'GET' && req.url === '/active-sessions.json') {
            try {
              const publicStatePath = path.resolve(__dirname, './public/active-sessions.json');
              const statePath = fs.existsSync(publicStatePath) ? publicStatePath : path.resolve(__dirname, '../var/db/autopilot-state.json');
              if (fs.existsSync(statePath)) {
                const stateContent = fs.readFileSync(statePath, 'utf-8');
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(stateContent);
              } else {
                res.writeHead(404, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'active-sessions.json not found' }));
              }
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url === '/autopilot-config.json') {
            try {
              const configPath = path.resolve(__dirname, '../config/autopilot-config.json');
              if (fs.existsSync(configPath)) {
                const configContent = fs.readFileSync(configPath, 'utf-8');
                const config = JSON.parse(configContent);

                // Dynamically load prompts from files
                config.prompts = config.prompts || {};
                const promptsDir = path.resolve(__dirname, '../prompts');
                const groups = ['planning', 'monitoring', 'audit', 'ceo', 'deliberation'];
                for (const group of groups) {
                  const groupDir = path.join(promptsDir, group);
                  if (fs.existsSync(groupDir)) {
                    const files = fs.readdirSync(groupDir);
                    for (const file of files) {
                      if (file.endsWith('.md')) {
                        const key = path.basename(file, '.md');
                        const content = fs.readFileSync(path.join(groupDir, file), 'utf-8');
                        config.prompts[key] = content;
                      }
                    }
                  }
                }

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
          } else if (req.method === 'GET' && req.url === '/registry.json') {
            try {
              const registryPath = path.resolve(__dirname, '../var/db/quota-registry.json');
              if (fs.existsSync(registryPath)) {
                const registryContent = fs.readFileSync(registryPath, 'utf-8');
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(registryContent);
              } else {
                res.writeHead(404, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'quota-registry.json not found' }));
              }
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url === '/jules-sessions.json') {
            try {
              const livePath = path.resolve(__dirname, '../var/db/jules-sessions.json');
              const fallbackPath = path.resolve(__dirname, './jules-sessions.json');
              const sessionPath = fs.existsSync(livePath) ? livePath : fallbackPath;
              if (fs.existsSync(sessionPath)) {
                const sessionContent = fs.readFileSync(sessionPath, 'utf-8');
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(sessionContent);
              } else {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify([]));
              }
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
                for (const r of repos) {
                  try {
                    const issuesJson = execSync(
                      `gh issue list --repo ${r} --limit 1000 --state all --json number,title,state,labels,assignees,body,createdAt,updatedAt,url`,
                      { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }
                    );
                    const parsed = JSON.parse(issuesJson);
                    if (Array.isArray(parsed)) {
                      parsed.forEach((issue: any) => issue.repo = r);
                      allIssues = allIssues.concat(parsed);
                    }
                  } catch (e) {}
                }
                const responseJson = JSON.stringify(allIssues);
                issuesCache = responseJson;
                issuesCacheTime = now;
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(responseJson);
              } catch (err) {
                // Fallback to static public file if GH command fails
                const fallbackPath = path.resolve(__dirname, './public/github-issues.json');
                if (fs.existsSync(fallbackPath)) {
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
                for (const r of repos) {
                  try {
                    const prsJson = execSync(
                      `gh pr list --repo ${r} --limit 1000 --state open --json number,title,state,mergeable,statusCheckRollup,headRefName,baseRefName,updatedAt,url,isDraft`,
                      { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }
                    );
                    const parsed = JSON.parse(prsJson);
                    if (Array.isArray(parsed)) {
                      parsed.forEach((pr: any) => pr.repo = r);
                      allPRs = allPRs.concat(parsed);
                    }
                  } catch (e) {}
                }
                const responseJson = JSON.stringify(allPRs);
                prsCache = responseJson;
                prsCacheTime = now;
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(responseJson);
              } catch (err) {
                // Fallback to static public file if GH command fails
                const fallbackPath = path.resolve(__dirname, './public/pull-requests.json');
                if (fs.existsSync(fallbackPath)) {
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
                  const promptsDir = path.resolve(__dirname, '../prompts');
                  const findPromptFile = (key: string) => {
                    const groups = ['planning', 'monitoring', 'audit', 'ceo', 'deliberation'];
                    for (const g of groups) {
                      const p = path.join(promptsDir, g, `${key}.md`);
                      if (fs.existsSync(p)) return p;
                    }
                    return null;
                  };

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

                const configPath = path.resolve(__dirname, '../config/autopilot-config.json');
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
                const quotaPath = path.resolve(__dirname, '../var/db/quota-registry.json');
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
              const memoryPath = path.resolve(__dirname, '../var/db/autopilot-memories.json');
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
                const memoryPath = path.resolve(__dirname, '../var/db/autopilot-memories.json');
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
                const statePath = path.resolve(__dirname, '../var/db/autopilot-state.json');
                const publicStatePath = path.resolve(__dirname, './public/active-sessions.json');
                const readableStatePath = fs.existsSync(statePath) ? statePath : publicStatePath;
                const state = readJsonFile(readableStatePath, { decisions_pending: [] });

                if (!Array.isArray(state.decisions_pending)) state.decisions_pending = [];

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
                const statePath = path.resolve(__dirname, '../var/db/autopilot-state.json');
                const publicStatePath = path.resolve(__dirname, './public/active-sessions.json');
                const readableStatePath = fs.existsSync(statePath) ? statePath : publicStatePath;
                const state = readJsonFile(readableStatePath, {});

                state.optimizer_queue = state.optimizer_queue || [];

                if (payload.action === 'reject') {
                  state.optimizer_queue = state.optimizer_queue.filter((item: any) => item.id !== payload.id);
                } else if (payload.action === 'run-now') {
                  state.run_control = state.run_control || {};
                  state.run_control.force_optimizer = true;
                  state.run_control.force_optimizer_requested_at = new Date().toISOString();
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
                      try { execSync(`gh label create "priority: high" --repo "${repo}" --color "CCCCCC" --description "High priority"`, { stdio: 'ignore' }); } catch (e) {}
                      try { execSync(`gh label create "bug" --repo "${repo}" --color "CCCCCC" --description "Bug"`, { stdio: 'ignore' }); } catch (e) {}
                      try { execSync(`gh label create "agent:gemini_cli" --repo "${repo}" --color "CCCCCC" --description "Gemini CLI agent"`, { stdio: 'ignore' }); } catch (e) {}

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
                const statePath = path.resolve(__dirname, '../var/db/autopilot-state.json');
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
          } else if (req.method === 'POST' && req.url === '/api/clear-alerts') {
            try {
              const flagPath = path.resolve(__dirname, '../var/db/clear-alerts.flag');
              const statePath = path.resolve(__dirname, '../var/db/autopilot-state.json');
              const publicStatePath = path.resolve(__dirname, './public/active-sessions.json');
              const readableStatePath = fs.existsSync(statePath) ? statePath : publicStatePath;
              const state = readJsonFile(readableStatePath, {});
              state.decisions_pending = [];
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
              const liveLogPath = path.resolve(__dirname, '../var/log/autopilot-live.log');
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
  },
})
