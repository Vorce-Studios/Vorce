with open('crates/vorce-bevy/src/systems.rs', 'r') as f:
    data = f.read()

data = data.replace('if let Some(mat) = materials.get_mut(handle) {', 'if let Some(mut mat) = materials.get_mut(handle) {')
data = data.replace('scale: hex_size,', 'hex_size,')

with open('crates/vorce-bevy/src/systems.rs', 'w') as f:
    f.write(data)
