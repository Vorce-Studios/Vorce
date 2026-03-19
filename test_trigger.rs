use mapmap_core::module::{ModulePart, ModulePartType, TriggerType};

fn main() {
    let part = ModulePart {
        id: 1,
        name: "Test".to_string(),
        part_type: ModulePartType::Trigger(TriggerType::Beat),
        ..Default::default()
    };
    println!("{:?}", part.schema());
}
