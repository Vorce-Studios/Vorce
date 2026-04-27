## Verlinktes Issue
Fixes #370

🎯 **What:**
Enabled NDI input and output capabilities in the module inspector UI and updated their runtime status.

💡 **Why:**
As requested in Issue #370 (and Paperclip VOR-38), NdiOutput is now considered active and needs to reflect its proper status in the UI so that users know it's fully supported instead of experimental.

✅ **Verification:**
Updated existing unit tests for `is_source_type_enum_supported` and `is_output_type_enum_supported` to expect `true` for NDI, and verified all tests pass via `cargo test -p vorce-ui`.

✨ **Result:**
The inspector UI for NDI Input and Output nodes now displays a positive "Runtime Active" indicator in MINT_ACCENT color instead of an unsupported warning, and capabilities correctly reflect NDI as a supported format.
