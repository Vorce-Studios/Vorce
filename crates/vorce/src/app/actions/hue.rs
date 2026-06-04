//! App actions for hue.

use crate::app::core::app_struct::App;
#[cfg(feature = "ndi")]
use crossbeam_channel::Sender;
use tracing::{error, info};
use vorce_ui::UIAction;
/// Handle UI actions
pub fn handle(app: &mut App, action: UIAction, _needs_sync: &mut bool) -> bool {
    match action {
        UIAction::RegisterHue => {
            info!("Linking with Philips Hue Bridge...");
            let ip = app.ui_state.user_config.hue_config.bridge_ip.clone();
            if ip.is_empty() {
                error!("Cannot link: No Bridge IP specified.");
            } else {
                match app.tokio_runtime.block_on(app.hue_controller.register(&ip)) {
                    Ok(new_config) => {
                        info!("Successfully linked with Hue Bridge!");
                        app.ui_state.user_config.hue_config.username = new_config.username;
                        app.ui_state.user_config.hue_config.client_key = new_config.client_key;
                        let _ = app.ui_state.user_config.save();
                    }
                    Err(e) => {
                        error!("Failed to link with Hue Bridge: {}", e);
                    }
                }
            }
        }
        UIAction::FetchHueGroups => {
            info!("Fetching Hue Entertainment Groups...");
            let bridge_ip = app.ui_state.user_config.hue_config.bridge_ip.clone();
            let username = app.ui_state.user_config.hue_config.username.clone();

            if bridge_ip.is_empty() || username.is_empty() {
                error!("Cannot fetch groups: Bridge IP or Username missing");
            } else {
                // Construct a temp config to fetch groups
                let config = vorce_control::hue::models::HueConfig {
                    bridge_ip: bridge_ip.clone(),
                    username: username.clone(),
                    ..Default::default()
                };

                info!("Calling get_entertainment_groups API...");
                // Blocking call
                match app
                    .tokio_runtime
                    .block_on(vorce_control::hue::api::groups::get_entertainment_groups(&config))
                {
                    Ok(groups) => {
                        info!("Successfully fetched {} entertainment groups", groups.len());
                        for g in &groups {
                            info!("  - Group: id='{}', name='{}'", g.id, g.name);
                        }
                        app.ui_state.available_hue_groups =
                            groups.into_iter().map(|g| (g.id, g.name)).collect();
                    }
                    Err(e) => {
                        error!("Failed to fetch groups: {:?}", e);
                    }
                }
            }
        }
        UIAction::ConnectHue => {
            info!("Connecting to Philips Hue Bridge...");
            let ui_hue = &app.ui_state.user_config.hue_config;
            let control_hue = vorce_control::hue::models::HueConfig {
                bridge_ip: ui_hue.bridge_ip.clone(),
                username: ui_hue.username.clone(),
                client_key: ui_hue.client_key.clone(),
                application_id: String::new(),
                entertainment_group_id: ui_hue.entertainment_area.clone(),
            };
            app.hue_controller.update_config(control_hue);

            if let Err(e) = app.tokio_runtime.block_on(app.hue_controller.connect()) {
                error!("Failed to connect to Hue Bridge: {}", e);
            } else {
                info!("Successfully connected to Hue Bridge");
            }
        }
        UIAction::DisconnectHue => {
            info!("Disconnecting from Philips Hue Bridge...");
            app.tokio_runtime.block_on(app.hue_controller.disconnect());
        }
        UIAction::DiscoverHueBridges => {
            info!("Discovering Philips Hue Bridges...");
            match app.tokio_runtime.block_on(vorce_control::hue::api::discovery::discover_bridges())
            {
                Ok(bridges) => {
                    info!("Discovered {} bridges", bridges.len());
                    app.ui_state.discovered_hue_bridges = bridges;
                }
                Err(e) => {
                    error!("Bridge discovery failed: {}", e);
                }
            }
        }
        _ => return false,
    }
    true
}
