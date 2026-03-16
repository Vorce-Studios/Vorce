with open("crates/mapmap-core/src/audio/analyzer_v2/tests.rs", "r") as f:
    lines = f.readlines()

new_lines = []
for i, line in enumerate(lines):
    if i == 0 and line.strip() == "#[cfg(test)]":
        continue
    if i == 1 and line.strip() == "mod tests {":
        continue

    # remove last closing brace
    if i == len(lines) - 1 and line.strip() == "}":
        continue

    if line.startswith("    "):
        new_lines.append(line[4:])
    else:
        new_lines.append(line)

with open("crates/mapmap-core/src/audio/analyzer_v2/tests.rs", "w") as f:
    f.writelines(new_lines)
