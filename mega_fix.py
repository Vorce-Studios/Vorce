import os

def resolve_nested(content):
    lines = content.splitlines()
    new_lines = []
    skip_ours = False
    for line in lines:
        if line.startswith("<<<<<<<"):
            skip_ours = True
            continue
        if line.startswith("======="):
            skip_ours = False
            continue
        if line.startswith(">>>>>>>"):
            skip_ours = False
            continue
        if not skip_ours:
            new_lines.append(line)
    return "\n".join(new_lines) + "\n"

def fix_all():
    for root, dirs, files in os.walk("."):
        if ".git" in dirs:
            dirs.remove(".git")
        if "target" in dirs:
            dirs.remove("target")
        for file in files:
            if file.endswith(".rs") or file.endswith(".md") or file.endswith(".wgsl"):
                path = os.path.join(root, file)
                try:
                    with open(path, "r", encoding="utf-8") as f:
                        content = f.read()
                    if "<<<<<<<" in content or "=======" in content or ">>>>>>>" in content:
                        print(f"Fixing {path}")
                        fixed = resolve_nested(content)
                        with open(path, "w", encoding="utf-8", newline='\n') as f:
                            f.write(fixed)
                except Exception as e:
                    pass

if __name__ == "__main__":
    fix_all()
