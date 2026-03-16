# Controller Overlay Redesign - Implementierungsplan

> **Erstellt:** 2025-12-27
> **Status:** In Arbeit
> **Priorität:** Hoch

---

## 📋 Anforderungen

### 1. MIDI Status & Controls (GLOBAL)
- [ ] **MIDI Connect Status** anzeigen in:
  - [ ] 🎹 MIDI Panel (Settings)
  - [ ] Werkzeugleiste (Toolbar) - immer sichtbar
- [ ] **MIDI Learn Button** verfügbar in:
  - [ ] MIDI Panel
  - [ ] Werkzeugleiste

### 2. Controller Overlay UI
- [ ] **Ecler Nuo4 Mixer-Foto als Hintergrund**
  - Pfad: `resources/controllers/ecler_nuo4/background.png`
  - Vom Benutzer bereitgestellt

- [ ] **Element-Assets** (PNG vom Benutzer):
  - Potis/Knobs
  - Tasten/Buttons
  - Fader

### 3. Element-Visualisierung
- [ ] **Platzierung** der PNGs gemäß `elements.json` Positionen
- [ ] **Animation**:
  - Knobs: Rotation basierend auf MIDI-Wert (0-127 → 0-270°)
  - Fader: Vertikale Position basierend auf Wert
  - Buttons: Aktiv/Inaktiv Zustand

### 4. Interaktive Features
- [ ] **Rahmen** um jedes MIDI-Element mit Farbanzeige:
  - 🟡 Gelb: MIDI Learn aktiv für dieses Element
  - 🟢 Grün: Bewegung erkannt (Wert ändert sich)
  - ⬜ Grau: Inaktiv

- [ ] **Mouseover-Tooltip** für jedes Element:
  - Element-Name (z.B. "CH2 GAIN")
  - MIDI-Typ (CC/Note)
  - Channel + CC/Note Nummer
  - Aktueller Wert (0-127 / 0-1.0)
  - Zuweisung (falls vorhanden)

### 5. Element-Liste mit Editor
- [ ] **Tabellarische Ansicht** aller MIDI-Elemente:
  - ID, Name, Typ, MIDI-Info, Zuweisung
- [ ] **Bearbeiten**:
  - MIDI Learn für einzelnes Element starten
  - Zuweisung ändern (Dropdown)
  - Zuweisung löschen

---

## 📁 Benötigte Assets (vom Benutzer)

| Asset | Pfad | Status |
|-------|------|--------|
| Mixer-Hintergrundbild | `resources/controllers/ecler_nuo4/background.png` | ⏳ Warte |
| Knob/Poti | `resources/controllers/ecler_nuo4/nuo4_knob.png` | ⏳ Warte |
| Fader Cap | `resources/controllers/ecler_nuo4/nuo4_fader.png` | ⏳ Warte |
| Button (normal) | `resources/controllers/ecler_nuo4/nuo4_button.png` | ⏳ Warte |
| Button (aktiv) | `resources/controllers/ecler_nuo4/nuo4_button_active.png` | ⏳ Warte |

---

## 🏗️ Implementierungs-Reihenfolge

### Phase 1: Globale Controls (HEUTE)
1. MIDI Status-Anzeige in Toolbar
2. MIDI Learn Button in Toolbar
3. Globaler MIDI Learn Modus

### Phase 2: Overlay Grundgerüst
1. Menü-Button zum Öffnen des Overlays
2. Hintergrundbild laden und anzeigen
3. Fenster skalierbar machen

### Phase 3: Element-Rendering
1. Assets laden (PNG → egui::TextureHandle)
2. Elemente gemäß JSON positionieren
3. Animation implementieren (Rotation/Translation)

### Phase 4: Interaktivität
1. Rahmen mit Farblogik
2. Hover-Detection + Tooltip
3. Klick → MIDI Learn starten

### Phase 5: Element-Editor
1. Liste aller Elemente
2. Zuweisungs-Editor
3. Persistierung in JSON/AppSettings

---

## 📝 Code-Änderungen

### Dateien zu modifizieren:
- `crates/stagegraph/src/main.rs` - Toolbar MIDI Controls
- `crates/stagegraph-ui/src/controller_overlay_panel.rs` - Komplettes Redesign
- `crates/stagegraph-ui/src/lib.rs` - Exports anpassen

### Neue Dateien:
- ❓ `crates/stagegraph-ui/src/midi_element_list.rs` (optional, könnte in overlay sein)

### Datei-Struktur für Assets:
```
resources/controllers/ecler_nuo4/
├── elements.json           ✅ Vorhanden
├── background.png          ⏳ Vom Benutzer
├── nuo4_knob.png          ⏳ Vom Benutzer
├── nuo4_knob_large.png    ⏳ Vom Benutzer (für große Encoder)
├── nuo4_fader.png         ⏳ Vom Benutzer
├── nuo4_button.png        ⏳ Vom Benutzer
└── nuo4_button_active.png ⏳ Vom Benutzer
```

---

## ▶️ Phase 1 starten

Sobald die Assets verfügbar sind, kann ich mit der Implementierung beginnen.
Für Phase 1 (Toolbar Controls) brauche ich keine Assets.

Soll ich mit **Phase 1 (MIDI Controls in Toolbar)** jetzt starten?
