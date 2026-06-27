#!/usr/bin/env python3
"""
Stage products from a barcode list into product_staging (never products).

Input CSV columns (header required):
    barcode,name_hint,brand_hint,category_hint

For each barcode it queries Open Food Facts, normalizes the result into a
ProductCandidate, scores it, and upserts into product_staging.

Examples:
    python3 scripts/product_import/import_products_from_barcodes.py \\
        --input data/barcodes_turkey_seed.csv --source open_food_facts --dry-run

    python3 scripts/product_import/import_products_from_barcodes.py \\
        --input data/barcodes_turkey_seed.csv --source open_food_facts --real
"""
from __future__ import annotations

import csv
import sys
import argparse

import common


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
        barcode = (row.get("barcode") or "").strip()
        if not barcode:
            continue
        product = common.fetch_off_product(barcode)
        if product is None:
            # OFF had nothing — stage a minimal candidate from the hints so the
            # barcode is still visible in the review queue (low quality).
            candidate = common.make_candidate(
                barcode=barcode,
                name=row.get("name_hint"),
                brand=row.get("brand_hint"),
                source=args.source or "open_food_facts",
                category_suggestion=row.get("category_hint"),
            )
        else:
            candidate = common.candidate_from_off(
                product,
                name_hint=row.get("name_hint"),
                brand_hint=row.get("brand_hint"),
                category_hint=row.get("category_hint"),
            )
            if args.source:
                candidate["source"] = args.source
        candidates.append(candidate)

    sys.exit(common.run_import(args, candidates))


if __name__ == "__main__":
    main()
