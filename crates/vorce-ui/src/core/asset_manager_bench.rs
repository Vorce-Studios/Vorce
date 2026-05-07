use std::time::Instant;
use tempfile::tempdir;
use crate::core::asset_manager::{AssetManager, EffectPreset, TransformPreset, ProjectTemplate};

pub fn run_benchmark() {
    let dir = tempdir().unwrap();
    let effects_dir = dir.path().join("effects");
    let transforms_dir = dir.path().join("transforms");
    let templates_dir = dir.path().join("templates");

    std::fs::create_dir_all(&effects_dir).unwrap();
    std::fs::create_dir_all(&transforms_dir).unwrap();
    std::fs::create_dir_all(&templates_dir).unwrap();

    // Create lots of dummy files
    for i in 0..1000 {
        let effect = EffectPreset {
            name: format!("Effect {}", i),
            name_lower: "".to_string(),
            category: "Category".to_string(),
            description: "Description".to_string(),
            description_lower: "".to_string(),
            tags: vec!["tag1".to_string(), "tag2".to_string()],
            tags_lower: vec![],
            favorite: false,
            parameters: std::collections::HashMap::new(),
            thumbnail: None,
        };
        std::fs::write(
            effects_dir.join(format!("{}.json", i)),
            serde_json::to_string(&effect).unwrap(),
        ).unwrap();

        let transform = TransformPreset {
            name: format!("Transform {}", i),
            description: "Description".to_string(),
            position: (0.0, 0.0),
            scale: (1.0, 1.0),
            rotation: (0.0, 0.0, 0.0),
            anchor: (0.0, 0.0),
        };
        std::fs::write(
            transforms_dir.join(format!("{}.json", i)),
            serde_json::to_string(&transform).unwrap(),
        ).unwrap();

        let template = ProjectTemplate {
            name: format!("Template {}", i),
            description: "Description".to_string(),
            tags: vec![],
            thumbnail: None,
            file_path: std::path::PathBuf::from("path"),
        };
        std::fs::write(
            templates_dir.join(format!("{}.json", i)),
            serde_json::to_string(&template).unwrap(),
        ).unwrap();
    }

    let start = Instant::now();
    let manager = AssetManager::new(dir.path().to_path_buf());
    let duration = start.elapsed();

    println!("Loading {} assets took: {:?}", 3000, duration);
}
