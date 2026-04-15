file_path = "crates/vorce-control/src/web/websocket.rs"
with open(file_path, "r") as f:
    content = f.read()

import re
content = content.replace("}\n}\n", "}\n}\n")
with open(file_path, "w") as f:
    f.write(content)
