use crate::app::App;
use vorce_media::LoopMode;

const STARTUP_OVERLAY_DURATION_SECS: f32 = 4.0;

fn set_startup_animation_error(
    startup: &mut crate::app::core::app_struct::StartupAnimationState,
    ui_message: impl Into<String>,
    log_message: impl Into<String>,
) {
    let ui_message = ui_message.into();
    if startup.error.as_deref() != Some(ui_message.as_str()) {
        tracing::error!("{}", log_message.into());
    }
    startup.error = Some(ui_message);
}

fn resolve_startup_animation_source(source_path: &str) -> Option<std::path::PathBuf> {
    let trimmed = source_path.trim();
    if trimmed.is_empty() {
        return None;
    }

    let direct_path = std::path::PathBuf::from(trimmed);
    if direct_path.exists() {
        return Some(direct_path);
    }

    if let Ok(relative_to_resources) = direct_path.strip_prefix("resources") {
        if let Some(resolved) =
            vorce_core::runtime_paths::existing_resource_path(relative_to_resources)
        {
            return Some(resolved);
        }
    }

    vorce_core::runtime_paths::existing_resource_path(trimmed)
}

fn load_startup_animation(app: &mut App, source_path: &str) {
    let resolved_path = resolve_startup_animation_source(source_path);
    let startup = &mut app.startup_animation;
    let needs_reload =
        startup.requested_path != source_path || startup.resolved_path != resolved_path;
    if !needs_reload {
        return;
    }

    startup.reset();
    startup.requested_path = source_path.to_string();
    startup.resolved_path = resolved_path.clone();

    let Some(path) = resolved_path else {
        set_startup_animation_error(
            startup,
            "Startup-Quelle fehlt",
            format!("Startup animation source not found: '{}'", source_path),
        );
        return;
    };

    match vorce_media::open_path_with_hw_accel(&path, vorce_media::HwAccelType::None) {
        Ok(mut player) => {
            let _ = player.set_loop_mode(LoopMode::PlayOnce);
            let _ = player.play();
            let _ = player.update(std::time::Duration::ZERO);
            startup.player = Some(player);
            startup.last_update = Some(std::time::Instant::now());
        }
        Err(err) => {
            set_startup_animation_error(
                startup,
                format!("Startup-Video konnte nicht geladen werden: {err}"),
                format!("Failed to load startup animation from {:?}: {}", path, err),
            );
        }
    }
}

fn update_startup_animation_texture(
    ctx: &egui::Context,
    app: &mut App,
) -> Option<(egui::TextureId, egui::Vec2)> {
    let startup = &mut app.startup_animation;
    let now = std::time::Instant::now();
    let dt =
        startup.last_update.map(|last| now.saturating_duration_since(last)).unwrap_or_default();
    startup.last_update = Some(now);

    let player = startup.player.as_mut()?;
    let _ = player.update(dt);
    let frame = player.last_frame()?;
    let vorce_io::format::FrameData::Cpu(data) = &frame.data else {
        set_startup_animation_error(
            startup,
            "Startup-Video lieferte keinen CPU-Frame",
            "Startup animation returned a non-CPU frame.",
        );
        return None;
    };

    let width = frame.format.width as usize;
    let height = frame.format.height as usize;
    let image = egui::ColorImage::from_rgba_unmultiplied([width, height], data.as_slice());

    if let Some(texture) = startup.texture.as_mut() {
        texture.set(
            image,
            egui::TextureOptions {
                magnification: egui::TextureFilter::Linear,
                minification: egui::TextureFilter::Linear,
                wrap_mode: egui::TextureWrapMode::ClampToEdge,
                mipmap_mode: None,
            },
        );
        Some((texture.id(), egui::vec2(width as f32, height as f32)))
    } else {
        let texture = ctx.load_texture(
            "startup_animation_video",
            image,
            egui::TextureOptions {
                magnification: egui::TextureFilter::Linear,
                minification: egui::TextureFilter::Linear,
                wrap_mode: egui::TextureWrapMode::ClampToEdge,
                mipmap_mode: None,
            },
        );
        let id = texture.id();
        startup.texture = Some(texture);
        Some((id, egui::vec2(width as f32, height as f32)))
    }
}

fn fit_size_within(source_size: egui::Vec2, max_size: egui::Vec2) -> egui::Vec2 {
    if source_size.x <= 0.0 || source_size.y <= 0.0 || max_size.x <= 0.0 || max_size.y <= 0.0 {
        return max_size;
    }

    let scale = (max_size.x / source_size.x).min(max_size.y / source_size.y);
    source_size * scale
}

pub fn render_startup_animation_overlay(ctx: &egui::Context, app: &mut App) {
    if !app.ui_state.user_config.startup_animation_enabled
        || app.ui_state.user_config.reduce_motion_enabled
    {
        app.startup_animation.reset();
        return;
    }

    let elapsed = app.start_time.elapsed().as_secs_f32();
    if elapsed >= STARTUP_OVERLAY_DURATION_SECS {
        app.startup_animation.reset();
        return;
    }

    let t = elapsed / STARTUP_OVERLAY_DURATION_SECS;
    let fade_in = (t / 0.2).clamp(0.0, 1.0);
    let fade_out = ((1.0 - t) / 0.25).clamp(0.0, 1.0);
    let alpha = fade_in.min(fade_out);

    let source_path = app.ui_state.user_config.startup_animation_path.trim().to_string();
    load_startup_animation(app, &source_path);

    let source_status =
        app.startup_animation.error.clone().unwrap_or_else(|| "Startup-Video aktiv".to_string());
    let resolved_path = app
        .startup_animation
        .resolved_path
        .as_ref()
        .map(|path| path.display().to_string())
        .filter(|path| !path.is_empty())
        .unwrap_or_else(|| source_path.clone());
    let video_frame = update_startup_animation_texture(ctx, app);

    let backdrop = egui::Color32::from_black_alpha((190.0 * alpha) as u8);
    let frame_fill = egui::Color32::from_rgba_premultiplied(14, 18, 26, (230.0 * alpha) as u8);

    ctx.request_repaint();

    egui::Area::new("startup_animation_overlay".into())
        .order(egui::Order::Foreground)
        .fixed_pos(ctx.content_rect().min)
        .show(ctx, |ui| {
            let rect = ctx.content_rect();
            ui.painter().rect_filled(rect, 0.0, backdrop);

            if let Some((texture_id, source_size)) = &video_frame {
                let video_rect = egui::Rect::from_center_size(
                    rect.center(),
                    fit_size_within(*source_size, rect.size()),
                );
                ui.painter().image(
                    *texture_id,
                    video_rect,
                    egui::Rect::from_min_max(egui::Pos2::ZERO, egui::pos2(1.0, 1.0)),
                    egui::Color32::WHITE.gamma_multiply(alpha),
                );
            }

            ui.scope_builder(egui::UiBuilder::new().max_rect(rect), |ui| {
                ui.with_layout(egui::Layout::bottom_up(egui::Align::Center), |ui| {
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
                                ui.heading("Vorce");
                                ui.label("Startup Animation");
                                ui.add_space(4.0);
                                ui.label(source_status);
                                if !resolved_path.is_empty() {
                                    ui.label(egui::RichText::new(resolved_path).small().weak());
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
