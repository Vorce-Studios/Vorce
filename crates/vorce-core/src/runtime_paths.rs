//! Runtime path helpers for locating packaged and development resources.

use std::env;
use std::path::{Path, PathBuf};

const ASSETS_ENV: &str = "VORCE_ASSETS_DIR";
const RESOURCES_ENV: &str = "VORCE_RESOURCES_DIR";
const LEGACY_ASSETS_ENV: &str = "Vorce_ASSETS_DIR";
const LEGACY_RESOURCES_ENV: &str = "Vorce_RESOURCES_DIR";

/// Resolve the assets directory for the current runtime environment.
pub fn assets_dir() -> PathBuf {
    resolve_named_dir(ASSETS_ENV, "assets")
}

/// Resolve the resources directory for the current runtime environment.
pub fn resources_dir() -> PathBuf {
    resolve_named_dir(RESOURCES_ENV, "resources")
}

/// Build a path inside the resolved assets directory.
pub fn asset_path(relative: impl AsRef<Path>) -> PathBuf {
    assets_dir().join(relative)
}

/// Build a path inside the resolved resources directory.
pub fn resource_path(relative: impl AsRef<Path>) -> PathBuf {
    resources_dir().join(relative)
}

/// Resolve an existing path inside the assets directory.
pub fn existing_asset_path(relative: impl AsRef<Path>) -> Option<PathBuf> {
    resolve_existing_path(ASSETS_ENV, LEGACY_ASSETS_ENV, "assets", relative.as_ref())
}

/// Resolve an existing path inside the resources directory.
pub fn existing_resource_path(relative: impl AsRef<Path>) -> Option<PathBuf> {
    resolve_existing_path(RESOURCES_ENV, LEGACY_RESOURCES_ENV, "resources", relative.as_ref())
}

fn resolve_named_dir(env_var: &str, dir_name: &str) -> PathBuf {
    let legacy_env = if env_var == ASSETS_ENV { LEGACY_ASSETS_ENV } else { LEGACY_RESOURCES_ENV };
    candidate_dirs(env_var, legacy_env, dir_name)
        .into_iter()
        .find(|path| path.exists())
        .unwrap_or_else(|| PathBuf::from(dir_name))
}

fn resolve_existing_path(
    env_var: &str,
    legacy_env_var: &str,
    dir_name: &str,
    relative: &Path,
) -> Option<PathBuf> {
    candidate_dirs(env_var, legacy_env_var, dir_name)
        .into_iter()
        .map(|base| base.join(relative))
        .find(|path| path.exists())
}

fn candidate_dirs(env_var: &str, legacy_env_var: &str, dir_name: &str) -> Vec<PathBuf> {
    let mut candidates = Vec::new();

    push_unique(
        &mut candidates,
        env::var_os(env_var).map(PathBuf::from).filter(|path| !path.as_os_str().is_empty()),
    );

    push_unique(
        &mut candidates,
        env::var_os(legacy_env_var).map(PathBuf::from).filter(|path| !path.as_os_str().is_empty()),
    );

    if let Some(exe_dir) = current_exe_dir() {
        push_unique(
            &mut candidates,
            bundle_resources_dir_from_exe_dir(&exe_dir).map(|path| path.join(dir_name)),
        );
        push_unique_ancestors_with_child(&mut candidates, &exe_dir, dir_name);
    }

    if let Ok(current_dir) = env::current_dir() {
        push_unique_ancestors_with_child(&mut candidates, &current_dir, dir_name);
    }

    // Linux system-wide installation path
    #[cfg(target_os = "linux")]
    {
        push_unique(&mut candidates, Some(PathBuf::from("/usr/share/vorce").join(dir_name)));
        push_unique(&mut candidates, Some(PathBuf::from("/usr/local/share/vorce").join(dir_name)));
    }

    candidates
}

fn current_exe_dir() -> Option<PathBuf> {
    env::current_exe().ok().and_then(|path| path.parent().map(Path::to_path_buf))
}

fn bundle_resources_dir_from_exe_dir(exe_dir: &Path) -> Option<PathBuf> {
    if exe_dir.file_name()? != "MacOS" {
        return None;
    }

    let contents_dir = exe_dir.parent()?;
    if contents_dir.file_name()? != "Contents" {
        return None;
    }

    Some(contents_dir.join("Resources"))
}

fn push_unique(candidates: &mut Vec<PathBuf>, candidate: Option<PathBuf>) {
    if let Some(candidate) = candidate {
        if !candidates.iter().any(|existing| existing == &candidate) {
            candidates.push(candidate);
        }
    }
}

fn push_unique_ancestors_with_child(candidates: &mut Vec<PathBuf>, start: &Path, child: &str) {
    for ancestor in start.ancestors() {
        push_unique(candidates, Some(ancestor.join(child)));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use serial_test::serial;
    use std::fs;
    use tempfile::tempdir;

    // A helper to temporarily set an environment variable.
    struct EnvVarGuard {
        key: &'static str,
        original_value: Option<std::ffi::OsString>,
    }

    impl EnvVarGuard {
        fn new(key: &'static str, value: &Path) -> Self {
            let original_value = env::var_os(key);
            env::set_var(key, value);
            Self { key, original_value }
        }

        fn clear(key: &'static str) -> Self {
            let original_value = env::var_os(key);
            env::remove_var(key);
            Self { key, original_value }
        }
    }

    impl Drop for EnvVarGuard {
        fn drop(&mut self) {
            match &self.original_value {
                Some(val) => env::set_var(self.key, val),
                None => env::remove_var(self.key),
            }
        }
    }

    #[test]
    #[serial]
    fn test_assets_dir_env_var() {
        let temp_dir = tempdir().unwrap();
        let path = temp_dir.path().join("my_assets");
        fs::create_dir_all(&path).unwrap();

        let _guard = EnvVarGuard::new(ASSETS_ENV, &path);
        assert_eq!(assets_dir(), path);
    }

    #[test]
    #[serial]
    fn test_assets_dir_legacy_env_var() {
        let temp_dir = tempdir().unwrap();
        let path = temp_dir.path().join("my_legacy_assets");
        fs::create_dir_all(&path).unwrap();

        let _guard_clear = EnvVarGuard::clear(ASSETS_ENV);
        let _guard = EnvVarGuard::new(LEGACY_ASSETS_ENV, &path);
        assert_eq!(assets_dir(), path);
    }

    #[test]
    #[serial]
    fn test_resources_dir_env_var() {
        let temp_dir = tempdir().unwrap();
        let path = temp_dir.path().join("my_resources");
        fs::create_dir_all(&path).unwrap();

        let _guard = EnvVarGuard::new(RESOURCES_ENV, &path);
        assert_eq!(resources_dir(), path);
    }

    #[test]
    #[serial]
    fn test_asset_path() {
        let temp_dir = tempdir().unwrap();
        let path = temp_dir.path().join("my_assets");
        fs::create_dir_all(&path).unwrap();

        let _guard = EnvVarGuard::new(ASSETS_ENV, &path);
        assert_eq!(asset_path("test.png"), path.join("test.png"));
    }

    #[test]
    #[serial]
    fn test_resource_path() {
        let temp_dir = tempdir().unwrap();
        let path = temp_dir.path().join("my_resources");
        fs::create_dir_all(&path).unwrap();

        let _guard = EnvVarGuard::new(RESOURCES_ENV, &path);
        assert_eq!(resource_path("config.json"), path.join("config.json"));
    }

    #[test]
    #[serial]
    fn test_existing_asset_path_found() {
        let temp_dir = tempdir().unwrap();
        let base_path = temp_dir.path().join("my_assets");
        fs::create_dir_all(&base_path).unwrap();
        let file_path = base_path.join("exists.png");
        fs::write(&file_path, "test").unwrap();

        let _guard = EnvVarGuard::new(ASSETS_ENV, &base_path);
        assert_eq!(existing_asset_path("exists.png"), Some(file_path));
    }

    #[test]
    #[serial]
    fn test_existing_asset_path_not_found() {
        let temp_dir = tempdir().unwrap();
        let base_path = temp_dir.path().join("my_assets");
        fs::create_dir_all(&base_path).unwrap();

        let _guard = EnvVarGuard::new(ASSETS_ENV, &base_path);
        assert_eq!(existing_asset_path("missing.png"), None);
    }

    #[test]
    #[serial]
    fn test_existing_resource_path_found() {
        let temp_dir = tempdir().unwrap();
        let base_path = temp_dir.path().join("my_resources");
        fs::create_dir_all(&base_path).unwrap();
        let file_path = base_path.join("exists.json");
        fs::write(&file_path, "test").unwrap();

        let _guard = EnvVarGuard::new(RESOURCES_ENV, &base_path);
        assert_eq!(existing_resource_path("exists.json"), Some(file_path));
    }

    #[test]
    fn detects_macos_bundle_resources_dir() {
        let exe_dir = Path::new("/Applications/Vorce.app/Contents/MacOS");
        let expected = PathBuf::from("/Applications/Vorce.app/Contents/Resources");
        assert_eq!(bundle_resources_dir_from_exe_dir(exe_dir), Some(expected));
    }

    #[test]
    fn ignores_non_bundle_paths() {
        let exe_dir = Path::new("/tmp/vorce/target/release");
        assert_eq!(bundle_resources_dir_from_exe_dir(exe_dir), None);
    }
}
