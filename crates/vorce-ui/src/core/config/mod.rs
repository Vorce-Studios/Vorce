//! User configuration management
//!.
//! Handles saving and loading user preferences including language settings.

use crate::theme::ThemeConfig;
pub mod io;
pub use io::*;
pub mod layout;
pub mod midi;
pub use crate::core::config::midi::MidiAssignment;
pub use crate::core::config::midi::MidiAssignmentTarget;

pub mod settings;

pub use layout::*;

pub use settings::*;


use serde::{Deserialize, Serialize};
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserConfig {
    /// Preferred language code (e.g., "en", "de")
    pub language: String,
    /// Last opened project path
    #[serde(default)]
    pub last_project: Option<String>,
    /// Recently opened files
    #[serde(default)]
    pub recent_files: Vec<String>,
    /// UI Theme settings
    #[serde(default)]
    pub theme: ThemeConfig,
    /// Target frame rate (FPS)
    #[serde(default)]
    /// Desired frame rate for playback or updates.
    pub target_fps: Option<f32>,
    /// Preferred GPU Adapter Name
    #[serde(default)]
    pub preferred_gpu: Option<String>,
    /// Vertical Sync Mode
    #[serde(default)]
    pub vsync_mode: VSyncMode,
    /// Audio meter style
    #[serde(default)]
    pub meter_style: AudioMeterStyle,
    /// Toolbar-Metriken (Sichtbarkeit + progressive Offenlegung)
    #[serde(default)]
    pub toolbar_metrics: ToolbarMetricsConfig,
    /// MIDI element assignments
    #[serde(default)]
    pub midi_assignments: Vec<MidiAssignment>,
    /// Selected audio input device name
    #[serde(default)]
    pub selected_audio_device: Option<String>,

    // === Window Geometry ===
    /// Window width in pixels
    #[serde(default)]
    pub window_width: Option<u32>,
    /// Window height in pixels
    #[serde(default)]
    pub window_height: Option<u32>,
    /// Window X position
    #[serde(default)]
    pub window_x: Option<i32>,
    /// Window Y position
    #[serde(default)]
    pub window_y: Option<i32>,
    /// Whether the window was maximized
    #[serde(default)]
    pub window_maximized: bool,

    // === Panel Visibility ===
    /// Show left sidebar
    #[serde(default = "default_true")]
    pub show_left_sidebar: bool,
    /// Show inspector panel
    #[serde(default = "default_true")]
    pub show_inspector: bool,
    /// Show timeline
    #[serde(default = "default_true")]
    pub show_timeline: bool,
    /// Show media browser
    #[serde(default = "default_true")]
    pub show_media_browser: bool,
    /// Show module canvas
    #[serde(default)]
    pub show_module_canvas: bool,
    /// Show controller overlay
    #[serde(default)]
    pub show_controller_overlay: bool,
    /// Whether the Web REST API is enabled.
    #[serde(default = "default_false")]
    pub web_api_enabled: bool,
    /// Port for the Web REST API.
    #[serde(default = "default_web_api_port")]
    pub web_api_port: u16,
    /// Show media manager window
    #[serde(default)]
    pub show_media_manager: bool,
    /// Show dashboard window
    #[serde(default = "default_true")]
    pub show_dashboard: bool,

    /// Enable NDI discovery
    #[serde(default = "default_true")]
    pub ndi_discovery: bool,

    /// Philips Hue Configuration
    #[serde(default)]
    pub hue_config: HueConfig,

    // === Global Output Settings ===
    /// Enable fullscreen for all projectors
    #[serde(default)]
    pub global_fullscreen: bool,

    /// Global UI font scale factor (0.8 - 1.4)
    #[serde(default = "default_ui_scale")]
    pub ui_scale: f32,

    /// Persisted application log level. Takes effect after restarting Vorce.
    #[serde(default)]
    pub log_level: AppLogLevel,

    /// Enable animated node visuals in module canvas
    #[serde(default = "default_true")]
    pub node_animations_enabled: bool,

    /// Enable startup intro animation.
    #[serde(default = "default_true")]
    pub startup_animation_enabled: bool,

    /// Video path for startup intro animation.
    #[serde(default = "default_startup_animation_path")]
    pub startup_animation_path: String,

    /// Reduziert Bewegungen/Animationen global für bessere Zugänglichkeit.
    #[serde(default)]
    pub reduce_motion_enabled: bool,

    /// Deaktiviert Sounds bei App-Start-Sequenzen.
    #[serde(default)]
    pub silent_startup_enabled: bool,

    /// Globales Profil für UI-Animationen.
    #[serde(default)]
    pub animation_profile: AnimationProfile,

    /// Enable short-circuit effect for invalid node connections
    #[serde(default = "default_true")]
    pub short_circuit_animation_enabled: bool,

    /// Verfügbare UI-Layoutprofile
    #[serde(default = "default_layout_profiles")]
    pub layouts: Vec<LayoutProfile>,
    /// Aktives Layoutprofil (id)
    #[serde(default = "default_active_layout_id")]
    pub active_layout_id: String,
}

fn default_web_api_port() -> u16 {
    8080
}

fn default_false() -> bool {
    false
}

fn default_true() -> bool {
    true
}

fn default_ui_scale() -> f32 {
    1.0
}

fn default_startup_animation_path() -> String {
    "resources/app_videos/MF-Mechanical_Cube_Logo_Splash_Animation.webm".to_string()
}

fn default_sidebar_width() -> f32 {
    300.0
}

fn default_inspector_width() -> f32 {
    360.0
}

fn default_timeline_height() -> f32 {
    200.0
}

fn default_layout_profiles() -> Vec<LayoutProfile> {
    vec![LayoutProfile::default_profile()]
}

fn default_active_layout_id() -> String {
    "default".to_string()
}

impl Default for UserConfig {
    fn default() -> Self {
        Self {
            language: "en".to_string(),
            last_project: None,
            recent_files: Vec::new(),
            theme: ThemeConfig::default(),
            target_fps: Some(60.0),
            preferred_gpu: None,
            vsync_mode: VSyncMode::default(),
            meter_style: AudioMeterStyle::default(),
            toolbar_metrics: ToolbarMetricsConfig::default(),
            midi_assignments: Vec::new(),
            selected_audio_device: None,
            // Window geometry - None means use default
            window_width: None,
            window_height: None,
            window_x: None,
            window_y: None,
            window_maximized: false,
            // Panel visibility defaults
            show_left_sidebar: true,
            show_inspector: true,
            show_timeline: true,
            show_media_browser: true,
            show_module_canvas: true,
            show_controller_overlay: false,
            web_api_enabled: false,
            web_api_port: 8080,
            show_media_manager: false,
            show_dashboard: true,
            ndi_discovery: true,
            hue_config: HueConfig::default(),
            global_fullscreen: false,
            ui_scale: 1.0,
            log_level: AppLogLevel::Info,
            node_animations_enabled: true,
            startup_animation_enabled: true,
            startup_animation_path: default_startup_animation_path(),
            reduce_motion_enabled: false,
            silent_startup_enabled: false,
            animation_profile: AnimationProfile::Subtle,
            short_circuit_animation_enabled: true,
            layouts: default_layout_profiles(),
            active_layout_id: default_active_layout_id(),
        }
    }
}

impl UserConfig {
    fn sync_legacy_visibility_fields_from_active_layout(&mut self) {
        let visibility = self.active_layout().map(|layout| layout.visibility);
        if let Some(visibility) = visibility {
            self.show_left_sidebar = visibility.show_left_sidebar;
            self.show_inspector = visibility.show_inspector;
            self.show_timeline = visibility.show_timeline;
            self.show_media_browser = visibility.show_media_browser;
            self.show_module_canvas = visibility.show_module_canvas;
        }
    }

    fn repair_for_startup(&mut self, report: &mut UserConfigLoadReport) -> bool {
        let mut repaired = false;

        if self.layouts.is_empty() {
            self.layouts = default_layout_profiles();
            report.errors.push(
                "User config contained no layout profiles. Restored the default layout."
                    .to_string(),
            );
            repaired = true;
        }

        if !self.layouts.iter().any(|l| l.id == self.active_layout_id) {
            let previous = self.active_layout_id.clone();
            self.active_layout_id =
                self.layouts.first().map(|l| l.id.clone()).unwrap_or_else(default_active_layout_id);
            report.errors.push(format!(
                "User config referenced missing active layout '{previous}'. Switched to '{}'.",
                self.active_layout_id
            ));
            repaired = true;
        }

        if let Some(layout) = self.active_layout_mut() {
            if !layout.visibility.has_primary_workspace() {
                layout.visibility.show_toolbar = true;
                layout.visibility.show_left_sidebar = true;
                layout.visibility.show_module_canvas = true;
                report.errors.push(format!(
                    "Recovered unusable startup layout '{}': all primary work areas were hidden.",
                    layout.name
                ));
                repaired = true;
            }
        }

        let fallback_visibility = LayoutVisibility {
            show_toolbar: true,
            show_left_sidebar: self.show_left_sidebar,
            show_inspector: self.show_inspector,
            show_timeline: self.show_timeline,
            show_media_browser: self.show_media_browser,
            show_module_canvas: self.show_module_canvas,
        };
        if !fallback_visibility.has_primary_workspace() {
            self.show_left_sidebar = true;
            self.show_module_canvas = true;
            report.errors.push(
                "Recovered unusable fallback visibility state: all primary work areas were hidden."
                    .to_string(),
            );
            repaired = true;
        }

        let before = (
            self.show_left_sidebar,
            self.show_inspector,
            self.show_timeline,
            self.show_media_browser,
            self.show_module_canvas,
        );
        self.sync_legacy_visibility_fields_from_active_layout();
        let after = (
            self.show_left_sidebar,
            self.show_inspector,
            self.show_timeline,
            self.show_media_browser,
            self.show_module_canvas,
        );
        if before != after {
            report.warnings.push(
                "Synchronized legacy visibility flags with the active layout profile.".to_string(),
            );
            repaired = true;
        }

        repaired
    }

    /// Update language and save
    pub fn set_language(&mut self, lang: &str) {
        self.language = lang.to_string();
    }

    /// Add a file to recent files list
    pub fn add_recent_file(&mut self, path: &str) {
        // Remove if already exists
        self.recent_files.retain(|p| p != path);
        // Add to front
        self.recent_files.insert(0, path.to_string());
        // Keep max 10 recent files
        self.recent_files.truncate(10);
    }

    /// Set or update a MIDI assignment
    pub fn set_midi_assignment(&mut self, element_id: &str, target: MidiAssignmentTarget) {
        // Remove existing assignment for this element
        self.midi_assignments.retain(|a| a.element_id != element_id);
        // Add new assignment
        self.midi_assignments.push(MidiAssignment { element_id: element_id.to_string(), target });
    }

    /// Remove a MIDI assignment
    pub fn remove_midi_assignment(&mut self, element_id: &str) {
        self.midi_assignments.retain(|a| a.element_id != element_id);
    }

    /// Set and save the selected audio device
    pub fn set_audio_device(&mut self, device: Option<String>) {
        self.selected_audio_device = device;
    }

    /// Get assignment for an element
    pub fn get_midi_assignment(&self, element_id: &str) -> Option<&MidiAssignment> {
        self.midi_assignments.iter().find(|a| a.element_id == element_id)
    }

    /// Get all assignments for a specific target type
    pub fn get_assignments_by_type(&self) -> (Vec<&MidiAssignment>, Vec<&MidiAssignment>) {
        let vorce: Vec<_> = self
            .midi_assignments
            .iter()
            .filter(|a| matches!(a.target, MidiAssignmentTarget::Vorce(_)))
            .collect();
        let streamerbot: Vec<_> = self
            .midi_assignments
            .iter()
            .filter(|a| matches!(a.target, MidiAssignmentTarget::StreamerBot(_)))
            .collect();
        (vorce, streamerbot)
    }

    /// Stellt sicher, dass mindestens ein valides Layoutprofil verfügbar ist.
    pub fn ensure_layout_profiles(&mut self) {
        if self.layouts.is_empty() {
            self.layouts = default_layout_profiles();
        }

        if !self.layouts.iter().any(|l| l.id == self.active_layout_id) {
            self.active_layout_id =
                self.layouts.first().map(|l| l.id.clone()).unwrap_or_else(default_active_layout_id);
        }
    }

    /// Liefert das aktive Layoutprofil.
    pub fn active_layout(&self) -> Option<&LayoutProfile> {
        self.layouts.iter().find(|l| l.id == self.active_layout_id)
    }

    /// Liefert das aktive Layoutprofil als mutable Referenz.
    pub fn active_layout_mut(&mut self) -> Option<&mut LayoutProfile> {
        self.layouts.iter_mut().find(|l| l.id == self.active_layout_id)
    }

    /// Wechselt das aktive Layoutprofil.
    pub fn set_active_layout(&mut self, layout_id: &str) -> bool {
        if self.layouts.iter().any(|l| l.id == layout_id) {
            self.active_layout_id = layout_id.to_string();
            true
        } else {
            false
        }
    }

    /// Erstellt ein neues Layoutprofil als Kopie der übergebenen Daten.
    pub fn add_layout_profile(&mut self, mut profile: LayoutProfile) {
        if profile.id.trim().is_empty() {
            profile.id = format!("layout-{}", self.layouts.len() + 1);
        }
        self.layouts.push(profile);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn test_default_config() {
        let config = UserConfig::default();
        assert_eq!(config.language, "en");
        assert!(config.recent_files.is_empty());
    }

    #[test]
    fn test_serialize_deserialize() {
        let config = UserConfig {
            language: "de".to_string(),
            last_project: Some("/path/to/project.Vorce".to_string()),
            recent_files: vec!["file1.mp4".to_string(), "file2.mp4".to_string()],
            theme: ThemeConfig::default(),
            target_fps: Some(60.0),
            preferred_gpu: None,
            vsync_mode: VSyncMode::default(),
            meter_style: AudioMeterStyle::Digital,
            toolbar_metrics: ToolbarMetricsConfig::default(),
            midi_assignments: Vec::new(),
            selected_audio_device: None,
            window_width: Some(1920),
            window_height: Some(1080),
            window_x: Some(100),
            window_y: Some(50),
            window_maximized: false,
            show_left_sidebar: true,
            show_inspector: true,
            show_timeline: true,
            show_media_browser: true,
            show_module_canvas: true,
            show_controller_overlay: false,
            web_api_enabled: false,
            web_api_port: 8080,
            show_media_manager: false,
            show_dashboard: true,
            ndi_discovery: true,
            hue_config: HueConfig::default(),
            global_fullscreen: true,
            ui_scale: 1.2,
            log_level: AppLogLevel::Info,
            node_animations_enabled: true,
            startup_animation_enabled: true,
            startup_animation_path: default_startup_animation_path(),
            reduce_motion_enabled: false,
            silent_startup_enabled: false,
            animation_profile: AnimationProfile::Subtle,
            short_circuit_animation_enabled: true,
            layouts: default_layout_profiles(),
            active_layout_id: default_active_layout_id(),
        };

        let json = serde_json::to_string(&config).unwrap();
        let loaded: UserConfig = serde_json::from_str(&json).unwrap();

        assert_eq!(loaded.language, "de");
        assert_eq!(loaded.recent_files.len(), 2);
        assert_eq!(loaded.meter_style, AudioMeterStyle::Digital);
    }

    #[test]
    fn test_ensure_layout_profiles_repairs_empty_state() {
        let mut config = UserConfig {
            layouts: Vec::new(),
            active_layout_id: "missing".to_string(),
            ..UserConfig::default()
        };

        config.ensure_layout_profiles();

        assert!(!config.layouts.is_empty());
        assert_eq!(config.active_layout_id, "default");
    }

    #[test]
    fn test_set_active_layout() {
        let mut config = UserConfig::default();
        config.add_layout_profile(LayoutProfile {
            id: "live".to_string(),
            name: "Live".to_string(),
            visibility: LayoutVisibility::default(),
            panel_sizes: LayoutPanelSizes::default(),
            lock_layout: false,
        });

        assert!(config.set_active_layout("live"));
        assert_eq!(config.active_layout_id, "live");
        assert!(!config.set_active_layout("does-not-exist"));
    }

    #[test]
    fn test_repair_for_startup_recovers_hidden_active_layout() {
        let mut config = UserConfig::default();
        if let Some(layout) = config.active_layout_mut() {
            layout.visibility.show_toolbar = false;
            layout.visibility.show_left_sidebar = false;
            layout.visibility.show_inspector = false;
            layout.visibility.show_timeline = false;
            layout.visibility.show_media_browser = false;
            layout.visibility.show_module_canvas = false;
        }
        config.show_left_sidebar = false;
        config.show_inspector = false;
        config.show_timeline = false;
        config.show_media_browser = false;
        config.show_module_canvas = false;

        let mut report = UserConfigLoadReport::default();
        let repaired = config.repair_for_startup(&mut report);

        assert!(repaired);
        assert!(config.active_layout().unwrap().visibility.show_left_sidebar);
        assert!(config.active_layout().unwrap().visibility.show_module_canvas);
        assert!(config.show_left_sidebar);
        assert!(config.show_module_canvas);
        assert!(report
            .errors
            .iter()
            .any(|entry| entry.contains("Recovered unusable startup layout")));
    }

    #[test]
    fn test_repair_for_startup_restores_missing_active_layout() {
        let mut config =
            UserConfig { active_layout_id: "missing".to_string(), ..UserConfig::default() };

        let mut report = UserConfigLoadReport::default();
        let repaired = config.repair_for_startup(&mut report);

        assert!(repaired);
        assert_eq!(config.active_layout_id, "default");
        assert!(report.errors.iter().any(|entry| entry.contains("missing active layout")));
    }

    #[test]
    fn test_existing_config_path_prefers_vorce_and_falls_back_to_mapflow() {
        let root = std::env::temp_dir().join(format!("vorce-config-test-{}", std::process::id()));
        let primary = root.join(APP_CONFIG_DIR).join(CONFIG_FILE_NAME);
        let legacy = root.join(LEGACY_APP_CONFIG_DIR).join(CONFIG_FILE_NAME);

        if root.exists() {
            fs::remove_dir_all(&root).unwrap();
        }

        fs::create_dir_all(legacy.parent().unwrap()).unwrap();
        fs::write(&legacy, "{}").unwrap();
        assert_eq!(
            UserConfig::resolve_existing_config_path(Some(primary.clone()), Some(legacy.clone())),
            Some(legacy.clone())
        );

        fs::create_dir_all(primary.parent().unwrap()).unwrap();
        fs::write(&primary, "{}").unwrap();
        assert_eq!(
            UserConfig::resolve_existing_config_path(Some(primary.clone()), Some(legacy)),
            Some(primary)
        );

        fs::remove_dir_all(root).unwrap();
    }
}
