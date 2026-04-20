//! Phase 6: Asset Management System
//!
//! Media library, effect preset browser, project templates,
//! and import/export workflows.

use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// Asset manager for managing presets, templates, and media libraries
pub struct AssetManager {
    /// Effect presets
    effect_presets: HashMap<String, EffectPreset>,
    /// Transform presets
    transform_presets: HashMap<String, TransformPreset>,
    /// Project templates
    project_templates: HashMap<String, ProjectTemplate>,
    /// User library path
    library_path: PathBuf,
}

/// Effect preset (saved effect configuration)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EffectPreset {
    /// Human-readable display name.
    pub name: String,
    #[serde(default)]
    pub name_lower: String,
    pub category: String,
    pub description: String,
    #[serde(default)]
    pub description_lower: String,
    pub tags: Vec<String>,
    #[serde(default)]
    pub tags_lower: Vec<String>,
    pub favorite: bool,
    pub parameters: HashMap<String, PresetParameter>,
    pub thumbnail: Option<PathBuf>,
}

/// Transform preset (saved transform configuration)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformPreset {
    /// Human-readable display name.
    pub name: String,
    pub description: String,
    /// 3D position coordinates [x, y, z].
    pub position: (f32, f32),
    /// Scale factors for the object's dimensions.
    pub scale: (f32, f32),
    /// Rotation angles in degrees.
    pub rotation: (f32, f32, f32),
    pub anchor: (f32, f32),
}

/// Project template
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectTemplate {
    /// Human-readable display name.
    pub name: String,
    pub description: String,
    pub tags: Vec<String>,
    pub thumbnail: Option<PathBuf>,
    pub file_path: PathBuf,
}

/// Preset parameter value
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PresetParameter {
    Float(f32),
    Int(i32),
    Bool(bool),
    String(String),
    Color([f32; 4]),
    Vector([f32; 3]),
}

impl AssetManager {
    pub fn new(library_path: PathBuf) -> Self {
        let mut manager = Self {
            effect_presets: HashMap::new(),
            transform_presets: HashMap::new(),
            project_templates: HashMap::new(),
            library_path,
        };
        manager.load_library();
        manager
    }

    /// Load library from disk
    fn load_library(&mut self) {
        // Load effect presets
        let effects_path = self.library_path.join("effects");
        if effects_path.exists() {
            if let Ok(entries) = std::fs::read_dir(effects_path) {
                let paths: Vec<_> = entries
                    .flatten()
                    .map(|e| e.path())
                    .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("json"))
                    .collect();

                let loaded_presets: Vec<_> = paths
                    .into_par_iter()
                    .filter_map(|path| std::fs::read_to_string(path).ok())
                    .filter_map(|data| serde_json::from_str::<EffectPreset>(&data).ok())
                    .map(|mut preset| {
                        preset.name_lower = preset.name.to_lowercase();
                        preset.description_lower = preset.description.to_lowercase();
                        preset.tags_lower = preset.tags.iter().map(|t| t.to_lowercase()).collect();
                        (preset.name.clone(), preset)
                    })
                    .collect();

                for (name, preset) in loaded_presets {
                    self.effect_presets.insert(name, preset);
                }
            }
        }

        // Load transform presets
        let transforms_path = self.library_path.join("transforms");
        if transforms_path.exists() {
            if let Ok(entries) = std::fs::read_dir(transforms_path) {
                let paths: Vec<_> = entries
                    .flatten()
                    .map(|e| e.path())
                    .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("json"))
                    .collect();

                let loaded_presets: Vec<_> = paths
                    .into_par_iter()
                    .filter_map(|path| std::fs::read_to_string(path).ok())
                    .filter_map(|data| serde_json::from_str::<TransformPreset>(&data).ok())
                    .map(|preset| (preset.name.clone(), preset))
                    .collect();

                for (name, preset) in loaded_presets {
                    self.transform_presets.insert(name, preset);
                }
            }
        }

        // Load project templates
        let templates_path = self.library_path.join("templates");
        if templates_path.exists() {
            if let Ok(entries) = std::fs::read_dir(templates_path) {
                let paths: Vec<_> = entries
                    .flatten()
                    .map(|e| e.path())
                    .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("json"))
                    .collect();

                let loaded_templates: Vec<_> = paths
                    .into_par_iter()
                    .filter_map(|path| std::fs::read_to_string(path).ok())
                    .filter_map(|data| serde_json::from_str::<ProjectTemplate>(&data).ok())
                    .map(|template| (template.name.clone(), template))
                    .collect();

                for (name, template) in loaded_templates {
                    self.project_templates.insert(name, template);
                }
            }
        }
    }

    /// Save effect preset
    pub fn save_effect_preset(&mut self, mut preset: EffectPreset) -> Result<(), std::io::Error> {
        let effects_path = self.library_path.join("effects");
        std::fs::create_dir_all(&effects_path)?;

        preset.name_lower = preset.name.to_lowercase();
        preset.description_lower = preset.description.to_lowercase();
        preset.tags_lower = preset.tags.iter().map(|t| t.to_lowercase()).collect();

        let canonical_effects_path = effects_path.canonicalize()?;

        let file_path = effects_path.join(format!("{}.json", preset.name));
        if let Some(parent) = file_path.parent() {
            std::fs::create_dir_all(parent)?;
            let canonical_parent = parent.canonicalize()?;
            if !canonical_parent.starts_with(&canonical_effects_path) {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::PermissionDenied,
                    "Path traversal detected",
                ));
            }
        } else {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "Invalid preset name",
            ));
        }
        let data = serde_json::to_string_pretty(&preset)?;
        std::fs::write(file_path, data)?;

        self.effect_presets.insert(preset.name.clone(), preset);
        Ok(())
    }

    /// Save transform preset
    pub fn save_transform_preset(&mut self, preset: TransformPreset) -> Result<(), std::io::Error> {
        let transforms_path = self.library_path.join("transforms");
        std::fs::create_dir_all(&transforms_path)?;

        let canonical_transforms_path = transforms_path.canonicalize()?;

        let file_path = transforms_path.join(format!("{}.json", preset.name));
        if let Some(parent) = file_path.parent() {
            std::fs::create_dir_all(parent)?;
            let canonical_parent = parent.canonicalize()?;
            if !canonical_parent.starts_with(&canonical_transforms_path) {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::PermissionDenied,
                    "Path traversal detected",
                ));
            }
        } else {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "Invalid preset name",
            ));
        }
        let data = serde_json::to_string_pretty(&preset)?;
        std::fs::write(file_path, data)?;

        self.transform_presets.insert(preset.name.clone(), preset);
        Ok(())
    }

    /// Get effect preset by name
    pub fn get_effect_preset(&self, name: &str) -> Option<&EffectPreset> {
        self.effect_presets.get(name)
    }

    /// Get transform preset by name
    pub fn get_transform_preset(&self, name: &str) -> Option<&TransformPreset> {
        self.transform_presets.get(name)
    }

    /// Get all effect presets
    pub fn effect_presets(&self) -> &HashMap<String, EffectPreset> {
        &self.effect_presets
    }

    /// Get all transform presets
    pub fn transform_presets(&self) -> &HashMap<String, TransformPreset> {
        &self.transform_presets
    }

    /// Get all project templates
    pub fn project_templates(&self) -> &HashMap<String, ProjectTemplate> {
        &self.project_templates
    }

    /// Search presets by query
    pub fn search_effect_presets(&self, query: &str) -> Vec<&EffectPreset> {
        let query_lower = query.to_lowercase();
        self.effect_presets
            .values()
            .filter(|preset| {
                preset.name_lower.contains(&query_lower)
                    || preset.description_lower.contains(&query_lower)
                    || preset.tags_lower.iter().any(|tag| tag.contains(&query_lower))
            })
            .collect()
    }

    /// Get effect presets by category
    pub fn effect_presets_by_category(&self, category: &str) -> Vec<&EffectPreset> {
        self.effect_presets.values().filter(|preset| preset.category == category).collect()
    }

    /// Get favorite effect presets
    pub fn favorite_effect_presets(&self) -> Vec<&EffectPreset> {
        self.effect_presets.values().filter(|preset| preset.favorite).collect()
    }

    /// Render asset browser UI
    pub fn ui(&mut self, ui: &mut egui::Ui) -> Option<AssetManagerAction> {
        let mut action = None;

        egui::Panel::top("asset_browser_tabs").show_inside(ui, |ui| {
            ui.horizontal(|ui| {
                let _ = ui.selectable_label(false, "Effect Presets");
                let _ = ui.selectable_label(false, "Transform Presets");
                let _ = ui.selectable_label(false, "Project Templates");
            });
        });

        // For now, just show effect presets
        egui::ScrollArea::vertical().show(ui, |ui| {
            for preset in self.effect_presets.values() {
                ui.horizontal(|ui| {
                    if preset.favorite {
                        ui.label("⭐");
                    }

                    if ui.button(&preset.name).clicked() {
                        action = Some(AssetManagerAction::LoadEffectPreset(preset.clone()));
                    }

                    ui.label(&preset.category);
                    ui.label(&preset.description);
                });
            }
        });

        action
    }
}

/// Actions that can be triggered by the asset manager
#[derive(Debug, Clone)]
pub enum AssetManagerAction {
    LoadEffectPreset(EffectPreset),
    LoadTransformPreset(TransformPreset),
    LoadProjectTemplate(ProjectTemplate),
    SaveEffectPreset,
    SaveTransformPreset,
}
