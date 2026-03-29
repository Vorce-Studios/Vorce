#!/usr/bin/env python3
"""Query the generated code atlas with agent-friendly filters."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ATLAS = REPO_ROOT / ".agent" / "atlas" / "code-atlas.json"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("query", nargs="*", help="Query tokens like crate:vorce-core tag:ui ModuleEvaluator")
    parser.add_argument("--atlas", default=str(DEFAULT_ATLAS), help="Path to code-atlas.json")
    parser.add_argument("--json", action="store_true", help="Emit JSON results")
    parser.add_argument("--limit", type=int, default=20, help="Maximum number of rows to show")
    parser.add_argument("--stats", action="store_true", help="Print atlas stats instead of querying")
    args = parser.parse_args()

    atlas_path = Path(args.atlas).resolve()
    atlas = json.loads(atlas_path.read_text(encoding="utf-8"))

    if args.stats:
        return print_stats(atlas)

    query_tokens = normalize_query_tokens(args.query)
    if not query_tokens:
        parser.error("Provide at least one query token or use --stats.")

    filters, free_terms = parse_query_tokens(query_tokens)
    results = search_files(atlas["files"], filters, free_terms)
    results = results[: max(args.limit, 1)]

    if args.json:
        print(json.dumps(results, indent=2, ensure_ascii=True))
        return 0

    print(format_results(results, filters, free_terms))
    return 0


def print_stats(atlas: dict) -> int:
    print(f"schema_version: {atlas['schema_version']}")
    print(f"generated_at: {atlas.get('generated_at', 'deterministic')}")
    print(f"workspace_root: {atlas['workspace_root']}")
    print(f"crates: {atlas['workspace']['crate_count']}")
    print(f"files: {atlas['workspace']['file_count']}")
    return 0


def parse_query_tokens(tokens: list[str]) -> tuple[dict[str, list[str]], list[str]]:
    filters: dict[str, list[str]] = {}
    free_terms: list[str] = []
    for token in tokens:
        if ":" in token:
            field, value = token.split(":", 1)
            field = field.strip().lower()
            value = value.strip()
            if field and value:
                filters.setdefault(field, []).append(value)
            continue
        free_terms.append(token.strip())
    return filters, [term for term in free_terms if term]


def normalize_query_tokens(tokens: list[str]) -> list[str]:
    if len(tokens) == 1 and " " in tokens[0]:
        return [part for part in tokens[0].split() if part]
    return tokens


def search_files(files: list[dict], filters: dict[str, list[str]], free_terms: list[str]) -> list[dict]:
    matches = []
    for file_entry in files:
        if not matches_filters(file_entry, filters):
            continue
        score = score_entry(file_entry, free_terms)
        if free_terms and score == 0:
            continue
        result = dict(file_entry)
        result["_score"] = score
        matches.append(result)

    matches.sort(
        key=lambda entry: (
            -entry["_score"],
            entry["crate"] or "",
            entry["path"],
        )
    )
    return matches


def matches_filters(file_entry: dict, filters: dict[str, list[str]]) -> bool:
    for field, values in filters.items():
        for value in values:
            normalized = value.lower()
            if field == "crate":
                if (file_entry.get("crate") or "").lower() != normalized:
                    return False
            elif field == "tag":
                if normalized not in {tag.lower() for tag in file_entry.get("tags", [])}:
                    return False
            elif field == "symbol":
                if not any(
                    normalized == symbol.lower() or normalized in symbol.lower()
                    for symbol in file_entry.get("symbol_names", [])
                ):
                    return False
            elif field == "path":
                if normalized not in file_entry.get("path", "").lower():
                    return False
            elif field == "kind":
                if normalized != file_entry.get("kind", "").lower():
                    return False
            elif field == "module":
                if normalized not in (file_entry.get("module_path") or "").lower():
                    return False
            elif field == "depends-on":
                if not any(normalized in dependency.lower() for dependency in file_entry.get("depends_on", [])):
                    return False
            elif field == "used-by":
                if not any(normalized in dependency.lower() for dependency in file_entry.get("used_by", [])):
                    return False
            else:
                haystack = searchable_text(file_entry)
                if normalized not in haystack:
                    return False
    return True


def score_entry(file_entry: dict, free_terms: list[str]) -> int:
    if not free_terms:
        return 1

    score = 0
    searchable = searchable_text(file_entry)
    path = file_entry.get("path", "").lower()
    module_path = (file_entry.get("module_path") or "").lower()
    symbols = [symbol.lower() for symbol in file_entry.get("symbol_names", [])]
    tags = {tag.lower() for tag in file_entry.get("tags", [])}

    for term in free_terms:
        normalized = term.lower()
        if any(normalized == symbol or normalized in symbol for symbol in symbols):
            score += 6
        if normalized in tags:
            score += 4
        if normalized == (file_entry.get("crate") or "").lower():
            score += 5
        if normalized in module_path:
            score += 3
        if normalized in path:
            score += 2
        if normalized in searchable:
            score += 1
    return score


def searchable_text(file_entry: dict) -> str:
    fields = [
        file_entry.get("path", ""),
        file_entry.get("crate") or "",
        file_entry.get("kind", ""),
        file_entry.get("summary", ""),
        file_entry.get("module_path") or "",
        " ".join(file_entry.get("tags", [])),
        " ".join(file_entry.get("key_facts", [])),
        " ".join(file_entry.get("symbol_names", [])),
        " ".join(file_entry.get("depends_on", [])),
        " ".join(file_entry.get("used_by", [])),
    ]
    return " ".join(fields).lower()


def format_results(results: list[dict], filters: dict[str, list[str]], free_terms: list[str]) -> str:
    lines = []
    query_bits = [f"{key}:{','.join(values)}" for key, values in sorted(filters.items())]
    query_bits.extend(free_terms)
    lines.append(f"Query: {' '.join(query_bits)}")
    lines.append(f"Matches: {len(results)}")
    lines.append("")

    if not results:
        lines.append("Keine Treffer.")
        return "\n".join(lines)

    for index, entry in enumerate(results, start=1):
        symbol_preview = build_symbol_preview(entry, filters)
        lines.append(f"{index}. {entry['path']}")
        lines.append(
            f"   crate={entry.get('crate') or '-'} | kind={entry['kind']} | module={entry.get('module_path') or '-'}"
        )
        lines.append(f"   summary={entry['summary']}")
        lines.append(f"   tags={', '.join(entry.get('tags', [])[:8])}")
        lines.append(f"   symbols={symbol_preview}")
        lines.append(
            f"   depends_on={len(entry.get('depends_on', []))} | used_by={len(entry.get('used_by', []))}"
        )
        lines.append("")

    return "\n".join(lines).rstrip()


def build_symbol_preview(entry: dict, filters: dict[str, list[str]]) -> str:
    symbols = entry.get("symbol_names", [])
    if not symbols:
        return "-"

    query_symbols = [value.lower() for value in filters.get("symbol", [])]
    prioritized: list[str] = []
    if query_symbols:
        prioritized.extend(
            symbol
            for symbol in symbols
            if any(query == symbol.lower() or query in symbol.lower() for query in query_symbols)
        )

    for symbol in symbols:
        if symbol not in prioritized:
            prioritized.append(symbol)

    preview = prioritized[:8]
    return ", ".join(preview)


if __name__ == "__main__":
    raise SystemExit(main())
