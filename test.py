import glob
import re

for file_path in glob.glob('C:/Users/Vinyl/.cargo/registry/src/**/wgpu-types-29*/src/**/*.rs', recursive=True):
    content = open(file_path, encoding='utf-8').read()
    if 'pub enum Maintain' in content or 'pub enum PollType' in content:
        print(f"Found in {file_path}:")
        match = re.search(r'pub enum (Maintain|PollType)[^}]*\}', content)
        if match:
            print(match.group(0))

for file_path in glob.glob('C:/Users/Vinyl/.cargo/registry/src/**/wgpu-29*/src/**/*.rs', recursive=True):
    content = open(file_path, encoding='utf-8').read()
    if 'pub fn poll' in content:
        print(f"Found poll in {file_path}:")
        match = re.search(r'pub fn poll[^{]*\{', content)
        if match:
            print(match.group(0))
