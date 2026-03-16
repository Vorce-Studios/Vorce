import os
import re

def rename_content(file_path):
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except UnicodeDecodeError:
        return

    new_content = content
    # Order matters
    new_content = new_content.replace('SubI', 'SubI')
    new_content = new_content.replace('SubI', 'SubI')
    new_content = new_content.replace('SUBI', 'SUBI')
    new_content = new_content.replace('SUBI', 'SUBI')
    new_content = new_content.replace('subi', 'subi')
    new_content = new_content.replace('subi', 'subi')
    new_content = new_content.replace('SubI', 'SubI') # the issue says replaces SubI
    new_content = new_content.replace('subi', 'subi')

    if new_content != content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(new_content)

def rename_files_and_dirs(root_dir):
    # Rename files and dirs bottom-up
    for dirpath, dirnames, filenames in os.walk(root_dir, topdown=False):
        # Skip git and target
        if '.git' in dirpath or 'target' in dirpath:
            continue

        for name in filenames:
            new_name = name
            new_name = new_name.replace('SubI', 'SubI')
            new_name = new_name.replace('SubI', 'SubI')
            new_name = new_name.replace('SUBI', 'SUBI')
            new_name = new_name.replace('SUBI', 'SUBI')
            new_name = new_name.replace('subi', 'subi')
            new_name = new_name.replace('subi', 'subi')
            if new_name != name:
                os.rename(os.path.join(dirpath, name), os.path.join(dirpath, new_name))

        for name in dirnames:
            if name == '.git' or name == 'target': continue
            new_name = name
            new_name = new_name.replace('SubI', 'SubI')
            new_name = new_name.replace('SubI', 'SubI')
            new_name = new_name.replace('SUBI', 'SUBI')
            new_name = new_name.replace('SUBI', 'SUBI')
            new_name = new_name.replace('subi', 'subi')
            new_name = new_name.replace('subi', 'subi')
            if new_name != name:
                os.rename(os.path.join(dirpath, name), os.path.join(dirpath, new_name))

def process_contents(root_dir):
    for dirpath, dirnames, filenames in os.walk(root_dir):
        if '.git' in dirpath or 'target' in dirpath:
            continue
        for name in filenames:
            # exclude some binary files like png, ico, icns
            if name.endswith(('.png', '.ico', '.icns', '.zip', '.tar.gz', '.dll', '.exe', '.pdf', '.ttf')):
                continue
            rename_content(os.path.join(dirpath, name))

if __name__ == '__main__':
    print("Processing contents...")
    process_contents('.')
    print("Renaming files and directories...")
    rename_files_and_dirs('.')
    print("Done.")
