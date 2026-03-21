import re
with open("crates/mapmap-ui/src/editors/module_canvas/inspector/source.rs", "r") as f:
    code = f.read()

# Let's just use replace_with_git_merge_diff since python replace isn't hitting. Wait, I can use re.sub for precision. Let's see the actual text.
