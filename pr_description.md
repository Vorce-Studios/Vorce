🎯 **What:**
The vulnerability fixed is a Path Traversal issue in the `save_effect_preset` and `save_transform_preset` functions within `AssetManager`. Previously, a malicious or malformed `preset.name` containing relative path separators (like `../`) could write files outside of the designated library directories.

⚠️ **Risk:**
If left unfixed, an attacker could supply a preset name starting with `../../../` to save arbitrary JSON data anywhere on the user's filesystem where the process has write permissions. This could lead to data overwrite, arbitrary code execution (e.g. overwriting config files), or denial of service by polluting the filesystem.

🛡️ **Solution:**
The fix addresses the vulnerability by strictly canonicalizing the destination paths and comparing them. We extract the file's parent directory, ensure it exists via `std::fs::create_dir_all`, canonicalize it, and verify that the resolved directory strictly starts with the canonical base path of the intended effects or transforms directory. Any path resolving outside of the target base directory will return a `PermissionDenied` I/O error instead of executing the file write.

🚨 **Schweregrad:** HIGH
💡 **Schwachstelle:** Path Traversal / Arbitrary File Write
🎯 **Impact:** Arbitrary files can be overwritten or created anywhere on the user's filesystem if the process has permission, potentially leading to RCE or DoS.
🔧 **Fix:** Introduced rigorous canonicalization checks `canonical_parent.starts_with(&canonical_base)` on `file_path.parent()` prior to issuing writes for both `save_effect_preset` and `save_transform_preset`.
✅ **Verifikation:** Added canonicalization validation ensuring malformed inputs return `Err(PermissionDenied)`. Confirmed `cargo test -p vorce-ui` continues to pass, ensuring normal path behaviors remain unbroken.
