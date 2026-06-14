use serde::{Deserialize, Serialize};

/// Sichtbarkeitseinstellungen für das Hauptlayout.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub struct LayoutVisibility {
    #[serde(default = "default_true")]
    pub show_toolbar: bool,
    #[serde(default = "default_true")]
    pub show_left_sidebar: bool,
    #[serde(default = "default_true")]
    pub show_inspector: bool,
    #[serde(default = "default_true")]
    pub show_timeline: bool,
    #[serde(default = "default_true")]
    pub show_media_browser: bool,
    #[serde(default = "default_true")]
    pub show_module_canvas: bool,
}

impl Default for LayoutVisibility {
    fn default() -> Self {
        Self {
            show_toolbar: true,
            show_left_sidebar: true,
            show_inspector: true,
            show_timeline: true,
            show_media_browser: true,
            show_module_canvas: true,
        }
    }
}

impl LayoutVisibility {
    pub(crate) fn has_primary_workspace(self) -> bool {
        self.show_module_canvas
            || self.show_left_sidebar
            || self.show_inspector
            || self.show_timeline
            || self.show_media_browser
    }
}

/// Größenparameter des Hauptlayouts.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub struct LayoutPanelSizes {
    #[serde(default = "super::default_sidebar_width")]
    pub left_sidebar_width: f32,
    #[serde(default = "super::default_inspector_width")]
    pub inspector_width: f32,
    #[serde(default = "super::default_timeline_height")]
    pub timeline_height: f32,
}

impl Default for LayoutPanelSizes {
    fn default() -> Self {
        Self {
            left_sidebar_width: super::default_sidebar_width(),
            inspector_width: super::default_inspector_width(),
            timeline_height: super::default_timeline_height(),
        }
    }
}

/// Persistentes Layout-Profil für die Arbeitsoberfläche.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LayoutProfile {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub visibility: LayoutVisibility,
    #[serde(default)]
    pub panel_sizes: LayoutPanelSizes,
    #[serde(default)]
    pub lock_layout: bool,
}

impl LayoutProfile {
    /// Standardprofil, das dem bisherigen Dock-Layout entspricht.
    pub fn default_profile() -> Self {
        Self {
            id: "default".to_string(),
            name: "Default".to_string(),
            visibility: LayoutVisibility::default(),
            panel_sizes: LayoutPanelSizes::default(),
            lock_layout: false,
        }
    }
}

fn default_true() -> bool {
    true
}
