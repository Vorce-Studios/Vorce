import datetime

with open("CHANGELOG.md", "r") as f:
    content = f.readlines()

new_entry = f"- {datetime.date.today().strftime('%Y-%m-%d')}: fix: Enable multi-threaded video pipeline and thread-local scaler (#1411)\n"

# Find the insertion point (after the first unreleased entry or under Unreleased header)
for i, line in enumerate(content):
    if line.startswith("- 2026"):
        content.insert(i, new_entry)
        break

with open("CHANGELOG.md", "w") as f:
    f.writelines(content)
