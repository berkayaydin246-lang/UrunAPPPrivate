#!/usr/bin/env python3
"""Fix Migros product names without touching any other product fields.

Re-fetches only the product page title from Migros and updates
``products.name``, ``products.normalized_name``, ``products.search_keywords``,
and ``products.updated_at`` when the current stored name differs from the
cleaned page title.

It never modifies: ingredients, nutrition, image_url, category, barcode,
source, source_url, verification_status, or any analysis field.

Why og:title is used as the authoritative name source:
  Migros's JSON-LD ``name`` field often carries only the product-line name
  (e.g. "Dried Fruits Kuru İncir Büyük 150G") while the page's og:title
  carries the full branded string ("Otto Dried Fruits Kuru İncir Büyük 150G |
  Migros"). The retailer suffix is stripped by clean_title().
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import requests  # noqa: E402

import common  # noqa: E402
from web_scraper import extractors, runner  # noqa: E402
from web_scraper.base import Fetcher  # noqa: E402


PRODUCT_FIELDS = "id,name,brand,source,source_url,updated_at"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, default=100, help="Max products to inspect")
    parser.add_argument("--dry-run", action="store_true", help="Inspect only; write nothing")
    parser.add_argument("--real", action="store_true", help="Write updates to products")
    parser.add_argument(
        "--only-source-url",
        default=None,
        help="Process only the product with this exact Migros source_url",
    )
    parser.add_argument(
        "--sleep-seconds",
        type=float,
        default=0.3,
        help="Delay between HTTP requests to Migros",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=15.0,
        help="Per-request timeout when fetching Migros pages",
    )
    parser.add_argument(
        "--source",
        default="web_scraper:migros",
        help="products.source filter (default: web_scraper:migros)",
    )
    return parser.parse_args()


def normalize_name(text: str) -> str:
    """Lowercase + Turkish → ASCII + collapse spaces. Matches Dart toSearchable()."""
    tr = str.maketrans(
        "çğıöşüÇĞİÖŞÜ",
        "cgiosuCGIOSU",
    )
    return re.sub(r"\s+", " ", text.lower().translate(tr)).strip()


def build_name_patch(
    new_name: str,
    brand: str | None,
    *,
    now: datetime | None = None,
) -> dict:
    """Build the only allowed name-repair update payload."""
    effective_now = (now or datetime.now(timezone.utc)).isoformat()
    patch: dict = {
        "name": new_name,
        "normalized_name": normalize_name(new_name),
        "search_keywords": runner.build_search_keywords(new_name, brand),
        "updated_at": effective_now,
    }
    return patch


def fetch_target_products(
    base_url: str,
    key: str,
    *,
    source: str,
    limit: int,
    only_source_url: str | None = None,
) -> list[dict]:
    params: dict = {
        "select": PRODUCT_FIELDS,
        "source": f"eq.{source}",
        "order": "updated_at.desc",
    }
    if only_source_url:
        params["source_url"] = f"eq.{only_source_url}"
        params["limit"] = "1"
    else:
        params["limit"] = str(limit)
    resp = requests.get(
        f"{base_url}/rest/v1/products",
        headers=common._supabase_headers(key),
        params=params,
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()


def fetch_page_title(
    fetcher: Fetcher,
    source_url: str,
) -> str | None:
    """Fetch a Migros product page and return the cleaned og:title / HTML title."""
    result = fetcher.get(source_url)
    if not result.ok or not result.html:
        return None
    soup = extractors.make_soup(result.html)
    meta = extractors.extract_meta(soup)
    jsonld = extractors.extract_jsonld(soup)
    # og:title is preferred because it usually carries the full "Brand Product" string;
    # JSON-LD name often omits the brand prefix on Migros pages.
    raw = (
        meta.get("og_title") or meta.get("title")
        or jsonld.get("name")
    )
    return runner.clean_title(raw)


def apply_product_patch(
    base_url: str,
    key: str,
    product_id: str,
    patch: dict,
) -> None:
    resp = requests.patch(
        f"{base_url}/rest/v1/products",
        headers=common._supabase_headers(key),
        params={"id": f"eq.{product_id}"},
        json=patch,
        timeout=30,
    )
    resp.raise_for_status()


def main() -> int:
    args = parse_args()
    real = bool(args.real) and not args.dry_run
    base_url, key = common.load_supabase_env()
    rows = fetch_target_products(
        base_url,
        key,
        source=args.source,
        limit=args.limit,
        only_source_url=args.only_source_url,
    )

    if not rows:
        print("No matching products found.")
        return 0

    fetcher = Fetcher(delay=max(0.0, args.sleep_seconds), timeout=args.timeout)
    stats = {
        "checked": 0,
        "updated": 0,
        "skipped_same": 0,
        "skipped_no_source_url": 0,
        "skipped_no_title": 0,
        "failed": 0,
    }

    for row in rows:
        stats["checked"] += 1
        source_url = (row.get("source_url") or "").strip()
        if not source_url:
            stats["skipped_no_source_url"] += 1
            print(f"[skipped_no_source_url] product_id={row.get('id')} name={row.get('name')!r}")
            continue

        try:
            new_name = fetch_page_title(fetcher, source_url)
        except Exception as exc:  # noqa: BLE001
            stats["failed"] += 1
            print(
                f"[failed] product_id={row.get('id')} source_url={source_url} error={exc}",
                file=sys.stderr,
            )
            continue

        if not new_name:
            stats["skipped_no_title"] += 1
            print(f"[skipped_no_title] product_id={row.get('id')} source_url={source_url}")
            continue

        current_name = (row.get("name") or "").strip()
        if new_name == current_name:
            stats["skipped_same"] += 1
            continue

        patch = build_name_patch(
            new_name,
            row.get("brand"),
            now=datetime.now(timezone.utc),
        )

        print("[would_update_name]")
        print(f'old_name="{current_name}"')
        print(f'new_name="{new_name}"')
        print(f"product_id={row.get('id')}")
        print(f"source_url={source_url}")

        if not real:
            continue

        try:
            apply_product_patch(base_url, key, row["id"], patch)
            stats["updated"] += 1
            print("[updated_name]")
        except Exception as exc:  # noqa: BLE001
            stats["failed"] += 1
            print(
                f"[failed] product_id={row.get('id')} source_url={source_url} error={exc}",
                file=sys.stderr,
            )

    print("Stats: " + " ".join(f"{k}={v}" for k, v in stats.items()))
    if not real:
        print("Dry-run complete. Pass --real to write name updates.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
