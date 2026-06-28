#!/usr/bin/env python3
"""Read-only diagnostic: report products with suspicious or missing category_tags.

Detects:
  • Products whose name suggests a category that conflicts with their tags.
    Example: a product named "kruvasan" tagged as "meyve" (fruit).
  • Products with empty / null category_tags.
  • Products tagged with a combination that looks wrong (e.g. "meyve" + snack tags).

Never writes to the database.

Usage
-----
# Requires SUPABASE_URL and SUPABASE_SERVICE_KEY in the environment
# (or a .env file in the repo root). Never commit those files.
#
#   export SUPABASE_URL=...
#   export SUPABASE_SERVICE_KEY=...
#   python audit_suspicious_category_tags.py
#
#   # show per-tag sample products
#   python audit_suspicious_category_tags.py --examples 5
#
#   # emit JSON for scripted processing
#   python audit_suspicious_category_tags.py --json
#
#   # only check a subset (for quick smoke-tests)
#   python audit_suspicious_category_tags.py --limit 500
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from typing import Any


# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

def _load_env() -> None:
    try:
        from dotenv import load_dotenv  # type: ignore
        root = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
        env_path = os.path.join(root, ".env")
        if os.path.exists(env_path):
            load_dotenv(env_path)
    except ImportError:
        pass


def _require_env(key: str) -> str:
    v = os.environ.get(key, "").strip()
    if not v:
        sys.exit(
            f"ERROR: ${key} is not set. "
            "Add it to your shell environment or a .env file in the repo root."
        )
    return v


# ---------------------------------------------------------------------------
# Suspicious-tag rules
# ---------------------------------------------------------------------------

# (name_pattern, forbidden_tag, description)
_SUSPICIOUS_RULES: list[tuple[re.Pattern[str], str, str]] = [
    (re.compile(r"kruvasan|croissant|pastry", re.I), "meyve",     "Pastry product tagged as fruit"),
    (re.compile(r"kruvasan|croissant|pastry", re.I), "meyve_sebze","Pastry product tagged as fruit/veg"),
    (re.compile(r"gazoz|soda|gazlı|cola",     re.I), "meyve",     "Carbonated drink tagged as fruit"),
    (re.compile(r"gazoz|soda|gazlı|cola",     re.I), "meyve_sebze","Carbonated drink tagged as fruit/veg"),
    (re.compile(r"lokum",                     re.I), "meyve",     "Lokum (Turkish delight) tagged as fruit"),
    (re.compile(r"lokum",                     re.I), "meyve_sebze","Lokum tagged as fruit/veg"),
    (re.compile(r"çikolata|cikolata|chocolate|krema|fındık|findik", re.I),
                                                      "meyve",     "Chocolate/spread tagged as fruit"),
    (re.compile(r"çikolata|cikolata|chocolate|krema", re.I),
                                                      "meyve_sebze","Chocolate tagged as fruit/veg"),
    (re.compile(r"bisküvi|biskuvi|biscuit|kek|gofret", re.I),
                                                      "meyve",     "Biscuit/cake tagged as fruit"),
]

# Tags that should never appear in the same product as fruit/veg tags
_CONFLICTING_TAG_PAIRS: list[tuple[str, str, str]] = [
    ("meyve",     "atistirmalik",    "fruit + snack umbrella"),
    ("meyve",     "gazli_icecek",    "fruit + carbonated drink"),
    ("meyve",     "cikolata_gofret", "fruit + chocolate"),
    ("meyve",     "biskuvi_kek",     "fruit + biscuit/cake"),
    ("meyve",     "sekerleme",       "fruit + confectionery"),
    ("meyve_sebze","atistirmalik",   "fruit/veg + snack umbrella"),
    ("meyve_sebze","gazli_icecek",   "fruit/veg + carbonated drink"),
]


def _check_product(
    row: dict[str, Any],
) -> list[str]:
    """Return a list of suspicion reasons for this product (empty = clean)."""
    name  = (row.get("name") or "").strip()
    brand = (row.get("brand") or "").strip()
    tags  = set(row.get("category_tags") or [])
    reasons: list[str] = []

    for pattern, forbidden, desc in _SUSPICIOUS_RULES:
        if pattern.search(name) and forbidden in tags:
            reasons.append(desc)

    for tag_a, tag_b, desc in _CONFLICTING_TAG_PAIRS:
        if tag_a in tags and tag_b in tags:
            reasons.append(f"Conflicting tags ({desc})")

    return reasons


# ---------------------------------------------------------------------------
# Supabase fetch
# ---------------------------------------------------------------------------

def _fetch_products(
    url: str,
    key: str,
    limit: int | None,
) -> list[dict[str, Any]]:
    try:
        from supabase import create_client  # type: ignore
    except ImportError:
        sys.exit(
            "ERROR: supabase-py is not installed. "
            "Run: pip install supabase"
        )

    client = create_client(url, key)
    q = (
        client.table("products")
        .select("id,name,brand,category_tags")
        .order("name")
    )
    if limit:
        q = q.limit(limit)
    resp = q.execute()
    return resp.data or []


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    _load_env()

    parser = argparse.ArgumentParser(
        description="Read-only audit of suspicious category_tags in products."
    )
    parser.add_argument(
        "--limit", type=int, default=None,
        help="Cap the number of products fetched (default: all).",
    )
    parser.add_argument(
        "--examples", type=int, default=3,
        help="Number of example products to print per issue type (default: 3).",
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Emit machine-readable JSON.",
    )
    args = parser.parse_args()

    url = _require_env("SUPABASE_URL")
    key = _require_env("SUPABASE_SERVICE_KEY")

    print("Fetching products…", file=sys.stderr)
    products = _fetch_products(url, key, args.limit)
    print(f"Fetched {len(products)} products.", file=sys.stderr)

    suspicious: list[dict[str, Any]] = []
    empty_tags: list[dict[str, Any]] = []

    for row in products:
        tags = row.get("category_tags") or []
        if not tags:
            empty_tags.append(row)
            continue
        reasons = _check_product(row)
        if reasons:
            suspicious.append({
                "id":            row.get("id"),
                "name":          row.get("name"),
                "brand":         row.get("brand"),
                "category_tags": tags,
                "reasons":       reasons,
            })

    # Group suspicious by first reason for the summary
    by_reason: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for entry in suspicious:
        by_reason[entry["reasons"][0]].append(entry)

    if args.json:
        print(json.dumps({
            "fetched":                    len(products),
            "suspicious_count":           len(suspicious),
            "empty_category_tags_count":  len(empty_tags),
            "suspicious_by_reason":       {
                r: [
                    {k: v for k, v in e.items() if k != "reasons"}
                    for e in entries
                ]
                for r, entries in by_reason.items()
            },
            "empty_samples": [
                {"id": r["id"], "name": r["name"], "brand": r["brand"]}
                for r in empty_tags[: args.examples]
            ],
        }, ensure_ascii=False, indent=2))
        return

    print()
    print(f"Total products checked : {len(products)}")
    print(f"Suspicious tag count   : {len(suspicious)}")
    print(f"Empty category_tags    : {len(empty_tags)}")

    if suspicious:
        print()
        print("── Suspicious products ──────────────────────────────────────────")
        for reason, entries in sorted(by_reason.items()):
            print(f"\n  [{len(entries)}] {reason}")
            for entry in entries[: args.examples]:
                tags_str = ", ".join(entry["category_tags"])
                print(f"    • {entry['name']!r} ({entry['brand']}) → [{tags_str}]")

    if empty_tags:
        print()
        print(f"── Products with no category_tags ({len(empty_tags)} total) ───")
        for row in empty_tags[: args.examples]:
            print(f"    • {row['name']!r} ({row.get('brand')})")

    print()
    print("NOTE: This script is read-only. No changes were made to the database.")
    print("      To fix suspicious tags, use the admin pipeline or backfill script.")


if __name__ == "__main__":
    main()
