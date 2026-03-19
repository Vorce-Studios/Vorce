with open("crates/mapmap-core/src/audio/analyzer_v2/tests.rs", "r") as f:
    content = f.read()

content = content.replace("#[cfg(test)]\nmod tests {\n    use crate::audio::analyzer_v2::{AudioAnalyzerV2, AudioAnalyzerV2Config};\n", "#[cfg(test)]\nuse crate::audio::analyzer_v2::{AudioAnalyzerV2, AudioAnalyzerV2Config};\n")
if content.endswith("}\n"):
    content = content[:-2] + "\n"

with open("crates/mapmap-core/src/audio/analyzer_v2/tests.rs", "w") as f:
    f.write(content)
