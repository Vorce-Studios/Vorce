with open("crates/mapmap-core/src/diagnostics.rs", "r") as f:
    code = f.read()

# Replace test code
code = code.replace("""if !module.connections.iter().any(|c| c.to_part == idx && c.to_socket == s_idx) {""", """if !module.connections.iter().any(|c| c.to_part == idx as u64 && c.to_socket == s_idx) {""")

code = code.replace("""if let crate::module::PartType::Source = part.part_type {""", """if matches!(part.part_type, crate::module::ModulePartType::Source(_)) {""")

with open("crates/mapmap-core/src/diagnostics.rs", "w") as f:
    f.write(code)
