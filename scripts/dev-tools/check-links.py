import re
import os

def check_file(filepath):
    print(f"Checking {filepath}...")
    with open(filepath, 'r') as f:
        content = f.read()

    # Find markdown links [text](url)
    links = re.findall(r'\[.*?\]\((.*?)\)', content)

    base_dir = os.path.dirname(filepath)

    for link in links:
        if link.startswith('http'):
            continue
        if link.startswith('#'):
            continue

        target = os.path.join(base_dir, link)
        if not os.path.exists(target):
            print(f"  BROKEN: {link} -> {target}")
        else:
            print(f"  OK: {link}")

check_file('README.md')
check_file('docs/A4_USER/B1_MANUAL/DOC-C0_README.md')
check_file('docs/A2_DEVELOPMENT/DOC-B0_README.md')
check_file('docs/A3_PROJECT/DOC-B0_README.md')
