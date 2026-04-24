import re

def replace_in_file(filepath, search_regex, replacement):
    with open(filepath, 'r') as f:
        content = f.read()

    new_content = re.sub(search_regex, replacement, content, flags=re.MULTILINE | re.DOTALL)

    with open(filepath, 'w') as f:
        f.write(new_content)

# We need to redo the changes we made to the UI colors!
