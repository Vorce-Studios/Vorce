import re

with open("crates/vorce/src/app/core/init.rs") as f:
    init_lines = f.readlines()

for i, line in enumerate(init_lines):
    if "fn init_ui_assets" in line:
        print(f"init_ui_assets found at line {i+1}")
        for j in range(i, i+10):
            print(f"{j+1}: {init_lines[j].strip()}")

with open("crates/vorce/src/app/loops/logic.rs") as f:
    logic_lines = f.readlines()

for i, line in enumerate(logic_lines):
    if "fn sync_web_status" in line:
        print(f"sync_web_status found at line {i+1}")
        for j in range(i, i+10):
            print(f"{j+1}: {logic_lines[j].strip()}")
