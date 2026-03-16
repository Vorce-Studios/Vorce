use mapmap_core::state::AppState;
use mapmap_io::project::{save_project, load_project};

fn main() {
    let original_state = AppState::default();
    let path = std::path::PathBuf::from("test_output.ron");
    save_project(&original_state, &path).unwrap();
    println!("Saved!");
    let loaded = load_project(&path);
    println!("Loaded: {:?}", loaded.is_ok());
}
