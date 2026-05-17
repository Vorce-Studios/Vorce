import os

with open("crates/vorce/src/app/core/init.rs") as f:
    init_lines = f.readlines()

for i, line in enumerate(init_lines):
    if "let mut control_manager = ControlManager::new();" in line:
        init_lines.insert(i, "        #[allow(unused_mut)]\n")
        break

for i, line in enumerate(init_lines):
    if "fn init_ui_assets(ui_state: &mut AppUI)" in line:
        init_lines.insert(i, "    #[allow(unused_variables)]\n")
        break

with open("crates/vorce/src/app/core/init.rs", "w") as f:
    f.writelines(init_lines)


with open("crates/vorce/src/app/loops/logic.rs") as f:
    logic_lines = f.readlines()

for i, line in enumerate(logic_lines):
    if "fn sync_web_status(app: &mut App)" in line:
        logic_lines.insert(i, "#[allow(unused_variables)]\n")
        break

with open("crates/vorce/src/app/loops/logic.rs", "w") as f:
    f.writelines(logic_lines)
