def replace_in_file(filepath, old_str, new_str):
    with open(filepath, 'r') as f:
        text = f.read()
    text = text.replace(old_str, new_str)
    with open(filepath, 'w') as f:
        f.write(text)

replace_in_file('crates/mapmap-ui/src/editors/mesh_editor/interaction.rs',
'''pub trait MeshEditorInteraction {
    fn handle_interaction(&mut self, input: InteractionInput) -> Option<MeshEditorAction>;
}

impl MeshEditorInteraction for MeshEditor {
''',
'''impl MeshEditor {
''')
replace_in_file('crates/mapmap-ui/src/editors/mesh_editor/interaction.rs', 'fn handle_interaction', 'pub fn handle_interaction')

replace_in_file('crates/mapmap-ui/src/editors/mesh_editor/ui.rs',
'''pub trait MeshEditorUi {
    fn ui(&mut self, ui: &mut Ui) -> Option<MeshEditorAction>;
    fn draw_grid(&self, painter: &egui::Painter, rect: Rect);
}

impl MeshEditorUi for MeshEditor {
''',
'''impl MeshEditor {
''')
replace_in_file('crates/mapmap-ui/src/editors/mesh_editor/ui.rs', 'fn ui', 'pub fn ui')
replace_in_file('crates/mapmap-ui/src/editors/mesh_editor/ui.rs', 'fn draw_grid', 'pub(crate) fn draw_grid')
