import re

file_path = ".github/workflows/CICD-DevFlow_Job01_Validation.yml"
with open(file_path, "r") as f:
    content = f.read()

# I need to update uses: dtolnay/rust-toolchain@stable to include toolchain input
content = content.replace("uses: dtolnay/rust-toolchain@stable\n        with:\n          toolchain:", "uses: dtolnay/rust-toolchain@stable\n        with:\n          toolchain:")
# Wait, it already has:
#       - name: Set up Rust
#         uses: dtolnay/rust-toolchain@stable
#         with:
#           toolchain: ${{ env.RUST_TOOLCHAIN }}

# The user mentioned:
# Das Job-Log zeigt einen Abbruch, da eine erforderliche Eingabe toolchain fehlt:
# "'toolchain' is a required input"

# Is it because of dtolnay/rust-toolchain@stable requiring toolchain and it's missing in some places?
