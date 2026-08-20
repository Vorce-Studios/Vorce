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
    use std::fs;
    use std::sync::Mutex;
    use tempfile::TempDir;
    static ENV_MUTEX: Mutex<()> = Mutex::new(());

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

    #[test]
    fn existing_resource_path_works() {
        // Prevent concurrent tests from stepping on each other's ENV changes
        let _lock = ENV_MUTEX.lock().unwrap();

        let temp = TempDir::new().unwrap();
        let resource_dir = temp.path().join("resources");
        fs::create_dir_all(&resource_dir).unwrap();

        let test_file = resource_dir.join("test_file.txt");
        fs::write(&test_file, "content").unwrap();

        // Temporarily set VORCE_RESOURCES_DIR to our test directory
        env::set_var(RESOURCES_ENV, &resource_dir);

        // existing file should be found
        let found = existing_resource_path("test_file.txt");
        assert_eq!(found, Some(test_file));

        // missing file should return None
        let missing = existing_resource_path("missing_file.txt");
        assert_eq!(missing, None);

        // Restore environment by unsetting test var
        env::remove_var(RESOURCES_ENV);
    }
}
