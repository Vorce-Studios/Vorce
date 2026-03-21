import re

with open('crates/mapmap-core/tests/module_tests.rs', 'r') as f:
    content = f.read()

content = content.replace('from_socket: 999,', 'from_socket: "999".to_string(),')
content = content.replace('to_socket: 0,', 'to_socket: "0".to_string(),')
content = content.replace('from_socket: 0,', 'from_socket: "0".to_string(),')
content = content.replace('to_socket: 999,', 'to_socket: "999".to_string(),')
content = content.replace('from_socket: 1,', 'from_socket: "1".to_string(),')

content = content.replace('module.connections[0].from_socket, 0', 'module.connections[0].from_socket, "0"')
content = content.replace('module.connections[0].to_socket, 0', 'module.connections[0].to_socket, "0"')

content = content.replace('conn.from_socket, 0', 'conn.from_socket, "0"')
content = content.replace('conn.to_socket, 0', 'conn.to_socket, "0"')

content = content.replace('module.remove_connection(1, 0, 2, 0);', 'module.remove_connection(1, "0".to_string(), 2, "0".to_string());')

with open('crates/mapmap-core/tests/module_tests.rs', 'w') as f:
    f.write(content)
