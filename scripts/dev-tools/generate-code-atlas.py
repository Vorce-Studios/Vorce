#!/usr/bin/env python3
"""Generate an agent-focused code atlas for the VjMapper workspace."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = REPO_ROOT / ".agent" / "atlas"
CRATE_DIAGRAM_DIRNAME = "crates"

CODE_FILE_SUFFIXES = {".rs", ".wgsl", ".py", ".ps1", ".sh"}
SKIP_DIRS = {
    ".git",
    "target",
    "coverage",
    ".temp-archive",
    ".venv",
    "__pycache__",
}
SPECIAL_TAGS = {
    "app": "application",
    "audio": "audio",
    "bevy": "bevy",
    "control": "control",
    "cue": "cue",
    "decklink": "video-io",
    "dmx": "lighting",
    "effect": "effects",
    "effects": "effects",
    "eval": "evaluation",
    "evaluator": "evaluation",
    "graph": "graph",
    "hue": "lighting",
    "inspector": "ui",
    "io": "io",
    "mapping": "mapping",
    "media": "media",
    "mesh": "mesh",
    "midi": "midi",
    "module": "modules",
    "module_eval": "evaluation",
    "node": "nodes",
    "osc": "osc",
    "orchestration": "orchestration",
    "output": "output",
    "paint": "painting",
    "panel": "ui",
    "panels": "ui",
    "pipeline": "pipeline",
    "render": "rendering",
    "renderer": "rendering",
    "resource": "resources",
    "shader": "shaders",
    "shaders": "shaders",
    "shortcuts": "shortcuts",
    "source": "sources",
    "stream": "streaming",
    "timeline": "timeline",
    "trigger": "triggers",
    "ui": "ui",
    "view": "ui",
    "web": "web",
}

RUST_SYMBOL_PATTERNS = [
    ("struct", re.compile(r"^\s*(pub(?:\([^)]*\))?\s+)?struct\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)),
    ("enum", re.compile(r"^\s*(pub(?:\([^)]*\))?\s+)?enum\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)),
    ("trait", re.compile(r"^\s*(pub(?:\([^)]*\))?\s+)?trait\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)),
    ("type", re.compile(r"^\s*(pub(?:\([^)]*\))?\s+)?type\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)),
    ("const", re.compile(r"^\s*(pub(?:\([^)]*\))?\s+)?const\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)),
    ("static", re.compile(r"^\s*(pub(?:\([^)]*\))?\s+)?static\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)),
    ("fn", re.compile(r"^\s*(pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)),
    ("mod", re.compile(r"^\s*(pub(?:\([^)]*\))?\s+)?mod\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:;|\{)", re.MULTILINE)),
]
GENERIC_SYMBOL_PATTERNS = {
    ".wgsl": [
        ("struct", re.compile(r"^\s*struct\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)),
        ("fn", re.compile(r"^\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)),
        ("var", re.compile(r"^\s*var(?:<[^>]+>)?\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)),
    ],
    ".py": [
        ("class", re.compile(r"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)),
        ("fn", re.compile(r"^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)),
    ],
    ".ps1": [
        ("function", re.compile(r"^\s*function\s+([A-Za-z_][A-Za-z0-9_-]*)", re.MULTILINE)),
    ],
    ".sh": [
        ("function", re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{", re.MULTILINE)),
    ],
}


@dataclass(frozen=True)
class WorkspacePackage:
    name: str
    manifest_path: Path
    root: Path
    description: str
    internal_dependencies: tuple[str, ...]
    crate_module_name: str


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Directory for atlas JSON and Mermaid files.",
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    crate_diagram_dir = output_dir / CRATE_DIAGRAM_DIRNAME
    output_dir.mkdir(parents=True, exist_ok=True)
    crate_diagram_dir.mkdir(parents=True, exist_ok=True)

    packages = load_workspace_packages()
    package_by_name = {package.name: package for package in packages}
    package_name_by_module = {
        package.crate_module_name: package.name for package in packages
    }
    source_entries, module_maps = collect_source_entries(packages)

    for entry in source_entries:
        enrich_entry(entry, package_by_name, package_name_by_module, module_maps)

    backfill_used_by(source_entries)

    files = [normalize_file_entry(entry) for entry in source_entries]
    crates = build_crate_entries(packages, source_entries)
    lookup = build_lookup_indexes(files, crates)

    write_workspace_mermaid(packages, output_dir / "workspace.mmd")
    write_crate_mermaid(source_entries, crate_diagram_dir)
    write_summary_markdown(files, crates, output_dir / "SUMMARY.md")

    atlas = {
        "schema_version": 1,
        "workspace_root": to_posix_path(REPO_ROOT),
        "workspace": {
            "crate_count": len(crates),
            "file_count": len(files),
            "crates": [crate["name"] for crate in crates],
        },
        "artifacts": {
            "summary_markdown": ".agent/atlas/SUMMARY.md",
            "workspace_mermaid": ".agent/atlas/workspace.mmd",
            "crate_mermaid_dir": ".agent/atlas/crates",
        },
        "crates": crates,
        "files": files,
        "lookup": lookup,
    }

    atlas_path = output_dir / "code-atlas.json"
    atlas_path.write_text(json.dumps(atlas, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(f"Code atlas written to {atlas_path}")
    return 0


def load_workspace_packages() -> list[WorkspacePackage]:
    command = ["cargo", "metadata", "--format-version", "1", "--no-deps"]
    result = subprocess.run(
        command,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    metadata = json.loads(result.stdout)
    packages_by_id = {package["id"]: package for package in metadata["packages"]}
    workspace_member_ids = metadata["workspace_members"]
    workspace_names = {
        packages_by_id[package_id]["name"] for package_id in workspace_member_ids
    }

    packages: list[WorkspacePackage] = []
    for package_id in workspace_member_ids:
        raw = packages_by_id[package_id]
        manifest_path = Path(raw["manifest_path"]).resolve()
        internal_dependencies = sorted(
            {
                dependency["name"]
                for dependency in raw.get("dependencies", [])
                if dependency["name"] in workspace_names and dependency["name"] != raw["name"]
            }
        )
        packages.append(
            WorkspacePackage(
                name=raw["name"],
                manifest_path=manifest_path,
                root=manifest_path.parent,
                description=(raw.get("description") or "").strip(),
                internal_dependencies=tuple(internal_dependencies),
                crate_module_name=raw["name"].replace("-", "_"),
            )
        )

    packages.sort(key=lambda package: package.name)
    return packages


def collect_source_entries(
    packages: Iterable[WorkspacePackage],
) -> tuple[list[dict], dict[str, dict[tuple[str, ...], str]]]:
    entries: list[dict] = []
    module_maps: dict[str, dict[tuple[str, ...], str]] = {}

    for package in packages:
        package_entries = discover_package_files(package)
        entries.extend(package_entries)
        module_maps[package.name] = build_module_map(package, package_entries)

    entries.extend(discover_repo_files())
    entries.sort(key=lambda entry: entry["path"])
    return entries, module_maps


def discover_package_files(package: WorkspacePackage) -> list[dict]:
    entries: list[dict] = []
    for directory_name in ("src", "tests", "examples", "benches"):
        directory = package.root / directory_name
        if not directory.exists():
            continue
        for path in iter_code_files(directory):
            entries.append(new_entry(path, crate_name=package.name, crate_root=package.root))

    build_script = package.root / "build.rs"
    if build_script.exists():
        entries.append(new_entry(build_script, crate_name=package.name, crate_root=package.root))
    return entries


def discover_repo_files() -> list[dict]:
    seen_paths = set()
    entries: list[dict] = []

    root_patterns = [
        REPO_ROOT / "scripts",
        REPO_ROOT / "shaders",
    ]
    for root in root_patterns:
        if not root.exists():
            continue
        for path in iter_code_files(root):
            if path in seen_paths:
                continue
            seen_paths.add(path)
            entries.append(new_entry(path, crate_name=None, crate_root=None))

    for path in REPO_ROOT.glob("*.py"):
        if path.name.startswith("."):
            continue
        if path.suffix in CODE_FILE_SUFFIXES:
            if path not in seen_paths:
                seen_paths.add(path)
                entries.append(new_entry(path, crate_name=None, crate_root=None))

    return entries


def iter_code_files(root: Path) -> Iterable[Path]:
    for current_root, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            dirname
            for dirname in dirnames
            if dirname not in SKIP_DIRS and not dirname.startswith(".ruff_cache")
        ]
        current_path = Path(current_root)
        for filename in filenames:
            path = current_path / filename
            if path.suffix.lower() not in CODE_FILE_SUFFIXES:
                continue
            if any(part in SKIP_DIRS for part in path.parts):
                continue
            yield path.resolve()


def new_entry(path: Path, crate_name: str | None, crate_root: Path | None) -> dict:
    relative_path = to_repo_relative(path)
    text = path.read_text(encoding="utf-8", errors="replace")
    kind = detect_kind(path, relative_path)
    return {
        "path": relative_path,
        "absolute_path": to_posix_path(path),
        "crate": crate_name,
        "crate_root": to_repo_relative(crate_root) if crate_root else None,
        "kind": kind,
        "line_count": text.count("\n") + (0 if text.endswith("\n") or not text else 1),
        "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "text": text,
    }


def detect_kind(path: Path, relative_path: str) -> str:
    suffix = path.suffix.lower()
    if suffix == ".rs":
        if "/tests/" in relative_path or relative_path.endswith("/tests.rs"):
            return "rust-test"
        if "/examples/" in relative_path:
            return "rust-example"
        if "/benches/" in relative_path:
            return "rust-bench"
        if path.name == "build.rs":
            return "rust-build-script"
        return "rust-source"
    if suffix == ".wgsl":
        return "shader"
    if suffix == ".py":
        return "python-script"
    if suffix == ".ps1":
        return "powershell-script"
    if suffix == ".sh":
        return "shell-script"
    return "code"


def build_module_map(package: WorkspacePackage, entries: Iterable[dict]) -> dict[tuple[str, ...], str]:
    module_map: dict[tuple[str, ...], str] = {}
    for entry in entries:
        if entry["crate"] != package.name or entry["kind"] not in {"rust-source", "rust-build-script"}:
            continue
        module_components = rust_module_components(package.root, Path(entry["path"]))
        if module_components is None:
            continue
        module_map[module_components] = entry["path"]
    return module_map


def rust_module_components(crate_root: Path, relative_path: Path) -> tuple[str, ...] | None:
    if relative_path.name == "build.rs":
        return ("build",)
    package_root_rel = Path(to_repo_relative(crate_root))
    if not relative_path.is_relative_to(package_root_rel):
        return None
    crate_relative = relative_path.relative_to(package_root_rel)
    if not crate_relative.parts or crate_relative.parts[0] != "src":
        return None

    parts = list(crate_relative.parts[1:])
    if not parts:
        return tuple()

    if parts[-1] in {"lib.rs", "main.rs"}:
        return tuple(parts[:-1])

    if parts[-1] == "mod.rs":
        return tuple(parts[:-1])

    parts[-1] = Path(parts[-1]).stem
    return tuple(parts)


def enrich_entry(
    entry: dict,
    package_by_name: dict[str, WorkspacePackage],
    package_name_by_module: dict[str, str],
    module_maps: dict[str, dict[tuple[str, ...], str]],
) -> None:
    path = REPO_ROOT / Path(entry["path"])
    text = entry["text"]
    suffix = path.suffix.lower()
    entry["summary"] = extract_summary(path, text, entry["kind"])
    entry["symbols"] = extract_symbols(path, text)
    entry["symbol_names"] = sorted({symbol["name"] for symbol in entry["symbols"]})
    entry["tags"] = derive_tags(entry["path"], entry["crate"], entry["kind"], entry["symbol_names"])
    entry["module_path"] = None
    entry["imports"] = []
    entry["depends_on"] = []
    entry["used_by"] = []
    entry["external_import_roots"] = []

    crate_name = entry["crate"]
    if suffix == ".rs" and crate_name in package_by_name:
        package = package_by_name[crate_name]
        module_components = rust_module_components(package.root, Path(entry["path"]))
        if module_components is not None:
            entry["module_path"] = "::".join(
                [package.crate_module_name, *module_components]
            )
        imports = extract_rust_imports(text)
        entry["imports"] = sorted(imports)
        module_map = module_maps.get(crate_name, {})
        depends_on = set()

        for dependency_path in resolve_mod_dependencies(package, entry["path"], text):
            depends_on.add(dependency_path)

        for import_path in imports:
            resolved = resolve_rust_import_path(
                import_path,
                module_components or tuple(),
                package.crate_module_name,
                module_map,
            )
            if not resolved:
                resolved = resolve_cross_crate_import_path(
                    import_path,
                    package.crate_module_name,
                    package_name_by_module,
                    module_maps,
                )
            if resolved and resolved != entry["path"]:
                depends_on.add(resolved)

        entry["depends_on"] = sorted(depends_on)
        entry["external_import_roots"] = sorted(
            {
                root
                for root in extract_external_import_roots(imports, package.crate_module_name)
                if root
            }
        )

    entry["key_facts"] = build_key_facts(entry)


def extract_summary(path: Path, text: str, kind: str) -> str:
    suffix = path.suffix.lower()
    summary = ""
    if suffix == ".rs":
        summary = extract_rust_doc_summary(text)
    elif suffix in {".py", ".ps1", ".sh", ".wgsl"}:
        summary = extract_comment_summary(text, suffix)

    if summary:
        return summary

    symbol_names = [symbol["name"] for symbol in extract_symbols(path, text)[:3]]
    if symbol_names:
        return f"{kind} containing {', '.join(symbol_names)}"
    return f"{kind} at {to_repo_relative(path)}"


def extract_rust_doc_summary(text: str) -> str:
    lines = text.splitlines()
    summary_lines: list[str] = []
    index = 0

    while index < len(lines) and (
        not lines[index].strip() or lines[index].lstrip().startswith("#!")
    ):
        index += 1

    while index < len(lines) and lines[index].lstrip().startswith("//!"):
        summary_lines.append(lines[index].split("//!", 1)[1].strip())
        index += 1

    if summary_lines:
        return collapse_summary(summary_lines)

    summary_lines = []
    for line in lines:
        stripped = line.lstrip()
        if stripped.startswith("///"):
            summary_lines.append(stripped.split("///", 1)[1].strip())
            continue
        if summary_lines:
            break
        if stripped and not stripped.startswith("#!") and not stripped.startswith("//"):
            break

    return collapse_summary(summary_lines)


def extract_comment_summary(text: str, suffix: str) -> str:
    prefixes = {
        ".py": "#",
        ".ps1": "#",
        ".sh": "#",
        ".wgsl": "//",
    }
    prefix = prefixes.get(suffix)
    if not prefix:
        return ""

    summary_lines: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            if summary_lines:
                break
            continue
        if stripped.startswith(prefix):
            summary_lines.append(stripped[len(prefix) :].strip())
            continue
        break
    return collapse_summary(summary_lines)


def collapse_summary(lines: list[str]) -> str:
    cleaned = [line for line in lines if line and not line.startswith("TODO")]
    if not cleaned:
        return ""
    summary = " ".join(cleaned)
    summary = re.sub(r"\s+", " ", summary).strip()
    if len(summary) > 220:
        return summary[:217].rstrip() + "..."
    return summary


def extract_symbols(path: Path, text: str) -> list[dict]:
    suffix = path.suffix.lower()
    symbols: list[dict] = []
    seen = set()

    if suffix == ".rs":
        for kind, pattern in RUST_SYMBOL_PATTERNS:
            for match in pattern.finditer(text):
                visibility = "pub" if match.group(1) else "private"
                name = match.group(2)
                key = (kind, name, visibility)
                if key in seen:
                    continue
                seen.add(key)
                symbols.append({"name": name, "kind": kind, "visibility": visibility})
        for name in extract_pub_use_symbols(text):
            key = ("reexport", name, "pub")
            if key in seen:
                continue
            seen.add(key)
            symbols.append({"name": name, "kind": "reexport", "visibility": "pub"})
    else:
        for kind, pattern in GENERIC_SYMBOL_PATTERNS.get(suffix, []):
            for match in pattern.finditer(text):
                name = match.group(1)
                key = (kind, name, "declared")
                if key in seen:
                    continue
                seen.add(key)
                symbols.append({"name": name, "kind": kind, "visibility": "declared"})

    symbols.sort(key=lambda symbol: (symbol["kind"], symbol["name"]))
    return symbols


def extract_pub_use_symbols(text: str) -> list[str]:
    names: list[str] = []
    for match in re.finditer(r"(?ms)^\s*pub\s+use\s+(.+?);", text):
        spec = match.group(1)
        alias_names = re.findall(r"\bas\s+([A-Za-z_][A-Za-z0-9_]*)", spec)
        if alias_names:
            names.extend(alias_names)
            continue
        for import_path in expand_use_tree(spec):
            leaf = import_path.split("::")[-1]
            if leaf and leaf not in {"self", "*"}:
                names.append(leaf)
    return names


def derive_tags(path: str, crate_name: str | None, kind: str, symbol_names: list[str]) -> list[str]:
    tags = set()
    if crate_name:
        tags.add(crate_name)
        tags.add(crate_name.replace("-", "_"))

    tags.add(kind)

    parts = [part.lower() for part in Path(path).parts]
    for part in parts:
        stem = Path(part).stem
        if stem in {"src", "crates", "tests", "examples", "benches"}:
            continue
        if stem.startswith("."):
            continue
        tags.add(stem)
        if stem in SPECIAL_TAGS:
            tags.add(SPECIAL_TAGS[stem])

    for symbol_name in symbol_names[:10]:
        lowered = symbol_name.lower()
        if lowered.endswith("renderer") or lowered.endswith("render"):
            tags.add("rendering")
        if lowered.endswith("panel") or lowered.endswith("view"):
            tags.add("ui")
        if "audio" in lowered:
            tags.add("audio")
        if "shader" in lowered:
            tags.add("shaders")
        if "module" in lowered:
            tags.add("modules")
        if "midi" in lowered:
            tags.add("midi")
        if "osc" in lowered:
            tags.add("osc")
        if "hue" in lowered:
            tags.add("lighting")

    return sorted(tag for tag in tags if tag)


def extract_rust_imports(text: str) -> list[str]:
    imports: list[str] = []
    for match in re.finditer(r"(?ms)^\s*(?:pub\s+)?use\s+(.+?);", text):
        imports.extend(expand_use_tree(match.group(1)))
    return sorted({value for value in imports if value})


def expand_use_tree(spec: str, prefix: str = "") -> list[str]:
    spec = re.sub(r"\s+as\s+[A-Za-z_][A-Za-z0-9_]*", "", spec)
    spec = re.sub(r"\s+", "", spec)
    if not spec:
        return []

    open_index = find_top_level_char(spec, "{")
    if open_index == -1:
        spec = spec.removesuffix("::*")
        if spec == "self":
            return [prefix[:-2]] if prefix.endswith("::") else ([prefix] if prefix else [])
        if not prefix:
            return [spec]
        return [prefix + spec]

    close_index = find_matching_brace(spec, open_index)
    base = spec[:open_index].rstrip(":")
    inner = spec[open_index + 1 : close_index]
    remainder = spec[close_index + 1 :]

    if base:
        if prefix:
            next_prefix = prefix + base + "::"
        else:
            next_prefix = base + "::"
    else:
        next_prefix = prefix

    values: list[str] = []
    for item in split_top_level(inner):
        if not item:
            continue
        if item == "self":
            if next_prefix.endswith("::"):
                values.append(next_prefix[:-2])
            elif next_prefix:
                values.append(next_prefix)
            continue
        values.extend(expand_use_tree(item + remainder, next_prefix))
    return values


def find_top_level_char(text: str, needle: str) -> int:
    depth = 0
    for index, char in enumerate(text):
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        elif char == needle and depth == 0:
            return index
    return -1


def find_matching_brace(text: str, open_index: int) -> int:
    depth = 0
    for index in range(open_index, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    raise ValueError(f"Unbalanced use tree: {text}")


def split_top_level(text: str, separator: str = ",") -> list[str]:
    parts: list[str] = []
    buffer: list[str] = []
    depth = 0
    for char in text:
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        if char == separator and depth == 0:
            parts.append("".join(buffer))
            buffer = []
            continue
        buffer.append(char)
    if buffer:
        parts.append("".join(buffer))
    return [part for part in (item.strip() for item in parts) if part]


def resolve_mod_dependencies(package: WorkspacePackage, entry_path: str, text: str) -> set[str]:
    dependencies = set()
    base_dir = rust_child_module_base_dir(package.root, Path(entry_path))
    if base_dir is None:
        return dependencies

    for match in re.finditer(r"^\s*(?:pub(?:\([^)]*\))?\s+)?mod\s+([A-Za-z_][A-Za-z0-9_]*)\s*;", text, re.MULTILINE):
        module_name = match.group(1)
        candidates = [
            base_dir / f"{module_name}.rs",
            base_dir / module_name / "mod.rs",
        ]
        for candidate in candidates:
            if candidate.exists():
                dependencies.add(to_repo_relative(candidate))
                break
    return dependencies


def rust_child_module_base_dir(crate_root: Path, relative_entry_path: Path) -> Path | None:
    absolute_entry_path = REPO_ROOT / relative_entry_path
    if not absolute_entry_path.exists():
        return None
    if absolute_entry_path.name == "build.rs":
        return None

    crate_relative = absolute_entry_path.relative_to(crate_root)
    if crate_relative.parts[0] != "src":
        return None

    if absolute_entry_path.name in {"lib.rs", "main.rs"}:
        return crate_root / "src"
    if absolute_entry_path.name == "mod.rs":
        return absolute_entry_path.parent
    return absolute_entry_path.with_suffix("")


def resolve_rust_import_path(
    import_path: str,
    current_module_components: tuple[str, ...],
    crate_module_name: str,
    module_map: dict[tuple[str, ...], str],
) -> str | None:
    if import_path == crate_module_name:
        return module_map.get(tuple())

    module_components = normalize_import_to_module_components(
        import_path,
        current_module_components,
        crate_module_name,
    )
    if module_components is None:
        return None

    for index in range(len(module_components), -1, -1):
        candidate = tuple(module_components[:index])
        if candidate in module_map:
            return module_map[candidate]
    return None


def resolve_cross_crate_import_path(
    import_path: str,
    current_crate_module_name: str,
    package_name_by_module: dict[str, str],
    module_maps: dict[str, dict[tuple[str, ...], str]],
) -> str | None:
    root = import_path.split("::", 1)[0]
    if root == current_crate_module_name:
        return None
    if root not in package_name_by_module:
        return None

    target_crate_name = package_name_by_module[root]
    target_module_map = module_maps.get(target_crate_name, {})
    if import_path == root:
        return target_module_map.get(tuple())

    prefix = f"{root}::"
    suffix = import_path[len(prefix) :] if import_path.startswith(prefix) else ""
    components = [part for part in suffix.split("::") if part]
    for index in range(len(components), -1, -1):
        candidate = tuple(components[:index])
        if candidate in target_module_map:
            return target_module_map[candidate]
    return None


def normalize_import_to_module_components(
    import_path: str,
    current_module_components: tuple[str, ...],
    crate_module_name: str,
) -> list[str] | None:
    if import_path.startswith("crate::"):
        return [part for part in import_path[len("crate::") :].split("::") if part]

    crate_prefix = f"{crate_module_name}::"
    if import_path.startswith(crate_prefix):
        return [part for part in import_path[len(crate_prefix) :].split("::") if part]

    if import_path == "self":
        return list(current_module_components)
    if import_path.startswith("self::"):
        suffix = [part for part in import_path[len("self::") :].split("::") if part]
        return [*current_module_components, *suffix]

    if import_path.startswith("super::"):
        remainder = import_path
        base = list(current_module_components)
        while remainder.startswith("super::"):
            remainder = remainder[len("super::") :]
            if base:
                base.pop()
        suffix = [part for part in remainder.split("::") if part]
        return [*base, *suffix]

    return None


def extract_external_import_roots(imports: Iterable[str], crate_module_name: str) -> set[str]:
    roots = set()
    ignored = {"crate", "self", "super", crate_module_name}
    for import_path in imports:
        root = import_path.split("::", 1)[0]
        if root not in ignored:
            roots.add(root)
    return roots


def build_key_facts(entry: dict) -> list[str]:
    facts = []
    if entry["crate"]:
        facts.append(f"crate: {entry['crate']}")
    if entry["module_path"]:
        facts.append(f"module: {entry['module_path']}")
    if entry["symbol_names"]:
        preview = ", ".join(entry["symbol_names"][:5])
        if len(entry["symbol_names"]) > 5:
            preview += ", ..."
        facts.append(f"symbols: {preview}")
    facts.append(f"local deps: {len(entry['depends_on'])}")
    facts.append(f"used by local files: {len(entry['used_by'])}")
    if entry["external_import_roots"]:
        preview = ", ".join(entry["external_import_roots"][:5])
        facts.append(f"external roots: {preview}")
    return facts


def backfill_used_by(entries: list[dict]) -> None:
    path_to_entry = {entry["path"]: entry for entry in entries}
    reverse_edges: dict[str, set[str]] = defaultdict(set)
    for entry in entries:
        for dependency in entry["depends_on"]:
            reverse_edges[dependency].add(entry["path"])

    for path, dependents in reverse_edges.items():
        if path in path_to_entry:
            path_to_entry[path]["used_by"] = sorted(dependents)
            path_to_entry[path]["key_facts"] = build_key_facts(path_to_entry[path])


def build_crate_entries(packages: list[WorkspacePackage], entries: list[dict]) -> list[dict]:
    files_by_crate: dict[str, list[dict]] = defaultdict(list)
    for entry in entries:
        if entry["crate"]:
            files_by_crate[entry["crate"]].append(entry)

    crate_entries = []
    for package in packages:
        crate_files = sorted(files_by_crate.get(package.name, []), key=lambda entry: entry["path"])
        crate_entry = {
            "name": package.name,
            "manifest_path": to_repo_relative(package.manifest_path),
            "root": to_repo_relative(package.root),
            "description": package.description,
            "crate_module_name": package.crate_module_name,
            "internal_dependencies": list(package.internal_dependencies),
            "file_count": len(crate_files),
            "source_files": [entry["path"] for entry in crate_files],
            "primary_tags": select_primary_tags(crate_files),
            "mermaid_path": f".agent/atlas/crates/{package.name}.mmd",
        }
        crate_entries.append(crate_entry)
    return crate_entries


def select_primary_tags(entries: Iterable[dict]) -> list[str]:
    counts: dict[str, int] = defaultdict(int)
    for entry in entries:
        for tag in entry["tags"]:
            counts[tag] += 1
    sorted_tags = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    return [tag for tag, _count in sorted_tags[:8]]


def build_lookup_indexes(files: list[dict], crates: list[dict]) -> dict:
    tag_to_files: dict[str, list[str]] = defaultdict(list)
    symbol_to_files: dict[str, list[str]] = defaultdict(list)
    crate_to_files: dict[str, list[str]] = defaultdict(list)

    for file_entry in files:
        for tag in file_entry["tags"]:
            tag_to_files[tag].append(file_entry["path"])
        for symbol_name in file_entry["symbol_names"]:
            symbol_to_files[symbol_name].append(file_entry["path"])
        if file_entry["crate"]:
            crate_to_files[file_entry["crate"]].append(file_entry["path"])

    return {
        "crates": {
            crate["name"]: crate["source_files"]
            for crate in crates
        },
        "tags": {tag: sorted(paths) for tag, paths in sorted(tag_to_files.items())},
        "symbols": {symbol: sorted(paths) for symbol, paths in sorted(symbol_to_files.items())},
        "crate_files": {crate: sorted(paths) for crate, paths in sorted(crate_to_files.items())},
    }


def write_workspace_mermaid(packages: list[WorkspacePackage], output_path: Path) -> None:
    lines = [
        "---",
        "title: VjMapper workspace atlas",
        "---",
        "flowchart LR",
    ]
    for package in packages:
        lines.append(f"    {mermaid_id(package.name)}[\"{package.name}\"]")
    if any(package.internal_dependencies for package in packages):
        lines.append("")
    for package in packages:
        for dependency in package.internal_dependencies:
            lines.append(f"    {mermaid_id(package.name)} --> {mermaid_id(dependency)}")
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_crate_mermaid(entries: list[dict], output_dir: Path) -> None:
    grouped: dict[str, list[dict]] = defaultdict(list)
    for entry in entries:
        if entry["crate"]:
            grouped[entry["crate"]].append(entry)

    for crate_name, crate_entries in grouped.items():
        lines = [
            "---",
            f"title: {crate_name} file atlas",
            "---",
            "flowchart LR",
        ]
        crate_root_prefix = f"{crate_entries[0]['crate_root']}/" if crate_entries and crate_entries[0].get("crate_root") else ""
        for entry in sorted(crate_entries, key=lambda value: value["path"]):
            node_id = mermaid_id(entry["path"])
            label = entry["path"].split(crate_root_prefix, 1)[-1] if crate_root_prefix else entry["path"]
            lines.append(f"    {node_id}[\"{label}\"]")

        edges = set()
        for entry in crate_entries:
            source_id = mermaid_id(entry["path"])
            for dependency in entry["depends_on"]:
                if not dependency.startswith(crate_root_prefix):
                    continue
                target_id = mermaid_id(dependency)
                edges.add((source_id, target_id))

        if edges:
            lines.append("")
            for source_id, target_id in sorted(edges):
                lines.append(f"    {source_id} --> {target_id}")

        (output_dir / f"{crate_name}.mmd").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_summary_markdown(files: list[dict], crates: list[dict], output_path: Path) -> None:
    lines = [
        "# Code Atlas Summary",
        "",
        f"- Crates indexed: {len(crates)}",
        f"- Files indexed: {len(files)}",
        "",
        "## Key Files",
        "",
    ]
    for file_entry in files[:20]:
        tags = ", ".join(file_entry["tags"][:5])
        lines.append(f"- `{file_entry['path']}`: {file_entry['summary']} ({tags})")

    lines.extend(
        [
            "",
            "## Usage",
            "",
            "- `python scripts/dev-tools/generate-code-atlas.py`",
            "- `python scripts/dev-tools/query-code-atlas.py \"crate:vorce-core tag:evaluation\"`",
            "- `python scripts/dev-tools/query-code-atlas.py \"symbol:ModuleEvaluator\" --json`",
            "",
        ]
    )
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def normalize_file_entry(entry: dict) -> dict:
    return {
        key: value
        for key, value in entry.items()
        if key != "text"
    }


def mermaid_id(value: str) -> str:
    sanitized = re.sub(r"[^A-Za-z0-9_]", "_", value)
    if not sanitized or sanitized[0].isdigit():
        sanitized = f"n_{sanitized}"
    return sanitized


def to_repo_relative(path: Path) -> str:
    return to_posix_path(path.resolve().relative_to(REPO_ROOT))


def to_posix_path(path: Path) -> str:
    return path.as_posix()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        print(exc.stderr or exc.stdout or str(exc), file=sys.stderr)
        raise
