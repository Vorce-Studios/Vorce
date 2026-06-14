# PART-RUN Architecture Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the PART-RUN architecture in Vorce-Autopilot_2.0 to strictly follow the hierarchical model and naming conventions.

**Architecture:** MAIN-RUN -> ROUTER -> SUB-RUN -> PART-RUN -> PART-AGENT -> MICRO-WORKER. Enforces consistent logging and tracking via `Invoke-PartRun`.

**Tech Stack:** PowerShell, Vorce-Autopilot 2.0 Orchestrator.

---

### Task 1: Refactor SUB-RUN-04_MR-02_CheckAndDoing__ReviewDispatch.ps1

**Files:**

- Modify: `Vorce-Autopilot_2.0/src/runs/SUB-RUN/SUB-RUN-04_MR-02_CheckAndDoing__ReviewDispatch.ps1`

- [ ] **Step 1: Remove outdated Monitoring Sequence code block**
  Remove the section `if ($Config.PSObject.Properties.Name -contains "monitoring_sequence") { ... }` (Lines 41-71).

- [ ] **Step 2: Wrap PR Review 'Invoke-CliTask' in 'Invoke-PartRun'**
  Find the `Invoke-CliTask` call for code reviews (around Line 140) and replace it with an `Invoke-PartRun` call following the naming convention.

```powershell
# Old code
$reviewResult = Invoke-CliTask -QuotaRegistry $QuotaRegistry -TaskType "code_review" -DryRun:$DryRun -Prompt $reviewPrompt

# New code
$partRunName = "PART-RUN-01_SR-04_MR-02_CheckAndDoing__PRReview-PR-$($review.pr_number)"
$reviewResult = Invoke-PartRun `
    -PartRunName $partRunName `
    -AgentType "QA-Manager" `
    -Prompt $reviewPrompt `
    -SubState $SubState `
    -Config $Config `
    -QuotaRegistry $QuotaRegistry `
    -DryRun:$DryRun
```

- [ ] **Step 3: Commit**

```bash
git add Vorce-Autopilot_2.0/src/runs/SUB-RUN/SUB-RUN-04_MR-02_CheckAndDoing__ReviewDispatch.ps1
git commit -m "refactor(sr-04): remove legacy monitoring sequence and wrap PR reviews in Part-Run"
```

---

### Task 2: Refine Naming in SUB-RUN-02_MR-01_Planning__Triage.ps1

**Files:**

- Modify: `Vorce-Autopilot_2.0/src/runs/SUB-RUN/SUB-RUN-02_MR-01_Planning__Triage.ps1`

- [ ] **Step 1: Update Part-Run names for CEO Proposal, QA Critique, and CEO Synthesis**
  Update the names to follow the `PART-RUN-{NR}_SR-{SR-NR}_MR-{MR-NR}_{Phase}__{Funktion}` convention.

```powershell
# Proposal
$proposalPartName = "PART-RUN-01_SR-02_MR-01_Planning__CEOProposal-Issue-$issueNum"

# Critique
$critiquePartName = "PART-RUN-02_SR-02_MR-01_Planning__QACritique-Issue-$issueNum"

# Synthesis
$synthesisPartName = "PART-RUN-03_SR-02_MR-01_Planning__CEOSynthesis-Issue-$issueNum"
```

- [ ] **Step 2: Commit**

```bash
git add Vorce-Autopilot_2.0/src/runs/SUB-RUN/SUB-RUN-02_MR-01_Planning__Triage.ps1
git commit -m "style(sr-02): refine Part-Run names to follow convention"
```

---

### Task 3: Refine Naming in SUB-RUN-03_MR-01_Planning__Strategy.ps1

**Files:**

- Modify: `Vorce-Autopilot_2.0/src/runs/SUB-RUN/SUB-RUN-03_MR-01_Planning__Strategy.ps1`

- [ ] **Step 1: Update Part-Run names for sequential planning steps**
  Update the name generation inside the loop (around Line 106).

```powershell
# Old code
$partName = "PART-RUN-01_SR-03_MR-01_Planning__$($step.label -replace '[^A-Za-z0-9]', '-')"

# New code
$partIdx = "{0:D2}" -f ($idx) # Need to maintain an index
$partName = "PART-RUN-$partIdx_SR-03_MR-01_Planning__$($step.label -replace '[^A-Za-z0-9]', '-')"
```

- [ ] **Step 2: Update Part-Run name for fallback single-phase planning**
  Update the name `PART-RUN-01_SR-03_MR-01_Planning__IssueProposal` (around Line 221).

- [ ] **Step 3: Commit**

```bash
git add Vorce-Autopilot_2.0/src/runs/SUB-RUN/SUB-RUN-03_MR-01_Planning__Strategy.ps1
git commit -m "style(sr-03): refine Part-Run names for strategy generation"
```

---

### Task 4: Refine Naming in SUB-RUN-05_MR-01_Planning__Optimization.ps1

**Files:**

- Modify: `Vorce-Autopilot_2.0/src/runs/SUB-RUN/SUB-RUN-05_MR-01_Planning__Optimization.ps1`

- [ ] **Step 1: Update Part-Run names for Memory Optimization and Optimizer Analysis**
  Update the names to follow the convention.

```powershell
# Memory Optimization
$partName = "PART-RUN-01_SR-05_MR-01_Planning__MemoryOptimization"

# Optimizer Analysis
$partName = "PART-RUN-02_SR-05_MR-01_Planning__OptimizerAnalysis"
```

- [ ] **Step 2: Commit**

```bash
git add Vorce-Autopilot_2.0/src/runs/SUB-RUN/SUB-RUN-05_MR-01_Planning__Optimization.ps1
git commit -m "style(sr-05): refine Part-Run names for optimization"
```

---

### Task 5: Verification

- [ ] **Step 1: Run a dry run of the Autopilot and check logs/state**
  Execute `Vorce-Autopilot_2.0/test-autopilot-regression.ps1` or a similar script in DryRun mode.
  Verify that `[PART-RUN]` log entries appear correctly and follow the new naming scheme.
  Verify that `var/run/.../PART-RUNS/` directories are created with correct names and `PART-RUN-STATE.json` files.

- [ ] **Step 2: Verify that no direct 'Invoke-CliTask' or CLI commands remain for AI prompts**
  Grep for `Invoke-CliTask` and `gemini` / `claude` calls in `SUB-RUN` directory to ensure they are all wrapped in `Invoke-PartRun` where applicable (excluding utility functions like `Get-GitHubPullRequests`).
