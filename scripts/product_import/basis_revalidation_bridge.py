#!/usr/bin/env python3
"""Section F/G bridge for the Dart historical basis revalidation service.

Fetches exactly ONE product URL right now and reports its CURRENT basis/
nutrition/identity evidence as JSON on stdout. Deliberately reuses the
SAME, already-tested extraction pipeline scrape_products_from_web.py's
own single-URL mode uses (web_scraper.runner.scrape_product_page ->
web_scraper.extractors.extract_nutrition ->
web_scraper.nutrition_parser.detect_basis/build_nutrition) rather than a
second, divergent implementation — the basis remediation pass explicitly
requires reusing "the current existing Migros adapter", never
reimplementing it.

This script performs a LIVE, READ-ONLY GET request. It never writes
anything — not to product_staging, not to products, not to any file. The
caller (HistoricalBasisRevalidationService, via the Dart
MigrosBasisSourceFetcher bridge) is solely responsible for what happens
with the result: identity verification, nutrition consistency checks, and
any eventual write all happen in Dart, through the ordinary
ProductScoringLifecycleService write path.

Usage:
    python3 scripts/product_import/basis_revalidation_bridge.py <url> [--source-id migros]

Prints a single JSON object to stdout:
    {
      "ok": true,
      "adapter_version": "migros_basis_revalidation_bridge_v1",
      "fetched_at": "2026-08-16T12:00:00+00:00",
      "final_url": "...",
      "barcode": "...",                   // may be null
      "canonical_url_identifier": "...",  // may be null
      "raw_basis_text": "...",            // may be null
      "normalized_basis": "per_100g",     // per_100g/per_100ml/per_100_generic/per_serving/unknown
      "nutrition": {...}                  // canonical nutrition_json shape, may be {}
    }
or, when the fetch itself failed:
    {"ok": false, "error": "..."}
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

# Same pattern scrape_products_from_web.py uses: make scripts/product_import
# importable so the web_scraper package resolves regardless of CWD.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from web_scraper import extractors, nutrition_parser, runner  # noqa: E402
from web_scraper.base import Fetcher  # noqa: E402

ADAPTER_VERSION = "migros_basis_revalidation_bridge_v1"

# Mirrors the Migros URL shape already relied upon elsewhere in this
# package (e.g. "...-p-9ebe02") — kept local to this bridge script since it
# is inherently retailer-specific; a future A101/BIM bridge would extract
# its own retailer's canonical identifier the same way, behind the SAME
# BasisSourceFetcher Dart interface.
_MIGROS_PRODUCT_ID_RE = re.compile(r"-p-([a-z0-9]+)", re.IGNORECASE)


def _canonical_identifier(url: str) -> str | None:
    match = _MIGROS_PRODUCT_ID_RE.search(url)
    return match.group(1).lower() if match else None


def revalidate_one(url: str, source_id: str = "migros") -> dict:
    fetcher = Fetcher()
    result = fetcher.get(url)
    if not result.ok or not result.html:
        return {"ok": False, "error": result.error or "fetch_failed"}

    candidate, error = runner.scrape_product_page(fetcher, url, source_id=source_id)
    if candidate is None:
        return {"ok": False, "error": error or "extraction_failed"}

    soup = extractors.make_soup(result.html)
    nutri = extractors.extract_nutrition(soup)
    normalized_basis = (
        nutrition_parser.detect_basis(nutri["basis_text"])
        if nutri["basis_text"]
        else nutrition_parser.BASIS_UNKNOWN
    )

    final_url = result.final_url or url
    return {
        "ok": True,
        "adapter_version": ADAPTER_VERSION,
        "fetched_at": datetime.now(timezone.utc).isoformat(),
        "final_url": final_url,
        "barcode": candidate.get("barcode"),
        "canonical_url_identifier": _canonical_identifier(final_url),
        "raw_basis_text": nutri["basis_text"] or None,
        "normalized_basis": normalized_basis,
        "nutrition": candidate.get("nutrition_json") or {},
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url")
    parser.add_argument("--source-id", default="migros")
    args = parser.parse_args()

    try:
        result = revalidate_one(args.url, source_id=args.source_id)
    except Exception as exc:  # noqa: BLE001 - always report as JSON, never a raw traceback
        result = {"ok": False, "error": f"unexpected_error: {exc}"}

    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
