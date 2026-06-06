#!/bin/bash
# check-ndi-env.sh - Probes the environment for NDI runtime assets.

echo "=== NDI Runtime Availability Probe ==="
echo ""

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Platform: Linux"
    if ldconfig -p | grep -q "libndi" || ls /usr/lib/libndi* >/dev/null 2>&1 || ls /usr/local/lib/libndi* >/dev/null 2>&1; then
        echo "✅ NDI runtime (libndi.so) found."
        exit 0
    else
        echo "❌ NDI runtime not found."
        echo "Please install the NDI SDK for Linux and ensure libndi is in your library path."
        exit 1
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Platform: macOS"
    if ls /usr/local/lib/libndi* >/dev/null 2>&1 || ls /Library/NDI\ SDK\ for\ Apple/lib/macOS/libndi* >/dev/null 2>&1; then
        echo "✅ NDI runtime (libndi.dylib) found."
        exit 0
    else
        echo "❌ NDI runtime not found."
        echo "Please install the NDI Tools/SDK for macOS."
        exit 1
    fi
elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    echo "Platform: Windows"
    if [ -n "$NDI_RUNTIME_DIR_V6" ] || [ -n "$NDI_RUNTIME_DIR_V5" ]; then
        echo "✅ NDI runtime environment variables found."
        exit 0
    elif [ -d "/c/Program Files/NDI/NDI 6 Runtime" ] || [ -d "C:\\Program Files\\NDI\\NDI 6 Runtime" ]; then
        echo "✅ NDI 6 runtime found in Program Files."
        exit 0
    else
        echo "❌ NDI runtime not found."
        echo "Please install the NDI Tools/Runtime for Windows."
        exit 1
    fi
else
    echo "Unsupported platform: $OSTYPE"
    exit 1
fi
