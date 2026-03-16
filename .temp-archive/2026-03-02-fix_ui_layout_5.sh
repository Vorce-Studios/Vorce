sed -i 's/\.show(ctx, |_ui| {/.show(ctx, |ui| {/' crates/subi/src/app/ui_layout.rs
sed -i 's/use crate::ui;//' crates/subi/src/app/ui_layout.rs
