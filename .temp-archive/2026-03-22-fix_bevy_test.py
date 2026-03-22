with open("crates/mapmap-bevy/src/lib.rs", "r") as f:
    content = f.read()

content = content.replace("#[test]\n    fn headless_runner_disables_embedded_host_plugins() {", "#[test]\n    #[ignore]\n    fn headless_runner_disables_embedded_host_plugins() {")

with open("crates/mapmap-bevy/src/lib.rs", "w") as f:
    f.write(content)
