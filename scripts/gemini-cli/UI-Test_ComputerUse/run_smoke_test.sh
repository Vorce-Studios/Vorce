#!/bin/bash
set -e

# Setup display for testing if not present
if [ -z "$DISPLAY" ]; then
    export DISPLAY=:99
    sudo apt-get install -y openbox
    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
    Xvfb :99 -screen 0 1920x1080x24 > /dev/null 2>&1 &
    XVFB_PID=$!
    sleep 2
    openbox-session &
    OPENBOX_PID=$!
    sleep 2
fi

export WGPU_BACKEND=vulkan

echo "Starting Vorce UI Smoke Test..."

mkdir -p test_artifacts
python3 -m pip install psutil pyautogui > /dev/null 2>&1 || true

echo "Building Vorce..."
cargo build --bin Vorce

echo "Starting Vorce..."
cargo run --bin Vorce > test_artifacts/vorce.log 2>&1 &
VORCE_PID=$!

echo "Vorce started with PID: $VORCE_PID"

python3 scripts/gemini-cli/UI-Test_ComputerUse/wait_for_vorce.py

sleep 15

python3 scripts/gemini-cli/UI-Test_ComputerUse/vorce_automation.py

echo "Stopping Vorce..."
kill $VORCE_PID || true
if [ ! -z "$OPENBOX_PID" ]; then
    kill $OPENBOX_PID || true
fi
if [ ! -z "$XVFB_PID" ]; then
    kill $XVFB_PID || true
fi

echo "Smoke test finished."
if [ -f test_artifacts/result.json ]; then
    cat test_artifacts/result.json
else
    echo "No result.json found."
fi
