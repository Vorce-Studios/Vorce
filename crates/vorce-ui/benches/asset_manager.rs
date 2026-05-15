use criterion::{black_box, criterion_group, criterion_main, Criterion};
use std::collections::HashMap;

use vorce_ui::core::asset_manager::{AssetManager, EffectPreset};

fn create_mock_presets(dir: &std::path::Path, count: usize) {
    let effects_dir = dir.join("effects");
    std::fs::create_dir_all(&effects_dir).unwrap();

    for i in 0..count {
        let preset = EffectPreset {
            name: format!("Preset {}", i),
            name_lower: format!("preset {}", i),
            category: "Test".to_string(),
            description: "Test description".to_string(),
            description_lower: "test description".to_string(),
            tags: vec!["tag1".to_string(), "tag2".to_string()],
            tags_lower: vec!["tag1".to_string(), "tag2".to_string()],
            favorite: false,
            parameters: HashMap::new(),
            thumbnail: None,
        };
        let file_path = effects_dir.join(format!("preset_{}.json", i));
        let data = serde_json::to_string(&preset).unwrap();
        std::fs::write(file_path, data).unwrap();
    }
}

pub fn load_library_benchmark(c: &mut Criterion) {
    let temp_dir = tempfile::tempdir().unwrap();
    let library_path = temp_dir.path().to_path_buf();

    create_mock_presets(&library_path, 100);

    c.bench_function("load_library_100_presets", |b| {
        b.iter(|| {
            let manager = AssetManager::new(library_path.clone());
            black_box(manager);
        })
    });
}

criterion_group!(benches, load_library_benchmark);
criterion_main!(benches);
