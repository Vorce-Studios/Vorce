        Stroke::NONE,
    ));
}

/// Standardized informational label, used as an explicit fallback when no active preview is available.
pub fn render_info_label(ui: &mut Ui, text: &str) {
    ui.label(egui::RichText::new(text).weak().italics());
}

/// Standardized missing preview banner.
pub fn render_missing_preview_banner(ui: &mut Ui) {
    ui.group(|ui| {
        render_info_label(ui, "No preview available yet.");
    });
}
