# Vorce-Autopilot Audit Workflow Analyse und Optimierungsvorschläge

**Stand:** 2026-06-07  
**Analysiert von:** Hermes Agent  
**Dokumenttyp:** Technische Analyse + Optimierungsvorschläge

---

## 1. Executive Summary

Der aktuelle Audit Workflow des Vorce-Autopiloten hat folgende Kernprobleme identifiziert:

- **Keine Möglichkeit, Audit Alerts manuell zu bearbeiten** (nur "Alle löschen")
- **Kein Kommentar-System für Alerts** (z.B. "PR #779 verletzt Namenskonvention – OK, da legacy")
- **Alerts werden nicht persistent in Memories gespeichert** (重复 alerts = repeated API calls)

**Empfohlene Lösung:**  
Implementierung eines **"Alert Closed Status"** + **"Comment-to-Memory"**-Workflow für wiederkehrende Alerts.

---

## 2. Aktueller Audit Workflow

### 2.1 Übersicht

```
┌────────────────────────────────────────────────────────────────────┐
│                    AUDIT-WORKFLOW (QA Manager)                      │
└────────────────────────────────────────────────────────────────────┘

1. audit-wakeup.ps1 (alle 15-60 min)
   └── Invoke-DualCeoTask (CEO + QA Manager deliberation)
       └── Liest Issues/PRs aus var/db/
       └── Führt mehrstufige Prüfung durch (audit_sequence in config)
       └── Gibt JSON zurück: { issues_found, action, remediation_command, dashboard_escalation }

2. Wenn Probleme gefunden (issues_found = true):
   └── action = "remediate": Versucht automatisch zu beheben (Invoke-Expression)
   └── action = "escalate": Erstellt DecisionPending Alert im Dashboard
   └── action = "none": Kein manuelles Eingreifen nötig

3. Dashboard visualisiert DecisionPending:
   └── Alert-Liste mit "Alle löschen" Button
   └── Jeder Alert: "Problem", "QA Manager Versuch", "CEO Sondersession"

4. User kann Alert bearbeiten via /api/alerts:
   └── action = "remove": Entfernt eine einzelne DecisionPending
   └── action = "escalate-user": Setzt Alert auf "awaiting_user"
```

### 2.2 Audit-Wakeup.ps1 (Quellcode)

**Datei:** `src/phases/audit-wakeup.ps1`  
**Funktion:** `Invoke-AuditWakeUp`

**Ablauf:**

1. **Step 1-3:** Daten sammeln (Issues, PRs, delegations)
2. **Step 4:** `audit_sequence` ausführen (mehrmals `Invoke-DualCeoTask`)
3. **Step 5:** Finaler Audit-Prompt (deutschsprachig, 7 MANDATE)
4. **Step 6:** Ergebnis parsen → DecisionPending hinzufügen oder Remediation starten

**Wichtige Prompts aus `audit-wakeup.ps1`:**

```powershell
MANDATE DES USERS (VERLETZUNG FÜHRT ZUM ABBRUCH):
1. Du MUSST DEINE ANTWORT ZWINGEND AUF DEUTSCH VERFASSEN!
2. Wenn du Probleme findest, DARFST DU NIEMALS SOFORT ESKALIEREN!
3. STRENGES VERBOT FÜR MERGE-KONFLIKTE: Keine Jules-Sessions für Merge-Konflikte!
4. STRENGES VERBOT FÜR JULES-CANCEL: Keine Sessions stoppen/löschen!
5. Nur wenn KI das Problem nicht lösen kann → 'escalate'
6. Jede Eskalation muss hochdetailliert sein!
7. Eine korrekte Eskalation enthält:
   - WELCHER PR/Issue betroffen ist
   - WARUM die KI es nicht selbst lösen konnte
   - WAS genau der User tun soll (Schritt für Schritt)
```

### 2.3 Dashboard (TypeScript/React)

**Datei:** `dashboard/src/pages/DashboardPage.tsx`  
**API:** `dashboard/vite.config.ts`

**Aktueller Alert-Render:**

```tsx
{sessions.decisions_pending.map((alert: any, idx) => {
  const id = alert.id || String(idx);
  return (
    <div key={id} className="bg-slate-950/50 border border-rose-500/20 rounded-lg p-4">
      <div className="flex flex-wrap items-start justify-between gap-3 mb-3">
        <div>
          <div className="font-semibold text-rose-200">
            {normalizeAuditText(alert.topic || 'QA Manager Alert')}
          </div>
          <div className="text-xs text-rose-300/70 mt-0.5">
            Zuständig: {owner} · {auditStageLabel(alert)} · {timeAgo(alert.created_at)}
          </div>
        </div>
        <button onClick={() => updateAuditAlert('remove', id)}>
          <Trash2 className="w-4 h-4" />
        </button>
      </div>

      {/* Problem, Remediation, CEO Sondersession Panels */}
    </div>
  );
})}
```

**Aktueller Alert API Handler:**

```typescript
// dashboard/vite.config.ts line 396-433
else if (req.method === 'POST' && req.url === '/api/alerts') {
  if (payload.action === 'clear') {
    state.decisions_pending = [];
  } else if (payload.action === 'remove') {
    state.decisions_pending = state.decisions_pending.filter(
      (alert, idx) => String(alert.id || idx) !== String(payload.id)
    );
  } else if (payload.action === 'escalate-user') {
    const alert = state.decisions_pending.find(...);
    alert.owner = 'user';
    alert.status = 'awaiting_user';
    alert.process_stage = 'user_decision';
    alert.escalation_level = 'user';
    alert.user_escalation_reason = payload.response || '...';
  }
}
```

---

## 3. Identifizierte Probleme

### 3.1 Klassifizierung nach Schweregrad

| Schweregrad | Problem | Betroffene Stellen | Auswirkung |
|-------------|---------|-------------------|------------|
| **Kritisch** | Keine Möglichkeit, Alerts mit Kommentar zu "schließen" | Dashboard + API | Endlose wiederkehrende Alerts |
| **Wichtig** | Alert-"Löschen" = echtes Löschen (kein Status-Update) | API + Frontend | Datenverlust |
| **Wichtig** | Keine Memory-Integration für wiederkehrende Alerts | Memory Store + Audit | repeat alerts = repeat calls |
| **Mittel** | `decisions_pending` hat kein `id`-Feld (nutzt Array-Index) | Frontend `alert.id || idx` | Bug: Index-Shift nach `remove` |
| **Mittel** | Keine `owner`-Zuweisung bei Create | `monitoring-wakeup.ps1:130` | Alle Alerts sind "QA Manager" |
| **Optional** | `created_at` ohne User-Überschreibung | PowerShell `Get-Date -Format 'o'` | Keine "Replay"-Unterstützung |

### 3.2 Detaillierte Problembeschreibung

#### Problem 1: **Wiederkehrende Alerts ohne Möglichkeit zur "Ignorieren"-Markierung**

**Beispiel aus User-Anfrage:**
> "PR #779 verletzt Vorce-Namenskonvention" – Dieses Alert erscheint jedes Mal neu.

**Grund:**
- `Add-DecisionPending` prüft nur `$_topic -eq $Topic` in `monitoring-wakeup.ps1:137`
- Wenn Alert bereits existiert, wird er **nicht neu hinzugefügt**
- **Aber:** Wenn Alert einmal durch `clear-alerts` oder `remove` gelöscht wurde, erscheint er beim nächsten Mal wieder neu (da PR immer noch offen)
- **Keine Möglichkeit für User, "Ignoriere dieses Alert für diesen PR" zu sagen**

**Folge:**
- User muss jedes Mal manuell löschen oder warten bis PR weg ist
- Keine Möglichkeit, dauerhafte Ausnahmen zu hinterlegen

#### Problem 2: **Kein Comment-System für Alerts**

**Aktueller State:**
- Alert hat nur `topic`, `context`, `created_at`
- Kein Feld für `comment` oder `user_notes`
- Kein Feld für `status` (pending/closed/ignored)

**Folge:**
- User kann keine Begründung für "Ignorieren" hinterlegen (z.B. "legacy PR")
- QA Manager sieht nicht, dass Alert manuell geprüft wurde

#### Problem 3: **"Alle löschen" löscht alle Alerts (inkl. wichtige Entscheidungen)**

**Aktueller State:**
- `/api/clear-alerts` setzt `state.decisions_pending = []`
- **Keine Unterscheidung** zwischen "manuell gelöscht" vs "neu entstanden"

**Folge:**
- User kann versehentlich wichtige Alerts löschen
- Keine Historie der Entscheidungen

#### Problem 4: **Keine Memory-Integration**

**Aktueller State:**
- `src/lib/memory-store.ps1` existiert und ist vollständig implementiert
- `Add-Memory` / `Search-Memories` / `Get-RelevantMemories` verfügbar
- **Aber:** Audit Alerts werden **nicht automatisch in Memories umgewandelt**

**Folge:**
- User-Sachen wie "PR #779 OK, da legacy" werden nicht als Memory gespeichert
- QA Manager weiß beim nächsten Mal nicht, dass dies bereits geklärt wurde

---

## 4. Optimierungsvorschläge

### 4.1 **Vorschlag A: Alert-Closed-Status mit Comment (MINIMAL CHANGE)**

**Ziel:** Alertstatus von `pending` → `closed` ändern (statt löschen)  
**Umfang:** ~200 Zeilen Codeänderung  
**Risiko:** Gering

#### Änderungen:

1. **Alert-Struktur erweitern** (`dashboard/src/types.ts`):
```typescript
export interface DecisionPending {
  id: string;  // ← neu: persistent ID
  topic: string;
  context: string;
  created_at: string;
  status: 'pending' | 'closed' | 'ignored';  // ← neu
  closed_by?: 'user' | 'system';
  closed_at?: string;
  user_comment?: string;  // ← neu
}
```

2. **Alert-Creation in PowerShell erweitern** (`monitoring-wakeup.ps1`):
```powershell
function Add-DecisionPending {
    param([Parameter(Mandatory)][object]$State, [Parameter(Mandatory)][string]$Topic, [Parameter(Mandatory)][string]$Context)
    
    $id = "alert-$(Get-Date -Format 'yyyyMMddHHmmss')-$([guid]::NewGuid().ToString('N').Substring(0,4))"
    
    $exists = $State.decisions_pending | Where-Object { $_.topic -eq $Topic -and $_.status -eq 'pending' }
    if (-not $exists) {
        $State.decisions_pending += @([ordered]@{
            id         = $id
            topic      = $Topic
            context    = $Context
            created_at = (Get-Date -Format 'o')
            status     = 'pending'  # ← neu
        })
    }
}
```

3. **API-Handler erweitern** (`vite.config.ts`):
```typescript
else if (payload.action === 'close-alert') {
  const alert = state.decisions_pending.find((item) => String(item.id) === String(payload.id));
  if (alert) {
    alert.status = 'closed';
    alert.closed_by = 'user';
    alert.closed_at = new Date().toISOString();
    alert.user_comment = payload.comment || 'Manuell geschlossen';
  }
}
else if (payload.action === 'ignore-alert') {
  const alert = state.decisions_pending.find((item) => String(item.id) === String(payload.id));
  if (alert) {
    alert.status = 'ignored';
    alert.closed_by = 'user';
    alert.closed_at = new Date().toISOString();
    alert.user_comment = payload.comment || 'Ignoriert (repeat-accept)';
    
    // ← Optional: In Memory umwandeln
    if (payload.create_memory && payload.create_memory === true) {
      const memory = {
        id: `mem-${Date.now()}`,
        text: `Ignore alert: ${alert.topic} | ${alert.context}`,
        type: 'temporary',
        priority: 'medium',
        created_at: new Date().toISOString(),
        source: 'dashboard_alert_close'
      };
      store.memories.push(memory);
    }
  }
}
```

4. **Frontend-Render erweitern** (`DashboardPage.tsx`):
```tsx
{sessions.decisions_pending.map((alert: any, idx) => {
  const id = alert.id || String(idx);
  
  if (alert.status === 'closed' || alert.status === 'ignored') {
    return (
      <div key={id} className="opacity-50 border-l-4 border-green-500">
        <div className="font-semibold text-green-200">Geschlossen: {alert.topic}</div>
        <div className="text-xs text-green-300">Geschlossen von: {alert.closed_by}</div>
        {alert.user_comment && <div className="text-sm text-slate-300">Kommentar: {alert.user_comment}</div>}
      </div>
    );
  }
  
  return (
    <div key={id} className="bg-slate-950/50 border border-rose-500/20 rounded-lg p-4">
      {/* ... existing render code ... */}
      <div className="mt-3">
        <button 
          onClick={() => updateAuditAlert('close-with-comment', id, prompt('Kommentar (optional):'))}
          className="text-xs px-3 py-1.5 rounded-lg bg-green-500/20 text-green-200"
        >
          Schließen & Kommentar
        </button>
        {alert.status !== 'ignored' && (
          <button 
            onClick={() => updateAuditAlert('ignore-with-comment', id, prompt('Warum ignorieren? (für Memory):'))}
            className="text-xs px-3 py-1.5 rounded-lg bg-amber-500/20 text-amber-200 ml-2"
          >
            Ignorieren & MemoryErstellen
          </button>
        )}
      </div>
    </div>
  );
})}
```

---

### 4.2 **Vorschlag B: Alert-to-Memory Auto-Wandlung (EMPFOHLEN)**

**Ziel:** Alerts mit `user_comment` automatisch in `autopilot-memories.json` umwandeln  
**Umfang:** ~300 Zeilen (PowerShell + API + Memory-Integration)  
**Risiko:** Mittel (Memory-Manipulation)

#### Ablauf:

```
User schließt Alert mit Comment
        ↓
API: Erstellt Memory mit Text="Ignore: [topic] | [context] | [user_comment]"
        ↓
Memory Store: Save-MemoryStore(autopilot-memories.json)
        ↓
QA Manager: Wenn Alert wieder auftaucht → Search-Memories("ignore PR #779")
        ↓
QA Manager: Memory gefunden → Skips Alert
```

#### PowerShell-Funktion (neu in `sources/audit-wakeup.ps1`):

```powershell
function Convert-AlertToMemory {
    param(
        [Parameter(Mandatory)][object]$DecisionPending,
        [string]$UserComment = ""
    )
    
    $memoryText = "IGNORE_ALERT: $($DecisionPending.topic)`nDetails: $($DecisionPending.context)`n"
    if (-not [string]::IsNullOrWhiteSpace($UserComment)) {
        $memoryText += "User-Kommentar: $UserComment"
    }
    
    $result = Add-Memory -Text $memoryText -Type "temporary" -Priority "medium" -Source "audit_alert_close"
    return $result
}
```

#### Integration in `monitoring-wakeup.ps1:847` (Cleanup):

```powershell
# --- Step 4: Cleanup decisions_pending (mit Memory-Integration) ---
foreach ($decision in $State.decisions_pending) {
    if ($decision.status -eq 'closed' -or $decision.status -eq 'ignored') {
        # Versuche, Alert in Memory umzuwandeln (für zukünftige Ignorierung)
        if (-not $decision.memory_id -and -not [string]::IsNullOrWhiteSpace($decision.user_comment)) {
            $memResult = Convert-AlertToMemory -DecisionPending $decision -UserComment $decision.user_comment
            if ($memResult) {
                $decision.memory_id = "mem-auto-$($decision.id)"  # ← neu: verknüpft Memory-ID
            }
        }
        
        # Entscheidung wegwerfen (nicht in decisions_pending belassen)
        $keep = $false
    }
    # ... existing cleanup logic ...
}
```

---

### 4.3 **Vorschlag C: Memory-basiertes Alert-Control (MAXIMAL OPTIMIERUNG)**

**Ziel:** QA Manager prüft automatisch vor Alert-Erstellung, ob ein类似es Memory existiert  
**Umfang:** ~500 Zeilen (PowerShell + Prompt-Engineering)  
**Risiko:** Hoch (Prompt-Veränderung)

#### Ablauf:

```
1. monitoring-wakeup.ps1 erkennt Alert-Situation (z.B. PR #779 Namenskonflikt)
        ↓
2. Run-SearchMemories("PR #779 Vorce-Namenskonvention")
        ↓
3. Wenn Memory gefunden: Skips Alert-Erstellung
        ↓
4. Wenn Memory nicht gefunden: Add-DecisionPending
```

#### PowerShell-Pseudocode:

```powershell
# In monitoring-wakeup.ps1, bevor Add-DecisionPending aufgerufen wird:
function Should-Skip-Alert {
    param([Parameter(Mandatory)][string]$AlertTopic, [Parameter(Mandatory)][string]$AlertContext)
    
    $query = "$AlertTopic $AlertContext"
    $result = Search-Memories -Query $query -Store (Read-MemoryStore)
    
    if (-not [string]::IsNullOrWhiteSpace($result)) {
        Write-Host "[MONITOR] Memory gefunden für '$AlertTopic' → Überspringe Alert." -ForegroundColor DarkGray
        return $true
    }
    return $false
}

# In decision-pending-creation:
if (-not (Should-Skip-Alert -AlertTopic $topic -AlertContext $context)) {
    Add-DecisionPending -State $State -Topic $topic -Context $context
}
```

#### Prompt-Änderung in `audit-wakeup.ps1`:

```powershell
# Neue Instruction für QA Manager:
"""
BEFORE CREATING A NEW ALERT:
1. Run Search-Memories with: "[Alert Topic] [Alert Context]"
2. If memory found: DO NOT create decision_pending, instead add user_comment to memory
3. If NO memory found: Create decision_pending as normal
"""
```

---

## 5. Empfohlene Implementierung

### 5.1 **Phase 1: Alert-Closed-Status (1-2 Stunden)**

1. Alert-Struktur erweitern (`id`, `status`, `user_comment`)
2. `Add-DecisionPending` mit `id` erweitern
3. `/api/alerts` um `close-alert`, `ignore-alert` erweitern
4. Dashboard-Render erweitern (grüner "closed"-Status)

**Bonus:** `user_comment` als Memory speichern (optional)

### 5.2 **Phase 2: Memory-Integration (2-3 Stunden)**

1. `Convert-AlertToMemory` Funktion erstellen
2. Cleanup-Logik in `monitoring-wakeup.ps1` erweitern
3. Memory-ID in DecisionPending speichern (`memory_id`)

### 5.3 **Phase 3: Memory-based Alert-Control (4-6 Stunden)**

1. `Should-Skip-Alert` Funktion erstellen
2. Prompt in `audit-wakeup.ps1` erweitern
3. Testen mit repetetiven Alerts (z.B. PR #779)

---

## 6. Kompatibilität mit bestehendem System

### 6.1 **Backward Compatibility**

| Feature | Betroffene Dateien | BC-Verschiebung | Lösung |
|---------|-------------------|-----------------|--------|
| Alert `id` neu | Frontend + API | Low (Array-Index fallback) | `alert.id || idx` bleibt erhalten |
| Alert `status` neu | API + Frontend | Medium (new field) | Default `pending` in PowerShell |
| `Search-Memories` in Prompt | `audit-wakeup.ps1` | Low (new instruction) | Keine BC-Issue, nur Erweiterung |

### 6.2 **Test-Plan**

1. **Unit Tests:**
   - `Add-DecisionPending` mit `id` erzeugt korrekte GUID
   - `/api/alerts` `close-alert` setzt `status = 'closed'`
   - `Search-Memories("PR #779")` findet repeat-alert-memory

2. **Integration Tests:**
   - `monitoring-wakeup.ps1` erstellt Alert → User schließt Alert → Alert erscheint nicht mehr
   - Memory wird erstellt → QA Manager überspringt Alert

3. **Manuelle Tests:**
   - Dashboard öffnet sich mit neuen Alert-Buttons
   - Kommentar erscheint im UI nach `close-with-comment`
   - Memory ist in `memories.json` sichtbar

---

## 7. FAQ

### Frag 1: **Warum nicht einfach `status` statt löschen?**

**Antwort:** 
- "Löschen" impliziert "wird nicht mehr benötigt"
- "Schließen" impliziert "wurde manuell geprüft"
- `status = 'closed'` behält Alert in Historie, `status = 'pending'` zeigt aktuelle Probleme

### Frag 2: **Warum Memory statt GitHub Issue Label?**

**Antwort:**
- Memorie-System existiert bereits (`src/lib/memory-store.ps1`)
- Memories sind für "Regeln und Ausnahmen" gedacht
- GitHub Labels sind für "Issue-Kategorisierung"
- Memorie-Integration ist einfacher (ein JSON-File)

### Frag 3: **Was passiert, wenn User Alert schließt, aber Memory vergisst?**

**Antwort:**
- Memory-System hat max **30 Einträge** (`memory-store.ps1:346`)
- `Optimize-AutopilotMemories` löscht alte Einträge
- QA Manager kann sich "Erinnerungen anzeigen" lassen

---

## 8. Anhänge

### 8.1 **Dateiliste der geänderten/analysierten Dateien**

| Datei | Zeilen | Status |
|-------|--------|--------|
| `src/phases/audit-wakeup.ps1` | 209 | Analysiert |
| `dashboard/src/types.ts` | 260 | Analysiert |
| `dashboard/src/pages/DashboardPage.tsx` | 915 | Analysiert |
| `dashboard/vite.config.ts` | 648 | Analysiert |
| `src/lib/memory-store.ps1` | 467 | Analysiert |
| `src/lib/state-manager.ps1` | 650 | Analysiert |
| `src/phases/monitoring-wakeup.ps1` | 952 | Analysiert |

### 8.2 **Audit-Alert-Status-Diagramm**

```
┌──────────────┐
│   PENDING    │  ← Alert erstellt (QA Manager)
└──────┬───────┘
       │
       │  User schließt mit Kommentar
       ▼
┌──────────────┐
│   CLOSED     │  ← Alert manuell geprüft
└──────┬───────┘
       │
       │  Alert wiederholt sich (PR offen)
       ▼
┌──────────────┐
│   IGNORED    │  ← Alert wird ignoriert (Memory erstellt)
└──────┬───────┘
       │
       │  User entfernt Memory
       ▼
┌──────────────┐
│   DELETED    │  ← Alert komplett entfernt
└──────────────┘
```

### 8.3 **Memory-Format (Beispiel)**

```json
{
  "id": "mem-20260607153045-a1b2",
  "text": "IGNORE_ALERT: PR #779 verletzt Vorce-Namenskonvention | Titel 'feature/new-ui' kann keinem gueltigen Vorce-Issue-Titel zugeordnet werden. Erwartet: PR_{IssueTitle}.\nUser-Kommentar: Legacy PR, wird nicht umbenannt",
  "type": "temporary",
  "priority": "medium",
  "created_at": "2026-06-07T15:30:45.000Z",
  "source": "audit_alert_close"
}
```

---

## 9. Next Steps

1. **User-Konsens:** Vorschlag A/B/CDiskussion
2. **Implementierung:** Phase 1 → Phase 2 → Phase 3
3. **Testing:** Unit/Integration/Manual Tests
4. **Dokumentation:** Update `docs/` mit neuen Workflows

---

**Ende der Dokumentation**
