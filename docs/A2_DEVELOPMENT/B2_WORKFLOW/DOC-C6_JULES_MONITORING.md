# Jules Session Monitoring Workflow

## Overview

The purpose of this workflow is to proactively detect and handle stuck or failed Jules AI development sessions. Active monitoring prevents pull requests from stalling and ensures issues are resolved efficiently.

## Monitoring Thresholds and States

We monitor all active Jules sessions against the following predefined alert states:

- **STALE**: Any active session that has not seen an update (progress, plan, or user message) in **> 1 hour**.
- **FAILED**: Any session that reaches the explicit `FAILED` state from the Jules API.

### Detection Script

The monitoring is automated using the PowerShell script `scripts/jules/monitor-jules-sessions.ps1`.

**Usage Example:**
```powershell
./scripts/jules/monitor-jules-sessions.ps1 -OnlyActive -IncludeActivities
```

This will fetch the sessions, evaluate the thresholds, and print alerts for any session matching the STALE or FAILED criteria.

## Workflow

### 1. Alert Generation
Alerts are generated when the monitoring script identifies a session meeting the critical criteria. The alert includes the repository, issue number, session state, time since last update, and recent activities.

### 2. Owner
- **Primary Owner**: The developer assigned to the linked GitHub issue.
- **Secondary Owner**: Project Lead / Jules Administrator.

### 3. Escalation Path
1. **Initial Alert**: The monitoring script outputs the alert. The primary owner is expected to review the issue.
2. **Review (within 24 hours)**: The primary owner reviews the recent activities to understand why the session is stuck (e.g., waiting for API quota, infinite loop, blocked on missing context).
3. **Escalation**: If the primary owner cannot resolve the stuck state or the issue persists beyond 48 hours, it must be escalated to the Project Lead or raised in the next daily sync.

### 4. Recovery Actions

Based on the type of alert, specific recovery actions must be taken:

#### For STALE Sessions (Active but stuck):
1. **Review Session Details**: Check the latest activities using the monitoring script (`-IncludeActivities`).
2. **Provide Guidance**: Use `respond-jules-session.ps1` to send a clarifying prompt or course-correction message to unblock Jules.
   ```powershell
   ./scripts/jules/respond-jules-session.ps1 -IssueNumber <ID> -Message "Please focus only on the file X and ignore file Y."
   ```
3. **Manual Intervention**: If Jules is stuck in a loop trying to perform an action it cannot complete, intervene manually by committing the required fix directly to the `B-Jules/<Issue>` branch, then prompt Jules to continue from the new state.

#### For FAILED Sessions:
1. **Diagnose**: Identify the exact failure reason from the latest activity summary.
2. **Restart / Re-prompt**:
   - If the failure is transient (e.g., API timeout), restart the session or prompt Jules again.
   - Use `create-jules-session.ps1` to create a fresh session if the current session is permanently broken, making sure to reference the existing work branch so progress isn't lost.
   ```powershell
   ./scripts/jules/create-jules-session.ps1 -IssueNumber <ID>
   ```
3. **Abort**: If the task is too complex for the current context, close the Jules session and re-assign the task for manual development. Update the GitHub issue state accordingly.
