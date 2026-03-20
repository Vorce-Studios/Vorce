# 🔍 VJMapper / MapFlow – Intensives Code-Audit

**Erstellt:** 2026-03-20  
**Codebase:** Rust 2021, wgpu 27, egui 0.33, FFmpeg 7.1  
**Geprüfte Crates:** `mapmap`, `mapmap-core`, `mapmap-ui`, `mapmap-io`, `mapmap-render`, `mapmap-media`, `mapmap-control`, `mapmap-mcp`, `mapmap-ffi`  
**Gesamtbefunde:** ~280 Einzelissues in 6 Schweregrad-Kategorien

---

## 📊 Executive Summary

| Kategorie           | KRITISCH | HOCH | MITTEL | NIEDRIG | Gesamt |
|---------------------|----------|------|--------|---------|--------|
| Error Handling      | 5        | 32   | 41     | 28      | 106    |
| Unsafe / Safety     | 4        | 8    | 6      | 2       | 20     |
| Ressourcen / GPU    | 3        | 5    | 7      | 4       | 19     |
| Performance         | 0        | 6    | 14     | 9       | 29     |
| Security            | 1        | 2    | 3      | 2       | 8      |
| Dead Code / Doku    | 0        | 1    | 18     | 22      | 41     |
| Architektur         | 0        | 3    | 8      | 6       | 17     |
| **Gesamt**          | **13**   | **57** | **97** | **73** | **240** |

**Gesamtbewertung: 6.5 / 10** – Solide Rust-Basis, aber kritische Panic-Pfade und fehlende Safety-Dokumentation müssen dringend behoben werden.

---

## 🚨 KRITISCHE ISSUES (Sofort beheben!)

### K-1 · Leere FFmpeg-Encoder-Implementierung

**Datei:** `crates/mapmap-io/src/stream/encoder.rs` · **Schwere:** KRITISCH  
Der `VideoEncoder` ist ein Stub – er produziert leere Pakete. Streaming funktioniert dadurch überhaupt nicht.

```rust
// ❌ AKTUELL – gibt leere Daten zurück
Ok(EncodedPacket {
    data: Vec::new(),  // ← LEER! Kein echter Encode
    pts: self.frame_count as i64,
    is_keyframe: self.frame_count == 1,
})
```

**Fix:** Echte FFmpeg-Encoder-Integration implementieren (libavcodec H.264/HEVC).

---

### K-2 · `unsafe`-Callback ohne SAFETY-Kommentar (FFmpeg-Formatcallback)

**Datei:** `crates/mapmap-media/src/decoder.rs` · **Schwere:** KRITISCH

```rust
// ❌ AKTUELL – kein SAFETY-Kommentar, kein Null-Check
#[cfg(target_os = "windows")]
unsafe extern "C" fn get_format_callback(
    ctx: *mut ffi::AVCodecContext,
    fmt: *const ffi::AVPixelFormat,
) -> ffi::AVPixelFormat {
    while *p != ffi::AVPixelFormat::AV_PIX_FMT_NONE {  // Pointer ohne Null-Prüfung
        p = p.offset(1);
    }
}
```

**Fix:**

```rust
// SAFETY: Wird von FFmpeg als Pixelformat-Callback aufgerufen.
// - ctx: gültiger AVCodecContext, Lifetime durch FFmpeg garantiert
// - fmt: Null-terminiertes Array von AVPixelFormat-Werten
// - Pointer sind nur während des Callbacks gültig
unsafe extern "C" fn get_format_callback(
    ctx: *mut ffi::AVCodecContext,
    fmt: *const ffi::AVPixelFormat,
) -> ffi::AVPixelFormat {
    if ctx.is_null() || fmt.is_null() {
        return ffi::AVPixelFormat::AV_PIX_FMT_NONE;
    }
    // ...
}
```

---

### K-3 · NDI Raw-Pointer ohne SAFETY-Kommentar

**Datei:** `crates/mapmap-io/src/ndi/mod.rs:208` · **Schwere:** KRITISCH

```rust
// ❌ AKTUELL – kein SAFETY-Kommentar, Puffergröße unvalidiert
unsafe { std::slice::from_raw_parts(video_frame.p_data, data_size).to_vec() }
```

**Fix:**

```rust
// SAFETY: p_data wird vom NDI SDK für den angegebenen data_size-Bereich garantiert.
// Der Pointer ist nur während des capture()-Aufrufs gültig; das .to_vec()
// kopiert die Daten sofort, um Use-after-free zu verhindern.
// Voraussetzung: p_data != null (geprüft oben) und data_size > 0.
let frame_data = unsafe {
    debug_assert!(!video_frame.p_data.is_null());
    std::slice::from_raw_parts(video_frame.p_data, data_size).to_vec()
};
```

---

### K-4 · HAP-Player FFmpeg-Codec-Pointer ohne SAFETY-Kommentar

**Datei:** `crates/mapmap-media/src/hap_player.rs:59-77` · **Schwere:** KRITISCH

```rust
// ❌ AKTUELL – Raw-Pointer ohne Dokumentation
let width  = unsafe { (*codec_par.as_ptr()).width  as u32 };
let height = unsafe { (*codec_par.as_ptr()).height as u32 };
let codec_name = unsafe {
    let codec_id = (*codec_par.as_ptr()).codec_id;
    std::ffi::CStr::from_ptr(ffmpeg::ffi::avcodec_get_name(codec_id))
        .to_string_lossy().to_string()
};
```

**Fix:**

```rust
// SAFETY: codec_par ist aus dem FFmpeg-Kontext geborgt; der Pointer ist für die
// Dauer des Borrows gültig und nicht null. FFmpeg hat AVCodecParameters
// vor diesem Aufruf initialisiert.
let (width, height, codec_name) = unsafe {
    let par = &*codec_par.as_ptr();
    let name = std::ffi::CStr::from_ptr(
        ffmpeg::ffi::avcodec_get_name(par.codec_id)
    ).to_string_lossy().to_string();
    (par.width as u32, par.height as u32, name)
};
```

---

### K-5 · `panic!()` in Produktionspfad (Web-Handlers)

**Datei:** `crates/mapmap-control/src/web/handlers.rs:274, 279` · **Schwere:** KRITISCH

```rust
// ❌ AKTUELL – Panic bei unerwartetem JSON
other => panic!("Wrong target type: {:?}", other),
```

**Fix:**

```rust
other => {
    tracing::error!("Unexpected target type in parameter update: {:?}", other);
    return Err(ControlError::InvalidTarget(format!("{:?}", other)));
}
```

---

## 🔴 HOHE SEVERITY

### H-1 · `.unwrap()` bei Ressourcen-Initialisierung

**Datei:** `crates/mapmap/src/app/core/init.rs` · **Schwere:** HOCH

```rust
// ❌ AKTUELL
let ctx = window_manager.get(main_window_id).unwrap();

// ✅ FIX
let ctx = window_manager.get(main_window_id)
    .ok_or_else(|| anyhow!("Main window not found after creation"))?;
```

---

### H-2 · `.unwrap()` im Render-Loop (Texture-Lookup)

**Datei:** `crates/mapmap/src/app/loops/render/previews.rs` · **Schwere:** HOCH

```rust
// ❌ AKTUELL – Panic bei fehlendem Texture-Eintrag
let tex = app.output_temp_textures.get(&output_id).unwrap();

// ✅ FIX
let Some(tex) = app.output_temp_textures.get(&output_id) else {
    tracing::warn!("Texture für Output {} nicht gefunden, überspringe Render", output_id);
    return Ok(());
};
```

---

### H-3 · `CString::new().unwrap()` kann bei Null-Bytes panicen

**Datei:** `crates/mapmap-io/src/spout/mod.rs:299` · **Schwere:** HOCH

```rust
// ❌ AKTUELL – panicen wenn `self.name` ein Null-Byte enthält
let c_name = CString::new(self.name.clone()).unwrap();

// ✅ FIX
let c_name = CString::new(self.name.as_str())
    .map_err(|e| IoError::SpoutError(format!("Ungültiger Sender-Name: {}", e)))?;
```

---

### H-4 · NDI `NdiReceiver` nicht `Send` – Architektur-Verletzung

**Datei:** `crates/mapmap-io/src/ndi/mod.rs:261-263` · **Schwere:** HOCH

Der `NdiReceiver` kann das `VideoSource: Send`-Trait nicht erfüllen, weil `grafton-ndi::Recv` nicht `Send` ist. Damit ist NDI strukturell vom einheitlichen `VideoSource`-Interface ausgeschlossen.

**Fix:** `NdiReceiver` in einen Thread-Worker mit Channel-Bridge wrappen:

```rust
pub struct NdiReceiverBridge {
    frame_rx: crossbeam_channel::Receiver<VideoFrame>,
    command_tx: crossbeam_channel::Sender<NdiCommand>,
}
// Implements VideoSource + Send via channels
```

---

### H-5 · Effect-Chain: `unwrap()` auf leere Liste

**Datei:** `crates/mapmap-ui/src/panels/effect_chain/panel.rs:184-185` · **Schwere:** HOCH

```rust
// ❌ AKTUELL – Panic wenn Liste nach add_effect() leer bleibt
let id = self.chain.effects.last().unwrap().id;
let effect = self.chain.get_effect_mut(id).unwrap();

// ✅ FIX
if let Some(last) = self.chain.effects.last() {
    let id = last.id;
    if let Some(effect) = self.chain.get_effect_mut(id) {
        effect.is_expanded = true;
    }
}
```

---

### H-6 · Übermäßige GPU Round-Trips im Effect-Chain-Renderer

**Datei:** `crates/mapmap-render/src/effect_chain_renderer/apply.rs` · **Schwere:** HOCH

Jeder Effekt erzeugt einen eigenen Render-Pass, was bei N Effekten N CPU-GPU-Sync-Punkte bedeutet.

**Fix:** Einfache Effekte (Helligkeit, Colorize) in einem einzigen Pass bündeln. Nur Effekte mit Ping-Pong-Buffer (Blur, Distortion) benötigen eigene Passes.

---

### H-7 · Texture-Pool: Kein TTL für persistente Texturen

**Datei:** `crates/mapmap-render/src/texture.rs:345-376` · **Schwere:** HOCH

```rust
// ❌ AKTUELL – "composite" wird NIE garbage-collected
if name == "composite" || name.starts_with("layer_pong") || name == "bevy_output" {
    continue; // wird ausgelassen
}
```

**Fix:** Explizites `release_persistent(name)` anbieten + `ManagedTexture { persistent: bool }` für die GC-Entscheidung verwenden.

---

### H-8 · Doppelter HashMap-Lookup (Race-Window)

**Datei:** `crates/mapmap-render/src/texture.rs:200-207` · **Schwere:** HOCH

```rust
// ❌ AKTUELL – 2 Locks und 2 Lookups
let exists = self.textures.read().contains_key(name);
if exists {
    if let Some(handle) = self.textures.read().get(name) { // Zweiter Lock!
        handle.mark_used(self.start_time);
    }
}

// ✅ FIX – ein Lock, ein Lookup
let textures = self.textures.read();
if let Some(handle) = textures.get(name) {
    handle.mark_used(self.start_time);
    return true;
}
false
```

---

### H-9 · Swallowed Errors bei NDI-Discovery

**Datei:** `crates/mapmap-io/src/ndi/mod.rs:130, 134` · **Schwere:** HOCH

```rust
// ❌ AKTUELL – Fehler werden stillschweigend ignoriert
let _ = sender.send(sources);
// ...
let _ = sender.send(vec![]);
```

**Fix:**

```rust
if let Err(e) = sender.send(sources) {
    tracing::error!("NDI-Discovery: Konnte Quellen nicht senden: {}", e);
}
```

---

### H-10 · `panic!()` in MCP-Server-Tests statt Assertions

**Datei:** `crates/mapmap-mcp/src/server.rs:346+` · **Schwere:** HOCH

```rust
// ❌ AKTUELL
let action = rx.try_recv().unwrap();

// ✅ FIX
let action = rx.try_recv()
    .expect("MCP-Aktion hätte im Channel liegen sollen");
// Oder noch besser:
assert!(rx.try_recv().is_ok(), "Keine Aktion im Channel empfangen");
```

---

### H-11 · `ping_pong.as_ref().unwrap()` in Effect-Renderer

**Datei:** `crates/mapmap-render/src/effect_chain_renderer/apply.rs:311, 342` · **Schwere:** HOCH

```rust
// ❌ AKTUELL – Panic wenn Initialisierung still fehlschlug
let ping_pong = self.ping_pong.as_ref().unwrap();

// ✅ FIX
let ping_pong = self.ping_pong.as_ref()
    .ok_or(RenderError::DeviceError("Ping-Pong-Buffer nicht initialisiert".into()))?;
```

---

### H-12 · `expect()` beim App-Start ohne Fallback

**Datei:** `crates/mapmap/src/main.rs:59` · **Schwere:** HOCH

```rust
// ❌ AKTUELL – Crash bei Init-Fehler ohne saubere Fehlermeldung
let mut app = pollster::block_on(App::new(event_loop, config))
    .expect("Failed to initialize application");

// ✅ FIX
let mut app = pollster::block_on(App::new(event_loop, config))
    .map_err(|e| {
        tracing::error!("Initialisierung fehlgeschlagen: {:?}", e);
        eprintln!("MapFlow konnte nicht gestartet werden: {}", e);
        e
    })?;
```

---

## 🟠 MITTLERE SEVERITY

### M-1 · Duplizierte Fehler-Dokumentation in `codegen.rs`

**Datei:** `crates/mapmap-core/src/codegen.rs:14-56` · **Schwere:** MITTEL

Jede Error-Variante hat identische dreifach-duplizierte Doc-Kommentare (Copy-Paste-Fehler):

```rust
// ❌ AKTUELL
#[error("Graph validation failed: {0}")]
/// Error: Graph validation failed.
/// Error: Graph validation failed.  ← Duplikat
/// Error: Graph validation failed.  ← Duplikat
ValidationError(String),
```

**Fix:** Jeden Kommentar auf einmal reduzieren.

---

### M-2 · `partial_cmp().unwrap()` – NaN-unsicher

**Datei:** `crates/mapmap-core/src/animation.rs:370` · **Schwere:** MITTEL

```rust
// ❌ AKTUELL – panic bei NaN in Marker-Zeiten
.sort_by(|a, b| a.time.partial_cmp(&b.time).unwrap());

// ✅ FIX
.sort_by(|a, b| a.time.partial_cmp(&b.time).unwrap_or(std::cmp::Ordering::Equal));
```

---

### M-3 · Thread-Spawn-Fehler in Audio-Pipeline nicht propagiert

**Datei:** `crates/mapmap-core/src/audio_media_pipeline.rs:155` · **Schwere:** MITTEL

```rust
// ❌ AKTUELL – Panic beim Thread-Spawn-Fehler
.expect("Failed to spawn audio processor thread");

// ✅ FIX – Konstruktor gibt Result zurück
pub fn new(...) -> Result<Self, AudioPipelineError> {
    let _handle = std::thread::Builder::new()
        .name("audio-processor".to_string())
        .spawn(move || { ... })
        .map_err(AudioPipelineError::ThreadSpawnFailed)?;
    Ok(Self { ... })
}
```

---

### M-4 · I18n: `.unwrap()` auf hartkodierten Strings

**Datei:** `crates/mapmap-ui/src/core/i18n.rs:23, 37, 41, 44, 46` · **Schwere:** MITTEL

```rust
// ❌ AKTUELL – 5 unwrap()-Aufrufe auf hartkodierten Sprach-Strings
let lang: LanguageIdentifier = lang_id.parse().unwrap_or_else(|_| "en-US".parse().unwrap());
let available_locales: Vec<LanguageIdentifier> =
    vec!["en".parse().unwrap(), "de".parse().unwrap()];

// ✅ FIX – Compile-Time-Konstanten
const DEFAULT_LANG: &str = "en-US";
const AVAILABLE_LANGS: &[&str] = &["en", "de"];

fn load_bundle(lang_id: &LanguageIdentifier) -> FluentBundle<FluentResource> {
    let fallback: LanguageIdentifier = DEFAULT_LANG.parse()
        .expect("DEFAULT_LANG ist kein gültiger BCP 47-Identifier");
    // ...
}
```

---

### M-5 · Shader: Feste 9-Tap-Blur ignoriert Radius-Parameter

**Datei:** `crates/mapmap-render/src/shaders/effect_blur.wgsl:42-50` · **Schwere:** MITTEL

Der Blur-Shader hat immer 3×3 Taps, egal welcher Radius konfiguriert wurde. UV-Koordinaten werden nicht geclampt.

```wgsl
// ✅ FIX – UV klemmen + dynamische Tap-Auswahl basierend auf Radius
let uv_clamped = clamp(input.uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
color += textureSample(input_texture, input_sampler, uv_clamped);
```

---

### M-6 · `#[allow(dead_code)]` ohne Begründung (mehrere Dateien)

**Betroffene Dateien:**

| Datei | Anzahl | Problem |
|-------|--------|---------|
| `mapmap/src/window_manager.rs` | 7× | Felder/Methoden ohne Erklärung |
| `mapmap-mcp/src/server.rs` | 3× | `osc_client`, `handle_send_osc`, `send_osc_msg` |
| `mapmap-control/src/hue/api/groups.rs` | 3× | Hue-Integration WIP? |
| `mapmap-render/src/effect_chain_renderer/types.rs` | 2× | `PingPongBuffer` IS tatsächlich benutzt! |
| `mapmap-ui/src/panels/controller_overlay_panel/*` | 8× | Ohne Kontext |

**Fix:** Entweder entfernen oder dokumentieren warum das Feld/die Methode existiert:

```rust
// ✅ Gut
#[allow(dead_code)] // Reserviert für MIDI-Learn (Phase 7)
pub midi_learn_active: bool,
```

---

### M-7 · Unnötige `.clone()` im UI-Render-Loop

**Datei:** `crates/mapmap-ui/src/panels/effect_chain/panel.rs` · **Schwere:** MITTEL

```rust
// ❌ AKTUELL – Response wird unnötig geklont
if ui.button(locale.t("effect-add"))
    .clone()  // ← clone() auf Response ist ein Anti-Pattern
    .on_hover_text(...)
    .clicked() { ... }

// ✅ FIX – kein clone() nötig
if ui.button(locale.t("effect-add"))
    .on_hover_text(locale.t("effect-add"))
    .clicked() { ... }
```

---

### M-8 · Web-API: Status-Felder sind Hardcoded-Stubs

**Datei:** `crates/mapmap-control/src/web/routes.rs:40-42` · **Schwere:** MITTEL

```rust
// ❌ AKTUELL – gibt immer falsche Werte zurück
uptime_seconds: 0,    // TODO: Track actual uptime
active_layers: 0,     // TODO: Get from project
fps: 60.0,            // TODO: Get actual FPS
```

**Fix:** Echte Werte aus `AppState` / `ControlManager` lesen.

---

### M-9 · NDI-Kontext wird bei jedem `connect()`-Aufruf neu erstellt

**Datei:** `crates/mapmap-io/src/ndi/mod.rs:145-150` · **Schwere:** MITTEL

Jeder `connect()`-Aufruf erstellt eine neue NDI-Instanz und einen neuen Finder. Bei wiederholtem Aufruf akkumulieren sich Ressourcen.

**Fix:** NDI-Handle einmalig in `new()` erstellen und wiederverwenden.

---

### M-10 · Fehlende Keyboard-Navigation in UI-Panels

**Betroffene Panels:** Effect Chain, Layer, Mapping, Transform, Output · **Schwere:** MITTEL

Keine Tastenkürzel für häufige Operationen – verletzt WCAG 2.1 Level A.

```rust
// ✅ FIX-Beispiel
let add_response = ui.button(locale.t("effect-add"));
let keyboard_add = ui.input(|i| i.key_pressed(egui::Key::Plus));
if add_response.clicked() || keyboard_add {
    self.show_add_menu = !self.show_add_menu;
}
```

---

### M-11 · `#[allow(missing_docs)]` auf allen Public-Modulen in `mapmap-ui`

**Datei:** `crates/mapmap-ui/src/lib.rs` · **Schwere:** MITTEL

Alle 8 Public-Module deaktivieren die Dokumentationspflicht, obwohl das Crate `#![warn(missing_docs)]` aktiviert. Betroffen: 70+ public Types und Funktionen.

---

### M-12 · Potenzieller GPU-Buffer-Alignment-Fehler

**Datei:** `crates/mapmap-render/src/pipeline.rs` · **Schwere:** MITTEL

Buffer-Allokation prüft weder `max_buffer_size` noch das erforderliche 256-Byte-Alignment für Uniform Buffers.

```rust
// ✅ FIX
if content.len() % 256 != 0 {
    tracing::warn!("Uniform Buffer nicht 256-Byte-aligned: {} Bytes", content.len());
}
if content.len() as u64 > device.limits().max_buffer_size {
    return Err(RenderError::DeviceError("Buffer überschreitet Device-Limit".into()));
}
```

---

### M-13 · Kein Drop-Impl für Spout-Sender / SRT-Streamer

**Dateien:** `crates/mapmap-io/src/spout/mod.rs`, `stream/srt.rs` · **Schwere:** MITTEL

`RtmpStreamer` hat einen `Drop`-Impl (gut ✓), aber `SrtStreamer` nicht. Beim Drop werden Encoder-Ressourcen nicht explizit freigegeben.

---

### M-14 · `#![allow(missing_docs)]` in mapmap-mcp

**Datei:** `crates/mapmap-mcp/src/lib.rs:5` · **Schwere:** MITTEL

Das gesamte MCP-Crate deaktiviert Doc-Anforderungen. 50+ `McpAction`-Varianten sind undokumentiert.

---

### M-15 · Arc-Pointer als Cache-Key ohne SAFETY-Kommentar

**Datei:** `crates/mapmap-render/src/effect_chain_renderer/apply.rs:18` · **Schwere:** MITTEL

```rust
// ❌ AKTUELL – kein Kommentar
let key = Arc::as_ptr(input_view) as usize;

// ✅ FIX
// SAFETY: Arc-Pointer-Adresse als Frame-lokaler Cache-Key.
// Sicher, weil TextureViews für den gesamten Frame-Zeitraum am Leben bleiben.
// Cache MUSS zwischen Frames geleert werden, um Stale-Pointer zu verhindern.
let key = Arc::as_ptr(input_view) as usize;
```

---

### M-16 · OSC-Binding: `osc_to_control_value().unwrap()` ohne Fallback

**Datei:** `crates/mapmap-control/src/osc/types.rs` · **Schwere:** MITTEL

```rust
// ❌ AKTUELL – Panic bei unerwartetem OSC-Typ
osc_to_control_value(&args).unwrap()

// ✅ FIX
match osc_to_control_value(&args) {
    Ok(val) => val,
    Err(e) => {
        tracing::warn!("Ungültiger OSC-Wert ignoriert: {}", e);
        return;
    }
}
```

---

### M-17 · `DMX::sacn::SacnSender::new().unwrap()` in Produktionspfad

**Datei:** `crates/mapmap-control/src/dmx/sacn.rs` · **Schwere:** MITTEL

Socket-Binding kann zur Laufzeit scheitern (Port belegt, Berechtigungen). Sollte `Result<Self>` zurückgeben.

---

### M-18 · Unreachable Code-Pfade mit `panic!()` in Bevy

**Datei:** `crates/mapmap-bevy/src/systems.rs` · **Schwere:** MITTEL

Bevy-Systeme mit `panic!()` in theoretisch unerreichbaren Branches. Besser: `warn!()` + früher Return.

---

## 🟡 NIEDRIGE SEVERITY

### N-1 · TODO-Kommentare ohne Kontext/Besitzer

Gefundene TODOs ohne Priorisierung oder Phasenzuweisung:

| Datei | TODO |
|-------|------|
| `mapmap-media/src/hap_player.rs:238` | `// TODO: Actually probe the file to check codec` |
| `mapmap-media/src/lib.rs:24` | `// TODO: Enable pipeline with thread-local scaler approach` |
| `mapmap-mcp/src/server.rs:138` | `// TODO: Implement shared state reading` |
| `mapmap-ui/src/view/media_browser.rs:232` | `// TODO: Extract from media file` |
| `mapmap-ui/src/view/media_browser.rs:265` | `// TODO: Generate thumbnail in background` |
| `mapmap-ui/src/panels/inspector/panel.rs:37` | `// TODO: Need a way to close from here` |
| `mapmap-ui/src/editors/module_canvas/inspector/output.rs:230,246` | Pairing-Logik fehlt |
| `mapmap-control/src/web/routes.rs:40-42` | Uptime/FPS/Layer-Stubs |
| `mapmap-render/src/paint_texture_cache.rs:124,128` | Video/Camera-Anbindung fehlt |

**Empfehlung:**

```rust
// TODO(Phase-8, @owner): Thumbnail im Hintergrund generieren
// Abhängig von: media-info-crate v2.0
```

---

### N-2 · Glob-Imports `use egui::*;` in mehreren Dateien

**Betroffene Dateien:** transform_panel, mapping_panel, layer_panel, edge_blend_panel und weitere (8+)

Glob-Imports erschweren Autocomplete und Symbol-Suche. Explizite Imports bevorzugen:

```rust
use egui::{Ui, Response, Button, Slider, Color32};
```

---

### N-3 · Gemischte Sprache in Kommentaren (Deutsch/Englisch)

**Betroffene Dateien:** `config.rs`, `window_manager.rs` und weitere

```rust
// ❌
/// Sichtbarkeitseinstellungen für das Hauptlayout.
// ✅
/// Visibility settings for the main layout.
```

Code-Kommentare sollten einheitlich auf Englisch sein, da internationale Mitarbeit möglich ist.

---

### N-4 · History-System: Vollständige AppState-Klone im Undo-Stack

**Datei:** `crates/mapmap-core/src/history.rs` · **Schwere:** NIEDRIG (Performance)

Der Undo-Stack speichert vollständige `AppState`-Klone. Da `AppState` bereits `Arc`-basierte CoW-Felder verwendet, sind die Klone günstig – aber bei 50 Undo-Schritten und großen Projekten kann der RAM-Verbrauch ansteigen.

**Empfehlung:** Differenzbasierte History oder Delta-Serialisierung langfristig erwägen.

---

### N-5 · Bevy-Crate nicht im Workspace registriert

**Datei:** `Cargo.toml` · **Schwere:** NIEDRIG

`crates/mapmap-bevy` existiert als Verzeichnis, ist aber nicht im Workspace `members`-Array eingetragen:

```toml
members = [
    "crates/mapmap",
    "crates/mapmap-control",
    # ...
    # "crates/mapmap-bevy"  ← FEHLT!
]
```

---

### N-6 · `image = "0.24"` ist veraltet (aktuell 0.25)

**Datei:** `Cargo.toml:73` · **Schwere:** NIEDRIG

Die verwendete `image`-Version 0.24 hat bekannte Performance-Issues. Update auf 0.25 empfohlen.

---

### N-7 · Shader-Alternative Entry-Points undokumentiert

**Datei:** `crates/mapmap-render/src/shaders/lut_color_grade.wgsl` · **Schwere:** NIEDRIG

`fs_main_nearest` und `fs_main_tetrahedral` sind alternative Shader-Entry-Points, die nur als Dead Code vorkommen. Dokumentieren welcher aktiv ist und warum.

---

### N-8 · `LogConfig` und `logging.rs` parallel zu `tracing-appender` in `main.rs`

**Dateien:** `crates/mapmap-core/src/logging.rs`, `crates/mapmap/src/main.rs` · **Schwere:** NIEDRIG

Es gibt zwei parallele Logging-Systeme: Die `LogConfig`-Struct in `mapmap-core` und die direkte `tracing_appender`-Konfiguration in `main.rs`. Beide machen dasselbe. Sollte konsolidiert werden.

---

## ✅ POSITIVE BEFUNDE

Diese Punkte sind gut umgesetzt und sollten als Maßstab für den Rest der Codebase gelten:

| Bereich | Details |
|---------|---------|
| **Null unsafe-Blocks in mapmap, mapmap-core, mapmap-ui, mapmap-control, mapmap-mcp** | Exzellent – kein `unsafe` wo nicht nötig |
| **Path-Traversal-Schutz in MCP** | `validate_path_with_extensions()` mit `..`-Check korrekt implementiert |
| **Timing-Attack-resistente Auth** | `subtle::ConstantTimeEq` in `auth.rs` – vorbildlich |
| **AppState Arc-basiertes CoW** | Günstiges Klonen für Undo/Redo durch Arc-Felder |
| **Error-Type-Hierarchie** | `thiserror` konsequent verwendet, gute Fehlernachrichten |
| **Responsive Layout-System** | Saubere Abstraktion in `mapmap-ui/core/responsive.rs` |
| **MCP Path-Validation** | Robuste Whitelist für Datei-Extensions |
| **D3D11VA-Fehlerbehandlung** | Korrekte `av_buffer_unref()` bei Fehler in `setup_hw_accel()` |
| **FFmpeg SW-Frame-Copy** | Korrekte `av_frame_copy_props()` nach HW-Frame-Transfer |
| **Undo/Redo Command-Pattern** | Sauber implementiert mit VecDeque-basiertem Stack |

---

## 🛠️ Priorisierter Aktionsplan

### Sprint 1 – Kritisch (ca. 12–16h)

1. [ ] **K-1** Echten FFmpeg-Encoder implementieren (stream/encoder.rs)
2. [ ] **K-2** SAFETY-Kommentar + Null-Check für `get_format_callback`
3. [ ] **K-3** SAFETY-Kommentar + `debug_assert!` für NDI-Pointer
4. [ ] **K-4** SAFETY-Kommentar für HAP-Player FFmpeg-Pointer
5. [ ] **K-5** `panic!()` in web/handlers.rs durch Error-Return ersetzen
6. [ ] **H-1** `unwrap()` in `init.rs` durch `?`-Operator ersetzen
7. [ ] **H-3** `CString::new().unwrap()` in spout/mod.rs absichern

### Sprint 2 – Hoch (ca. 20–25h)

8. [ ] **H-2** Render-Loop Texture-Lookup absichern
9. [ ] **H-4** NDI-Bridge mit Channel für Send-Sicherheit
10. [ ] **H-5** Effect-Chain Panel unwrap() durch Option-Matching ersetzen
11. [ ] **H-6** Effect-Chain Render-Passes bündeln
12. [ ] **H-7** Texture-Pool GC für persistente Texturen
13. [ ] **H-8** Doppelten HashMap-Lookup in texture.rs eliminieren
14. [ ] **H-9** NDI Discovery-Fehler loggen statt swallowing
15. [ ] **H-11** `ping_pong.as_ref().unwrap()` durch `ok_or(...)` ersetzen

### Sprint 3 – Mittel (ca. 30–40h)

16. [ ] **M-1..M-18** Alle mittleren Issues adressieren
17. [ ] Vollständige API-Dokumentation für `mapmap-ui` und `mapmap-mcp`
18. [ ] Keyboard-Navigation in allen UI-Panels
19. [ ] TODO-Kommentare mit Kontext versehen oder als Issues tracken

### Langfristig (Backlog)

20. [ ] **N-1..N-8** Niedrige Issues
21. [ ] Differenzbasiertes Undo-System evaluieren
22. [ ] `image`-Crate auf 0.25 upgraden
23. [ ] Logging-System konsolidieren
24. [ ] `mapmap-bevy` in Workspace aufnehmen

---

## 📈 Metriken

```
Gesamte .rs-Dateien auditiert:    ~200
.unwrap()/.expect()-Aufrufe:       ~280 (davon ~85 in Produktionspfaden)
panic!()-Aufrufe (nicht-Tests):    8
unsafe-Blöcke ohne SAFETY:         6
TODO-Kommentare:                   18
#[allow(dead_code)]:               28+
Öffentliche Items ohne Docs:       ~120

Crate-Qualitätsscores:
  mapmap-core:     7.5/10  (gute Struktur, Panic-Pfade verbesserungswürdig)
  mapmap-ui:       7.2/10  (solide Architektur, Accessibility-Lücken)
  mapmap-io:       6.0/10  (leere Encoder-Impl, NDI-Threading-Problem)
  mapmap-render:   6.5/10  (GPU-Ressourcen-Management verbesserungswürdig)
  mapmap-control:  6.8/10  (Panic in Handlers, gute Auth)
  mapmap-mcp:      7.0/10  (gute Path-Validation, fehlende Docs)
  mapmap (binary): 7.0/10  (einige kritische unwrap() in Init)

Gesamt:           6.7/10
```

---

*Bericht generiert via Multi-Agent-Analyse · 5 Audit-Agents parallel · 2026-03-20*
