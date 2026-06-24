# Combined Detailed Implementation and Cleanup Plan (Vorce-Factory)

## Goal Description
This plan provides the **highly granular, unambiguous step-by-step instructions** required for cheaper sub-agents to implement the remaining gap points from `AGENT_PROMPTS_RUN_DASHBOARD_AUDIT_RENAME.md` (NA-04 to NA-23) and the Agent-to-Agent (A2A) integration. No details have been omitted to ensure error-free execution.

## 1. Current Status (IST-Zustand)
- **Completed**: NA-01 (Syntax/Runtime Blockers), NA-02 (Test Harness), NA-03 (Topology/Hierarchy).
- **Open**: NA-04 to NA-23.
- **New Requirements**: Google A2A protocol integration (`@a2a-js/sdk` for JS, HTTP/JSON-RPC for PowerShell).

## 2. Agent-to-Agent (A2A) Integration (Detailed Execution Plan)

### 2.1 Backend (PowerShell A2A Client)
**File to Create**: `Vorce-Factory/src/lib/integrations/A2AClient.ps1`
**Tasks**:
1. Create function `Send-VorceA2AMessage -TargetAgent <String> -MessageType <String> -Payload <Hashtable> -CorrelationId <String>`.
2. Wrap the payload in a JSON-RPC 2.0 schema: 
   `@{ jsonrpc = "2.0"; method = "sendMessage"; params = @{ target = $TargetAgent; type = $MessageType; payload = $Payload; correlationId = $CorrelationId }; id = [guid]::NewGuid().ToString() }`
3. Use `Invoke-RestMethod -Uri "http://localhost:5174/api/a2a" -Method Post -Body ($Body | ConvertTo-Json -Depth 10) -ContentType "application/json"`.
4. Wrap the HTTP call in a `try/catch` to suppress errors silently if the Dashboard/A2A Hub is offline (non-blocking).

### 2.2 Integration into RunEngine & DeliberationEngine
**Files to Modify**: `RunEngine.ps1`, `DeliberationEngine.ps1`
**Tasks**:
1. **Live Task Monitoring (`RunEngine.ps1`)**: Inside `Invoke-VorceSubRunParallel` and `Invoke-VorcePartRun`, after the run state changes (started, completed, failed), invoke:
   `Send-VorceA2AMessage -TargetAgent "Dashboard" -MessageType "TaskProgress" -Payload @{ runId = $RunState.id; name = $RunState.name; status = $RunState.status } -CorrelationId $MainRunId`
2. **QA-to-CEO Feedback (`DeliberationEngine.ps1`)**: In the Critique phase, if the QA agent detects an issue, send:
   `Send-VorceA2AMessage -TargetAgent "CEO" -MessageType "CritiqueFeedback" -Payload $ValidationResults -CorrelationId $PhaseId`

### 2.3 Frontend/Dashboard A2A Hub (Node.js/Express)
**File to Create/Modify**: `Vorce-Factory/web/Dashboard/server/A2AServer.js` (or integrate into `WebSocketServer.js`)
**Tasks**:
1. Set up an Express endpoint `POST /api/a2a`.
2. Parse incoming JSON-RPC payloads.
3. Integrate `@a2a-js/sdk` to construct the standard A2A message object.
4. If `target === "Dashboard"`, broadcast the message to all connected React clients via WebSockets using the event `a2a_message`.
5. If `target === "CEO"`, append the message to the CEO's task queue or write to a shared state file.

### 2.4 Frontend React UI
**File to Create**: `Vorce-Factory/web/Dashboard/src/components/A2ALiveMonitor.tsx`
**Tasks**:
1. Subscribe to the WebSocket connection.
2. Listen for the `a2a_message` event.
3. Maintain an array state of messages.
4. Render a live feed. Use distinct styling: e.g., Blue for `TaskProgress`, Orange/Red for `CritiqueFeedback`.

## 3. Detailed Remaining Implementation Steps (NA-04 to NA-23)

### NA-04: State-Schema, History, and Persistence
- **Files**: `StateManager.ps1`, `RunEngine.ps1`, `Vorce-Orchestrator.ps1`
- **Tasks**:
  1. Ensure `Save-VorceRunState` uses Schema 2. 
  2. Set IDs: MAIN `main_run_id` = own ID; SUB `parent_run_id` = MAIN-ID; PART `parent_run_id` = SUB-ID.
  3. Ensure `Save-VorceRunState` explicitly retains these fields: `resume`, `execution_graph`, `attempts`, `result_ref`, `result_id`, `reusable`, `error`, `error_class`, `retry_after`, `parts`.
  4. Write the latest state to `var/run-states` and the immutable history to `var/run-history/<TYPE>/<RunName>/<RunId>.json`.
  5. Remove legacy `Set-Content` JSON writes from `RunEngine.ps1`.
- **Acceptance**: New states are Schema 2; SUB/PART parent relationships are correct; attempts array is preserved; duplicate write logic is removed.

### NA-05: Router-Contract and Config
- **Files**: `RouterEngine.ps1`, `*-Router.ps1`, `Dashboard/src/types.ts`
- **Tasks**:
  1. Implement `Resolve-VorceRouterDecision` which MUST return `{id, name, script, configured_enabled, mode, condition, active, reason, evidence}`.
  2. Update all 5 router scripts to use this central resolver.
  3. Store the full decision list in `MainState.metadata.router_decision`.
  4. Ensure the Dashboard UI limits settings to a dropdown for conditions and whitelisted number fields (no raw PowerShell injection).
- **Acceptance**: Dashboard and backend share the exact same JSON contract. All decisions are deterministic.

### NA-06: Logging-Core
- **Files**: `Write-Log.ps1`, `Vorce-Factory.ps1`, `AgentRunner.ps1`, `Test-Logging.ps1`
- **Tasks**:
  1. Remove the competing `Write-VorceLog` function in `Vorce-Factory.ps1`.
  2. Dot-source the central `Write-Log.ps1` module.
  3. Log schema MUST include: `timestamp`, `level`, `event_type`, `component`, `session_id`, `correlation_id`, `main_run_id`, `run_name`, `provider`, `duration_ms`, `message`, `data`, `pid`.
  4. Mandatory Events: `run_started`, `run_completed`, `run_failed`, `provider_attempt`, `attempt_failed`.
  5. Implement secret redaction (e.g., Bearer tokens, GitHub PATs) before writing.
  6. Use File-Locks (Mutex) or per-job temp files to ensure parallel logging does not corrupt the JSONL.
- **Acceptance**: JSONL remains parseable during parallel jobs. Only one logging implementation exists.

### NA-07: Process Supervisor
- **Files**: `Start-Vorce-Factory.ps1`, `Vorce-Factory.ps1`
- **Tasks**:
  1. Write a process registry to `var/tmp/vorce-processes.json` containing: `component, pid, parent_pid, started_at, command_path, working_directory, port, health_url, stdout_path, stderr_path, session_id`.
  2. Modify process-stopping logic to use the PID from the registry. Verify `CommandPath` before stopping to prevent killing foreign processes.
  3. On process crash, log the last 30 lines of `stdout`/`stderr`.
- **Acceptance**: Stopping components works via PID, not broad port-killing.

### NA-08: Provider Normalization
- **Files**: `ProviderRegistry.ps1`, `QuotaManager.ps1`, `AgentRunner.ps1`
- **Tasks**:
  1. Implement `Resolve-VorceProviderId` to map to canonical IDs: `gemini_cli`, `claude_code`, `codex_orchestrator`, `kiro_cli`, `cline_cli`, `copilot_cli`, `cursor_agent`, `jules`.
  2. Ensure `QuotaManager` and `AgentRunner` strictly call this resolver first.
- **Acceptance**: No duplicate alias mappings. Unknown providers return a structured error.

### NA-09: AgentRunner and Fallback
- **Files**: `AgentRunner.ps1`, `QuotaManager.ps1`
- **Tasks**:
  1. Support `prompt_transport` = `argument|stdin|tempfile`. For tempfiles, save to `var/tmp/agent-artifacts/<main>/<part>/<attempt>/`.
  2. If a provider fails (e.g., timeout, exit code 1), immediately try the next provider in the chain (e.g., `routing_rules.<TaskType>`).
  3. Emit a structured result: `{ success: false, provider: "...", model: "...", attempt_id: "...", exit_code: 1, stdout_path: "...", stderr_path: "...", error_class: "timeout", retryable: true, fallback_recommended: true }`.
  4. If chain exhausted, set status to `waiting_provider` and `resume_required = true`. DO NOT block/sleep for 15 minutes.
- **Acceptance**: All configured providers run or are skipped with explicit reasons. Tempfile transport works.

### NA-10: Result Validation
- **Files**: `AgentResultValidator.ps1`
- **Tasks**:
  1. Accept `ExpectedOutput` modes: `text`, `json`, `json_schema`, `exact`.
  2. Strip markdown code fences (```json ... ```) before parsing.
  3. Map errors to explicit classes: `invalid_json`, `schema_mismatch`, `empty_output`.
  4. Valid `no_work` outputs must NOT trigger a fallback.
- **Acceptance**: Invalid JSON triggers fallback; `no_work` completes the part-run gracefully.

### NA-11: Deliberation and LLM Part-Runs
- **Files**: `DeliberationEngine.ps1`
- **Tasks**:
  1. Assign a `phase_id` to each deliberation step (Proposal, Critique, Synthesis).
  2. If Proposal succeeds but Critique is unavailable (and `fallback_to_single=true`), complete with `single_agent_fallback`.
  3. If Deliberation returns `waiting_provider`, DO NOT save the proposal as `created`.
- **Acceptance**: Accurate propagation of `waiting_provider`.

### NA-12: MAIN-Run Resume and Checkpoint
- **Files**: `StateManager.ps1`, `RunEngine.ps1`, `Vorce-Factory.ps1`
- **Tasks**:
  1. Implement `-ResumeRunId` flag.
  2. Before executing a Part-Run, call `Get-VorceReusableRunResult`. It must check: matching `main_run_id`, matching `input_fingerprint`, matching `DependencyResultIds`, and `reusable=true`.
  3. If true, skip execution, emit event `run_reused`.
  4. Ensure side-effect tasks (like creating GitHub issues) use an `idempotency_key` so they don't duplicate on resume.
- **Acceptance**: Unfinished runs can be resumed without re-running successfully completed parts.

### NA-13: Provider Test Suite
- **Files**: `Test-LLMProviders.ps1`
- **Tasks**:
  1. Modes: `-DiscoveryOnly`, `-DryRun`, `-FakeCli`, `-Smoke`.
  2. Create a mock CLI script (`FakeCli.ps1`) to simulate success, timeout, empty output, and invalid JSON.
  3. Default run MUST NOT invoke paid LLM APIs.
- **Acceptance**: The test suite covers all error scenarios without incurring costs.

### NA-14: CLI Security
- **Files**: `GitHubClient.ps1`, Node configs
- **Tasks**:
  1. Remove all string-interpolated `Start-Process gh` calls. Replace with an array-based helper (`$ProcessArgs = @("issue", "create", "--title", $Title)`).
  2. Node.js `execSync` must be replaced with `spawnSync` using arrays.
- **Acceptance**: Escaped characters in titles/bodies cannot cause arbitrary shell execution.

### NA-15: Run-Summary API
- **Files**: Dashboard backend, `Test-RunSummary.ps1`
- **Tasks**:
  1. Implement `GET /run-summary.json`.
  2. Calculate stats purely from `var/run-history`.
  3. Count total provider attempts, fallbacks, token usage, cost, and reused checkpoints. Provide 24h and 7d aggregates.
- **Acceptance**: Dashboard shows accurate historical counts rather than hardcoded 0s.

### NA-16: Dashboard Code Quality
- **Files**: `web/Dashboard/package.json`
- **Tasks**:
  1. Add a `typecheck` script (`tsc --noEmit`).
  2. Fix all 18 existing ESLint errors (e.g., add missing `let`/`const` inside `switch` block scopes, remove unused imports).
  3. Remove the obsolete `LiveLogMonitor.tsx` component completely.
- **Acceptance**: `npm run typecheck`, `lint`, and `build` succeed with 0 errors.

### NA-17: Log Retention
- **Files**: `LogMaintenance.ps1`
- **Tasks**:
  1. JSONL: Retain 30 days, gzip after 2 days.
  2. Text sessions: Max 30 files, max 30 days.
  3. Agent Artifacts: Delete successes after 24h, failures after 7d.
  4. Never delete active files belonging to PIDs in the process registry.

### NA-18: Rename Sweep
- **Tasks**: Replace all active visible references of "Autopilot" with "Vorce-Factory" in scripts and Dashboard UIs. Technical identifiers (`autopilot.ps1`) remain if aliased.

### NA-19: Optimizer Split
- **Tasks**: Split `MAIN-RUN-04_Optimizer` into exactly 5 SUB-RUNs (e.g., PerformanceDataCollection, SystemAnalysis, ProposalGeneration, ApprovedChangeDispatch, ChangeEvaluation) and 12 PART-RUNs as dictated by the prompt. Ensure only ProposalGeneration uses an LLM.

### NA-20: MemoryOptimization Split
- **Tasks**: Split `MAIN-RUN-05_MemoryOptimization` into 5 SUB-RUNs (MemoryInventory, SelectionPolicy, Maintenance, MasterIssueContext, Reporting) and 9 PART-RUNs. Implement `Select-VorceRelevantMemories`.

### NA-21: Dashboard - Optimizer & Memory
- **Tasks**: Add UI sections for Optimizer Proposals (Approve/Reject) and Memory Maintenance. The API must reject high-risk auto-applies without manual approval.

### NA-22: Console Menu
- **Tasks**: Update `Start-Vorce-Factory.ps1`.
  - Normal run starts ONLY the Dashboard Base.
  - Show menu: `[1] Start Runs`, `[2] Stop All`, `[S] Status`, `[Q] Quit`.
  - `[1]` ensures `MAIN-RUN-01_Planning` runs exactly once as initial planning.

### NA-23: End-to-End Testing
- **Tasks**: 
  - Ensure every `Test-*.ps1` correctly uses exit code 1 on failure.
  - Run all tests before considering implementation complete.

## 4. Four-Eyes Principle (4-Augen-Prinzip) Validation Checklist

**Auditing Agent Instructions**:
- [ ] 1. Run `Test-PowerShellSyntax.ps1` -> Verify Exit Code 0.
- [ ] 2. Check `A2AClient.ps1` -> Verify `Invoke-RestMethod` uses the JSON-RPC schema precisely.
- [ ] 3. Run the Dashboard -> Open the UI and confirm `A2ALiveMonitor` successfully displays TaskProgress WebSocket events.
- [ ] 4. Inspect `StateManager.ps1` -> Verify the `Save-VorceRunState` function retains `resume`, `execution_graph`, and `attempts`.
- [ ] 5. Run `Test-AgentRunner.ps1` -> Ensure FakeCLI timeout scenarios result in `fallback_recommended = true`.
- [ ] 6. Inspect `Start-Vorce-Factory.ps1` -> Verify `Stop-Process` relies on `vorce-processes.json` PIDs and validates the `CommandPath`.
- [ ] 7. Dashboard Build -> In `web/Dashboard`, run `npm run lint` and `npm run typecheck`. Confirm 0 errors.
- [ ] 8. Toplogy Test -> Run `Test-RunTopology.ps1`. Ensure exactly 5 MAIN, 24 SUB, and 36 PART-RUNs exist (once NA-19 and NA-20 are merged).
- [ ] 9. Check `GitHubClient.ps1` -> Verify no string-interpolated arguments exist (e.g. `$title`), only array parameters `@("issue", "create", ...)`.
