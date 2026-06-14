pub mod buttons;
pub mod hold_action;
pub mod info_panels;
pub mod lists;
pub mod sliders;

pub use buttons::*;
pub use hold_action::*;
pub use info_panels::*;
pub use lists::*;
pub use sliders::*;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::widgets::icons::AppIcon;
    use egui::Context;
    use egui::Ui;

    fn test_ui(func: impl FnMut(&mut Ui)) {
        let ctx = Context::default();
        let mut func = func;
        #[allow(deprecated)]
        let _ = ctx.run(Default::default(), |ctx| {
            #[allow(deprecated)]
            egui::CentralPanel::default().show(ctx, |ui| {
                func(ui);
            });
        });
    }

    #[test]
    fn test_render_header() {
        test_ui(|ui| {
            render_header(ui, "Test Header");
        });
    }

    #[test]
    fn test_render_info_label() {
        test_ui(|ui| {
            render_info_label(ui, "Test Label");
        });
    }

    #[test]
    fn test_render_info_label_with_size() {
        test_ui(|ui| {
            render_info_label_with_size(ui, "Test Label", 12.0);
        });
    }

    #[test]
    fn test_render_missing_preview_banner() {
        test_ui(|ui| {
            render_missing_preview_banner(ui);
        });
    }

    #[test]
    fn test_cyber_list_item() {
        test_ui(|ui| {
            let id = ui.id().with("test_list_item");
            cyber_list_item(ui, id, false, false, |ui| {
                ui.label("List item content");
            });
            cyber_list_item(ui, id.with("2"), true, false, |ui| {
                ui.label("List item content");
            });
            cyber_list_item(ui, id.with("3"), false, true, |ui| {
                ui.label("List item content");
            });
        });
    }

    #[test]
    fn test_colored_progress_bar() {
        test_ui(|ui| {
            colored_progress_bar(ui, 0.5);
        });
    }

    #[test]
    fn test_styled_slider() {
        test_ui(|ui| {
            let mut value = 0.5;
            styled_slider(ui, &mut value, 0.0..=1.0, 0.0);
        });
    }

    #[test]
    fn test_styled_slider_log() {
        test_ui(|ui| {
            let mut value = 10.0;
            styled_slider_log(ui, &mut value, 1.0..=100.0, 10.0);
        });
    }

    #[test]
    fn test_styled_drag_value() {
        test_ui(|ui| {
            let mut value = 0.5;
            styled_drag_value(ui, &mut value, 0.01, 0.0..=1.0, 0.5, "", "");
        });
    }

    #[test]
    fn test_styled_button() {
        test_ui(|ui| {
            styled_button(ui, "Test Button", false);
        });
    }

    #[test]
    fn test_icon_button() {
        test_ui(|ui| {
            icon_button(
                ui,
                "Test Icon",
                ui.visuals().text_color(),
                ui.visuals().text_color(),
                false,
            );
        });
    }

    #[test]
    fn test_icon_button_simple() {
        test_ui(|ui| {
            icon_button_simple(ui, None, AppIcon::Add, 16.0, "Test Icon");
        });
    }

    #[test]
    fn test_icon_button_compact() {
        test_ui(|ui| {
            icon_button_compact(ui, None, AppIcon::Add, "Test Icon");
        });
    }

    #[test]
    fn test_check_hold_state() {
        test_ui(|ui| {
            let id = ui.id().with("test_hold");
            let (triggered, progress) = check_hold_state(ui, id, false);
            assert!(!triggered);
            assert_eq!(progress, 0.0);

            // Test interaction starting
            let (triggered, progress) = check_hold_state(ui, id, true);
            assert!(!triggered);
            assert!(progress >= 0.0);
        });
    }
}
