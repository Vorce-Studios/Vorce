file_path = "crates/vorce-control/src/web/websocket.rs"
with open(file_path, "r") as f:
    content = f.read()

import re
content = re.sub(r"pub async fn ws_handler\(\n    ws: WebSocketUpgrade,\n    _headers: HeaderMap,\n    State\(state\): State<AppState>,\n\) -> Response \{\n    // Set max message size to prevent DoS attacks\n    ws\.max_message_size\(MAX_MESSAGE_SIZE\)\n        \.on_upgrade\(\|socket\| handle_socket\(socket, state\)\)\n\}",
r"pub async fn ws_handler(\n    ws: WebSocketUpgrade,\n    _headers: HeaderMap,\n    State(state): State<AppState>,\n) -> Response {\n    // Set max message size to prevent DoS attacks\n    ws.max_message_size(MAX_MESSAGE_SIZE)\n        .on_upgrade(|socket| handle_socket(socket, state))\n}", content)

with open(file_path, "w") as f:
    f.write(content)
