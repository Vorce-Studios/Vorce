with open("crates/mapmap/src/app/core/app_struct.rs", "r") as f:
    content = f.read()

content = content.replace("/// Configuration for application initialization.\npub struct InitializationConfig {", "/// Configuration for application initialization.\n#[derive(Default)]\npub struct InitializationConfig {")

with open("crates/mapmap/src/app/core/app_struct.rs", "w") as f:
    f.write(content)
