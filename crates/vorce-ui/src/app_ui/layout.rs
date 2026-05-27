use crate::AppUI;

impl AppUI {
    /// Wendet das aktive Layoutprofil auf die Runtime-Sichtbarkeitsflags an.
    pub fn apply_active_layout(&mut self) {
        if let Some(layout) = self.user_config.active_layout() {
            self.show_toolbar = layout.visibility.show_toolbar;
            self.show_left_sidebar = layout.visibility.show_left_sidebar;
            self.show_inspector = layout.visibility.show_inspector;
            self.show_timeline = layout.visibility.show_timeline;
            self.show_media_browser = layout.visibility.show_media_browser;
            self.show_module_canvas = layout.visibility.show_module_canvas;
        }
    }

    /// Synchronisiert die Runtime-Sichtbarkeiten zurück in das aktive Layoutprofil.
    pub fn sync_runtime_to_active_layout(&mut self) {
        if let Some(layout) = self.user_config.active_layout_mut() {
            layout.visibility.show_toolbar = self.show_toolbar;
            layout.visibility.show_left_sidebar = self.show_left_sidebar;
            layout.visibility.show_inspector = self.show_inspector;
            layout.visibility.show_timeline = self.show_timeline;
            layout.visibility.show_media_browser = self.show_media_browser;
            layout.visibility.show_module_canvas = self.show_module_canvas;     
        }
    }

    /// Update responsive styles based on viewport size
    ///
    /// Only updates every 500ms to preserve performance
    pub fn update_responsive_styles(&mut self, ctx: &egui::Context) {
        // Keep style updates frequent enough for live settings changes while avoiding per-frame churn.
        if self.last_style_update.elapsed().as_millis() < 120 {
            return;
        }
        self.last_style_update = std::time::Instant::now();

        let layout = crate::core::responsive::ResponsiveLayout::new(ctx);       

        let mut style = (*ctx.global_style()).clone();
        let base_font_size = self.user_config.theme.font_size.max(10.0);        
        let user_scale = self.user_config.ui_scale.clamp(0.8, 1.4);

        // Scale font sizes
        let scaled_size = layout.scale_font(base_font_size) * user_scale;       

        style.text_styles.insert(egui::TextStyle::Body, egui::FontId::proportional(scaled_size));
        style.text_styles.insert(egui::TextStyle::Button, egui::FontId::proportional(scaled_size));
        style
            .text_styles
            .insert(egui::TextStyle::Heading, egui::FontId::proportional(scaled_size * 1.4));
        style
            .text_styles
            .insert(egui::TextStyle::Small, egui::FontId::proportional(scaled_size * 0.85));

        // Scale spacing
        let spacing_scale = (layout.scale_font(1.0) / 14.0) * user_scale; // Normalize scale factor
        style.spacing.item_spacing = egui::vec2(8.0, 6.0) * spacing_scale;      
        style.spacing.button_padding = egui::vec2(8.0, 4.0) * spacing_scale;    

        ctx.set_global_style(style);
    }
}
