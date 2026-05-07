sed -i 's/let inputs = self.graph\[self.node_id\].inputs.clone();/let inputs_len = self.graph\[self.node_id\].inputs.len();\n            for i in 0..inputs_len {\n                let param_id = self.graph\[self.node_id\].inputs\[i\].1;\n                let param_name = self.graph\[self.node_id\].inputs\[i\].0.clone();/g' crates/vendor/egui_node_editor/src/editor_ui.rs
sed -i 's/for (param_name, param_id) in inputs {//g' crates/vendor/egui_node_editor/src/editor_ui.rs

sed -i 's/let outputs = self.graph\[self.node_id\].outputs.clone();/let outputs_len = self.graph\[self.node_id\].outputs.len();\n            for i in 0..outputs_len {\n                let param_id = self.graph\[self.node_id\].outputs\[i\].1;\n                let param_name = self.graph\[self.node_id\].outputs\[i\].0.clone();/g' crates/vendor/egui_node_editor/src/editor_ui.rs
sed -i 's/for (param_name, param_id) in outputs {//g' crates/vendor/egui_node_editor/src/editor_ui.rs
