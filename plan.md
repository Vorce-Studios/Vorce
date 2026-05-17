The Windows CI failed because of some warnings that are treated as errors. The warnings are:

1. `warning: variable does not need to be mutable` at `crates\vorce\src\app\core\init.rs:197:13` (`let mut control_manager = ControlManager::new();`)
2. `warning: unused variable: ui_state` at `crates\vorce\src\app\core\init.rs:358:23` (`fn init_ui_assets(ui_state: &mut AppUI)`)
3. `warning: unused variable: app` at `crates\vorce\src\app\loops\logic.rs:233:20` (`fn sync_web_status(app: &mut App)`)

Wait, the third one is in `fn sync_web_status(app: &mut App)` and it uses `app` when `#[cfg(feature = "http-api")]` is active. If `http-api` is disabled, `app` is unused. To fix this without breaking `http-api`, I should prepend `_` to `app` but maybe change `app: &mut App` to `#[allow(unused_variables)] app: &mut App` or `_app: &mut App`? Or we can put `#[allow(unused_variables)]` above `fn sync_web_status` and `fn init_ui_assets`.

For `control_manager`, it is used later. Let's see:

```rust
        let mut control_manager = ControlManager::new();

        #[cfg(feature = "http-api")]
        if ui_state.user_config.web_api_enabled {
            let web_config =
                vorce_control::web::WebServerConfig::new(ui_state.user_config.web_api_port);
            if let Err(e) = control_manager.init_web_server(web_config) {
                error!("Failed to initialize Web API: {}", e);
            }
        }
```

If `http-api` is not enabled, `control_manager` is not mutated.

We can add `#[allow(unused_mut)]` above `let mut control_manager` or `#[allow(unused_variables)]` for the functions.
