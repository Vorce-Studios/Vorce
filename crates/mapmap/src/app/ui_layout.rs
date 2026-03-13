use crate::app::App;
use mapmap_ui as ui;

const STARTUP_OVERLAY_DURATION_SECS: f32 = 4.0;

fn render_startup_animation_overlay(ctx: &egui::Context, app: &App) {
    if !app.ui_state.user_config.startup_animation_enabled {
        return;
    }
    if app.ui_state.user_config.reduce_motion_enabled {
        return;
    }

    let elapsed = app.start_time.elapsed().as_secs_f32();
    if elapsed >= STARTUP_OVERLAY_DURATION_SECS {
        return;
    }

    let t = elapsed / STARTUP_OVERLAY_DURATION_SECS;
    let fade_in = (t / 0.2).clamp(0.0, 1.0);
    let fade_out = ((1.0 - t) / 0.25).clamp(0.0, 1.0);
    let alpha = fade_in.min(fade_out);

    let source_path = app.ui_state.user_config.startup_animation_path.trim();
    let source_exists = !source_path.is_empty() && std::path::Path::new(source_path).exists();
    let source_status = if source_exists {
        "Startup-Quelle gefunden"
    } else {
        "Startup-Quelle fehlt"
    };

    let backdrop = egui::Color32::from_black_alpha((190.0 * alpha) as u8);
    let frame_fill = egui::Color32::from_rgba_premultiplied(14, 18, 26, (230.0 * alpha) as u8);

    egui::Area::new("startup_animation_overlay".into())
        .order(egui::Order::Foreground)
        .fixed_pos(ctx.content_rect().min)
        .show(ctx, |ui| {
            let rect = ctx.content_rect();
            ui.painter().rect_filled(rect, 0.0, backdrop);

            ui.scope_builder(egui::UiBuilder::new().max_rect(rect), |ui| {
                ui.centered_and_justified(|ui| {
                    egui::Frame::default()
                        .fill(frame_fill)
                        .corner_radius(egui::CornerRadius::same(12))
                        .inner_margin(egui::Margin::symmetric(24, 18))
                        .stroke(egui::Stroke::new(
                            1.0,
                            egui::Color32::from_rgba_premultiplied(
                                111,
                                188,
                                255,
                                (180.0 * alpha) as u8,
                            ),
                        ))
                        .show(ui, |ui| {
                            ui.vertical_centered(|ui| {
                                ui.heading("MapFlow");
                                ui.label("Startup Animation");
                                ui.add_space(4.0);
                                ui.label(source_status);
                                if !source_path.is_empty() {
                                    ui.label(egui::RichText::new(source_path).small().weak());
                                }
                                if app.ui_state.user_config.silent_startup_enabled {
                                    ui.label(egui::RichText::new("Silent Startup aktiv").small());
                                }
                                ui.add_space(8.0);
                                ui.add(
                                    egui::ProgressBar::new(t)
                                        .desired_width(280.0)
                                        .show_percentage(),
                                );
                            });
                        });
                });
            });
        });
}

/// Main UI orchestration function.
/// Renders the entire application UI layout using egui.
pub fn show(ctx: &egui::Context, app: &mut App) {
    app.ui_state.update_responsive_styles(ctx);

    let viewport_rect = ctx.content_rect();
    let viewport_width = viewport_rect.width();
    let viewport_height = viewport_rect.height();
    let compact_height = viewport_height < 760.0;
    
    let active_layout = app.ui_state.user_config.active_layout().cloned();
    let layout_sizes = active_layout
        .as_ref()
        .map(|layout| layout.panel_sizes)
        .unwrap_or_default();
    let layout_locked = active_layout
        .as_ref()
        .map(|layout| layout.lock_layout)
        .unwrap_or(false);

    let sidebar_default = if layout_sizes.left_sidebar_width > 0.0 {
        layout_sizes.left_sidebar_width
    } else {
        (viewport_width * 0.2).clamp(240.0, 420.0)
    }.clamp(220.0, (viewport_width * 0.45).max(340.0));

    let inspector_default = if layout_sizes.inspector_width > 0.0 {
        layout_sizes.inspector_width
    } else {
        (viewport_width * 0.24).clamp(260.0, 520.0)
    }.clamp(260.0, (viewport_width * 0.5).max(420.0));

    let timeline_default_height = if layout_sizes.timeline_height > 0.0 {
        layout_sizes.timeline_height
    } else {
        if compact_height {
            (viewport_height * 0.22).clamp(90.0, 150.0)
        } else {
            (viewport_height * 0.26).clamp(140.0, 300.0)
        }
    }.clamp(100.0, 500.0);

    // 1. Global Menu Bar (Top-most)
    let menu_actions = ui::view::menu_bar::show(ctx, &mut app.ui_state);
    for action in menu_actions {
        app.ui_state.actions.push(action);
    }

    // 2. Toolbar (Separate Panel below Menu)
    if app.ui_state.show_toolbar {
        egui::TopBottomPanel::top("toolbar_panel")
            .resizable(!layout_locked)
            .min_height(if compact_height { 36.0 } else { 44.0 })
            .frame(
                egui::Frame::default()
                    .fill(ctx.style().visuals.window_fill())
                    .inner_margin(egui::Margin::symmetric(16, 4))
                    .stroke(egui::Stroke::new(
                        1.0,
                        ctx.style().visuals.widgets.noninteractive.bg_stroke.color,
                    )),
            )
            .show(ctx, |ui_obj| {
                ui_obj.horizontal_wrapped(|ui_obj| {
                    if ui_obj
                        .small_button(if app.ui_state.show_left_sidebar {
                            "◀ Sidebar"
                        } else {
                            "▶ Sidebar"
                        })
                        .clicked()
                    {
                        app.ui_state.show_left_sidebar = !app.ui_state.show_left_sidebar;
                        app.ui_state.user_config.show_left_sidebar = app.ui_state.show_left_sidebar;
                        let _ = app.ui_state.user_config.save();
                    }
                    if ui_obj
                        .small_button(if app.ui_state.show_inspector {
                            "Inspector ▶"
                        } else {
                            "Inspector ◀"
                        })
                        .clicked()
                    {
                        app.ui_state.show_inspector = !app.ui_state.show_inspector;
                        app.ui_state.user_config.show_inspector = app.ui_state.show_inspector;
                        let _ = app.ui_state.user_config.save();
                    }
                    if ui_obj
                        .small_button(if app.ui_state.show_timeline {
                            "▼ Timeline"
                        } else {
                            "▲ Timeline"
                        })
                        .clicked()
                    {
                        app.ui_state.show_timeline = !app.ui_state.show_timeline;
                        app.ui_state.user_config.show_timeline = app.ui_state.show_timeline;
                        let _ = app.ui_state.user_config.save();
                    }
                    ui_obj.separator();
                    ui::view::menu_bar::toolbar::show(ui_obj, &mut app.ui_state);
                });
            });
    }

    // 3. Left Panel: Sidebar (Collapsible & Resizable)
    if app.ui_state.show_left_sidebar {
        egui::SidePanel::left("left_sidebar_panel")
            .resizable(!layout_locked)
            .default_width(sidebar_default)
            .min_width(if compact_height { 180.0 } else { 220.0 })
            .max_width((viewport_width * 0.45).max(340.0))
            .show(ctx, |ui_obj| {
                egui::TopBottomPanel::top("left_sidebar_preview")
                    .resizable(true)
                    .default_height(if compact_height { 120.0 } else { 180.0 })
                    .min_height(110.0)
                    .show_inside(ui_obj, |ui| {
                        ui.vertical_centered(|ui| {
                            ui.heading(app.ui_state.i18n.t("preview"));
                        });
                        app.media_manager_ui.render_preview(ui, &app.state.media_state);
                    });

                egui::CentralPanel::default().show_inside(ui_obj, |ui| {
                    ui.vertical_centered(|ui| {
                        ui.heading(app.ui_state.i18n.t("media-browser"));
                    });
                    app.media_manager_ui.render(ui, &mut app.ui_state.actions);
                });
            });
    }

    // 4. Right Panel: Inspector (Collapsible & Resizable)
    if app.ui_state.show_inspector {
        egui::SidePanel::right("right_inspector_panel")
            .resizable(!layout_locked)
            .default_width(inspector_default)
            .min_width(if compact_height { 220.0 } else { 260.0 })
            .max_width((viewport_width * 0.5).max(420.0))
            .show(ctx, |ui_obj| {
                ui_obj.vertical_centered(|ui| {
                    ui.heading(app.ui_state.i18n.t("inspector"));
                });

                ui_obj.separator();

                egui::ScrollArea::vertical().show(ui_obj, |ui| {
                    app.ui_state.inspector.ui(
                        ui,
                        &mut app.state.module_manager,
                        &app.ui_state.i18n,
                        &app.state.mapping_manager,
                    );

                    // Legacy panels (can be toggled separately or integrated)
                    if app.ui_state.show_transforms {
                        app.ui_state.transform_panel.render(ctx, &app.ui_state.i18n);
                    }

                    // Effect chain integrated into inspector side
                    egui::TopBottomPanel::bottom("inspector_effect_chain_split")
                        .resizable(true)
                        .default_height(240.0)
                        .min_height(120.0)
                        .show_inside(ui, |_ui| {
                            app.ui_state.effect_chain_panel.ui(
                                ctx,
                                &app.ui_state.i18n,
                                app.ui_state.icon_manager.as_ref(),
                                Some(&mut app.recent_effect_configs),
                            );
                        });
                });
            });
    }

    // 5. Bottom Panel: Timeline (Resizable)
    if app.ui_state.show_timeline {
        egui::TopBottomPanel::bottom("bottom_panel")
            .resizable(!layout_locked)
            .default_height(timeline_default_height)
            .min_height(if compact_height { 80.0 } else { 100.0 })
            .show(ctx, |ui_obj| {
                ui_obj.horizontal(|ui| {
                    ui.heading(app.ui_state.i18n.t("timeline"));
                    if ui
                        .small_button("✕")
                        .on_hover_text("Timeline ausblenden")
                        .clicked()
                    {
                        app.ui_state.show_timeline = false;
                        app.ui_state.user_config.show_timeline = false;
                        let _ = app.ui_state.user_config.save();
                    }
                });

                let state = &mut app.state;
                let animator = std::sync::Arc::make_mut(&mut state.effect_animator);
                let mut modules: Vec<ui::TimelineModule> = state
                    .module_manager
                    .modules()
                    .iter()
                    .map(|m| ui::TimelineModule {
                        id: m.id,
                        // Optimization: Borrow name string to prevent allocation overhead in UI hot loop.
                        name: &m.name,
                    })
                    .collect();
                modules.sort_by_key(|m| m.id);

                if let Some(action) = app.ui_state.timeline_panel.ui(ui_obj, animator, &modules) {
                    app.ui_state.actions.push(action);
                }
            });
    }

    // 6. Central Panel: Module Canvas (Remaining Space)
    egui::CentralPanel::default().show(ctx, |ui_obj| {
        app.ui_state.module_canvas.ui(
            ui_obj,
            &mut app.state.module_manager,
            &mut app.state.mapping_manager,
            &app.ui_state.i18n,
            app.ui_state.icon_manager.as_ref(),
        );
    });

    // 7. Overlays (Floating)
    render_startup_animation_overlay(ctx, app);
}
