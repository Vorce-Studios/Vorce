import re

with open('crates/mapmap-core/src/module_eval/evaluator/mod.rs', 'r') as f:
    content = f.read()

content = content.replace('module.add_connection(t_id, format!("trigger_{}_event_out", t_id), m_id, format!("media_{}_trigger_in", m_id));', 'module.add_connection(t_id, format!("trigger_{}_event_out", t_id), m_id, format!("fx_{}_media_in", m_id));')
content = content.replace('module.add_connection(t_id, format!("trigger_{}_event_out", t_id), m_id, format!("fx_{}_trigger_in", m_id));', 'module.add_connection(t_id, format!("trigger_{}_event_out", t_id), m_id, format!("fx_{}_media_in", m_id));')

with open('crates/mapmap-core/src/module_eval/evaluator/mod.rs', 'w') as f:
    f.write(content)
