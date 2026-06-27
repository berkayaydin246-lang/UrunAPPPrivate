#!/usr/bin/env python3
"""
Stage products from a JSON file into product_staging (never products).

Input: a JSON array of objects, each with ProductCandidate-style fields:
    barcode, name, brand, category_suggestion, category_tags (list),
    ingredients_text, nutrition_json (object), image_front_url,
    image_ingredients_url, image_nutrition_url, source, source_url

Examples:
    python3 scripts/product_import/import_products_from_json.py \\
        --input data/manual_seed_products.example.json --source manual_seed --dry-run

    python3 scripts/product_import/import_products_from_json.py \\
        --input data/manual_seed_products.example.json --source manual_seed --real
"""
from __future__ import annotations

import sys
import json
import argparse

import common


def load_objects(path: str) -> list[dict]:
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"ERROR: input file not found: {path}", file=sys.stderr)
        sys.exit(2)
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid JSON in {path}: {exc}", file=sys.stderr)
        sys.exit(2)

    if isinstance(data, dict):
        data = [data]
    if not isinstance(data, list):
        print("ERROR: JSON root must be an array (or a single object).", file=sys.stderr)
        sys.exit(2)
    return [obj for obj in data if isinstance(obj, dict)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    common.add_common_args(parser)
    args = parser.parse_args()

    objects = load_objects(args.input)
    candidates: list[dict] = []
    for obj in objects:
        source = args.source or (obj.get("source") or "").strip() or "manual_seed"
        tags = obj.get("category_tags")
        if tags is not None and not isinstance(tags, list):
            tags = None
        nutrition = obj.get("nutrition_json")
        if nutrition is not None and not isinstance(nutrition, dict):
            nutrition = None
        candidate = common.make_candidate(
            barcode=obj.get("barcode"),
            name=obj.get("name"),
            brand=obj.get("brand"),
            source=source,
            category_suggestion=obj.get("category_suggestion"),
            category_tags=tags,
            ingredients_text=obj.get("ingredients_text"),
            nutrition_json=nutrition,
            image_front_url=obj.get("image_front_url"),
            image_ingredients_url=obj.get("image_ingredients_url"),
            image_nutrition_url=obj.get("image_nutrition_url"),
            source_url=obj.get("source_url"),
        )
        candidates.append(candidate)

    sys.exit(common.run_import(args, candidates))


if __name__ == "__main__":
    main()
