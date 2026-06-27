#!/usr/bin/env python3
"""
Stage products from a manual CSV into product_staging (never products).

Input CSV columns (header required; most are optional):
    barcode,name,brand,category_suggestion,category_tags,ingredients_text,
    nutrition_json,image_front_url,image_ingredients_url,image_nutrition_url,
    source,source_url

- category_tags: comma- or pipe-separated, or a JSON array.
- nutrition_json: a JSON object string (normalized on import).

Examples:
    python3 scripts/product_import/import_products_from_csv.py \\
        --input data/manual_seed_products.example.csv --source manual_seed --dry-run

    python3 scripts/product_import/import_products_from_csv.py \\
        --input data/manual_seed_products.example.csv --source manual_seed --real
"""
from __future__ import annotations

import csv
import sys
import json
import argparse

import common


def parse_tags(raw: str | None) -> list[str] | None:
    if not raw:
        return None
    raw = raw.strip()
    if not raw:
        return None
    if raw.startswith("["):
        try:
            value = json.loads(raw)
            if isinstance(value, list):
                return [str(t).strip() for t in value if str(t).strip()]
        except json.JSONDecodeError:
            pass
    parts = [p.strip() for p in raw.replace("|", ",").split(",")]
    return [p for p in parts if p] or None


def parse_nutrition(raw: str | None) -> dict | None:
    if not raw or not raw.strip():
        return None
    try:
        value = json.loads(raw)
        return value if isinstance(value, dict) else None
    except json.JSONDecodeError:
        print(f"WARN: skipping invalid nutrition_json: {raw[:60]!r}", file=sys.stderr)
        return None


def load_rows(path: str) -> list[dict[str, str]]:
    try:
        with open(path, newline="", encoding="utf-8") as f:
            return list(csv.DictReader(f))
    except FileNotFoundError:
        print(f"ERROR: input file not found: {path}", file=sys.stderr)
        sys.exit(2)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    common.add_common_args(parser)
    args = parser.parse_args()

    rows = load_rows(args.input)
    candidates: list[dict] = []
    for row in rows:
        source = args.source or (row.get("source") or "").strip() or "manual_seed"
        candidate = common.make_candidate(
            barcode=row.get("barcode"),
            name=row.get("name"),
            brand=row.get("brand"),
            source=source,
            category_suggestion=row.get("category_suggestion"),
            category_tags=parse_tags(row.get("category_tags")),
            ingredients_text=row.get("ingredients_text"),
            nutrition_json=parse_nutrition(row.get("nutrition_json")),
            image_front_url=row.get("image_front_url"),
            image_ingredients_url=row.get("image_ingredients_url"),
            image_nutrition_url=row.get("image_nutrition_url"),
            source_url=row.get("source_url"),
        )
        candidates.append(candidate)

    sys.exit(common.run_import(args, candidates))


if __name__ == "__main__":
    main()
