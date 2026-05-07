sed -i 's/for (param_name, param_id) in inputs {/for (param_name, param_id) in inputs {\n                let param_id = *param_id;/g' crates/vendor/egui_node_editor/src/editor_ui.rs
