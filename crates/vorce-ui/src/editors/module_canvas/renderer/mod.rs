pub mod pipeline;
pub mod side_effects;
pub mod interaction;

use crate::i18n::LocaleManager;
use crate::UIAction;
use egui::Ui;
use vorce_core::module::ModuleManager;

use super::state::ModuleCanvas;
use super::ModuleCanvasRenderOptions;

pub fn show(
    canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    manager: &mut ModuleManager,
    locale: &LocaleManager,
    actions: &mut Vec<UIAction>,
    options: ModuleCanvasRenderOptions,
) {
    side_effects::handle_playback_and_learn(canvas, ui, manager);

    if let Some(module_id) = canvas.active_module_id {
        pipeline::render_canvas(canvas, ui, manager, module_id, locale, actions, options);
    } else {
        ui.centered_and_justified(|ui| {
            ui.vertical_centered(|ui| {
                ui.add_space(50.0);
                ui.heading("\u{1F527} Module Canvas");
                ui.add_space(10.0);
                ui.label("Click '\u{2795} New Module' to create a module.");
                ui.label("Please select an existing module from the toolbar above.");
            });
        });
    }
}
