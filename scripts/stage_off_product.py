#!/usr/bin/env python3
"""
Stage a single Open Food Facts product into the product_staging table.

This is a developer/testing tool for the staging pipeline. It is NOT a bulk
importer and it NEVER writes to the `products` table.

Usage:
    # Inspect only — fetch, map, score, print. No DB write.
    python3 scripts/stage_off_product.py --barcode 8690526069906 --dry-run

    # Write the candidate to product_staging via Supabase REST.
    export SUPABASE_URL=https://your-project.supabase.co
    export SUPABASE_SERVICE_KEY=your-service-role-key
    python3 scripts/stage_off_product.py --barcode 8690526069906 --real

Requirements:
    pip install requests python-dotenv

Note:
    The authoritative mapping/scoring logic lives in Dart
    (OpenFoodFactsCandidateConnector + ProductCandidateQualityEvaluator).
    This script intentionally reimplements only a minimal subset for quick
    command-line testing. Keep heavy logic in Dart; do not grow this script
    into a parallel implementation.
"""
from __future__ import annotations

import os
import sys
import json
import argparse
from typing import Any

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

try:
    import requests
except ImportError:
    print(
        "ERROR: 'requests' package is required. Install with: pip install requests",
        file=sys.stderr,
    )
    sys.exit(1)

SOURCE = "open_food_facts"
# Human-facing product URL base (used for source_url display only).
OFF_BASE = "https://tr.openfoodfacts.org"

# API fetch endpoints. v2 (world) is preferred; v0 (world) is the fallback.
OFF_V2_URL = "https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
OFF_V0_URL = "https://world.openfoodfacts.org/api/v0/product/{barcode}.json"

OFF_FETCH_FIELDS = (
    "code,url,product_name,product_name_tr,product_name_en,"
    "abbreviated_product_name,abbreviated_product_name_tr,"
    "generic_name,generic_name_tr,brands,quantity,categories,"
    "categories_tags,nutriments,ingredients_text,ingredients_text_tr,"
    "ingredients_text_en,image_front_url,image_url,selected_images"
)

# Open Food Facts requires API clients to send a descriptive User-Agent,
# otherwise requests may be rejected with HTTP 403. Replace the contact email
# with a project address when one exists.
OFF_HEADERS = {
    "User-Agent": "FoodAnalyzerApp/0.1 (contact: dev@example.com)",
    "Accept": "application/json",
}

# Quality weights — must stay in sync with
# lib/features/product_staging/services/product_candidate_quality_evaluator.dart
_WEIGHTS = {
    "barcode": 15,
    "name": 15,
    "brand": 10,
    "front_image": 15,
    "ingredients": 25,
    "nutrition": 20,
    "category": 10,
}
_MIN_INGREDIENTS_LEN = 20

# OFF nutriment key → NutritionData.toMap key (per 100g/ml, dash variants).
_NUTRI_KEYS = {
    "energy_kcal": ["energy-kcal_100g", "energy-kcal_100ml", "energy-kcal"],
    "fat": ["fat_100g", "fat_100ml", "fat"],
    "saturated_fat": ["saturated-fat_100g", "saturated-fat_100ml", "saturated-fat"],
    "carbohydrates": ["carbohydrates_100g", "carbohydrates_100ml", "carbohydrates"],
    "sugars": ["sugars_100g", "sugars_100ml", "sugars"],
    "fiber": ["fiber_100g", "fiber_100ml", "fiber"],
    "proteins": ["proteins_100g", "proteins_100ml", "proteins"],
    "salt": ["salt_100g", "salt_100ml", "salt"],
    "sodium": ["sodium_100g", "sodium_100ml", "sodium"],
}


def _product_from_response(data: dict[str, Any]) -> dict[str, Any] | None:
    """Extract the product dict from an OFF API response, or None if not found.

    Handles both v0 (`status == 1`) and v2 (`status == "success"`) shapes by
    trusting the presence of a non-empty `product` object.
    """
    status = data.get("status")
    found = status in (1, "1", "success", "success_with_warnings")
    product = data.get("product")
    if found and isinstance(product, dict) and product:
        return product
    return None


def fetch_off_product(barcode: str) -> dict[str, Any] | None:
    """Fetch a product from Open Food Facts.

    Tries the v2 world endpoint first, then falls back to the v0 world endpoint
    when v2 returns 403/404/5xx (or a transport error). Returns the product
    dict, or None when OFF genuinely has no such product.

    On a hard HTTP failure (all endpoints fail) prints a friendly message and
    exits with a non-zero code instead of raising a traceback.
    """
    attempts = [
        (OFF_V2_URL.format(barcode=barcode), {"fields": OFF_FETCH_FIELDS}),
        (OFF_V0_URL.format(barcode=barcode), {"lc": "tr"}),
    ]

    last_status: object = "unknown"
    for url, params in attempts:
        try:
            resp = requests.get(
                url, params=params, headers=OFF_HEADERS, timeout=15
            )
        except requests.RequestException as exc:
            last_status = type(exc).__name__
            continue

        if resp.status_code == 200:
            try:
                return _product_from_response(resp.json())
            except ValueError:
                last_status = "invalid-json"
                continue

        last_status = resp.status_code
        # Retry the next endpoint on 403 / 404 / 5xx; stop on other 4xx.
        if resp.status_code in (403, 404) or resp.status_code >= 500:
            continue
        break

    print(
        f"Open Food Facts request failed: status={last_status}",
        file=sys.stderr,
    )
    sys.exit(3)


def pick_name(product: dict[str, Any]) -> str | None:
    for key in (
        "product_name_tr",
        "product_name",
        "generic_name_tr",
        "generic_name",
        "product_name_en",
    ):
        val = (product.get(key) or "").strip()
        if val:
            return val
    return None


def first_brand(product: dict[str, Any]) -> str | None:
    brands = (product.get("brands") or "").strip()
    if not brands:
        return None
    first = brands.split(",")[0].strip()
    return first or None


def pick_ingredients(product: dict[str, Any]) -> str | None:
    for key in ("ingredients_text_tr", "ingredients_text", "ingredients_text_en"):
        val = (product.get(key) or "").strip()
        if val:
            return val
    return None


def select_front_image(product: dict[str, Any]) -> str | None:
    display = (
        product.get("selected_images", {})
        .get("front", {})
        .get("display", {})
    )
    for locale in ("tr", "en"):
        val = (display.get(locale) or "").strip()
        if val:
            return val
    for val in display.values():
        if val and str(val).strip():
            return str(val).strip()
    for key in ("image_front_url", "image_url"):
        val = (product.get(key) or "").strip()
        if val:
            return val
    return None


def _num(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value.replace(",", "."))
        except ValueError:
            return None
    return None


def map_nutrition(product: dict[str, Any]) -> dict[str, Any]:
    nutriments = product.get("nutriments") or {}
    out: dict[str, Any] = {}
    for target, candidates in _NUTRI_KEYS.items():
        for key in candidates:
            val = _num(nutriments.get(key))
            if val is not None:
                out[target] = val
                break
    return out


def build_candidate(product: dict[str, Any]) -> dict[str, Any]:
    barcode = (product.get("code") or "").strip() or None
    name = pick_name(product)
    brand = first_brand(product)
    ingredients = pick_ingredients(product)
    image = select_front_image(product)
    nutrition = map_nutrition(product)
    category_suggestion = (product.get("categories") or "").strip() or None
    category_tags = [str(t) for t in (product.get("categories_tags") or [])] or None
    source_url = (product.get("url") or "").strip() or (
        f"{OFF_BASE}/product/{barcode}" if barcode else None
    )

    candidate: dict[str, Any] = {
        "barcode": barcode,
        "name": name,
        "brand": brand,
        "category_suggestion": category_suggestion,
        "category_tags": category_tags,
        "image_front_url": image,
        "ingredients_text": ingredients,
        "nutrition_json": nutrition or None,
        "source": SOURCE,
        "source_url": source_url,
        "raw_source_payload": product,
        "name_source": SOURCE if name else None,
        "brand_source": SOURCE if brand else None,
        "image_source": SOURCE if image else None,
        "ingredients_source": SOURCE if ingredients else None,
        "nutrition_source": SOURCE if nutrition else None,
        "category_source": SOURCE if (category_suggestion or category_tags) else None,
    }
    return candidate


def evaluate(candidate: dict[str, Any]) -> tuple[int, list[str], str]:
    score = 0
    missing: list[str] = []

    def has_text(v: Any) -> bool:
        return isinstance(v, str) and v.strip() != ""

    if has_text(candidate.get("barcode")):
        score += _WEIGHTS["barcode"]
    else:
        missing.append("barcode")

    if has_text(candidate.get("name")):
        score += _WEIGHTS["name"]
    else:
        missing.append("name")

    if has_text(candidate.get("brand")):
        score += _WEIGHTS["brand"]
    else:
        missing.append("brand")

    if has_text(candidate.get("image_front_url")):
        score += _WEIGHTS["front_image"]
    else:
        missing.append("front_image")

    ing = candidate.get("ingredients_text")
    if isinstance(ing, str) and len(ing.strip()) > _MIN_INGREDIENTS_LEN:
        score += _WEIGHTS["ingredients"]
    else:
        missing.append("ingredients")

    if candidate.get("nutrition_json"):
        score += _WEIGHTS["nutrition"]
    else:
        missing.append("nutrition")

    if has_text(candidate.get("category_suggestion")) or candidate.get("category_tags"):
        score += _WEIGHTS["category"]
    else:
        missing.append("category")

    score = min(score, 100)
    if score >= 75:
        status = "pending"
    elif score >= 45:
        status = "needs_review"
    else:
        status = "insufficient_data"
    return score, missing, status


def insert_staging(candidate: dict[str, Any], score: int, missing: list[str], status: str) -> None:
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_KEY", "")
    if not url or not key:
        print(
            "ERROR: SUPABASE_URL and SUPABASE_SERVICE_KEY must be set for --real.",
            file=sys.stderr,
        )
        sys.exit(1)

    payload = {k: v for k, v in candidate.items() if v is not None}
    payload["quality_score"] = score
    payload["missing_fields"] = missing
    payload["status"] = status

    resp = requests.post(
        f"{url}/rest/v1/product_staging",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
        json=payload,
        timeout=30,
    )
    resp.raise_for_status()
    rows = resp.json()
    staged_id = rows[0]["id"] if rows else "(unknown)"
    print(f"Staged into product_staging with id={staged_id}")


def print_summary(candidate: dict[str, Any], score: int, missing: list[str], status: str) -> None:
    nutrition = candidate.get("nutrition_json") or {}
    print("── ProductCandidate summary ──────────────────────────────")
    print(f"  barcode        : {candidate.get('barcode')}")
    print(f"  name           : {candidate.get('name')}")
    print(f"  brand          : {candidate.get('brand')}")
    print(f"  front image    : {'yes' if candidate.get('image_front_url') else 'no'}")
    ing = candidate.get("ingredients_text") or ""
    print(f"  ingredients    : {len(ing)} chars")
    print(f"  nutrition keys : {sorted(nutrition.keys())}")
    print(f"  category       : {candidate.get('category_suggestion')}")
    print(f"  source         : {candidate.get('source')}")
    print("──────────────────────────────────────────────────────────")
    print(f"  quality_score  : {score}")
    print(f"  missing_fields : {missing}")
    print(f"  status         : {status}")
    print("──────────────────────────────────────────────────────────")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Stage a single OFF product into product_staging."
    )
    parser.add_argument("--barcode", required=True, help="Product barcode")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--dry-run", action="store_true", help="Inspect only (default)")
    group.add_argument("--real", action="store_true", help="Write to product_staging")
    args = parser.parse_args()

    product = fetch_off_product(args.barcode)
    if product is None:
        print(f"No OFF product found for barcode {args.barcode}", file=sys.stderr)
        sys.exit(2)

    candidate = build_candidate(product)
    score, missing, status = evaluate(candidate)
    print_summary(candidate, score, missing, status)

    if args.real:
        insert_staging(candidate, score, missing, status)
    else:
        print("\nDry run — nothing written. Pass --real to stage this candidate.")


if __name__ == "__main__":
    main()
