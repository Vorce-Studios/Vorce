import re

with open('crates/mapmap-core/src/module_eval/evaluator/mod.rs', 'r') as f:
    content = f.read()

# Replace hardcoded test indices with correct string IDs
content = content.replace('module.add_connection(s_id, "0".to_string(), l_id, "0".to_string());', 'module.add_connection(s_id, format!("source_{}_media_out", s_id), l_id, format!("layer_{}_media_in", l_id));')

content = content.replace('module.add_connection(l_id, "0".to_string(), o_id, "0".to_string());', 'module.add_connection(l_id, format!("layer_{}_layer_out", l_id), o_id, format!("output_{}_layer_in", o_id));')

content = content.replace('module.add_connection(t_id, "0".to_string(), l_id, "1".to_string());', 'module.add_connection(t_id, format!("trigger_{}_event_out", t_id), l_id, format!("layer_{}_trigger_in", l_id));')

content = content.replace('module.add_connection(t_id, "0".to_string(), m_id, "0".to_string());', 'module.add_connection(t_id, format!("trigger_{}_event_out", t_id), m_id, format!("media_{}_trigger_in", m_id));')

content = content.replace('module.add_connection(m_id, "1".to_string(), s_id, "2".to_string());', 'module.add_connection(m_id, format!("hue_{}_link_out", m_id), s_id, format!("hue_{}_link_in", s_id));')

content = content.replace('module.remove_connection(l_id, "0".to_string(), o_id, "0".to_string());', 'module.remove_connection(l_id, format!("layer_{}_layer_out", l_id), o_id, format!("output_{}_layer_in", o_id));')

with open('crates/mapmap-core/src/module_eval/evaluator/mod.rs', 'w') as f:
    f.write(content)
