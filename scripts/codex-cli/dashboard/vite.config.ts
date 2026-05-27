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

export default defineConfig({
  plugins: [
    react(),
    {
      name: 'api-middleware',
      configureServer(server) {
        server.middlewares.use((req: any, res: any, next: any) => {
          if (req.method === 'GET' && req.url === '/active-sessions.json') {
            try {
              const statePath = path.resolve(__dirname, '../autopilot-state.json');
              if (fs.existsSync(statePath)) {
                const stateContent = fs.readFileSync(statePath, 'utf-8');
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(stateContent);
              } else {
                res.writeHead(404, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'autopilot-state.json not found' }));
              }
            } catch (err) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
            }
          } else if (req.method === 'GET' && req.url === '/autopilot-config.json') {
            try {
              const configPath = path.resolve(__dirname, '../autopilot-config.json');
              if (fs.existsSync(configPath)) {
                const configContent = fs.readFileSync(configPath, 'utf-8');
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(configContent);
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
              const registryPath = path.resolve(__dirname, '../quota-registry.json');
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
          } else if (req.method === 'GET' && req.url === '/github-issues.json') {
            const now = Date.now();
            if (issuesCache && (now - issuesCacheTime < CACHE_TTL)) {
              res.writeHead(200, { 'Content-Type': 'application/json' });
              res.end(issuesCache);
            } else {
              try {
                const issuesJson = execSync(
                  'gh issue list --repo Vorce-Studios/Vorce --limit 100 --state all --json number,title,state,labels,assignees,body,createdAt,updatedAt,url',
                  { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }
                );
                issuesCache = issuesJson;
                issuesCacheTime = now;
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(issuesJson);
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
                const prsJson = execSync(
                  'gh pr list --repo Vorce-Studios/Vorce --limit 100 --state all --json number,title,state,mergeable,statusCheckRollup,headRefName,baseRefName,updatedAt,url',
                  { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }
                );
                prsCache = prsJson;
                prsCacheTime = now;
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(prsJson);
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
                const configPath = path.resolve(__dirname, '../autopilot-config.json');
                const publicConfigPath = path.resolve(__dirname, './public/autopilot-config.json');
                fs.writeFileSync(configPath, JSON.stringify(config, null, 2), 'utf-8');
                fs.writeFileSync(publicConfigPath, JSON.stringify(config, null, 2), 'utf-8');
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
                const quotaPath = path.resolve(__dirname, '../quota-registry.json');
                const publicRegistryPath = path.resolve(__dirname, './public/registry.json');
                const publicDataPath = path.resolve(__dirname, './public/data.json');
                fs.writeFileSync(quotaPath, JSON.stringify(quota, null, 2), 'utf-8');
                fs.writeFileSync(publicRegistryPath, JSON.stringify(quota, null, 2), 'utf-8');
                fs.writeFileSync(publicDataPath, JSON.stringify(quota, null, 2), 'utf-8');
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'ok', message: 'Quota registry saved' }));
              } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'error', message: err instanceof Error ? err.message : String(err) }));
              }
            });
          } else if (req.method === 'GET' && req.url === '/memories.json') {
            try {
              const memoryPath = path.resolve(__dirname, '../autopilot-memories.json');
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
                const memoryPath = path.resolve(__dirname, '../autopilot-memories.json');
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
                fs.writeFileSync(memoryPath, storeStr, 'utf-8');
                fs.writeFileSync(publicMemoryPath, storeStr, 'utf-8');
                
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'ok', message: 'Memories updated successfully' }));
              } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ status: 'error', message: err instanceof Error ? err.message : String(err) }));
              }
            });
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
