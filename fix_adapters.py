import os
import sys

# Correct base path provided by you
BASE_PATH = r'C:\Users\Vinyl\Desktop\VJMapper\vorce-studios_company\paperclip'

def fix_cursor_execute():
    """
    Fixes the cursor-local adapter to use the correct executable command,
    addressing the 'MODULE_NOT_FOUND' error.
    """
    path = os.path.join(BASE_PATH, r'packages\adapters\cursor-local\src\server\execute.ts')
    print(f"Attempting to patch {path}...")
    try:
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()

        old_cmd = 'const command = asString(config.command, "node").trim();'
        # Use a raw string (r'') to prevent issues with backslashes in the path
        new_cmd = r'const command = asString(config.command, "C:\Users\Vinyl\AppData\Local\cursor-agent\agent.cmd").trim();'
        
        if old_cmd in content:
            content = content.replace(old_cmd, new_cmd)
            with open(path, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"SUCCESS: Patched cursor-local adapter.")
        else:
            print(f"WARNING: Could not find the expected command line in {path}. It might already be patched.")

    except FileNotFoundError:
        print(f"ERROR: File not found at {path}. Please ensure the path is correct.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    if not os.path.isdir(BASE_PATH):
        print(f"FATAL: The directory '{BASE_PATH}' does not exist. Please verify the path.", file=sys.stderr)
        sys.exit(1)
    
    print("Starting adapter fix script...")
    fix_cursor_execute()
    print("Adapter fix script finished.")
