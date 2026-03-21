use mapmap_core::AppState;
use mapmap_io::project_format::ProjectFile;

fn main() {
    let original_state = AppState::default();
    let project_file = ProjectFile::new(original_state);
    let serialized = ron::ser::to_string_pretty(&project_file, ron::ser::PrettyConfig::default()).unwrap();
    println!("{}", serialized);
}
