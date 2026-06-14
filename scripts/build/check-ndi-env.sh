#!/bin/bash
# Diagnostic script to check NDI build environment

echo "=== NDI Build Environment Diagnostic ==="
echo ""

echo "1. Checking NDI headers:"
NDI_HEADER_PATHS=(
    "/usr/share/NDI SDK for Linux/include/Processing.NDI.Lib.h"
    "/usr/include/Processing.NDI.Lib.h"
    "/usr/local/include/Processing.NDI.Lib.h"
    "/opt/ndi/include/Processing.NDI.Lib.h"
)

HEADER_FOUND=false
for path in "${NDI_HEADER_PATHS[@]}"; do
    if [ -f "$path" ]; then
        echo "   ✅ NDI SDK header found at: $path"
        HEADER_FOUND=true
        break
    fi
done

if [ "$HEADER_FOUND" = false ]; then
    echo "   ❌ NDI SDK header NOT found"
    echo "   You need to install the NDI SDK."
fi
echo ""

echo "2. Checking NDI library:"
if ldconfig -p | grep -q "libndi"; then
    echo "   ✅ NDI runtime library found in ldconfig"
else
    echo "   ❌ NDI runtime library NOT found in ldconfig"
    echo "   You may need to add the SDK library path to ld.so.conf.d or export LD_LIBRARY_PATH"
fi
echo ""

echo "=== Summary ==="
if [ "$HEADER_FOUND" = true ]; then
    echo "✅ NDI SDK seems available! You should be able to build with:"
    echo "   cargo build --release --features ndi"
else
    echo "❌ NDI SDK missing from build environment"
    echo ""
    echo "Please download and install the NDI SDK for Linux from: https://ndi.video/tools/ndi-sdk/"
    echo "Follow their instructions to accept the EULA and install to /usr/share/NDI SDK for Linux/"
fi
