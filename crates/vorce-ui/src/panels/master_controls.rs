use crate::{AppUI, UIAction};
use egui::{Context, Ui};
use vorce_control::ControlTarget;

pub fn render_master_controls(
    app_ui: &mut AppUI,
    ctx: &Context,
    layer_manager: &mut vorce_core::LayerManager,
) {
    if !app_ui.show_master_controls {
        return;
    }

    egui::Window::new(app_ui.i18n.t("panel-master"))
        .default_size([360.0, 300.0])
        .show(ctx, |ui: &mut Ui| {
            render_master_controls_embedded(app_ui, ui, layer_manager);
        });
}

pub fn render_master_controls_embedded(
    app_ui: &mut AppUI,
    ui: &mut Ui,
    layer_manager: &mut vorce_core::LayerManager,
) {
    let is_learning = app_ui.is_midi_learn_mode;
    let last_active_element = app_ui.controller_overlay.last_active_element.clone();
    let last_active_time = app_ui.controller_overlay.last_active_time;

    let composition = &mut layer_manager.composition;

    let old_master_opacity = composition.master_opacity;
    let response = ui.add(
        egui::Slider::new(&mut composition.master_opacity, 0.0..=1.0)
            .text(app_ui.i18n.t("label-master-opacity")),
    );
    AppUI::midi_learn_helper(
        ui,
        &response,
        ControlTarget::MasterOpacity,
        is_learning,
        last_active_element.as_ref(),
        last_active_time,
        &mut app_ui.actions,
    );
    if (composition.master_opacity - old_master_opacity).abs() > 0.001 {
        app_ui.actions.push(UIAction::SetMasterOpacity(composition.master_opacity));
    }

    let old_master_speed = composition.master_speed;
    let response = ui.add(
        egui::Slider::new(&mut composition.master_speed, 0.1..=10.0)
            .text(app_ui.i18n.t("label-master-speed")),
    );
    AppUI::midi_learn_helper(
        ui,
        &response,
        ControlTarget::PlaybackSpeed(None),
        is_learning,
        last_active_element.as_ref(),
        last_active_time,
        &mut app_ui.actions,
    );
    if (composition.master_speed - old_master_speed).abs() > 0.001 {
        app_ui.actions.push(UIAction::SetMasterSpeed(composition.master_speed));
    }
}
