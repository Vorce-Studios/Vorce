use super::SettingsContext;
use egui::{Context, RichText};

pub fn show(_ctx: &Context, ui: &mut egui::Ui, context: &mut SettingsContext) {
    ui.heading(RichText::new("Node-Animationen").color(ui.visuals().strong_text_color()));
    ui.add_space(4.0);
    let mut node_anim_changed = false;
    node_anim_changed |= ui
        .checkbox(
            &mut context.ui_state.user_config.node_animations_enabled,
            "Node-Animationen aktivieren",
        )
        .changed();
    node_anim_changed |= ui
        .checkbox(
            &mut context.ui_state.user_config.short_circuit_animation_enabled,
            "Kurzschluss-Effekt bei falschen Verbindungen",
        )
        .changed();
    node_anim_changed |= ui
        .checkbox(
            &mut context.ui_state.user_config.startup_animation_enabled,
            "App-Start-Animation aktivieren",
        )
        .changed();
    ui.horizontal(|ui| {
        ui.label("Startup-Video:");
        node_anim_changed |= ui
            .text_edit_singleline(&mut context.ui_state.user_config.startup_animation_path)
            .changed();
        if ui.button("Standard").clicked() {
            context.ui_state.user_config.startup_animation_path =
                "resources/app_videos/Vorce-Mechanical_Cube_Logo_Splash_Animation.webm".to_string();
            node_anim_changed = true;
        }
    });
    node_anim_changed |= ui
        .checkbox(
            &mut context.ui_state.user_config.reduce_motion_enabled,
            "Reduce Motion (Bewegungen reduzieren)",
        )
        .changed();
    node_anim_changed |= ui
        .checkbox(
            &mut context.ui_state.user_config.silent_startup_enabled,
            "Silent Startup (kein Startsound)",
        )
        .changed();
    ui.horizontal(|ui| {
        ui.label("Animationsprofil:");
        use vorce_ui::core::config::AnimationProfile;
        egui::ComboBox::from_id_salt("ui_animation_profile")
            .selected_text(context.ui_state.user_config.animation_profile.to_string())
            .show_ui(ui, |ui| {
                for profile in
                    [AnimationProfile::Off, AnimationProfile::Subtle, AnimationProfile::Cinematic]
                {
                    if ui
                        .selectable_label(
                            context.ui_state.user_config.animation_profile == profile,
                            profile.to_string(),
                        )
                        .clicked()
                    {
                        context.ui_state.user_config.animation_profile = profile;
                        let _ = context.ui_state.user_config.save();
                    }
                }
            });
    });
    if node_anim_changed {
        let _ = context.ui_state.user_config.save();
    }

    ui.add_space(10.0);
    ui.separator();

    ui.heading(RichText::new("Layout Profiles").color(ui.visuals().strong_text_color()));
    ui.add_space(4.0);

    let active_layout_before = context.ui_state.user_config.active_layout_id.clone();
    let layout_items: Vec<(String, String)> = context
        .ui_state
        .user_config
        .layouts
        .iter()
        .map(|l| (l.id.clone(), l.name.clone()))
        .collect();

    let mut selected_layout_id = active_layout_before.clone();
    ui.horizontal(|ui| {
        ui.label("Aktives Layout:");
        egui::ComboBox::from_id_salt("layout_profile_selector")
            .selected_text(
                layout_items
                    .iter()
                    .find(|(id, _)| id == &selected_layout_id)
                    .map(|(_, name)| name.clone())
                    .unwrap_or_else(|| selected_layout_id.clone()),
            )
            .show_ui(ui, |ui| {
                for (id, name) in &layout_items {
                    if ui.selectable_label(selected_layout_id == *id, name).clicked() {
                        selected_layout_id = id.clone();
                    }
                }
            });

        if ui.button("Duplizieren").clicked() {
            if let Some(active) = context.ui_state.user_config.active_layout().cloned() {
                let mut clone = active;
                let next = context.ui_state.user_config.layouts.len() + 1;
                clone.id = format!("layout-{}", next);
                clone.name = format!("{} {}", clone.name, next);
                context.ui_state.user_config.add_layout_profile(clone);
                let _ = context.ui_state.user_config.save();
            }
        }

        if ui.button("Zurücksetzen").clicked() {
            if let Some(layout) = context.ui_state.user_config.active_layout_mut() {
                let id = layout.id.clone();
                let name = layout.name.clone();
                *layout = vorce_ui::core::config::LayoutProfile::default_profile();
                layout.id = id;
                layout.name = name;
            }
            context.ui_state.apply_active_layout();
            let _ = context.ui_state.user_config.save();
        }
    });

    if selected_layout_id != active_layout_before
        && context.ui_state.user_config.set_active_layout(&selected_layout_id)
    {
        context.ui_state.apply_active_layout();
        let _ = context.ui_state.user_config.save();
    }

    ui.add_space(4.0);
    ui.label("Panel-Sichtbarkeit");
    let mut changed_visibility = false;
    changed_visibility |= ui.checkbox(&mut context.ui_state.show_toolbar, "Toolbar").changed();
    changed_visibility |=
        ui.checkbox(&mut context.ui_state.show_left_sidebar, "Left Sidebar").changed();
    changed_visibility |= ui.checkbox(&mut context.ui_state.show_inspector, "Inspector").changed();
    changed_visibility |= ui.checkbox(&mut context.ui_state.show_timeline, "Timeline").changed();
    changed_visibility |=
        ui.checkbox(&mut context.ui_state.show_media_browser, "Media Browser").changed();
    changed_visibility |=
        ui.checkbox(&mut context.ui_state.show_module_canvas, "Module Canvas").changed();

    if changed_visibility {
        context.ui_state.sync_runtime_to_active_layout();
        let _ = context.ui_state.user_config.save();
    }

    if let Some(layout) = context.ui_state.user_config.active_layout_mut() {
        ui.add_space(4.0);
        ui.label("Panel-Größen");
        let mut changed_sizes = false;
        changed_sizes |= ui
            .add(
                egui::Slider::new(&mut layout.panel_sizes.left_sidebar_width, 220.0..=640.0)
                    .text("Sidebar Breite"),
            )
            .changed();
        changed_sizes |= ui
            .add(
                egui::Slider::new(&mut layout.panel_sizes.inspector_width, 260.0..=760.0)
                    .text("Inspector Breite"),
            )
            .changed();
        changed_sizes |= ui
            .add(
                egui::Slider::new(&mut layout.panel_sizes.timeline_height, 100.0..=500.0)
                    .text("Timeline Höhe"),
            )
            .changed();
        changed_sizes |= ui.checkbox(&mut layout.lock_layout, "Layout sperren").changed();

        if changed_sizes {
            let _ = context.ui_state.user_config.save();
        }
    }

    ui.add_space(10.0);
    ui.separator();
}
