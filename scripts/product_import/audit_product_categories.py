#!/usr/bin/env python3
"""Read-only audit of the category_tags distribution in the products table.

Connects to Supabase using SUPABASE_URL + SUPABASE_SERVICE_KEY from the
environment (or a .env file in the repo root).  Never writes anything.

Usage examples
--------------
# Show all tags found in the DB with product counts:
python audit_product_categories.py

# Limit to products from the Migros web scraper:
python audit_product_categories.py --source web_scraper:migros

# Show 5 example products per tag, emit JSON:
python audit_product_categories.py --examples-per-tag 5 --json

# Show only the first 1000 products (useful for quick smoke-tests):
python audit_product_categories.py --limit 1000

Flags
-----
--source TEXT        Filter by `source` column substring (e.g. 'migros').
--limit N            Cap the number of products fetched from Supabase.
--examples-per-tag N Print N product name/brand examples per tag (default 0).
--json               Emit machine-readable JSON instead of human text.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from typing import Any

# ---------------------------------------------------------------------------
# Environment setup
# ---------------------------------------------------------------------------

def _load_env() -> None:
    """Load .env from the repo root if python-dotenv is available."""
    try:
        from dotenv import load_dotenv  # type: ignore
        root = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
        env_path = os.path.join(root, ".env")
        if os.path.exists(env_path):
            load_dotenv(env_path)
    except ImportError:
        pass


def _require_env(key: str) -> str:
    value = os.environ.get(key, "").strip()
    if not value:
        sys.exit(
            f"ERROR: ${key} is not set.  "
            "Add it to your shell environment or a .env file in the repo root."
        )
    return value


# ---------------------------------------------------------------------------
# Supabase helpers (read-only, no supabase-py required — uses raw HTTP)
# ---------------------------------------------------------------------------

def _fetch_products(
    url: str,
    key: str,
    *,
    source_filter: str | None,
    limit: int | None,
) -> list[dict[str, Any]]:
    """Fetch name, brand, source, category_tags from products (read-only)."""
    try:
        import urllib.request
        import urllib.parse
    except ImportError as exc:
        sys.exit(f"ERROR: urllib not available: {exc}")

    select = "name,brand,source,category_tags"
    params: dict[str, str] = {"select": select, "order": "name"}

    if source_filter:
        params["source"] = f"ilike.*{source_filter}*"
    if limit:
        params["limit"] = str(limit)

    qs = "&".join(f"{k}={urllib.parse.quote(str(v), safe='=*.,')}" for k, v in params.items())
    endpoint = f"{url.rstrip('/')}/rest/v1/products?{qs}"

    req = urllib.request.Request(
        endpoint,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
            "Prefer": "count=none",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
            if not isinstance(data, list):
                sys.exit(f"ERROR: unexpected response shape: {data!r}")
            return data
    except Exception as exc:
        sys.exit(f"ERROR: Supabase request failed: {exc}")


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------

def _analyse(
    products: list[dict[str, Any]],
    examples_per_tag: int,
) -> dict[str, Any]:
    tag_counts: dict[str, int] = defaultdict(int)
    tag_examples: dict[str, list[str]] = defaultdict(list)
    no_tag_count = 0
    null_tags_count = 0

    for p in products:
        raw = p.get("category_tags")
        if raw is None:
            null_tags_count += 1
            continue
        if not raw:
            no_tag_count += 1
            continue
        name = (p.get("name") or "").strip()
        brand = (p.get("brand") or "").strip()
        label = f"{name} ({brand})" if brand else name

        for tag in raw:
            tag_counts[tag] += 1
            if len(tag_examples[tag]) < examples_per_tag:
                tag_examples[tag].append(label)

    sorted_tags = sorted(tag_counts.items(), key=lambda kv: (-kv[1], kv[0]))

    return {
        "total_products": len(products),
        "products_with_no_tags": no_tag_count,
        "products_with_null_tags": null_tags_count,
        "unique_tags": len(tag_counts),
        "tags": [
            {
                "tag": tag,
                "count": count,
                **({"examples": tag_examples[tag]} if examples_per_tag else {}),
            }
            for tag, count in sorted_tags
        ],
    }


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def _print_text(result: dict[str, Any]) -> None:
    print(f"Total products fetched : {result['total_products']}")
    print(f"With null category_tags: {result['products_with_null_tags']}")
    print(f"With empty category_tags: {result['products_with_no_tags']}")
    print(f"Unique tags found      : {result['unique_tags']}")
    print()
    print(f"{'TAG':<35} {'COUNT':>6}")
    print("-" * 44)
    for entry in result["tags"]:
        print(f"  {entry['tag']:<33} {entry['count']:>6}")
        for ex in entry.get("examples", []):
            print(f"    • {ex}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    _load_env()

    parser = argparse.ArgumentParser(
        description="Read-only audit of category_tags in the products table."
    )
    parser.add_argument(
        "--source",
        default=None,
        help="Filter products by source column substring (e.g. 'migros').",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Maximum number of products to fetch.",
    )
    parser.add_argument(
        "--examples-per-tag",
        type=int,
        default=0,
        dest="examples_per_tag",
        help="Print N product name+brand examples per tag (default 0).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="as_json",
        help="Emit machine-readable JSON output.",
    )
    args = parser.parse_args()

    supabase_url = _require_env("SUPABASE_URL")
    service_key = _require_env("SUPABASE_SERVICE_KEY")

    print(
        f"Fetching products from {supabase_url} "
        f"(source={args.source or 'all'}, limit={args.limit or 'none'})…",
        file=sys.stderr,
    )

    products = _fetch_products(
        supabase_url,
        service_key,
        source_filter=args.source,
        limit=args.limit,
    )

    print(f"Fetched {len(products)} products.", file=sys.stderr)

    result = _analyse(products, examples_per_tag=args.examples_per_tag)

    if args.as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        _print_text(result)


if __name__ == "__main__":
    main()
