# Audit Workflow Analyse & Optimierungsvorschläge

**Analysiert von**: Hermes Agent
**Datum**: 2026-06-07
**Basis**: `DashboardPage.tsx`, `vite.config.ts` API-Endpoints

---

## Aktueller Audit Alert Workflow

### 1. Alert-Entstehung

- Audit-System erkennt Probleme (z.B. PR #779 verletzt Vorce-Namenskonvention)
- Alert wird in `state.decisions_pending` gespeichert
- Alert enthält: `topic`, `context`, `remediation_command`, `remediation_result`, `owner`

### 2. Alert-Anzeige im Dashboard

```tsx
{sessions.decisions_pending && sessions.decisions_pending.length > 0 && (
  <div className="audit-alerts">
    {sessions.decisions_pending.map((alert, idx) => (
      <AlertCard key={id} alert={alert} />
    ))}
  </div>
)}
```

### 3. Aktuelle Aktionen für jeden Alert

1. **"Alle löschen"** - `/api/clear-alerts` → `state.decisions_pending = []`
2. **Einzelner Alert "Trashing"** - `updateAuditAlert('remove', id)` → Alert aus Liste entfernt
3. **"An mich eskalieren"** - `updateAuditAlert('escalate-user', id, reason)` → Alert wird User-zuständig

### 4. API-Endpunkt `/api/alerts` (vite.config.ts:396-502)

```typescript
// NEW: Handle "close-alert" action - mark alert as closed with optional comment
if (payload.action === 'close-alert') {
  alert.status = 'closed';
  alert.closed_by = 'user';
  alert.closed_at = new Date().toISOString();
  alert.user_comment = payload.comment || 'Manuell geschlossen';
  return;
}

// NEW: Handle "ignore-alert" action - mark alert as ignored and create memory
if (payload.action === 'ignore-alert') {
  alert.status = 'ignored';
  // Erstelle Memory-Entry für zukünftige Verwendung
  const memoryEntry = {
    id: `mem-${Date.now()}-${Math.random().toString(36).substr(2, 4)}`,
    text: `IGNORE_ALERT: ${alert.topic}\\nDetails: ${alert.context}\\nUser-Kommentar: ${alert.user_comment}`,
    type: 'temporary',
    priority: 'medium',
    created_at: new Date().toISOString(),
    source: 'dashboard_alert_ignore'
  };
  store.memories.push(memoryEntry);
  return;
}
```

---

## Analyse der Probleme

### Problem 1: alerts wiederholen sich bei gleichen PRs

**Beschreibung**: Alert für "PR #779 verletzt Vorce-Namenskonvention" erscheint jedes Mal wieder, auch wenn der User ihn bereits "gelöscht"/"geschlossen" hat.

**Ursache**:

1. Alert ist **temporär** - speichert sich nicht dauerhaft im State
2. PR #779 existiert weiterhin im GitHub
3. Audit-System prüft jedes Mal alle offenen PRs neu
4. Keine Memory-Basierung - die Alerts werden nicht als "verarbeitet" markiert

**Betroffenen Bereiche**:

- `/api/clear-alerts` löscht nur die Anzeige, nicht die zugrundeliegende PR-Prüfung
- `remove` Aktion entfernt nur den Alert aus `decisions_pending`, nicht als "verarbeitet" markiert

---

### Problem 2: Keine Möglichkeit für "Permanente Ignorierung" mit Kommentar

**Beschreibung**: User kann Alert nur "remove" (temporär) oder "clear" (alle löschen), aber **nicht dauerhaft ignorieren mit Begründung**.

**Aktuelle Limitationen**:

1. `remove` Aktion löscht Alert nur aus `decisions_pending` →下次 wieder erscheinen
2. Kein `ignore-permanent` Action mit Memory-Erstellung
3. Kein Kommentar-Feld in der UI für User-Feedback

---

### Problem 3: UI ist unklar - was passiert beim "Löschen"?

**Beschreibung**: User klickt auf "Löschen"-Button und denkt, das Problem ist gelöst, aber es erscheint beim nächsten Scan neu.

**UI-Probleme**:

1. Button-Title sagt nur "Audit Alert löschen" → unklar ob temporär oder permanent
2. Keine Status-Anzeige (`closed`, `ignored`, `solved`)
3. Keine Feedback-Nachricht nach Aktion

---

## Optimierungsvorschläge

### ### 🔴 Vorschlag 1: "Close/Ignore" als primäre Aktion (Empfohlen)

**Konzept**: Ersetze "Trash"-Button durch "Close"-Button mit Kommentar-Feld.

**Implementierung**:

```tsx
// Neue Aktion: Close mit Kommentar
<div className="flex gap-2 mt-3">
  <button onClick={() => updateAuditAlert('close-alert', id)}>
    <CheckCircle className="w-4 h-4" />
    Schließen
  </button>
  <button onClick={() => updateAuditAlert('ignore-alert', id)}>
    <Ban className="w-4 h-4" />
    Ignorieren & Memory
  </button>
</div>

// Modal für Kommentar
{showCommentModal && (
  <div className="modal">
    <input
      placeholder="Kommentar: Warum wird dieser Alert ignoriert?"
      onChange={(e) => setComment(e.target.value)}
    />
    <button onClick={() => updateAuditAlert('ignore-alert', id, comment)}>
      Ignorieren
    </button>
  </div>
)}
```

**API-Changes**:

```typescript
// In vite.config.ts: close-alert
if (payload.action === 'close-alert') {
  alert.status = 'closed';
  alert.closed_by = 'user';
  alert.closed_at = new Date().toISOString();
  alert.user_comment = payload.comment || 'Manuell geschlossen';
  return { status: 'ok', alert };
}

// In vite.config.ts: ignore-alert (existiert bereits!)
// Erstelle Memory für zukünftige Verwendung
// Alert wird als 'ignored' markiert und erscheint nicht mehr
```

**Vorteile**:

- ✅ User-Feedback wird dokumentiert
- ✅ Memory wird erstellt für zukünftige PR-Prüfungen
- ✅/alert wird als "closed" markiert (kein erneutes Erscheinen)
- ✅ Begründung ist für andere Agenten sichtbar

**Nachteile**:

- ⚠️ Required UI-Änderung (Modal für Kommentar)

---

### ### 🟡 Vorschlag 2: Status-Anzeige & Verlauf

**Konzept**: Füge Status-Chip und History-Log zu jedem Alert hinzu.

**Implementierung**:

```tsx
<div className="flex items-center gap-2 mb-2">
  {alert.status === 'closed' && (
    <span className="text-[10px] px-2 py-1 bg-emerald-500/20 text-emerald-300 rounded">
      Geschlossen
    </span>
  )}
  {alert.status === 'ignored' && (
    <span className="text-[10px] px-2 py-1 bg-slate-500/20 text-slate-300 rounded">
      Ignoriert
    </span>
  )}
  <span className="text-[10px] text-slate-500">
    {alert.user_comment && `Begründung: ${alert.user_comment}`}
  </span>
</div>
```

**Vorteile**:

- ✅ User sieht sofort Status
- ✅ Comment wird sichtbar
- ✅ Verlauf wird dokumentiert

---

### ### 🟢 Vorschlag 3: "Never Again" Memory-Pattern

**Konzept**: Automatische Memory-Erstellung bei "Ignore" mit smarter Pattern-Matching.

**Implementierung**:

```typescript
// Memory-Entry für ignored Alert
const memoryEntry = {
  id: `mem-${Date.now()}`,
  text: `IGNORE_ALERT_PATTERN: ${alert.topic}\\nContext: ${alert.context}\\nComment: ${alert.user_comment}\\nPattern: "${alert.topic}" für "$VORCE_NAMING_CONVENTION"`,
  type: 'permanent',
  priority: 'high',
  tags: ['vorce-naming-convention', 'pr-alerts'],
  created_at: new Date().toISOString(),
  source: 'dashboard_alert_ignore'
};

// Zukunft: Agent prüft "IGNORE_ALERT_PATTERN" Memory before Alert-Erstellung
// Wenn PR-Nummer im Context enthalten → Alert nicht erzeugen
```

**Vorteile**:

- ✅ Memory ist strukturiert für spätere Nutzung
- ✅ Agent kann "Never Again" Regeln abrufen
- ✅ Reduktion von wiederholten Alerts

**Nachteile**:

- ⚠️ Required Backend-Änderung (Agent prüft Memory before Alert)

---

### ### 🔵 Vorschlag 4: Batch-Processing für wiederkehrende Alerts

**Konzept**: Wenn mehrere Alerts gleicher Art (z.B. alle "PR #XXX verletzt Namenskonvention"), bieten "Alle ignorieren" an.

**Implementierung**:

```tsx
{sessions.decisions_pending.filter(a => a.topic.includes('Namenskonvention')).length > 1 && (
  <button
    onClick={() => bulkIgnoreAlerts('Namenskonvention', comment)}
    className="mt-3 text-sm text-amber-300 hover:text-amber-200"
  >
    Alle Namenskonflikt-Alerts ignorieren
  </button>
)}
```

**Vorteile**:

- ✅ schneller für wiederkehrende Probleme
- ✅ weniger Clicks für User

---

## Empfohlene Implementierung

### Phase 1: UI-Update (Sofort)

**Änderungen**:

1. "Trash"-Button durch "Close"-Button ersetzen
2. Modal für Kommentar-Feld hinzufügen
3. Status-Chip für `closed`, `ignored` hinzufügen

**Code-Änderungen**:

```tsx
// DashboardPage.tsx: Close-Button statt Trash
<div className="flex justify-end gap-2 mt-3">
  {/* Kommentar Modal */}
  {showCommentModal === id && (
    <div className="modal">
      <input
        placeholder="Kommentar (warum ignorieren/geschlossen?)"
        value={commentDraft}
        onChange={(e) => setCommentDraft(e.target.value)}
      />
      <div className="flex gap-2 mt-2">
        <button onClick={() => {
          updateAuditAlert('close-alert', id, commentDraft);
          setShowCommentModal(null);
        }}>
          Schließen
        </button>
        <button onClick={() => {
          updateAuditAlert('ignore-alert', id, commentDraft);
          setShowCommentModal(null);
        }}>
          Ignorieren & Memory
        </button>
        <button onClick={() => setShowCommentModal(null)}>
          Abbrechen
        </button>
      </div>
    </div>
  )}

  {/* Status-Chip */}
  {alert.status === 'closed' && (
    <span className="text-xs text-emerald-400">Geschlossen: {timeAgo(alert.closed_at)}</span>
  )}
  {alert.status === 'ignored' && (
    <span className="text-xs text-amber-400">Ignoriert: {timeAgo(alert.closed_at)}</span>
  )}

  {/* Action Buttons */}
  {!alert.status && (
    <button onClick={() => setShowCommentModal(id)}>
      <CheckCircle className="w-4 h-4" />
      Schließen
    </button>
  )}
  {!alert.status && (
    <button onClick={() => setShowCommentModal(id)}>
      <Ban className="w-4 h-4" />
      Ignorieren
    </button>
  )}
</div>
```

---

### Phase 2: Backend-Check (Nächster Sprint)

**Änderungen**:

1. Agent prüft Memory vor Alert-Erstellung
2. Wenn Memory entry exists für `IGNORE_ALERT: ${topic}` → Alert nicht erzeugen
3. Memory entries werden periodic cleaned up nach 90 Tagen

**Code-Änderungen** (Backend):

```typescript
// In audit-phase.ts
function shouldGenerateAlert(alert: Alert): boolean {
  // Prüfe auf Ignored-Memory
  const ignored = memories.find(m =>
    m.text.includes(`IGNORE_ALERT: ${alert.topic}`) &&
    !m.text.includes('repeat-accept')
  );

  if (ignored) {
    console.log(`[Audit] Skip alert (ignored by user): ${alert.topic}`);
    return false;
  }

  return true;
}
```

---

## Fazit

### Aktueller Status

- ✅ API-Endpunkte existieren bereits (`close-alert`, `ignore-alert`)
- ✅ Memory-Erstellung ist implementiert
- ❌ UI fehlt (Trash-Button statt Close-Button)
- ❌ Keine Status-Anzeige
- ❌ Kein Kommentar-Feld in UI

### Empfohlene Nächste Schritte

1. **Sofort**: UI Update - Close-Button mit Modal & Kommentar
2. **Sprint 1**: Status-Chips & Verlauf anzeigen
3. **Sprint 2**: Agent prüft Memory before Alert-Erstellung
4. **Optional**: Bulk-Processing für wiederkehrende Alerts

### Warum das wichtig ist

- **User Experience**: User wissen nicht, warum Alerts neu erscheinen
- **Wiederholte Arbeit**: User müssen jedes Mal denselben Alert "löschen"
- **Memory-Nutzung**: Die Memory-Speicherung ist bereits implementiert, wird aber nicht genutzt
- **Agenten-Kooperation**: Andere Agenten (Jules, Claude) sollen "Never Again" Regeln respektieren

---

**Author**: Hermes Agent
**Review**: User-Basierter Workflow für Audit-Alerts
**Status**: Ready for Implementation
