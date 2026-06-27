#!/usr/bin/env python3
"""
Shared logic for the product seeding/import pipeline.

Every candidate produced here is written to `product_staging` ONLY — never to
`products`. Admin review (the existing staging admin UI) is what promotes a
staged row into the final products catalog.

This module mirrors the Dart ProductCandidateQualityEvaluator scoring intent in
Python so command-line imports score candidates the same way. Keep the heavy
canonical logic in Dart; this file is the import-time helper.
"""
from __future__ import annotations

import os
import re
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

# ── Constants ────────────────────────────────────────────────────────────────

VALID_SOURCES = {"manual_seed", "open_food_facts", "future_source"}

# Quality weights (sum = 100). Mirrors the Dart evaluator field set.
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

# Status thresholds (Part 6 of the seeding spec).
_PENDING_THRESHOLD = 70
_NEEDS_REVIEW_THRESHOLD = 40

# Open Food Facts (reuses the same approach as scripts/stage_off_product.py).
OFF_V2_URL = "https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
OFF_V0_URL = "https://world.openfoodfacts.org/api/v0/product/{barcode}.json"
OFF_FETCH_FIELDS = (
    "code,url,product_name,product_name_tr,product_name_en,"
    "abbreviated_product_name,abbreviated_product_name_tr,"
    "generic_name,generic_name_tr,brands,quantity,categories,"
    "categories_tags,nutriments,ingredients_text,ingredients_text_tr,"
    "ingredients_text_en,image_front_url,image_url,selected_images"
)
OFF_HEADERS = {
    "User-Agent": "FoodAnalyzerApp/0.1 (contact: dev@example.com)",
    "Accept": "application/json",
}

# Normalized nutrition keys stored in nutrition_json.
_NUTRITION_FIELDS = [
    "energy_kcal",
    "fat",
    "saturated_fat",
    "carbohydrates",
    "sugars",
    "fiber",
    "proteins",
    "salt",
    "sodium",
]

# Accepted source keys → normalized field. Covers OFF dash keys + common CSV keys.
_NUTRITION_ALIASES: dict[str, list[str]] = {
    "energy_kcal": [
        "energy_kcal", "energy_kcal_100g", "kcal_100g", "calories_100g",
        "energy-kcal_100g", "energy-kcal_100ml", "energy-kcal",
    ],
    "fat": ["fat", "fat_100g", "fat_100ml"],
    "saturated_fat": [
        "saturated_fat", "saturated_fat_100g", "saturated-fat_100g",
        "saturated-fat_100ml", "saturated-fat",
    ],
    "carbohydrates": ["carbohydrates", "carbohydrates_100g", "carbohydrates_100ml"],
    "sugars": ["sugars", "sugars_100g", "sugars_100ml"],
    "fiber": ["fiber", "fiber_100g", "fiber_100ml"],
    "proteins": ["proteins", "proteins_100g", "proteins_100ml"],
    "salt": ["salt", "salt_100g", "salt_100ml"],
    "sodium": ["sodium", "sodium_100g", "sodium_100ml"],
}


# ── Environment ──────────────────────────────────────────────────────────────

def load_supabase_env() -> tuple[str, str]:
    """Return (SUPABASE_URL, SUPABASE_SERVICE_KEY) or exit with a clear message."""
    url = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_KEY", "").strip()
    if not url or not key:
        print(
            "ERROR: SUPABASE_URL and SUPABASE_SERVICE_KEY must be set "
            "(export them or put them in .env).\n"
            "       Never commit the service key or ship it in the Flutter app.",
            file=sys.stderr,
        )
        sys.exit(2)
    return url, key


def _supabase_headers(key: str, *, prefer: str = "return=representation") -> dict[str, str]:
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": prefer,
    }


# ── Nutrition normalization (Part 4) ─────────────────────────────────────────

def _to_float(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        v = value.strip().replace(",", ".")
        if not v:
            return None
        try:
            return float(v.split()[0])
        except ValueError:
            return None
    return None


def normalize_nutrition(raw: dict[str, Any] | None) -> dict[str, Any]:
    """Normalize a raw nutrition map into the project's nutrition_json shape.

    Maps common per-100g / OFF dash keys onto canonical fields, and derives
    salt from sodium when salt is absent (salt = sodium * 2.5).
    """
    if not raw or not isinstance(raw, dict):
        return {}
    out: dict[str, Any] = {}
    for field, aliases in _NUTRITION_ALIASES.items():
        for key in aliases:
            val = _to_float(raw.get(key))
            if val is not None:
                out[field] = val
                break
    # Derive salt from sodium when missing (sodium grams * 2.5).
    if "salt" not in out and "sodium" in out:
        out["salt"] = round(out["sodium"] * 2.5, 4)
    return out


# ── Ingredients normalization (Part 5) ───────────────────────────────────────

def clean_ingredients(text: str | None) -> str | None:
    """Collapse whitespace and trim. Preserves Turkish characters; no parsing."""
    if not text:
        return None
    cleaned = re.sub(r"\s+", " ", str(text)).strip()
    return cleaned or None


# ── Quality scoring (Part 6) ─────────────────────────────────────────────────

def _has_text(value: Any) -> bool:
    return isinstance(value, str) and value.strip() != ""


def evaluate_quality(candidate: dict[str, Any]) -> tuple[int, list[str], str]:
    """Return (quality_score, missing_fields, suggested_status)."""
    score = 0
    missing: list[str] = []

    if _has_text(candidate.get("barcode")):
        score += _WEIGHTS["barcode"]
    else:
        missing.append("barcode")

    if _has_text(candidate.get("name")):
        score += _WEIGHTS["name"]
    else:
        missing.append("name")

    if _has_text(candidate.get("brand")):
        score += _WEIGHTS["brand"]
    else:
        missing.append("brand")

    if _has_text(candidate.get("image_front_url")) or _has_text(
        candidate.get("image_front_storage_path")
    ):
        score += _WEIGHTS["front_image"]
    else:
        missing.append("front_image")

    ing = candidate.get("ingredients_text")
    if isinstance(ing, str) and len(ing.strip()) > _MIN_INGREDIENTS_LEN:
        score += _WEIGHTS["ingredients"]
    else:
        missing.append("ingredients")

    if isinstance(candidate.get("nutrition_json"), dict) and candidate["nutrition_json"]:
        score += _WEIGHTS["nutrition"]
    else:
        missing.append("nutrition")

    if _has_text(candidate.get("category_suggestion")) or candidate.get("category_tags"):
        score += _WEIGHTS["category"]
    else:
        missing.append("category")

    score = min(score, 100)
    if score >= _PENDING_THRESHOLD:
        status = "pending"
    elif score >= _NEEDS_REVIEW_THRESHOLD:
        status = "needs_review"
    else:
        status = "insufficient_data"
    return score, missing, status


# ── Validation (Part 12) ─────────────────────────────────────────────────────

def validate_candidate(candidate: dict[str, Any]) -> list[str]:
    """Return a list of validation errors (empty when valid)."""
    errors: list[str] = []

    barcode = (candidate.get("barcode") or "").strip()
    if not barcode:
        errors.append("barcode is required")
    elif not re.fullmatch(r"\d{8,14}", barcode):
        errors.append(f"barcode must be 8-14 digits, got {barcode!r}")

    source = (candidate.get("source") or "").strip()
    if not source:
        errors.append("source is required")
    elif source not in VALID_SOURCES:
        errors.append(f"source must be one of {sorted(VALID_SOURCES)}, got {source!r}")

    nutrition = candidate.get("nutrition_json")
    if nutrition is not None and not isinstance(nutrition, dict):
        errors.append("nutrition_json must be a JSON object")

    tags = candidate.get("category_tags")
    if tags is not None and not isinstance(tags, list):
        errors.append("category_tags must be a list")

    return errors


# ── Candidate building ───────────────────────────────────────────────────────

def make_candidate(
    *,
    barcode: str | None,
    name: str | None,
    brand: str | None,
    source: str,
    category_suggestion: str | None = None,
    category_tags: list[str] | None = None,
    ingredients_text: str | None = None,
    nutrition_json: dict[str, Any] | None = None,
    image_front_url: str | None = None,
    image_front_storage_path: str | None = None,
    image_ingredients_url: str | None = None,
    image_nutrition_url: str | None = None,
    source_url: str | None = None,
    raw_source_payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Build a normalized candidate dict ready for staging."""
    candidate = {
        "barcode": (barcode or "").strip() or None,
        "name": (name or "").strip() or None,
        "brand": (brand or "").strip() or None,
        "category_suggestion": (category_suggestion or "").strip() or None,
        "category_tags": category_tags or None,
        "ingredients_text": clean_ingredients(ingredients_text),
        "nutrition_json": normalize_nutrition(nutrition_json) or None,
        "image_front_url": (image_front_url or "").strip() or None,
        "image_front_storage_path": (image_front_storage_path or "").strip() or None,
        "image_ingredients_url": (image_ingredients_url or "").strip() or None,
        "image_nutrition_url": (image_nutrition_url or "").strip() or None,
        "source": source,
        "source_url": (source_url or "").strip() or None,
        "raw_source_payload": raw_source_payload,
        # Field-level provenance.
        "name_source": source if (name or "").strip() else None,
        "brand_source": source if (brand or "").strip() else None,
        "image_source": source if (image_front_url or "").strip() else None,
        "ingredients_source": source if (ingredients_text or "").strip() else None,
        "nutrition_source": source if nutrition_json else None,
        "category_source": source if (category_suggestion or category_tags) else None,
    }
    return candidate


# ── Open Food Facts source (Part 2) ──────────────────────────────────────────

def _off_product_from_response(data: dict[str, Any]) -> dict[str, Any] | None:
    status = data.get("status")
    found = status in (1, "1", "success", "success_with_warnings")
    product = data.get("product")
    if found and isinstance(product, dict) and product:
        return product
    return None


def fetch_off_product(barcode: str) -> dict[str, Any] | None:
    """Fetch one OFF product (v2 world, fallback v0). None when not found.

    Returns None on transport/HTTP errors too (so a bad barcode doesn't abort a
    whole batch import).
    """
    attempts = [
        (OFF_V2_URL.format(barcode=barcode), {"fields": OFF_FETCH_FIELDS}),
        (OFF_V0_URL.format(barcode=barcode), {"lc": "tr"}),
    ]
    for url, params in attempts:
        try:
            resp = requests.get(url, params=params, headers=OFF_HEADERS, timeout=15)
        except requests.RequestException:
            continue
        if resp.status_code == 200:
            try:
                product = _off_product_from_response(resp.json())
            except ValueError:
                continue
            if product is not None:
                return product
            continue
        if resp.status_code in (403, 404) or resp.status_code >= 500:
            continue
        break
    return None


def _off_pick(product: dict[str, Any], keys: list[str]) -> str | None:
    for key in keys:
        val = (product.get(key) or "").strip()
        if val:
            return val
    return None


def _off_select_front_image(product: dict[str, Any]) -> str | None:
    display = product.get("selected_images", {}).get("front", {}).get("display", {})
    for locale in ("tr", "en"):
        val = (display.get(locale) or "").strip()
        if val:
            return val
    for val in display.values():
        if val and str(val).strip():
            return str(val).strip()
    return _off_pick(product, ["image_front_url", "image_url"])


def candidate_from_off(
    product: dict[str, Any],
    *,
    name_hint: str | None = None,
    brand_hint: str | None = None,
    category_hint: str | None = None,
) -> dict[str, Any]:
    """Map a raw OFF product dict into a normalized candidate (source=open_food_facts)."""
    barcode = (product.get("code") or "").strip() or None
    name = _off_pick(
        product,
        ["product_name_tr", "product_name", "generic_name_tr", "generic_name",
         "product_name_en"],
    ) or name_hint
    brands = (product.get("brands") or "").strip()
    brand = (brands.split(",")[0].strip() if brands else None) or brand_hint
    ingredients = _off_pick(
        product, ["ingredients_text_tr", "ingredients_text", "ingredients_text_en"]
    )
    category_suggestion = (product.get("categories") or "").strip() or category_hint
    category_tags = [str(t) for t in (product.get("categories_tags") or [])] or None
    source_url = (product.get("url") or "").strip() or (
        f"https://world.openfoodfacts.org/product/{barcode}" if barcode else None
    )

    return make_candidate(
        barcode=barcode,
        name=name,
        brand=brand,
        source="open_food_facts",
        category_suggestion=category_suggestion,
        category_tags=category_tags,
        ingredients_text=ingredients,
        nutrition_json=product.get("nutriments"),
        image_front_url=_off_select_front_image(product),
        source_url=source_url,
        raw_source_payload=product,
    )


# ── Supabase staging upsert (Parts 3 & 7) ────────────────────────────────────

def _fetch_existing(url: str, key: str, barcode: str, source: str) -> dict[str, Any] | None:
    """Find an existing staging row for (barcode, source)."""
    resp = requests.get(
        f"{url}/rest/v1/product_staging",
        headers=_supabase_headers(key),
        params={
            "select": "*",
            "barcode": f"eq.{barcode}",
            "source": f"eq.{source}",
            "limit": "1",
        },
        timeout=30,
    )
    resp.raise_for_status()
    rows = resp.json()
    return rows[0] if rows else None


def _scored_payload(
    candidate: dict[str, Any],
) -> tuple[dict[str, Any], int, list[str], str]:
    score, missing, status = evaluate_quality(candidate)
    payload = {k: v for k, v in candidate.items() if v is not None}
    payload["quality_score"] = score
    payload["missing_fields"] = missing
    payload["status"] = status
    return payload, score, missing, status


def _merge_fill_missing(existing: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    """Fill only fields that are null/empty in the existing row."""
    patch: dict[str, Any] = {}
    fillable = [
        "name", "brand", "category_suggestion", "category_tags",
        "ingredients_text", "nutrition_json", "image_front_url",
        "image_front_storage_path", "image_ingredients_url",
        "image_nutrition_url", "source_url",
    ]
    for f in fillable:
        existing_val = existing.get(f)
        new_val = candidate.get(f)
        empty = existing_val is None or existing_val == "" or existing_val == [] or existing_val == {}
        if empty and new_val not in (None, "", [], {}):
            patch[f] = new_val
    return patch


class UpsertResult:
    def __init__(self, action: str, score: int, status: str, detail: str = ""):
        self.action = action  # inserted | updated | skipped
        self.score = score
        self.status = status
        self.detail = detail


def upsert_candidate(
    url: str,
    key: str,
    candidate: dict[str, Any],
    *,
    dry_run: bool,
    force: bool,
    only_missing: bool,
    min_quality: int,
) -> UpsertResult:
    """Insert or merge a candidate into product_staging (never products)."""
    payload, score, missing, status = _scored_payload(candidate)
    barcode = candidate["barcode"]
    source = candidate["source"]

    # Explicit min-quality gate.
    if score < min_quality:
        return UpsertResult("skipped", score, status, f"below min-quality {min_quality}")

    if dry_run:
        existing = None
    else:
        existing = _fetch_existing(url, key, barcode, source)

    if existing is None:
        if dry_run:
            return UpsertResult("inserted", score, status, "(dry-run)")
        resp = requests.post(
            f"{url}/rest/v1/product_staging",
            headers=_supabase_headers(key),
            json=payload,
            timeout=30,
        )
        resp.raise_for_status()
        return UpsertResult("inserted", score, status)

    # Existing row found.
    existing_status = existing.get("status")
    if existing_status in ("approved", "rejected") and not force:
        return UpsertResult(
            "skipped", score, status,
            f"existing status={existing_status} (use --force to override)",
        )

    existing_score = existing.get("quality_score") or 0
    fill_patch = _merge_fill_missing(existing, candidate)

    better = score > existing_score
    if only_missing:
        better = False  # only fill gaps, never replace on score

    if not better and not fill_patch and not force:
        return UpsertResult("skipped", score, status, "no improvement / no gaps")

    if dry_run:
        return UpsertResult("updated", score, status, "(dry-run)")

    if better or force:
        # Replace with the better candidate, but preserve admin_notes + never lower
        # the recorded status of an already-reviewed row (handled above).
        update = {k: v for k, v in payload.items() if k != "admin_notes"}
        update.update(fill_patch)  # ensure any gaps also filled
    else:
        # only fill missing fields; recompute score on the merged result
        merged = {**existing, **fill_patch}
        update = fill_patch
        update["quality_score"], update["missing_fields"], update["status"] = (
            evaluate_quality(merged)
        )

    resp = requests.patch(
        f"{url}/rest/v1/product_staging",
        headers=_supabase_headers(key),
        params={"barcode": f"eq.{barcode}", "source": f"eq.{source}"},
        json=update,
        timeout=30,
    )
    resp.raise_for_status()
    return UpsertResult("updated", score, status)


# ── CLI helpers ──────────────────────────────────────────────────────────────

def add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--input", required=True, help="Path to the input file")
    parser.add_argument(
        "--source",
        default=None,
        choices=sorted(VALID_SOURCES),
        help="Override the candidate source",
    )
    parser.add_argument("--limit", type=int, default=None, help="Max rows to process")
    parser.add_argument("--dry-run", action="store_true", help="Inspect only; no writes")
    parser.add_argument("--real", action="store_true", help="Write to product_staging")
    parser.add_argument(
        "--force", action="store_true",
        help="Overwrite existing rows even if approved/rejected or worse quality",
    )
    parser.add_argument(
        "--only-missing", action="store_true",
        help="Only fill missing fields; never replace on quality",
    )
    parser.add_argument(
        "--min-quality", type=int, default=0,
        help="Skip candidates whose quality_score is below this value",
    )


def resolve_write_mode(args: argparse.Namespace) -> bool:
    """Returns True for a real write. Default is dry-run for safety."""
    return bool(args.real) and not args.dry_run


def print_candidate_summary(candidate: dict[str, Any], result: UpsertResult) -> None:
    nutrition = candidate.get("nutrition_json") or {}
    print(
        f"  [{result.action:8}] barcode={candidate.get('barcode')} "
        f"name={candidate.get('name')!r} brand={candidate.get('brand')!r} "
        f"score={result.score} status={result.status} "
        f"nutri={len(nutrition)} "
        f"img={'yes' if candidate.get('image_front_url') else 'no'}"
        + (f" — {result.detail}" if result.detail else "")
    )


def run_import(args: argparse.Namespace, candidates: list[dict[str, Any]]) -> int:
    """Validate, score and stage a list of candidates. Returns process exit code."""
    real = resolve_write_mode(args)
    url = key = ""
    if real:
        url, key = load_supabase_env()

    if args.limit is not None:
        candidates = candidates[: args.limit]

    counts = {"inserted": 0, "updated": 0, "skipped": 0, "invalid": 0}
    print(f"Processing {len(candidates)} candidate(s) — mode={'REAL' if real else 'DRY-RUN'}")

    for candidate in candidates:
        errors = validate_candidate(candidate)
        if errors:
            counts["invalid"] += 1
            print(
                f"  [invalid ] barcode={candidate.get('barcode')} — {'; '.join(errors)}",
                file=sys.stderr,
            )
            continue
        try:
            result = upsert_candidate(
                url, key, candidate,
                dry_run=not real,
                force=args.force,
                only_missing=args.only_missing,
                min_quality=args.min_quality,
            )
        except requests.HTTPError as exc:
            counts["invalid"] += 1
            print(f"  [error   ] barcode={candidate.get('barcode')} — HTTP {exc}", file=sys.stderr)
            continue
        counts[result.action] += 1
        print_candidate_summary(candidate, result)

    print(
        f"\nDone. inserted={counts['inserted']} updated={counts['updated']} "
        f"skipped={counts['skipped']} invalid={counts['invalid']}"
    )
    if not real:
        print("Dry-run — nothing was written. Pass --real to stage candidates.")
    return 0
