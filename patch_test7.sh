sed -i 's/let inputs = self.graph\[self.node_id\].inputs.clone();/let inputs_len = self.graph\[self.node_id\].inputs.len();\n            for i in 0..inputs_len {\n                let param_id = self.graph\[self.node_id\].inputs\[i\].1;/g' crates/vendor/egui_node_editor/src/editor_ui.rs
sed -i 's/for (param_name, param_id) in inputs {//g' crates/vendor/egui_node_editor/src/editor_ui.rs
sed -i 's/\&param_name,/\&self.graph\[self.node_id\].inputs\[i\].0,/g' crates/vendor/egui_node_editor/src/editor_ui.rs
