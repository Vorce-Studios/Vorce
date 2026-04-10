use super::window_manager::WindowManager;
use vorce_render::WgpuBackend;
use winit::event_loop::EventLoop;

#[test]
fn test_create_window_manager() {
    let wm = WindowManager::new();
    assert_eq!(wm.window_ids().count(), 0);
}

#[test]
#[ignore]
fn test_create_main_window() {
    let event_loop = EventLoop::new().unwrap();
    let backend = pollster::block_on(WgpuBackend::new(None)).unwrap();
    let mut wm = WindowManager::new();
    let main_window_id = wm.create_main_window(&event_loop, &backend).unwrap();
    assert!(wm.get(main_window_id).is_some());
}
