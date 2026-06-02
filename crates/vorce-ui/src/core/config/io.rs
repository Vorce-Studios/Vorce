use super::UserConfig;
use std::fs;
use std::path::PathBuf;

pub(crate) const APP_CONFIG_DIR: &str = "Vorce";
pub(crate) const LEGACY_APP_CONFIG_DIR: &str = "MapFlow";
pub(crate) const CONFIG_FILE_NAME: &str = "config.json";

/// Diagnostics captured while loading and repairing the persisted user config.
#[derive(Debug, Clone, Default)]
pub struct UserConfigLoadReport {
    /// Path that was used as the load source, if any.
    pub source_path: Option<PathBuf>,
    /// Whether the legacy MapFlow config path was used.
    pub used_legacy_config_path: bool,
    /// Whether defaults were used because no config existed or loading failed.
    pub loaded_defaults: bool,
    /// Non-fatal notes about the load process.
    pub warnings: Vec<String>,
    /// Recoveries or failures that should be visible in the log.
    pub errors: Vec<String>,
}

impl UserConfigLoadReport {
    /// Emit the collected diagnostics through tracing once logging is initialized.
    pub fn emit_logs(&self) {
        match &self.source_path {
            Some(path) => {
                if self.used_legacy_config_path {
                    tracing::warn!("Loaded user config from legacy path {:?}", path);
                } else {
                    tracing::info!("Loaded user config from {:?}", path);
                }
            }
            None if self.loaded_defaults => {
                tracing::info!("No user config found. Using built-in defaults.");
            }
            None => {}
        }

        for warning in &self.warnings {
            tracing::warn!("{warning}");
        }

        for error in &self.errors {
            tracing::error!("{error}");
        }
    }
}

impl UserConfig {
    /// Get the config file path
    pub(crate) fn config_path() -> Option<PathBuf> {
        Self::config_path_for_app(APP_CONFIG_DIR)
    }

    pub(crate) fn legacy_config_path() -> Option<PathBuf> {
        Self::config_path_for_app(LEGACY_APP_CONFIG_DIR)
    }

    pub(crate) fn config_path_for_app(app_name: &str) -> Option<PathBuf> {
        dirs::config_dir().map(|mut p| {
            p.push(app_name);
            p.push(CONFIG_FILE_NAME);
            p
        })
    }

    pub(crate) fn resolve_existing_config_path(
        primary: Option<PathBuf>,
        legacy: Option<PathBuf>,
    ) -> Option<PathBuf> {
        if let Some(path) = primary.as_ref().filter(|path| path.exists()) {
            return Some(path.clone());
        }

        legacy.filter(|path| path.exists()).or(primary)
    }

    /// Load configuration from disk with diagnostics about recovery steps and failures.
    pub fn load_with_report() -> (Self, UserConfigLoadReport) {
        let primary = Self::config_path();
        let legacy = Self::legacy_config_path();
        let selected_path = Self::resolve_existing_config_path(primary.clone(), legacy.clone());

        let mut report = UserConfigLoadReport {
            source_path: selected_path.clone(),
            used_legacy_config_path: matches!(
                (&selected_path, &legacy),
                (Some(selected), Some(legacy_path)) if selected == legacy_path
            ),
            ..Default::default()
        };

        let mut loaded = match selected_path.as_ref() {
            Some(path) if path.exists() => match fs::read_to_string(path) {
                Ok(content) => match serde_json::from_str(&content) {
                    Ok(config) => config,
                    Err(err) => {
                        report.loaded_defaults = true;
                        report.errors.push(format!(
                            "Failed to parse user config {:?}: {}. Falling back to defaults.",
                            path, err
                        ));
                        Self::default()
                    }
                },
                Err(err) => {
                    report.loaded_defaults = true;
                    report.errors.push(format!(
                        "Failed to read user config {:?}: {}. Falling back to defaults.",
                        path, err
                    ));
                    Self::default()
                }
            },
            _ => {
                report.loaded_defaults = true;
                Self::default()
            }
        };

        if report.used_legacy_config_path {
            report.warnings.push(
                "Using legacy MapFlow config path. Saving from the app will migrate it to Vorce."
                    .to_string(),
            );
        }

        if loaded.repair_for_startup(&mut report) {
            if let Err(err) = loaded.save() {
                report.errors.push(format!(
                    "Failed to save repaired user config to the Vorce config path: {}",
                    err
                ));
            }
        }

        (loaded, report)
    }

    /// Load configuration from disk
    pub fn load() -> Self {
        let (loaded, report) = Self::load_with_report();
        report.emit_logs();
        loaded
    }

    /// Save configuration to disk
    pub fn save(&self) -> Result<(), std::io::Error> {
        if let Some(path) = Self::config_path() {
            // Ensure parent directory exists
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent)?;
            }
            let content = serde_json::to_string_pretty(self)?;
            fs::write(&path, content)?;
        }
        Ok(())
    }
}
