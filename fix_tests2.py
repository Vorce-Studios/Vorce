import re

with open('crates/mapmap-core/src/diagnostics.rs', 'r') as f:
    content = f.read()

content = content.replace('to_socket: 0,', 'to_socket: "0".to_string(),')

with open('crates/mapmap-core/src/diagnostics.rs', 'w') as f:
    f.write(content)


with open('crates/mapmap-core/tests/comprehensive_node_tests.rs', 'r') as f:
    content = f.read()

content = re.sub(r'add_connection\(([^,]+),\s*(\d+),\s*([^,]+),\s*(\d+)\)', r'add_connection(\1, "\2".to_string(), \3, "\4".to_string())', content)
content = re.sub(r'remove_connection\(([^,]+),\s*(\d+),\s*([^,]+),\s*(\d+)\)', r'remove_connection(\1, "\2".to_string(), \3, "\4".to_string())', content)

content = content.replace('.insert(\n            0,', '.insert(\n            "0".to_string(),')

with open('crates/mapmap-core/tests/comprehensive_node_tests.rs', 'w') as f:
    f.write(content)
