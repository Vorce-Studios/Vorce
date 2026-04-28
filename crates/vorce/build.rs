#[cfg(windows)]
extern crate winres;

fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default() == "windows" {
        #[cfg(windows)]
        copy_runtime_dlls();

        #[cfg(windows)]
        {
            let mut res = winres::WindowsResource::new();
            res.set_icon("../../resources/app_icons/Vorce_Logo_LQ-Full.ico");
            res.compile().unwrap();
        }
    }
}

#[cfg(windows)]
fn copy_runtime_dlls() {
    use std::collections::HashSet;
    use std::path::PathBuf;

    let manifest_dir =
        PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR missing"));
    let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR missing"));
    let profile_dir =
        out_dir.ancestors().nth(3).expect("Failed to resolve target profile dir").to_path_buf();
    let workspace_root = manifest_dir.join("..").join("..");
    let runtime_dirs = [
        workspace_root.join("vcpkg_installed").join("x64-windows").join("bin"),
        workspace_root.join("vcpkg").join("packages").join("ffmpeg_x64-windows").join("bin"),
        workspace_root.join("vcpkg").join("installed").join("x64-windows").join("bin"),
    ];

    for runtime_dir in &runtime_dirs {
        println!("cargo:rerun-if-changed={}", runtime_dir.display());
    }

    let dll_prefixes = ["av", "sw", "pkgconf"];
    let mut copied_names = HashSet::new();
    let mut copied_any = false;

    if copy_prefixed_runtime_dlls(&profile_dir, &runtime_dirs, &dll_prefixes, &mut copied_names) {
        copied_any = true;
    }

    if std::env::var_os("CARGO_FEATURE_NDI").is_some() {
        println!("cargo:rerun-if-env-changed=NDI_RUNTIME_DIR");
        println!("cargo:rerun-if-env-changed=NDI_SDK_DIR");

        let ndi_runtime_dirs = ndi_runtime_dirs();
        for runtime_dir in &ndi_runtime_dirs {
            println!("cargo:rerun-if-changed={}", runtime_dir.display());
        }

        if copy_named_runtime_dll(
            &profile_dir,
            "Processing.NDI.Lib.x64.dll",
            &ndi_runtime_dirs,
            &mut copied_names,
        ) {
            copied_any = true;
        } else {
            println!(
                "cargo:warning=NDI feature enabled, but Processing.NDI.Lib.x64.dll was not found in known runtime directories"
            );
        }
    }

    if !copied_any {
        println!("cargo:warning=No runtime DLLs were copied into {}", profile_dir.display());
    }
}

#[cfg(windows)]
fn copy_prefixed_runtime_dlls(
    profile_dir: &std::path::Path,
    runtime_dirs: &[std::path::PathBuf],
    dll_prefixes: &[&str],
    copied_names: &mut std::collections::HashSet<String>,
) -> bool {
    let mut copied_any = false;

    for runtime_dir in runtime_dirs.iter().filter(|dir| dir.is_dir()) {
        let entries = match std::fs::read_dir(runtime_dir) {
            Ok(entries) => entries,
            Err(err) => {
                println!(
                    "cargo:warning=Failed to read runtime DLL directory {}: {}",
                    runtime_dir.display(),
                    err
                );
                continue;
            }
        };

        for entry in entries.flatten() {
            let path = entry.path();
            let file_name = match path.file_name().and_then(|name| name.to_str()) {
                Some(name) => name,
                None => continue,
            };
            let is_runtime_dll = path
                .extension()
                .and_then(|ext| ext.to_str())
                .map(|ext| ext.eq_ignore_ascii_case("dll"))
                .unwrap_or(false)
                && dll_prefixes.iter().any(|prefix| file_name.starts_with(prefix));
            if !is_runtime_dll {
                continue;
            }

            if copy_runtime_dll(profile_dir, &path, copied_names) {
                copied_any = true;
            }
        }
    }

    copied_any
}

#[cfg(windows)]
fn copy_named_runtime_dll(
    profile_dir: &std::path::Path,
    dll_name: &str,
    runtime_dirs: &[std::path::PathBuf],
    copied_names: &mut std::collections::HashSet<String>,
) -> bool {
    for runtime_dir in runtime_dirs.iter().filter(|dir| dir.is_dir()) {
        let candidate = runtime_dir.join(dll_name);
        if candidate.is_file() && copy_runtime_dll(profile_dir, &candidate, copied_names) {
            return true;
        }
    }

    false
}

#[cfg(windows)]
fn copy_runtime_dll(
    profile_dir: &std::path::Path,
    source: &std::path::Path,
    copied_names: &mut std::collections::HashSet<String>,
) -> bool {
    let file_name = match source.file_name().and_then(|name| name.to_str()) {
        Some(name) => name,
        None => return false,
    };
    if copied_names.contains(file_name) {
        return false;
    }

    if !is_valid_runtime_dll(source) {
        println!("cargo:warning=Skipping invalid runtime DLL candidate: {}", source.display());
        return false;
    }

    let destination = profile_dir.join(file_name);
    match std::fs::copy(source, &destination) {
        Ok(_) => {
            copied_names.insert(file_name.to_owned());
            true
        }
        Err(err) => {
            println!(
                "cargo:warning=Failed to copy runtime DLL {} -> {}: {}",
                source.display(),
                destination.display(),
                err
            );
            false
        }
    }
}

#[cfg(windows)]
fn ndi_runtime_dirs() -> Vec<std::path::PathBuf> {
    let mut dirs = Vec::new();

    if let Some(path) = env_dir("NDI_RUNTIME_DIR") {
        dirs.push(path.clone());
        dirs.push(path.join("v6"));
        dirs.push(path.join("Bin").join("x64"));
    }

    if let Some(path) = env_dir("NDI_SDK_DIR") {
        dirs.push(path.clone());
        dirs.push(path.join("Bin").join("x64"));
        dirs.push(path.join("Lib").join("x64"));
    }

    if let Some(program_files) = env_dir("ProgramFiles") {
        let ndi_root = program_files.join("NDI");
        dirs.push(ndi_root.join("NDI 6 Runtime").join("v6"));
        dirs.push(ndi_root.join("NDI 6 SDK").join("Bin").join("x64"));

        if let Ok(entries) = std::fs::read_dir(&ndi_root) {
            for entry in entries.flatten() {
                let path = entry.path();
                dirs.push(path.join("v6"));
                dirs.push(path.join("Bin").join("x64"));
            }
        }
    }

    dirs
}

#[cfg(windows)]
fn env_dir(name: &str) -> Option<std::path::PathBuf> {
    std::env::var_os(name).map(std::path::PathBuf::from)
}

#[cfg(windows)]
fn is_valid_runtime_dll(path: &std::path::Path) -> bool {
    use std::io::{Read, Seek, SeekFrom};

    let file_name =
        path.file_name().and_then(|name| name.to_str()).unwrap_or_default().to_ascii_lowercase();
    if file_name.starts_with("pkgconf") {
        return true;
    }

    let mut file = match std::fs::File::open(path) {
        Ok(file) => file,
        Err(_) => return false,
    };

    let mut dos_header = [0_u8; 64];
    if file.read_exact(&mut dos_header).is_err() || &dos_header[0..2] != b"MZ" {
        return false;
    }

    let pe_offset = u32::from_le_bytes([
        dos_header[0x3c],
        dos_header[0x3d],
        dos_header[0x3e],
        dos_header[0x3f],
    ]) as u64;

    if file.seek(SeekFrom::Start(pe_offset)).is_err() {
        return false;
    }

    let mut pe_signature = [0_u8; 4];
    file.read_exact(&mut pe_signature).is_ok() && pe_signature == *b"PE\0\0"
}
