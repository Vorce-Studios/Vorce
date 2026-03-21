import re

with open('crates/mapmap-core/tests/module_tests.rs', 'r') as f:
    content = f.read()

content = re.sub(r'add_connection\(([^,]+),\s*(\d+),\s*([^,]+),\s*(\d+)\)', r'add_connection(\1, "\2".to_string(), \3, "\4".to_string())', content)
content = re.sub(r'remove_connection\(([^,]+),\s*(\d+),\s*([^,]+),\s*(\d+)\)', r'remove_connection(\1, "\2".to_string(), \3, "\4".to_string())', content)
content = re.sub(r'connect_parts\(([^,]+),\s*(\d+),\s*([^,]+),\s*(\d+)\)', r'connect_parts(\1, "\2".to_string(), \3, "\4".to_string())', content)

with open('crates/mapmap-core/tests/module_tests.rs', 'w') as f:
    f.write(content)
