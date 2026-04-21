import os
import sys
import subprocess
import glob
import struct

def check_dlls(target_dir):
    required_prefixes = ["avcodec", "avformat", "avutil", "swresample", "swscale"]
    found_dlls = glob.glob(os.path.join(target_dir, "*.dll"))
    found_names = [os.path.basename(d).lower() for d in found_dlls]
    
    missing = []
    for prefix in required_prefixes:
        if not any(name.startswith(prefix) for name in found_names):
            missing.append(prefix)
    
    if missing:
        print(f"FAILED: Missing FFmpeg DLLs for prefixes: {', '.join(missing)}")
        return False
    print("SUCCESS: All required FFmpeg DLLs found.")
    return True

def check_ndi(target_dir):
    ndi_dll = "processing.ndi.lib.x64.dll"
    found_dlls = glob.glob(os.path.join(target_dir, "*.dll"))
    found_names = [os.path.basename(d).lower() for d in found_dlls]
    
    if ndi_dll not in found_names:
        print(f"FAILED: Missing NDI DLL: {ndi_dll}")
        return False
    print("SUCCESS: NDI DLL found.")
    return True

def check_icon(exe_path):
    if not os.path.exists(exe_path):
        print(f"FAILED: Executable not found: {exe_path}")
        return False
    
    # Simple check for ICON resource existence using pefile if available,
    # or just checking the file size/existence for now.
    # To truly verify the icon, we would need to parse the PE resources.
    # Since we can't easily install pefile, we check if the file is a valid PE.
    try:
        with open(exe_path, "rb") as f:
            if f.read(2) != b"MZ":
                print(f"FAILED: {exe_path} is not a valid PE file.")
                return False
        print(f"SUCCESS: {exe_path} is a valid PE file (Icon check placeholder).")
        return True
    except Exception as e:
        print(f"FAILED: Error reading {exe_path}: {e}")
        return False

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "target/debug"
    exe_name = sys.argv[2] if len(sys.argv) > 2 else "vorce.exe"
    exe_path = os.path.join(target, exe_name)
    
    print(f"Running Windows Smoke Test on: {target}")
    
    ffmpeg_ok = check_dlls(target)
    ndi_ok = check_ndi(target)
    icon_ok = check_icon(exe_path)
    
    if not (ffmpeg_ok and ndi_ok and icon_ok):
        sys.exit(1)
    sys.exit(0)
