with open("crates/vorce-ui/src/editors/module_canvas/types.rs", "r") as f:
    content = f.read()

content = content.replace("MoveSelection {\n        #[allow(clippy::type_complexity)]\n        part_positions:", "MoveSelection {\n        part_positions:")

content = content.replace("pub enum CanvasAction {", "#[allow(clippy::type_complexity)]\npub enum CanvasAction {")

with open("crates/vorce-ui/src/editors/module_canvas/types.rs", "w") as f:
    f.write(content)
