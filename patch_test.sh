sed -i 's/let inputs = self.graph\[self.node_id\].inputs.clone();/let inputs = \&self.graph\[self.node_id\].inputs;/g' crates/vendor/egui_node_editor/src/editor_ui.rs
