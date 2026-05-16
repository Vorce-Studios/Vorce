# Codex CLI Synchronization and Quota Management Improvements Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor database management to use locked JSON helpers and implement a robust recursive usage reset logic.

**Architecture:** 
- Dot-source `state-manager.ps1` in `database-manager.ps1` to access thread-safe file operations.
- Replace standard `Get-Content`/`Set-Content` in database managers with `Read-JsonLocked` and `Write-JsonLocked`.
- Implement a recursive property reset function in `quota-manager.ps1` to clear all model-specific usage data during the daily reset.

**Tech Stack:** PowerShell 7.4+, JSON

---

### Task 1: Refactor `database-manager.ps1`

**Files:**
- Modify: `scripts/codex-cli/lib/database-manager.ps1`

- [ ] **Step 1: Update imports and refactor `Read-Database` and `Write-Database`**

```powershell
# scripts/codex-cli/lib/database-manager.ps1

# Dot-source state-manager to get Read-JsonLocked/Write-JsonLocked
. (Join-Path $PSScriptRoot "state-manager.ps1")

function Read-Database {
    Initialize-Database
    $data = Read-JsonLocked -Path $DbPath
    if ($null -eq $data) { return @() }
    
    if ($data -isnot [array]) {
        return @($data)
    }
    return $data
}

function Write-Database {
    param([Parameter(Mandatory)][array]$Data)
    Write-JsonLocked -Path $DbPath -Data $Data | Out-Null
}
```

- [ ] **Step 2: Verify database operations still work**
Run a test script to read and write to the database.

---

### Task 2: Improve Daily Reset Logic in `quota-manager.ps1`

**Files:**
- Modify: `scripts/codex-cli/lib/quota-manager.ps1`

- [ ] **Step 1: Implement recursive reset function and update `Read-QuotaRegistry`**

```powershell
# scripts/codex-cli/lib/quota-manager.ps1

function Reset-UsageObject {
    param([Parameter(Mandatory)][object]$Obj)

    foreach ($prop in $Obj.PSObject.Properties) {
        if ($prop.Value -is [System.Management.Automation.PSCustomObject]) {
            Reset-UsageObject -Obj $prop.Value
        }
        else {
            if ($prop.Value -is [int] -or $prop.Value -is [long] -or $prop.Value -is [double] -or $prop.Value -is [decimal]) {
                if ($prop.Name -like "*cost*") {
                    $prop.Value = 0.0
                } else {
                    $prop.Value = 0
                }
            }
        }
    }
}

# In Read-QuotaRegistry:
if ($registry.last_reset_date -ne $today) {
    foreach ($providerName in ($registry.providers.PSObject.Properties.Name)) {
        $provider = $registry.providers.$providerName
        if ($provider.usage_today) {
            Reset-UsageObject -Obj $provider.usage_today
        }
    }
    $registry.last_reset_date = $today
    Save-QuotaRegistry -Registry $registry
    Write-Host "[QUOTA] Taeglicher Reset durchgefuehrt." -ForegroundColor DarkGray
}
```

---

### Task 3: Verification

- [ ] **Step 1: Create a reproduction script**
Create `scripts/codex-cli/test-quota-reset.ps1` that:
1. Backs up `quota-registry.json`.
2. Sets `last_reset_date` to yesterday.
3. Adds deep usage fields to a provider (e.g. `usage_today.gemini-1.5-pro.input_tokens = 1000`).
4. Runs `Read-QuotaRegistry`.
5. Verifies all fields are 0.
6. Restores backup.

- [ ] **Step 2: Run verification script and confirm success**
Expected: ALL usage fields reset to 0/0.0.

- [ ] **Step 3: Cleanup**
Remove test script and backup.
