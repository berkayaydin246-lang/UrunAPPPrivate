#!/usr/bin/env python3
"""Auto-reject product_staging rows that have BOTH missing ingredients AND
missing nutrition.

Products with neither field have no analyzable data (cannot support ingredient
analysis or nutrition queries) and should not reach the admin review queue.

This script is safe to run multiple times — it only sets status='rejected' on
matching rows that are still in reviewable statuses. It never touches approved
rows, never modifies product data fields, and never deletes any rows.

Usage:
  # Preview (no DB changes):
  python3 auto_reject_empty_info_staging_products.py \\
      --source web_scraper:migros --statuses pending,needs_review,inceleme --dry-run

  # Apply:
  python3 auto_reject_empty_info_staging_products.py \\
      --source web_scraper:migros --statuses pending,needs_review,inceleme --real

Requires SUPABASE_URL and SUPABASE_SERVICE_KEY in the environment or a
.env file in the project root.
"""
from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime, timezone

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

_AUTO_REJECT_NOTE = (
    "İçindekiler ve besin değerleri eksik olduğu için otomatik reddedildi."
)
_PAGE_SIZE = 1000


def _supabase_env() -> tuple[str, str]:
    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_KEY", "").strip()
    if not url or not key:
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


def _fetch_page(
    base_url: str,
    key: str,
    *,
    source: str,
    statuses: list[str],
    offset: int,
) -> list[dict]:
    params = {
        "select": "id,name,barcode,source,source_url,status,"
                  "ingredients_text,nutrition_json,admin_notes",
        "source": f"eq.{source}",
        "status": f"in.({','.join(statuses)})",
        "order": "created_at.asc",
        "limit": str(_PAGE_SIZE),
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


def _has_ingredients(row: dict) -> bool:
    text = (row.get("ingredients_text") or "").strip()
    return bool(text)


def _has_nutrition(row: dict) -> bool:
    nj = row.get("nutrition_json")
    if not nj:
        return False
    if isinstance(nj, dict):
        return bool(nj)
    return False


def _should_auto_reject(row: dict) -> bool:
    return not _has_ingredients(row) and not _has_nutrition(row)


def _reject_row(base_url: str, key: str, row_id: str) -> None:
    now = datetime.now(tz=timezone.utc).isoformat()
    payload = {
        "status": "rejected",
        "admin_notes": _AUTO_REJECT_NOTE,
        "updated_at": now,
    }
    resp = requests.patch(
        f"{base_url}/rest/v1/product_staging",
        headers={**common._supabase_headers(key), "Prefer": "return=minimal"},
        params={"id": f"eq.{row_id}"},
        json=payload,
        timeout=30,
    )
    resp.raise_for_status()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        default="web_scraper:migros",
        help="Staging source to scan (default: web_scraper:migros)",
    )
    parser.add_argument(
        "--statuses",
        default="pending,needs_review,inceleme",
        help="Comma-separated statuses to process "
             "(default: pending,needs_review,inceleme). "
             "'approved' is never included unless explicitly passed.",
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--dry-run",
        action="store_true",
        dest="dry_run",
        help="Preview matching rows without making any DB changes.",
    )
    mode.add_argument(
        "--real",
        action="store_true",
        dest="real",
        help="Update matching rows to rejected status.",
    )
    args = parser.parse_args()

    statuses = [s.strip() for s in args.statuses.split(",") if s.strip()]
    if "approved" in statuses:
        print(
            "WARNING: 'approved' is included in --statuses. "
            "Approved rows will NOT be modified — they are skipped automatically.",
            file=sys.stderr,
        )
        statuses = [s for s in statuses if s != "approved"]

    if not statuses:
        sys.exit("No valid statuses to process.")

    base_url, key = _supabase_env()

    print(f"Source:   {args.source}")
    print(f"Statuses: {statuses}")
    print(f"Mode:     {'DRY-RUN (no changes)' if args.dry_run else 'REAL (will update DB)'}")
    print()

    all_rows: list[dict] = []
    offset = 0
    while True:
        page = _fetch_page(
            base_url, key,
            source=args.source,
            statuses=statuses,
            offset=offset,
        )
        all_rows.extend(page)
        if len(page) < _PAGE_SIZE:
            break
        offset += _PAGE_SIZE

    print(f"Fetched {len(all_rows)} rows with status in {statuses}.")

    targets = [r for r in all_rows if _should_auto_reject(r)]
    print(f"Rows with BOTH ingredients and nutrition missing: {len(targets)}")

    if not targets:
        print("Nothing to reject.")
        return

    print()
    col_id = 36
    col_name = 40
    header = f"{'ID':<{col_id}}  {'Name':<{col_name}}  Status"
    print(header)
    print("-" * len(header))
    for row in targets[:50]:
        rid = str(row.get("id") or "")[:col_id]
        name = str(row.get("name") or "")[:col_name]
        status = str(row.get("status") or "")
        print(f"{rid:<{col_id}}  {name:<{col_name}}  {status}")
    if len(targets) > 50:
        print(f"  ... and {len(targets) - 50} more rows.")

    print()

    if args.dry_run:
        print(
            f"DRY-RUN: {len(targets)} row(s) would be set to rejected. "
            "Run with --real to apply."
        )
        return

    # Real mode: update each row.
    updated = 0
    failed = 0
    for row in targets:
        rid = row["id"]
        try:
            _reject_row(base_url, key, rid)
            updated += 1
        except Exception as exc:
            print(f"  ERROR rejecting {rid}: {exc}", file=sys.stderr)
            failed += 1

    print(f"Done. Updated: {updated}  Failed: {failed}")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
