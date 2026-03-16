sed -i 's/\.show(ctx, |_ui| {/.show(ctx, |ui| {/' crates/subi/src/app/ui_layout.rs
sed -i '0,/\.show(ctx, |ui| {/s//\.show(ctx, |_ui| {/' crates/subi/src/app/ui_layout.rs
