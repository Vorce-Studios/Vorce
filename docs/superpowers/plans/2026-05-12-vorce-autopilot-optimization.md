# Vorce Autopilot Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize the Vorce Autopilot system for stability, concurrency, and responsiveness while fixing critical iteration and security bugs.

**Architecture:** Hybrid orchestration system with a persistent monitor loop, decoupled telemetry sync, and safe library-based state management.

**Tech Stack:** PowerShell 7, GitHub CLI (gh), JSON, REST APIs.

---

### Task 1: Atomic and Synchronized File Access

**Files:**
- Modify: `scripts/codex-cli/lib/state-manager.ps1`
- Modify: `scripts/codex-cli/lib/quota-manager.ps1`

- [ ] **Step 1: Implement `Read-JsonLocked` and `Write-JsonLocked` helpers**
Add these to `lib/state-manager.ps1` to ensure atomic operations.

```powershell
function Read-JsonLocked {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    
    $maxRetries = 5
    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            # Use FileStream with Share Read to prevent reading partially written files
            $fileStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            $reader = [System.IO.StreamReader]::new($fileStream)
            $content = $reader.ReadToEnd()
            $reader.Close()
            $fileStream.Close()
            return ($content | ConvertFrom-Json)
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    throw "Konnte Datei nach $maxRetries Versuchen nicht gesperrt lesen: $Path"
}

function Write-JsonLocked {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Data
    )
    $json = $Data | ConvertTo-Json -Depth 10
    $tempPath = "$Path.tmp"
    
    $maxRetries = 5
    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            # Write to temp file then move (atomic on Windows/NTFS)
            $json | Set-Content $tempPath -Encoding UTF8 -ErrorAction Stop
            Move-Item $tempPath $Path -Force -ErrorAction Stop
            return
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    throw "Konnte Datei nach $maxRetries Versuchen nicht gesperrt schreiben: $Path"
}
```

- [ ] **Step 2: Update `Read-AutopilotState` and `Save-AutopilotState`**
Refactor to use the new locked helpers.

- [ ] **Step 3: Update `Read-QuotaRegistry` and `Save-QuotaRegistry`**
Refactor to use the new locked helpers in `lib/quota-manager.ps1`.

- [ ] **Step 4: Verify with a parallel write test script**
Create a temporary script that tries to write 100 times from two processes and check for data loss.

---

### Task 2: Robust Quota Reset Logic

**Files:**
- Modify: `scripts/codex-cli/lib/quota-manager.ps1`

- [ ] **Step 1: Update `Read-QuotaRegistry` to reset all telemetry fields**
Modify the reset loop to handle nested usage blocks.

```powershell
    # Daily reset check
    $today = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
    if ($registry.last_reset_date -ne $today) {
        foreach ($providerName in ($registry.providers.PSObject.Properties.Name)) {
            $provider = $registry.providers.$providerName
            # Reset the top-level usage if it exists
            if ($provider.usage_today) {
                foreach ($modelProp in $provider.usage_today.PSObject.Properties) {
                    $modelUsage = $modelProp.Value
                    if ($modelUsage -is [PSCustomObject] -or $modelUsage -is [System.Collections.IDictionary]) {
                        foreach ($usageField in $modelUsage.PSObject.Properties.Name) {
                            $modelUsage.$usageField = 0
                            if ($usageField -match "cost") { $modelUsage.$usageField = 0.0 }
                        }
                    } else {
                        $provider.usage_today.$($modelProp.Name) = 0
                        if ($modelProp.Name -match "cost") { $provider.usage_today.$($modelProp.Name) = 0.0 }
                    }
                }
            }
        }
        $registry.last_reset_date = $today
        Save-QuotaRegistry -Registry $registry
    }
```

- [ ] **Step 2: Verify reset logic manually**
Change `last_reset_date` in `quota-registry.json` to yesterday and run `Read-QuotaRegistry`.

---

### Task 3: Fix Iteration Bugs in Monitoring

**Files:**
- Modify: `scripts/codex-cli/phases/monitoring-wakeup.ps1`
- Modify: `scripts/codex-cli/lib/state-manager.ps1`

- [ ] **Step 1: Refactor `Invoke-MonitoringWakeUp` loop**
Use a copy of the array for iteration.

```powershell
    $activeDelegations = @($State.active_delegations) # Copy for safe iteration
    foreach ($delegation in $activeDelegations) {
        # ... logic ...
    }
```

- [ ] **Step 2: Update `Complete-Delegation` to not overwrite but modify reference if possible**
Actually, overwriting is fine if the loop iterates over a copy. But we should ensure `State` is updated correctly.

- [ ] **Step 3: Fix `retry_count` persistence**
Ensure `Save-AutopilotState` is called after updating `retry_count`.

---

### Task 4: Improved Loop Responsiveness

**Files:**
- Modify: `scripts/codex-cli/autopilot.ps1`

- [ ] **Step 1: Implement chunked sleep**
Instead of `Start-Sleep -Seconds $sleepSeconds`, use a loop that checks for a "cancel" or "interrupt" flag file.

```powershell
    $interruptFile = Join-Path $ScriptDir "autopilot.wakeup"
    $remaining = $sleepSeconds
    while ($remaining -gt 0) {
        if (Test-Path $interruptFile) {
            Remove-Item $interruptFile -Force
            Write-Host "[LOOP] Manueller Wake-Up getriggert!" -ForegroundColor Yellow
            break
        }
        $step = [Math]::Min(10, $remaining)
        Start-Sleep -Seconds $step
        $remaining -= $step
    }
```

---

### Task 5: Secure CLI Invocation

**Files:**
- Modify: `scripts/codex-cli/phases/planning-wakeup.ps1`
- Modify: `scripts/codex-cli/phases/monitoring-wakeup.ps1`

- [ ] **Step 1: Replace `Invoke-Expression` with direct calls**
Use `& gh issue create ...` with an array of arguments to avoid injection.

```powershell
    $labels = @($newIssue.labels) + @($Config.issue_filters.autopilot_label)
    $ghArgs = @("issue", "create", "--repo", $repo, "--title", $newIssue.title, "--body", $newIssue.body)
    foreach ($l in $labels) { $ghArgs += @("--label", $l) }
    $created = & gh @ghArgs 2>&1
```

---

### Task 6: Real PR Commenting

**Files:**
- Modify: `scripts/codex-cli/phases/monitoring-wakeup.ps1`

- [ ] **Step 1: Implement `gh pr comment` in the review loop**
After `Invoke-CliTask` for code review, use the output to post a comment.

```powershell
    if ($reviewResult.success) {
        $comment = $reviewResult.output
        & gh pr comment $review.pr_number --repo $repo --body $comment
        $review.review_status = "completed"
    }
```

---

### Task 7: Final Verification

- [ ] **Step 1: Run `Start-Autopilot.ps1` with `-DryRun`**
- [ ] **Step 2: Check logs for JSON errors or synchronization warnings**
- [ ] **Step 3: Verify dashboard still receives data correctly**
