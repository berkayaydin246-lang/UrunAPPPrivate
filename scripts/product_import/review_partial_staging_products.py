#!/usr/bin/env python3
"""List product_staging rows that have enough identity data to be approved
but were skipped or remain pending only because nutrition or ingredients are
missing.

This script does NOT auto-approve anything. It prints rows that an admin can
review and approve manually via the admin panel or the CLI staging tools.

Usage:
  python3 review_partial_staging_products.py [--source web_scraper:migros] [--limit 200]

Requires SUPABASE_URL and SUPABASE_SERVICE_KEY in the environment or a
.env file in the project root.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

# Allow running from any directory.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    import requests
except ImportError:
    sys.exit("requests library not found — run: pip install requests")

try:
    import common
except ImportError:
    sys.exit(
        "Could not import common module. "
        "Run this script from scripts/product_import/ or its parent."
    )


_REVIEWABLE_STATUSES = ("pending", "needs_review")
_PAGE_SIZE = 1000


def _supabase_env() -> tuple[str, str]:
    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_KEY", "").strip()
    if not url or not key:
        # Try loading from project root .env
        try:
            env_path = os.path.join(
                os.path.dirname(__file__), "..", "..", ".env"
            )
            with open(env_path) as f:
                for line in f:
                    line = line.strip()
                    if "=" in line and not line.startswith("#"):
                        k, _, v = line.partition("=")
                        os.environ.setdefault(k.strip(), v.strip())
        except FileNotFoundError:
            pass
        url = os.environ.get("SUPABASE_URL", "").strip()
        key = os.environ.get("SUPABASE_SERVICE_KEY", "").strip()
    if not url or not key:
        sys.exit(
            "Missing SUPABASE_URL or SUPABASE_SERVICE_KEY. "
            "Set them in the environment or in a .env file."
        )
    return url, key


def _fetch_staging_page(
    base_url: str, key: str, *, source: str, offset: int, page_size: int
) -> list[dict]:
    select_fields = (
        "id,name,brand,source,source_url,barcode,"
        "image_front_url,ingredients_text,nutrition_json,"
        "quality_score,missing_fields,status,created_at,updated_at"
    )
    params = {
        "select": select_fields,
        "source": f"eq.{source}",
        "status": f"in.({','.join(_REVIEWABLE_STATUSES)})",
        "order": "created_at.asc",
        "limit": str(page_size),
        "offset": str(offset),
    }
    resp = requests.get(
        f"{base_url}/rest/v1/product_staging",
        headers=common._supabase_headers(key),
        params=params,
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()


def _has_minimum_identity(row: dict) -> bool:
    """True when the row has the minimum fields required for manual approval."""
    name = (row.get("name") or "").strip()
    source_url = (row.get("source_url") or "").strip()
    barcode = (row.get("barcode") or "").strip()
    return bool(name) and (bool(source_url) or bool(barcode))


def _has_useful_image(row: dict) -> bool:
    img = (row.get("image_front_url") or "").strip()
    return bool(img)


def _has_ingredients(row: dict) -> bool:
    text = (row.get("ingredients_text") or "").strip()
    return len(text) >= 20


def _has_nutrition(row: dict) -> bool:
    nj = row.get("nutrition_json")
    return bool(nj)


def _completeness_label(row: dict) -> str:
    has_img = _has_useful_image(row)
    has_ing = _has_ingredients(row)
    has_nut = _has_nutrition(row)
    if has_img and has_ing and has_nut:
        return "complete"
    if (row.get("name") or "").strip() and (row.get("source_url") or "").strip():
        if has_img and (has_ing or has_nut):
            return "partial"
        return "minimal"
    return "insufficient"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        default="web_scraper:migros",
        help="Staging source to review (default: web_scraper:migros)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=200,
        help="Max rows to display (default: 200)",
    )
    parser.add_argument(
        "--missing",
        choices=["nutrition", "ingredients", "both", "any"],
        default="any",
        help=(
            "Filter by which field is missing. "
            "'any' = nutrition OR ingredients missing (default). "
            "'both' = both missing. 'nutrition' or 'ingredients' = exactly that."
        ),
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="output_json",
        help="Output rows as JSON instead of human-readable table",
    )
    args = parser.parse_args()

    base_url, key = _supabase_env()

    print(f"Fetching {args.source} staging rows with status in {_REVIEWABLE_STATUSES} …")
    all_rows: list[dict] = []
    offset = 0
    while True:
        page = _fetch_staging_page(
            base_url, key, source=args.source, offset=offset, page_size=_PAGE_SIZE
        )
        all_rows.extend(page)
        if len(page) < _PAGE_SIZE:
            break
        offset += _PAGE_SIZE
    print(f"Total rows fetched: {len(all_rows)}")

    # Filter to rows that have minimum identity (approvable) but are missing
    # one or both of the recommended fields.
    candidates: list[dict] = []
    for row in all_rows:
        if not _has_minimum_identity(row):
            continue  # cannot be approved even with the relaxed rules

        has_ing = _has_ingredients(row)
        has_nut = _has_nutrition(row)

        include = False
        if args.missing == "any":
            include = not has_ing or not has_nut
        elif args.missing == "both":
            include = not has_ing and not has_nut
        elif args.missing == "nutrition":
            include = not has_nut
        elif args.missing == "ingredients":
            include = not has_ing

        if include:
            candidates.append(row)

    print(f"Approvable-but-partial rows: {len(candidates)}")

    if not candidates:
        print("Nothing to review — all approvable rows have complete data.")
        return

    displayed = candidates[: args.limit]
    if len(candidates) > args.limit:
        print(f"(Showing first {args.limit} of {len(candidates)} rows)")

    if args.output_json:
        print(json.dumps(displayed, ensure_ascii=False, indent=2))
        return

    # Human-readable output
    print()
    col_id = 36
    col_name = 40
    col_completeness = 12
    col_flags = 22

    header = (
        f"{'ID':<{col_id}}  "
        f"{'Name':<{col_name}}  "
        f"{'Level':<{col_completeness}}  "
        f"{'Missing':<{col_flags}}  "
        f"Status"
    )
    print(header)
    print("-" * len(header))

    for row in displayed:
        row_id = str(row.get("id") or "")[:col_id]
        name = str(row.get("name") or "")[:col_name]
        level = _completeness_label(row)
        has_ing = _has_ingredients(row)
        has_nut = _has_nutrition(row)
        has_img = _has_useful_image(row)
        flags = ", ".join(
            f
            for f, missing in [
                ("nutrition", not has_nut),
                ("ingredients", not has_ing),
                ("image", not has_img),
                ("brand", not (row.get("brand") or "").strip()),
                ("barcode", not (row.get("barcode") or "").strip()),
            ]
            if missing
        )
        status = str(row.get("status") or "")
        print(
            f"{row_id:<{col_id}}  "
            f"{name:<{col_name}}  "
            f"{level:<{col_completeness}}  "
            f"{flags:<{col_flags}}  "
            f"{status}"
        )

    print()
    print(
        "These rows can be approved manually via the admin panel.\n"
        "They were not auto-approved because optional fields (nutrition,\n"
        "ingredients) were missing — this is now allowed by the approval rules.\n"
        "Do NOT auto-approve rejected rows without admin review."
    )


if __name__ == "__main__":
    main()
