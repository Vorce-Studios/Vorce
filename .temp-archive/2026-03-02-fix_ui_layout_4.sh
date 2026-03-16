sed -i 's/use subi_ui as ui_crate;//' crates/subi/src/app/ui_layout.rs
sed -i 's/pub fn show/#[allow(missing_docs)]\npub fn show/' crates/subi/src/app/ui_layout.rs
sed -i 's/\.show(ctx, |ui| {/.show(ctx, |_ui| {/' crates/subi/src/app/ui_layout.rs
