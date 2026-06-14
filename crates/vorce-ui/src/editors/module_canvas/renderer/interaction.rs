use super::super::controller;
use super::super::state::ModuleCanvas;
use egui::Ui;
use vorce_core::module::VorceModule;

pub fn handle_keyboard_shortcuts(
    canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    module: &mut VorceModule,
    module_changed: &mut bool,
    needs_repair: &mut bool,
    response: &egui::Response,
) {
    let ctrl_held = ui.input(|i| i.modifiers.ctrl);

    if response.secondary_clicked()
        && canvas.dragging_part.is_none()
        && canvas.creating_connection.is_none()
    {
        if let Some(pointer_pos) = response.interact_pointer_pos() {
            canvas.context_menu_pos = Some(pointer_pos);
            canvas.context_menu_part = None;
            canvas.context_menu_connection = None;
        }
    }

    if ctrl_held && ui.input(|i| i.key_pressed(egui::Key::A)) {
        canvas.selected_parts = module.parts.iter().map(|p| p.id).collect();
    }

    if !ui.memory(|m| m.focused().is_some())
        && (ui.input(|i| i.key_pressed(egui::Key::Delete))
            || ui.input(|i| i.key_pressed(egui::Key::Backspace)))
        && !canvas.selected_parts.is_empty()
    {
        controller::safe_delete_selection(canvas, module);
        *module_changed = true;
        *needs_repair = true;
    }

    if ui.input(|i| i.key_pressed(egui::Key::Escape)) {
        if canvas.show_search {
            canvas.show_search = false;
        } else {
            canvas.selected_parts.clear();
        }
    }

    if ctrl_held && ui.input(|i| i.key_pressed(egui::Key::F)) {
        canvas.show_search = !canvas.show_search;
        if canvas.show_search {
            canvas.search_filter.clear();
        }
    }

    if ctrl_held && ui.input(|i| i.key_pressed(egui::Key::Z)) && !canvas.undo_stack.is_empty() {
        if let Some(action) = canvas.undo_stack.pop() {
            controller::apply_undo_action(module, &action);
            canvas.redo_stack.push(action);
            *module_changed = true;
            *needs_repair = true;
        }
    }

    if ctrl_held && ui.input(|i| i.key_pressed(egui::Key::Y)) && !canvas.redo_stack.is_empty() {
        if let Some(action) = canvas.redo_stack.pop() {
            controller::apply_redo_action(module, &action);
            canvas.undo_stack.push(action);
            *module_changed = true;
            *needs_repair = true;
        }
    }
}
