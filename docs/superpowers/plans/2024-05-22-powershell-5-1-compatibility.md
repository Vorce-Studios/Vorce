# PowerShell 5.1 Compatibility Refactoring Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all PowerShell 7+ null-coalescing (`??`) and optional chaining (`?.`) operators with PowerShell 5.1 compatible logic across the `Vorce-Factory/src` directory.

**Architecture:** We will use standard PowerShell `if`/`else` blocks or subexpressions `$(if (...) { ... } else { ... })` to mimic the behavior of modern operators while maintaining compatibility with legacy environments.

**Tech Stack:** PowerShell 5.1

---

### Task 1: Refactor Planning Strategy Proposal Creation

**Files:**
- Modify: `VjMapper/Vorce-Factory/src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-03_MR-01_Planning__Strategy/PART-RUNS/PART-RUN-01_MR-01_Planning__Strategy__CreateProposal.ps1:97`

- [ ] **Step 1: Replace null-coalescing operator in $proposalFile assignment**

```powershell
# Old
$proposalFile = Join-Path $proposalsDir "proposal_$($targetIssue.number ?? $targetIssue.id).json"

# New
$proposalFile = Join-Path $proposalsDir "proposal_$($(if ($null -ne $targetIssue.number) { $targetIssue.number } else { $targetIssue.id })).json"
```

- [ ] **Step 2: Verify syntax correctness (manual check)**

- [ ] **Step 3: Commit changes**

```bash
git add VjMapper/Vorce-Factory/src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-03_MR-01_Planning__Strategy/PART-RUNS/PART-RUN-01_MR-01_Planning__Strategy__CreateProposal.ps1
git commit -m "refactor: replace PS7 null-coalescing operator in CreateProposal.ps1"
```

---

### Task 2: Refactor Session Sync

**Files:**
- Modify: `VjMapper/Vorce-Factory/src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-01_MR-02_CheckAndDoing__SessionSync/PART-RUNS/PART-RUN-01_MR-02_CheckAndDoing__SessionSync__SyncActiveSessions.ps1:64`

- [ ] **Step 1: Replace null-coalescing operator in Write-VorceStep**

```powershell
# Old
Write-VorceStep -Message "Status geändert: $($delegation.previousStatus ?? 'unknown') → $newStatus" -Status "OK"

# New
Write-VorceStep -Message "Status geändert: $($(if ($null -ne $delegation.previousStatus) { $delegation.previousStatus } else { 'unknown' })) → $newStatus" -Status "OK"
```

- [ ] **Step 2: Commit changes**

```bash
git add VjMapper/Vorce-Factory/src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-01_MR-02_CheckAndDoing__SessionSync/PART-RUNS/PART-RUN-01_MR-02_CheckAndDoing__SessionSync__SyncActiveSessions.ps1
git commit -m "refactor: replace PS7 null-coalescing operator in SyncActiveSessions.ps1"
```

---

### Task 3: Refactor Jules Session Inspection (Optional Chaining)

**Files:**
- Modify: `VjMapper/Vorce-Factory/src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-02_MR-02_CheckAndDoing__JulesCheck/PART-RUNS/PART-RUN-01_MR-02_CheckAndDoing__JulesCheck__InspectJulesSessions.ps1:97`

- [ ] **Step 1: Replace optional chaining and null-coalescing**

```powershell
# Old
$session.lastActivity = ($commentsResult[0]?.created_at ?? $ghResult.createdAt)

# New
$session.lastActivity = $(
    $val = if ($null -ne $commentsResult[0]) { $commentsResult[0].created_at } else { $null }
    if ($null -ne $val) { $val } else { $ghResult.createdAt }
)
```

- [ ] **Step 2: Commit changes**

```bash
git add VjMapper/Vorce-Factory/src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-02_MR-02_CheckAndDoing__JulesCheck/PART-RUNS/PART-RUN-01_MR-02_CheckAndDoing__JulesCheck__InspectJulesSessions.ps1
git commit -m "refactor: replace PS7 optional chaining and null-coalescing in InspectJulesSessions.ps1"
```

---

### Task 4: Refactor Jules Queue Refill

**Files:**
- Modify: `VjMapper/Vorce-Factory/src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-05_MR-02_CheckAndDoing__JulesRefill/PART-RUNS/PART-RUN-01_MR-02_CheckAndDoing__JulesRefill__RefillJulesQueue.ps1:71`

- [ ] **Step 1: Replace null-coalescing operator**

```powershell
# Old
**Task Type:** $($task.taskType ?? "general")

# New
**Task Type:** $($(if ($null -ne $task.taskType) { $task.taskType } else { "general" }))
```

- [ ] **Step 2: Commit changes**

```bash
git add VjMapper/Vorce-Factory/src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-05_MR-02_CheckAndDoing__JulesRefill/PART-RUNS/PART-RUN-01_MR-02_CheckAndDoing__JulesRefill__RefillJulesQueue.ps1
git commit -m "refactor: replace PS7 null-coalescing operator in RefillJulesQueue.ps1"
```

---

### Task 5: Refactor Jules Supervision Audit

**Files:**
- Modify: `VjMapper/Vorce-Factory/src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-03_MR-03_Audit__JulesSupervision/PART-RUNS/PART-RUN-01_MR-03_Audit__JulesSupervision__SuperviseJulesSessions.ps1:44-45`

- [ ] **Step 1: Replace null-coalescing in status and timestamp**

```powershell
# Old
status = $session.status ?? "unknown";
timestamp = $session.timestamp ?? "unknown"

# New
status = $(if ($null -ne $session.status) { $session.status } else { "unknown" });
timestamp = $(if ($null -ne $session.timestamp) { $session.timestamp } else { "unknown" })
```

- [ ] **Step 2: Commit changes**

```bash
git add VjMapper/Vorce-Factory/src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-03_MR-03_Audit__JulesSupervision/PART-RUNS/PART-RUN-01_MR-03_Audit__JulesSupervision__SuperviseJulesSessions.ps1
git commit -m "refactor: replace PS7 null-coalescing operator in SuperviseJulesSessions.ps1"
```

---

### Task 6: Refactor Alert Disposition Audit

**Files:**
- Modify: `VjMapper/Vorce-Factory/src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-04_MR-03_Audit__AlertDisposition/PART-RUNS/PART-RUN-01_MR-03_Audit__AlertDisposition__DispositionAlerts.ps1:43-46`

- [ ] **Step 1: Replace null-coalescing in alert_id and timestamp**

```powershell
# Old
alert_id = $alert.id ?? "unknown"
timestamp = $alert.timestamp ?? "unknown"

# New
alert_id = $(if ($null -ne $alert.id) { $alert.id } else { "unknown" })
timestamp = $(if ($null -ne $alert.timestamp) { $alert.timestamp } else { "unknown" })
```

- [ ] **Step 2: Commit changes**

```bash
git add VjMapper/Vorce-Factory/src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-04_MR-03_Audit__AlertDisposition/PART-RUNS/PART-RUN-01_MR-03_Audit__AlertDisposition__DispositionAlerts.ps1
git commit -m "refactor: replace PS7 null-coalescing operator in DispositionAlerts.ps1"
```

---

### Task 7: Refactor Performance Data Collection

**Files:**
- Modify: `VjMapper/Vorce-Factory/src/runs/MAIN-RUN-04_Optimizer/SUB-RUNS/SUB-RUN-01_MR-04_Optimizer__PerformanceDataCollection/PART-RUNS/PART-RUN-01_MR-04_Optimizer__PerformanceDataCollection__CollectPerformanceMetrics.ps1:68-81`

- [ ] **Step 1: Replace null-coalescing for provider usage metrics**

```powershell
# Old
daily_calls = $provider.usage_today.calls ?? 0
daily_cost_usd = $provider.usage_today.estimated_cost_usd ?? 0
daily_limit = $provider.daily_limit ?? 0
daily_budget_usd = $provider.daily_budget_usd ?? 0

# New
daily_calls = $(if ($null -ne $provider.usage_today.calls) { $provider.usage_today.calls } else { 0 })
daily_cost_usd = $(if ($null -ne $provider.usage_today.estimated_cost_usd) { $provider.usage_today.estimated_cost_usd } else { 0 })
daily_limit = $(if ($null -ne $provider.daily_limit) { $provider.daily_limit } else { 0 })
daily_budget_usd = $(if ($null -ne $provider.daily_budget_usd) { $provider.daily_budget_usd } else { 0 })
```

- [ ] **Step 2: Replace null-coalescing for global stats**

```powershell
# Old
total_issues_processed = if ($ConfigBag.GlobalState.stats) { $ConfigBag.GlobalState.stats.total_issues_processed ?? 0 } else { 0 }
total_runs_completed = if ($ConfigBag.GlobalState.stats) { $ConfigBag.GlobalState.stats.total_runs ?? 0 } else { 0 }

# New
total_issues_processed = if ($ConfigBag.GlobalState.stats) { if ($null -ne $ConfigBag.GlobalState.stats.total_issues_processed) { $ConfigBag.GlobalState.stats.total_issues_processed } else { 0 } } else { 0 }
total_runs_completed = if ($ConfigBag.GlobalState.stats) { if ($null -ne $ConfigBag.GlobalState.stats.total_runs) { $ConfigBag.GlobalState.stats.total_runs } else { 0 } } else { 0 }
```

- [ ] **Step 3: Commit changes**

```bash
git add VjMapper/Vorce-Factory/src/runs/MAIN-RUN-04_Optimizer/SUB-RUNS/SUB-RUN-01_MR-04_Optimizer__PerformanceDataCollection/PART-RUNS/PART-RUN-01_MR-04_Optimizer__PerformanceDataCollection__CollectPerformanceMetrics.ps1
git commit -m "refactor: replace PS7 null-coalescing operator in CollectPerformanceMetrics.ps1"
```

---

### Task 8: Refactor System Analysis

**Files:**
- Modify: `VjMapper/Vorce-Factory/src/runs/MAIN-RUN-04_Optimizer/SUB-RUNS/SUB-RUN-02_MR-04_Optimizer__SystemAnalysis/PART-RUNS/PART-RUN-01_MR-04_Optimizer__SystemAnalysis__AnalyzeSystemPerformance.ps1:70`

- [ ] **Step 1: Replace null-coalescing for error_rate**

```powershell
# Old
error_rate = [math]::Round($_.errors / $_.sub_runs * 100, 2) ?? 0

# New
$calculatedErrorRate = [math]::Round($_.errors / $_.sub_runs * 100, 2)
error_rate = $(if ($null -ne $calculatedErrorRate) { $calculatedErrorRate } else { 0 })
```

- [ ] **Step 2: Commit changes**

```bash
git add VjMapper/Vorce-Factory/src/runs/MAIN-RUN-04_Optimizer/SUB-RUNS/SUB-RUN-02_MR-04_Optimizer__SystemAnalysis/PART-RUNS/PART-RUN-01_MR-04_Optimizer__SystemAnalysis__AnalyzeSystemPerformance.ps1
git commit -m "refactor: replace PS7 null-coalescing operator in AnalyzeSystemPerformance.ps1"
```

---

### Task 9: Refactor Memory Maintenance

**Files:**
- Modify: `VjMapper/Vorce-Factory/src/runs/MAIN-RUN-05_MemoryOptimization/SUB-RUNS/SUB-RUN-01_MR-05_MemoryOptimization__MemoryMaintenance/PART-RUNS/PART-RUN-01_MR-05_MemoryOptimization__MemoryMaintenance__OptimizeMemoryStore.ps1:64-88`

- [ ] **Step 1: Replace null-coalescing in type, priority, and source**

```powershell
# Old
$type = $memory.type ?? "unknown"
$priority = $memory.priority ?? "medium"
$source = $memory.source ?? "unknown"

# New
$type = if ($null -ne $memory.type) { $memory.type } else { "unknown" }
$priority = if ($null -ne $memory.priority) { $memory.priority } else { "medium" }
$source = if ($null -ne $memory.source) { $memory.source } else { "unknown" }
```

- [ ] **Step 2: Commit changes**

```bash
git add VjMapper/Vorce-Factory/src/runs/MAIN-RUN-05_MemoryOptimization/SUB-RUNS/SUB-RUN-01_MR-05_MemoryOptimization__MemoryMaintenance/PART-RUNS/PART-RUN-01_MR-05_MemoryOptimization__MemoryMaintenance__OptimizeMemoryStore.ps1
git commit -m "refactor: replace PS7 null-coalescing operator in OptimizeMemoryStore.ps1"
```
