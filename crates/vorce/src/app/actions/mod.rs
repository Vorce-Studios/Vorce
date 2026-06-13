pub mod global;
pub mod hue;
pub mod layer;
pub mod mapping;
pub mod mcp;
pub mod media;
pub mod midi;
pub mod ndi;
pub mod node;
pub mod output;
pub mod playback;
pub mod project;
pub mod settings;
pub use mcp::*;

use crate::app::core::app_struct::App;
use anyhow::Result;
use vorce_ui::UIAction;

/// Handle global UI actions
pub fn handle_ui_actions(app: &mut App) -> Result<bool> {
    let actions = app.ui_state.take_actions();
    let mut needs_sync = false;
    let visibility_before = (
        app.ui_state.show_toolbar,
        app.ui_state.show_left_sidebar,
        app.ui_state.show_inspector,
        app.ui_state.show_timeline,
        app.ui_state.show_media_browser,
        app.ui_state.show_module_canvas,
    );

    for action in actions {
        match action {
            // Node Editor
            UIAction::NodeAction(node_action) => {
                app.ui_state.node_editor_panel.handle_action(node_action.clone());
                if let Err(e) = node::handle(app, node_action) {
                    eprintln!("Error handling node action: {}", e);
                }
            }

            // Settings
            UIAction::SelectAudioDevice(..) => {
                settings::handle_select_audio_device(app, action, &mut needs_sync)
            }
            UIAction::UpdateAudioConfig(..) => {
                settings::handle_update_audio_config(app, action, &mut needs_sync)
            }
            UIAction::SetTargetFps(..) => {
                settings::handle_set_target_fps(app, action, &mut needs_sync)
            }
            UIAction::SetVsyncMode(..) => {
                settings::handle_set_vsync_mode(app, action, &mut needs_sync)
            }
            UIAction::SetPreferredGpu(..) => {
                settings::handle_set_preferred_gpu(app, action, &mut needs_sync)
            }
            UIAction::SetLanguage(..) => {
                settings::handle_set_language(app, action, &mut needs_sync)
            }
            UIAction::SetMeterStyle(..) => {
                settings::handle_set_meter_style(app, action, &mut needs_sync)
            }

            // Global/Window
            UIAction::SetGlobalFullscreen(..) => {
                global::handle_set_global_fullscreen(app, action, &mut needs_sync)
            }
            UIAction::OpenShaderGraph(..) => {
                global::handle_open_shader_graph(app, action, &mut needs_sync)
            }
            UIAction::ToggleModuleCanvas => {
                global::handle_toggle_module_canvas(app, action, &mut needs_sync)
            }
            UIAction::ToggleFullscreen => {
                global::handle_toggle_fullscreen(app, action, &mut needs_sync)
            }
            UIAction::ToggleControllerOverlay => {
                global::handle_toggle_controller_overlay(app, action, &mut needs_sync)
            }
            UIAction::ResetLayout => global::handle_reset_layout(app, action, &mut needs_sync),
            UIAction::ToggleMediaManager => {
                global::handle_toggle_media_manager(app, action, &mut needs_sync)
            }
            UIAction::Exit => global::handle_exit(app, action, &mut needs_sync),
            UIAction::OpenSettings => global::handle_open_settings(app, action, &mut needs_sync),
            UIAction::OpenAbout => global::handle_open_about(app, action, &mut needs_sync),
            UIAction::OpenLicense => global::handle_open_license(app, action, &mut needs_sync),
            UIAction::ToggleMidiLearn => {
                global::handle_toggle_midi_learn(app, action, &mut needs_sync)
            }
            UIAction::ToggleAudioPanel => {
                global::handle_toggle_audio_panel(app, action, &mut needs_sync)
            }

            // Playback
            UIAction::Play => playback::handle_play(app, action, &mut needs_sync),
            UIAction::Pause => playback::handle_pause(app, action, &mut needs_sync),
            UIAction::Stop => playback::handle_stop(app, action, &mut needs_sync),
            UIAction::SetSpeed(..) => playback::handle_set_speed(app, action, &mut needs_sync),
            UIAction::SetLoopMode(..) => {
                playback::handle_set_loop_mode(app, action, &mut needs_sync)
            }
            UIAction::TimelineAction(..) => {
                playback::handle_timeline_action(app, action, &mut needs_sync)
            }

            // Project
            UIAction::Export => project::handle_export(app, action, &mut needs_sync),
            UIAction::SaveProjectAs => {
                project::handle_save_project_as(app, action, &mut needs_sync)
            }
            UIAction::SaveProject(..) => project::handle_save_project(app, action, &mut needs_sync),
            UIAction::LoadProject(..) => project::handle_load_project(app, action, &mut needs_sync),
            UIAction::LoadRecentProject(..) => {
                project::handle_load_recent_project(app, action, &mut needs_sync)
            }
            UIAction::SetCompositionName(..) => {
                project::handle_set_composition_name(app, action, &mut needs_sync)
            }
            UIAction::SetMasterOpacity(..) => {
                project::handle_set_master_opacity(app, action, &mut needs_sync)
            }
            UIAction::SetMasterSpeed(..) => {
                project::handle_set_master_speed(app, action, &mut needs_sync)
            }
            UIAction::SetMasterBlackout(..) => {
                project::handle_set_master_blackout(app, action, &mut needs_sync)
            }

            // Media
            UIAction::PickMediaFile(..) => {
                media::handle_pick_media_file(app, action, &mut needs_sync)
            }
            UIAction::SetMediaFile(..) => {
                media::handle_set_media_file(app, action, &mut needs_sync)
            }
            UIAction::MediaCommand(..) => media::handle_media_command(app, action, &mut needs_sync),
            UIAction::ManualTrigger(..) => {
                media::handle_manual_trigger(app, action, &mut needs_sync)
            }

            // NDI
            UIAction::GetNdiSenderStatus(..) => {
                ndi::handle_get_ndi_sender_status(app, action, &mut needs_sync)
            }
            #[cfg(feature = "ndi")]
            UIAction::ConnectNdiSource { .. } => {
                ndi::handle_connect_ndi_source(app, action, &mut needs_sync)
            }
            #[cfg(feature = "ndi")]
            UIAction::DisconnectNdiSource { .. } => {
                ndi::handle_disconnect_ndi_source(app, action, &mut needs_sync)
            }

            // Mapping
            UIAction::AddPaint => mapping::handle_add_paint(app, action, &mut needs_sync),
            UIAction::RemovePaint(..) => mapping::handle_remove_paint(app, action, &mut needs_sync),
            UIAction::AddMapping => mapping::handle_add_mapping(app, action, &mut needs_sync),
            UIAction::RemoveMapping(..) => {
                mapping::handle_remove_mapping(app, action, &mut needs_sync)
            }
            UIAction::SelectMapping(..) => {
                mapping::handle_select_mapping(app, action, &mut needs_sync)
            }
            UIAction::ToggleMappingVisibility(..) => {
                mapping::handle_toggle_mapping_visibility(app, action, &mut needs_sync)
            }
            UIAction::UpdateMappingMesh(..) => {
                mapping::handle_update_mapping_mesh(app, action, &mut needs_sync)
            }

            // Output
            UIAction::AddOutput(..) => output::handle_add_output(app, action, &mut needs_sync),
            UIAction::RemoveOutput(..) => {
                output::handle_remove_output(app, action, &mut needs_sync)
            }
            UIAction::ConfigureOutput(..) => {
                output::handle_configure_output(app, action, &mut needs_sync)
            }

            // MIDI
            UIAction::SetMidiAssignment(..) => {
                midi::handle_set_midi_assignment(app, action, &mut needs_sync)
            }

            // Hue
            UIAction::RegisterHue => hue::handle_register_hue(app, action, &mut needs_sync),
            UIAction::FetchHueGroups => hue::handle_fetch_hue_groups(app, action, &mut needs_sync),
            UIAction::ConnectHue => hue::handle_connect_hue(app, action, &mut needs_sync),
            UIAction::DisconnectHue => hue::handle_disconnect_hue(app, action, &mut needs_sync),
            UIAction::DiscoverHueBridges => {
                hue::handle_discover_hue_bridges(app, action, &mut needs_sync)
            }

            // Layer
            UIAction::SetLayerOpacity(..) => {
                layer::handle_set_layer_opacity(app, action, &mut needs_sync)
            }
            UIAction::SetLayerBlendMode(..) => {
                layer::handle_set_layer_blend_mode(app, action, &mut needs_sync)
            }
            UIAction::SetLayerVisibility(..) => {
                layer::handle_set_layer_visibility(app, action, &mut needs_sync)
            }
            UIAction::AddLayer => layer::handle_add_layer(app, action, &mut needs_sync),
            UIAction::CreateGroup => layer::handle_create_group(app, action, &mut needs_sync),
            UIAction::ReparentLayer(..) => {
                layer::handle_reparent_layer(app, action, &mut needs_sync)
            }
            UIAction::SwapLayers(..) => layer::handle_swap_layers(app, action, &mut needs_sync),
            UIAction::ToggleGroupCollapsed(..) => {
                layer::handle_toggle_group_collapsed(app, action, &mut needs_sync)
            }
            UIAction::RemoveLayer(..) => layer::handle_remove_layer(app, action, &mut needs_sync),
            UIAction::DuplicateLayer(..) => {
                layer::handle_duplicate_layer(app, action, &mut needs_sync)
            }
            UIAction::RenameLayer(..) => layer::handle_rename_layer(app, action, &mut needs_sync),
            UIAction::ToggleLayerSolo(..) => {
                layer::handle_toggle_layer_solo(app, action, &mut needs_sync)
            }
            UIAction::ToggleLayerBypass(..) => {
                layer::handle_toggle_layer_bypass(app, action, &mut needs_sync)
            }
            UIAction::EjectAllLayers => {
                layer::handle_eject_all_layers(app, action, &mut needs_sync)
            }
            UIAction::SetLayerTransform(..) => {
                layer::handle_set_layer_transform(app, action, &mut needs_sync)
            }
            UIAction::ApplyResizeMode(..) => {
                layer::handle_apply_resize_mode(app, action, &mut needs_sync)
            }

            _ => {
                // Other actions
            }
        }
    }

    // Handle MCP Actions
    crate::app::actions::mcp::handle_mcp_actions(app);

    let visibility_after = (
        app.ui_state.show_toolbar,
        app.ui_state.show_left_sidebar,
        app.ui_state.show_inspector,
        app.ui_state.show_timeline,
        app.ui_state.show_media_browser,
        app.ui_state.show_module_canvas,
    );

    if visibility_before != visibility_after {
        app.ui_state.sync_runtime_to_active_layout();
        let _ = app.ui_state.user_config.save();
    }

    Ok(needs_sync)
}
