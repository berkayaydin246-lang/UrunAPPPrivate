#!/usr/bin/env python3
"""Orchestration: turn configured sources/URLs into staged product candidates.

Pure, network-free helpers (quality scoring, dedupe key, merge) live here too so
they can be unit-tested directly. The scraping functions use a [base.Fetcher];
the staging upsert talks to Supabase via the existing `common` helpers.

NOTHING here writes to `products`. Candidates only ever land in `product_staging`.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from datetime import datetime, timezone

# Make the sibling `common` module importable (scripts/product_import/common.py).
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402  (shared OFF/staging helpers; reused, not duplicated)

from . import extractors, image_scoring, ingredient_parser, nutrition_parser  # noqa: E402
from . import source_adapters  # noqa: E402
from .base import Fetcher  # noqa: E402

try:
    import requests  # noqa: E402
except ImportError as exc:  # pragma: no cover
    raise SystemExit("ERROR: 'requests' is required.") from exc


SOURCE_PREFIX = "web_scraper"

# ── Quality scoring (Part 9): barcode-optional ───────────────────────────────
# Weights sum to 100 WITHOUT barcode (web-discovered products often lack one).
# A present barcode is a capped bonus, so it improves but is never required.
_W_NAME = 18
_W_BRAND = 12
_W_IMAGE = 18
_W_INGREDIENTS = 25
_W_NUTRITION = 20
_W_CATEGORY = 7
_BARCODE_BONUS = 10
_MIN_INGREDIENTS_LEN = 20

_PENDING_THRESHOLD = 80
_NEEDS_REVIEW_THRESHOLD = 50

# Source trust ranking for cross-source merges (Part 10).
_TRUST = {"manual_seed": 3, "open_food_facts": 1}


def source_trust(source: str | None) -> int:
    if not source:
        return 0
    if source.startswith(SOURCE_PREFIX):
        return 2
    return _TRUST.get(source, 0)


def _has_text(value: object) -> bool:
    return isinstance(value, str) and value.strip() != ""


def _has_nutrition(value: object) -> bool:
    return isinstance(value, dict) and len(value) > 0


def evaluate_quality_web(candidate: dict) -> tuple[int, list[str], str]:
    """Deterministic completeness score tuned for web-discovered products.

    Returns (quality_score, missing_fields, suggested_status). Never approves.
    """
    score = 0
    missing: list[str] = []

    if _has_text(candidate.get("name")):
        score += _W_NAME
    else:
        missing.append("name")

    if _has_text(candidate.get("brand")):
        score += _W_BRAND
    else:
        missing.append("brand")

    if _has_text(candidate.get("image_front_url")) or _has_text(
        candidate.get("image_front_storage_path")
    ):
        score += _W_IMAGE
    else:
        missing.append("front_image")

    ing = candidate.get("ingredients_text")
    if isinstance(ing, str) and len(ing.strip()) > _MIN_INGREDIENTS_LEN:
        if ingredient_parser.is_suspicious(ing):
            # Present but junk-looking → no points, flagged for admin review.
            missing.append("ingredients_suspicious")
        else:
            score += _W_INGREDIENTS
    else:
        missing.append("ingredients")

    if _has_nutrition(candidate.get("nutrition_json")):
        score += _W_NUTRITION
    else:
        missing.append("nutrition")

    if _has_text(candidate.get("category_suggestion")) or candidate.get("category_tags"):
        score += _W_CATEGORY
    else:
        missing.append("category")

    # Barcode is optional for web products: a bonus, and only reported as a
    # soft-missing field (it does not block usability).
    if _has_text(candidate.get("barcode")):
        score += _BARCODE_BONUS
    else:
        missing.append("barcode")

    score = min(score, 100)
    if score >= _PENDING_THRESHOLD:
        status = "pending"
    elif score >= _NEEDS_REVIEW_THRESHOLD:
        status = "needs_review"
    else:
        status = "insufficient_data"
    return score, missing, status


# ── Normalization / keys ─────────────────────────────────────────────────────

def normalize_for_match(text: str | None) -> str:
    """ASCII-folded, lowercase, alnum-only key used for name/brand dedupe."""
    if not text:
        return ""
    table = str.maketrans(
        {"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u",
         "â": "a", "î": "i", "û": "u"}
    )
    folded = text.lower().translate(table)
    return re.sub(r"[^a-z0-9]+", "", folded)


_STOPWORDS = {"ve", "ile", "and", "the", "bir", "g", "ml", "kg", "lt", "gr"}


def build_search_keywords(
    name: str | None, brand: str | None, category: str | None = None
) -> list[str]:
    """Lightweight keyword tokens for products.search_keywords (array overlap)."""
    tokens: set[str] = set()
    for source in (name, brand, category):
        if not source:
            continue
        for word in re.split(r"[\s\-–—,/|()]+", source.lower()):
            word = word.strip()
            if len(word) < 2 or word in _STOPWORDS:
                continue
            tokens.add(word)
            ascii_word = normalize_for_match(word)
            if ascii_word and ascii_word != word:
                tokens.add(ascii_word)
    return sorted(t for t in tokens if len(t) >= 2)


def dedupe_key(candidate: dict) -> tuple:
    """Matching priority (Part 10): barcode → source_url → normalized name+brand."""
    barcode = (candidate.get("barcode") or "").strip()
    if barcode:
        return ("barcode", barcode)
    source_url = (candidate.get("source_url") or "").strip()
    if source_url:
        return ("source_url", source_url)
    return (
        "name_brand",
        normalize_for_match(candidate.get("name")),
        normalize_for_match(candidate.get("brand")),
    )


# ── Merge (Part 10) ──────────────────────────────────────────────────────────

_FILLABLE = [
    "barcode", "name", "brand", "category_suggestion", "category_tags",
    "search_keywords", "image_ingredients_url", "image_nutrition_url",
    "ingredients_text", "nutrition_json", "source_url",
]


def _empty(value: object) -> bool:
    return value is None or value == "" or value == [] or value == {}


def _image_score_of(candidate: dict) -> int:
    payload = candidate.get("raw_source_payload") or {}
    if isinstance(payload, dict):
        return int(payload.get("image_best_score") or 0)
    return 0


def merge_fill_missing(existing: dict, incoming: dict) -> dict:
    """Merge [incoming] into [existing] per Part 10 rules; recompute quality.

    - Fill only fields that are null/empty in existing.
    - Prefer the better-scored image (never replace a better image with a worse).
    - Prefer a source that actually carries ingredients/nutrition.
    - Preserve admin_notes. Keep existing source unless it is less trusted.
    - Recompute quality_score / missing_fields / status on the result.
    """
    merged = dict(existing)

    for field in _FILLABLE:
        if _empty(merged.get(field)) and not _empty(incoming.get(field)):
            merged[field] = incoming[field]
            src_field = _provenance_field(field)
            if src_field and not _empty(incoming.get(src_field)):
                merged[src_field] = incoming[src_field]

    # Image: replace only when incoming scores strictly higher.
    if _image_score_of(incoming) > _image_score_of(existing) and _has_text(
        incoming.get("image_front_url")
    ):
        merged["image_front_url"] = incoming["image_front_url"]
        merged["image_source"] = incoming.get("image_source")
        # keep the best score in payload for future comparisons
        payload = dict(merged.get("raw_source_payload") or {})
        payload["image_best_score"] = _image_score_of(incoming)
        merged["raw_source_payload"] = payload
    elif _empty(merged.get("image_front_url")) and _has_text(
        incoming.get("image_front_url")
    ):
        merged["image_front_url"] = incoming["image_front_url"]
        merged["image_source"] = incoming.get("image_source")

    # Prefer a source that brought ingredients+nutrition when existing lacked them.
    if (
        not _has_text(existing.get("ingredients_text"))
        and _has_text(incoming.get("ingredients_text"))
        and source_trust(incoming.get("source")) >= source_trust(existing.get("source"))
    ):
        merged["source"] = incoming.get("source", merged.get("source"))

    # Preserve admin_notes from existing (never clobbered by a scrape).
    if _has_text(existing.get("admin_notes")):
        merged["admin_notes"] = existing["admin_notes"]

    score, missing, status = evaluate_quality_web(merged)
    merged["quality_score"] = score
    merged["missing_fields"] = missing
    # Do not silently downgrade a human-set status; the caller guards approved/
    # rejected rows. For pending/needs_review/insufficient_data, recompute.
    merged["status"] = status
    return merged


def _provenance_field(field: str) -> str | None:
    return {
        "name": "name_source",
        "brand": "brand_source",
        "ingredients_text": "ingredients_source",
        "nutrition_json": "nutrition_source",
        "category_suggestion": "category_source",
        "category_tags": "category_source",
    }.get(field)


# ── Scraping one product page → candidate dict ───────────────────────────────


def build_image_candidate_pool(
    soup,
    page_url: str,
    *,
    jsonld: dict | None = None,
    meta: dict | None = None,
    api_metadata: dict | None = None,
) -> list[image_scoring.ImageCandidate]:
    """Build a provenance-rich pool of image candidates for one product page."""
    jsonld = jsonld or {}
    meta = meta or {}
    api_meta = api_metadata or {}
    img_pool: list[image_scoring.ImageCandidate] = []

    for i, u in enumerate(jsonld.get("images", []) or []):
        img_pool.append(
            image_scoring.ImageCandidate(
                url=u,
                in_schema=True,
                gallery_index=i,
                source="embedded_json",
            )
        )
    if meta.get("og_image"):
        img_pool.append(
            image_scoring.ImageCandidate(
                url=meta["og_image"],
                source="category_card",
            )
        )
    for ref in extractors.images_near_title_refs(soup, page_url):
        img_pool.append(
            image_scoring.ImageCandidate(
                url=ref["url"],
                near_title=True,
                # gallery_index intentionally None: near-title proximity is not a
                # reliable gallery-order signal. Gallery position (+20 / -10) must
                # come only from gather_gallery_image_refs below, where the order
                # matches the page's actual image carousel / gallery widget.
                gallery_index=None,
                source="detail_gallery",
                context_text=ref.get("context_text"),
            )
        )
    for j, ref in enumerate(extractors.gather_gallery_image_refs(soup, page_url)):
        img_pool.append(
            image_scoring.ImageCandidate(
                url=ref["url"],
                in_gallery=True,
                gallery_index=j,
                source="detail_gallery",
                context_text=ref.get("context_text"),
            )
        )

    api_image = api_meta.get("api_image_url")
    if api_image and isinstance(api_image, str):
        img_pool.append(
            image_scoring.ImageCandidate(
                url=api_image,
                in_schema=True,
                is_api_primary=True,
                gallery_index=0,
                source="api_primary",
            )
        )
    return img_pool


def select_product_images(
    image_candidates: list[image_scoring.ImageCandidate],
    *,
    name: str | None = None,
    brand: str | None = None,
    barcode: str | None = None,
) -> dict:
    """Pick the safest public-facing product image and preserve debug metadata."""
    selection = image_scoring.select_primary_image(
        image_candidates,
        name=name,
        brand=brand,
        barcode=barcode,
    )
    best = selection.selected
    label_images = [
        c
        for c in selection.scored
        if c is not best
        and image_scoring.is_label_role(image_scoring.classify_image_role(c))
    ]
    return {
        "image_front_url": best.url if best else None,
        "image_front_role": image_scoring.classify_image_role(best),
        "image_quality": selection.quality,
        "image_confidence": selection.confidence,
        "image_best_score": best.score if best else 0,
        "image_ingredients_url": label_images[0].url if label_images else None,
        "image_candidates": [
            image_scoring.serialize_candidate(c) for c in selection.scored[:12]
        ],
    }


def scrape_product_image_data(
    fetcher: Fetcher,
    url: str,
    source_id: str,
    *,
    api_metadata: dict | None = None,
) -> tuple[dict | None, str | None]:
    """Fetch only image-related metadata for a product page."""
    result = fetcher.get(url)
    if not result.ok or not result.html:
        return None, result.error or "fetch failed"

    soup = extractors.make_soup(result.html)
    final_url = result.final_url or url
    jsonld = extractors.extract_jsonld(soup)
    meta = extractors.extract_meta(soup)
    api_meta = api_metadata or {}
    # Same og:title priority as assemble_candidate — see comment there.
    name = clean_title(
        meta.get("og_title") or meta.get("title")
        or jsonld.get("name")
        or api_meta.get("api_name")
    )
    brand = (
        str(api_meta.get("api_brand")).strip()
        if isinstance(api_meta.get("api_brand"), str) and api_meta.get("api_brand").strip()
        else None
    )
    image_data = select_product_images(
        build_image_candidate_pool(
            soup,
            final_url,
            jsonld=jsonld,
            meta=meta,
            api_metadata=api_meta,
        ),
        name=name,
        brand=brand,
    )
    image_data.update(
        {
            "source": f"{SOURCE_PREFIX}:{source_id}",
            "source_url": final_url,
            "name": name,
            "brand": brand,
        }
    )
    return image_data, None


def assemble_candidate(
    *,
    source_id: str,
    url: str,
    jsonld: dict,
    meta: dict,
    sections: dict,
    image_candidates: list,
    category: str | None,
    nutrition_json: dict | None = None,
    nutrition_warnings: list | None = None,
    nutrition_basis: str | None = None,
    nutrition_strategy: str | None = None,
    ingredients_raw: str | None = None,
    breadcrumb_category: str | None = None,
    api_metadata: dict | None = None,
) -> dict:
    """Pure assembly of a candidate dict from already-extracted page parts."""
    source = f"{SOURCE_PREFIX}:{source_id}"
    api_meta = api_metadata or {}

    # og:title / HTML title are preferred over the JSON-LD name field because many
    # retailers (including Migros) store a brand-stripped product-line name in
    # JSON-LD while the page title carries the full "Brand Product Size" string.
    # clean_title() removes the retailer suffix from og:title, so this is safe.
    name = clean_title(
        meta.get("og_title") or meta.get("title")
        or jsonld.get("name")
        or api_meta.get("api_name")
    )

    # Brand priority: api_metadata > detail_page > dynamic_category_brand > hardcoded_known_brand.
    _api_brand = api_meta.get("api_brand") or None
    _page_brand = jsonld.get("brand") or None
    _dynamic_brands = api_meta.get("category_dynamic_brands") or []
    if _api_brand:
        brand = _api_brand
        brand_source_method = "api_metadata"
    elif _page_brand:
        brand = _page_brand
        brand_source_method = "detail_page"
    else:
        _dyn_brand = _match_dynamic_brand(name, _dynamic_brands)
        if _dyn_brand:
            brand = _dyn_brand
            brand_source_method = "dynamic_category_brand"
        else:
            brand = infer_brand(name)
            brand_source_method = "hardcoded_known_brand" if brand else "missing"

    # Parent-brand override: when the API/dynamic/etc. returned a product line
    # instead of the real parent brand, correct it using the title as ground truth.
    brand_raw = None  # non-None only when an override happens
    if brand:
        _parent = detect_parent_brand_override(name, brand)
        if _parent and _parent != brand:
            brand_raw = brand  # preserve pre-override brand for debug
            brand = _parent
            brand_source_method = "parent_brand_override"

    barcode = jsonld.get("barcode")

    # Ingredients: cleaned from whatever generic strategy found (section/JSON).
    if ingredients_raw is None:
        ingredients_raw = sections.get("ingredients")
    _cleaned_ingredients = ingredient_parser.clean_ingredients(ingredients_raw)
    _ing_quality = ingredient_parser.ingredient_quality(_cleaned_ingredients)
    if _ing_quality == ingredient_parser.INGREDIENT_QUALITY_REJECTED_JUNK:
        # Clear junk text entirely — admin sees empty field, not garbage.
        ingredients_text = None
    else:
        ingredients_text = _cleaned_ingredients

    # Nutrition: computed by the caller via the multi-strategy extractor.
    nutrition_json = nutrition_json or None
    nutrition_warnings = nutrition_warnings or []
    basis = nutrition_basis

    image_data = select_product_images(
        image_candidates,
        name=name,
        brand=brand,
        barcode=barcode,
    )

    category_suggestion = (
        jsonld.get("category") or breadcrumb_category
        or api_meta.get("api_category") or category
    )
    category_tags = [category] if category else None

    candidate: dict = {
        "barcode": barcode,
        "name": name,
        "brand": brand,
        "category_suggestion": category_suggestion,
        "category_tags": category_tags,
        "search_keywords": build_search_keywords(name, brand, category) or None,
        "image_front_url": image_data["image_front_url"],
        "image_front_storage_path": None,
        "image_ingredients_url": image_data["image_ingredients_url"],
        "ingredients_text": ingredients_text,
        "nutrition_json": nutrition_json or None,
        "source": source,
        "source_url": url,
        "brand_source_method": brand_source_method,
        "brand_raw": brand_raw,  # non-None only when parent_brand_override applied
        "ingredient_quality": _ing_quality,
        "image_front_role": image_data["image_front_role"],
        "image_quality": image_data["image_quality"],
        "image_confidence": image_data["image_confidence"],
        "raw_source_payload": {
            "jsonld": jsonld or None,
            "meta": meta or None,
            "api_metadata": api_meta or None,
            "ingredients_raw": ingredients_raw,
            "ingredients_quality": _ing_quality,
            "nutrition_basis": basis,
            "nutrition_strategy": nutrition_strategy,
            "nutrition_warnings": nutrition_warnings,
            "image_candidates": image_data["image_candidates"],
            "image_best_score": image_data["image_best_score"],
            "image_front_role": image_data["image_front_role"],
            "image_quality": image_data["image_quality"],
            "image_confidence": image_data["image_confidence"],
            "scraped_at": datetime.now(timezone.utc).isoformat(),
        },
        # field-level provenance
        "name_source": source if _has_text(name) else None,
        "brand_source": source if _has_text(brand) else None,
        "image_source": source if image_data["image_front_url"] else None,
        "ingredients_source": source if ingredients_text else None,
        "nutrition_source": source if nutrition_json else None,
        "category_source": source if (category_suggestion or category_tags) else None,
    }

    score, missing, status = evaluate_quality_web(candidate)
    candidate["quality_score"] = score
    candidate["missing_fields"] = missing
    candidate["status"] = status
    return candidate


# Common retailer suffixes appended to <title>/og:title (case-insensitive).
_RETAILER_SUFFIXES = (
    "migros", "carrefoursa", "carrefour", "trendyol", "hepsiburada", "getir",
    "a101", "bim", "şok", "sok", "macrocenter", "metro", "amazon",
)

# A conservative list of well-known Turkish/global food brands. Used only to
# infer a brand when metadata is missing AND the product name confidently
# starts with one of these (longest match first). Never invents a brand.
KNOWN_BRANDS = [
    # Snacks / global
    "Pınar", "Eti", "Ülker", "Ruffles", "Lay's", "Lays", "Frito Lay", "Torku",
    "Nestle", "Nestlé", "Tadelle", "İçim", "Sütaş", "Danone", "Coca-Cola",
    "Pepsi", "Dimes", "Sek", "Banvit", "Haribo", "Milka", "Oreo", "Algida",
    "Doritos", "Cheetos", "Tat", "Yudum", "Komili", "Sana", "Nutella",
    # Meat / poultry / charcuterie
    "Namet", "Maret", "Polonez", "Apikoğlu", "Şahin", "Cumhuriyet",
    "Erşan", "Beşler", "Lezita", "Gedik", "Şenpiliç", "Beypiliç",
    "Keskinoğlu", "Erpiliç", "HasTavuk", "Has Tavuk", "Orvital", "Akpiliç",
    "Bolca", "CP", "Migros",
    # Dairy / cheese
    "Lente Cheese", "Lente",
    "Trakya Çiftliği", "Hasmandıra", "Güneydoğu",
    "Eker", "Activia", "Tikveşli", "Yörükoğlu", "Aynes", "Muratbey",
    "Bahçıvan", "Ekici", "İçimino", "President", "Babybel",
    "La Vache Qui Rit", "Lavache Qui Rit", "Karper", "Kiri", "Mis", "Dost",
    "Anadolu Lezzetleri", "Kebir", "Trabzon Çiftliği", "Tahsildaroğlu",
    "Ezine", "Süper Maya",
    # Breakfast / pantry
    "Antalya Reçelcisi", "Pol's Gurme",
    "Koska", "Tamek", "Datçam", "Tatlan", "Kartad", "Yenigün",
    "Doğadan", "Lipton", "Çaykur", "Kellogg's", "Kellogg", "Nesquik",
    "Sarelle", "Fiskobirlik", "Balparmak", "Marmarabirlik", "Fora",
    "Orkide", "Bizim",
]
_KNOWN_BRAND_LOOKUP = {normalize_for_match(b): b for b in KNOWN_BRANDS}

# Maps parent brands to their product-line / sub-brand names.
# Used to correct cases where the API returns a sub-brand instead of the
# real consumer-facing parent brand (e.g. api_brand="Lifalif" → brand="Eti").
_PARENT_BRAND_MAP: dict[str, frozenset[str]] = {
    "Eti": frozenset({
        "Lifalif", "Cin", "Burçak", "Form", "Petito", "Popkek",
        "Hoşbeş", "Negro", "Crax", "Wanted", "Browni", "Puf",
        "Tutku", "Cicibebe", "Kombo", "Benim'o",
    }),
    "Ülker": frozenset({
        "Çokokrem", "Dankek", "Halley", "Albeni", "Çokonat", "Metro",
        "Laviva", "Biskrem", "Çizi", "Rondo", "Dido", "Krispi",
    }),
    "Nestle": frozenset({
        "Nesquik", "Fitness", "KitKat", "Damak", "Nescafe", "Nesfit",
    }),
    "Nestlé": frozenset({
        "Nesquik", "Fitness", "KitKat", "Damak", "Nescafe", "Nesfit",
    }),
    "Kellogg's": frozenset({
        "Corn Flakes", "Granola", "Special K", "Coco Pops", "Frosties",
    }),
    "Kellogg": frozenset({
        "Corn Flakes", "Granola", "Special K", "Coco Pops", "Frosties",
    }),
}


def detect_parent_brand_override(name: str | None, current_brand: str | None) -> str | None:
    """Return the parent brand when BOTH conditions hold: the product title starts
    with the parent brand, AND current_brand is a known sub-brand of that parent.

    Conservative: returns None when either condition is not unambiguously met,
    so an uncommon brand is never silently discarded.
    """
    if not name or not current_brand:
        return None
    norm_current = normalize_for_match(current_brand)
    name_norm = normalize_for_match(name)
    for parent, sub_brands in _PARENT_BRAND_MAP.items():
        if not any(normalize_for_match(sub) == norm_current for sub in sub_brands):
            continue
        parent_norm = normalize_for_match(parent)
        if name_norm.startswith(parent_norm):
            return parent
    return None


def clean_title(name: str | None) -> str | None:
    """Clean a product title: collapse whitespace and strip retailer suffixes."""
    if not name:
        return None
    text = re.sub(r"\s+", " ", name).strip()
    # Strip a trailing " - <Retailer>" / " | <Retailer>" segment.
    parts = re.split(r"\s*[\|»\-–—]\s*", text)
    if len(parts) > 1 and normalize_for_match(parts[-1]) in {
        normalize_for_match(s) for s in _RETAILER_SUFFIXES
    }:
        text = " ".join(parts[:-1]).strip()
    # Also handle a clean " | site" tail generically.
    text = re.split(r"\s+[\|»]\s+", text)[0].strip()
    return text or None


_DYNAMIC_BRAND_MIN_LEN = 3  # skip brands whose normalized form is shorter than this


def _match_dynamic_brand(name: str | None, brands: list[str]) -> str | None:
    """Title-prefix match against a dynamic brand list; longest match wins.

    Used when per-product api_brand is absent and the detail page offers no
    JSON-LD brand. Falls back to KNOWN_BRANDS only when this also misses.
    Brands whose normalized form is shorter than _DYNAMIC_BRAND_MIN_LEN are
    skipped to avoid matching on generic short tokens.
    """
    if not name or not brands:
        return None
    lookup: dict[str, str] = {}
    for b in brands:
        key = normalize_for_match(b)
        if len(key) >= _DYNAMIC_BRAND_MIN_LEN:
            lookup[key] = b
    if not lookup:
        return None
    tokens = name.split()
    if not tokens:
        return None
    for n in (4, 3, 2, 1):
        if len(tokens) < n:
            continue
        key = normalize_for_match("".join(tokens[:n]))
        if key in lookup:
            return lookup[key]
    return None


def infer_brand(name: str | None) -> str | None:
    """Cautiously infer a brand from the product name's leading tokens.

    Tries the longest brand first (3 → 2 → 1 leading tokens) so multi-word
    brands ("Anadolu Lezzetleri", "La Vache Qui Rit") win over single-token
    prefixes. Matching is Turkish-folded and case-insensitive. Only returns a
    brand on a confident whole-token match against KNOWN_BRANDS — never invents.
    """
    if not name:
        return None
    tokens = name.split()
    if not tokens:
        return None
    for n in (4, 3, 2, 1):
        if len(tokens) < n:
            continue
        key = normalize_for_match("".join(tokens[:n]))
        if key in _KNOWN_BRAND_LOOKUP:
            return _KNOWN_BRAND_LOOKUP[key]
    return None


def scrape_product_page(
    fetcher: Fetcher, url: str, source_id: str,
    *, category: str | None = None, api_metadata: dict | None = None
) -> tuple[dict | None, str | None]:
    """Fetch one product page and assemble a candidate. Returns (candidate, error)."""
    result = fetcher.get(url)
    if not result.ok or not result.html:
        return None, result.error or "fetch failed"

    soup = extractors.make_soup(result.html)
    final_url = result.final_url or url
    jsonld = extractors.extract_jsonld(soup)
    meta = extractors.extract_meta(soup)
    sections = extractors.extract_sections(soup)

    # Generic multi-strategy nutrition (HTML tables / div rows / embedded JSON /
    # labeled text) → canonical nutrition_json.
    nutri = extractors.extract_nutrition(soup)
    nutrition_json, nutrition_warnings = nutrition_parser.build_nutrition(
        nutri["pairs"], basis_text=nutri["basis_text"], fallback_text=nutri["fallback_text"]
    )
    nutrition_basis = (
        nutrition_parser.detect_basis(nutri["basis_text"]) if nutri["basis_text"] else None
    )

    # Generic ingredients (labeled section, then embedded JSON).
    ingredients_raw = extractors.extract_ingredients_text(soup)

    breadcrumb_category = extractors.extract_breadcrumb_category(soup)

    img_pool = build_image_candidate_pool(
        soup,
        final_url,
        jsonld=jsonld,
        meta=meta,
        api_metadata=api_metadata,
    )

    candidate = assemble_candidate(
        source_id=source_id,
        url=final_url,
        jsonld=jsonld,
        meta=meta,
        sections=sections,
        image_candidates=img_pool,
        category=category,
        nutrition_json=nutrition_json,
        nutrition_warnings=nutrition_warnings,
        nutrition_basis=nutrition_basis,
        nutrition_strategy=nutri["strategy"],
        ingredients_raw=ingredients_raw,
        breadcrumb_category=breadcrumb_category,
        api_metadata=api_metadata,
    )
    if not _has_text(candidate.get("name")):
        return None, "no product name found"
    return candidate, None


# ── Staging upsert (Part 10/12) ──────────────────────────────────────────────

# Exact set of columns in product_staging. Only these may be sent as top-level
# keys to PostgREST — any unknown key causes a 400 PGRST204 error. Debug/meta
# fields that are not real columns (brand_source_method, ingredient_quality,
# dynamic brand lists) are stored inside raw_source_payload.debug instead.
_STAGING_COLUMNS = frozenset({
    "barcode", "name", "brand", "category_suggestion", "category_tags",
    "search_keywords", "image_front_url", "image_front_storage_path",
    "image_ingredients_url", "image_nutrition_url",
    "ingredients_text", "nutrition_json",
    "source", "source_url", "raw_source_payload",
    "name_source", "brand_source", "image_source", "ingredients_source",
    "nutrition_source", "category_source",
    "quality_score", "missing_fields", "status", "admin_notes",
})

# Candidate keys that have no DB column — stored in raw_source_payload.debug.
_CANDIDATE_DEBUG_FIELDS = (
    "brand_source_method",
    "ingredient_quality",
    "brand_raw",
    "image_front_role",
    "image_quality",
    "image_confidence",
)


def _scored_insert_payload(candidate: dict) -> dict:
    """Build a product_staging insert dict with only valid schema columns.

    Debug fields (brand_source_method, ingredient_quality) are moved into
    raw_source_payload.debug so they survive without requiring extra columns.
    """
    payload = {
        k: v for k, v in candidate.items()
        if not _empty(v) and k in _STAGING_COLUMNS
    }
    # Always include the computed review fields even if 0/empty.
    payload["quality_score"] = candidate.get("quality_score", 0)
    payload["missing_fields"] = candidate.get("missing_fields", [])
    payload["status"] = candidate.get("status", "insufficient_data")
    # Enrich raw_source_payload with debug fields that have no DB column.
    debug_extra = {k: candidate[k] for k in _CANDIDATE_DEBUG_FIELDS if candidate.get(k)}
    if debug_extra:
        raw = dict(payload.get("raw_source_payload") or {})
        existing_debug = raw.get("debug") or {}
        raw["debug"] = {**existing_debug, **debug_extra}
        payload["raw_source_payload"] = raw
    return payload


def _log_staging_error(resp, payload: dict, candidate: dict, method: str) -> None:
    """Log actionable details when a PostgREST staging request fails."""
    status = getattr(resp, "status_code", "?")
    body = ""
    try:
        body = resp.text[:1000] if hasattr(resp, "text") else ""
    except Exception:  # noqa: BLE001
        pass
    print(f"  [staging-error] {method} {status}", file=sys.stderr)
    print(f"  response={body}", file=sys.stderr)
    print(f"  payload_keys={sorted(payload.keys())}", file=sys.stderr)
    print(f"  candidate_name={candidate.get('name')!r}", file=sys.stderr)
    print(f"  candidate_source_url={candidate.get('source_url')!r}", file=sys.stderr)


def _find_existing(url: str, key: str, candidate: dict) -> dict | None:
    headers = common._supabase_headers(key)
    kind = dedupe_key(candidate)[0]
    base = f"{url}/rest/v1/product_staging"
    source = candidate["source"]

    if kind == "barcode":
        params = {
            "select": "*",
            "barcode": f"eq.{candidate['barcode']}",
            "source": f"eq.{source}",
            "limit": "1",
        }
        rows = requests.get(base, headers=headers, params=params, timeout=30)
        rows.raise_for_status()
        data = rows.json()
        return data[0] if data else None

    if kind == "source_url":
        params = {
            "select": "*",
            "source_url": f"eq.{candidate['source_url']}",
            "source": f"eq.{source}",
            "limit": "1",
        }
        rows = requests.get(base, headers=headers, params=params, timeout=30)
        rows.raise_for_status()
        data = rows.json()
        return data[0] if data else None

    # name+brand: fetch this source's barcode-less rows and match in Python.
    params = {
        "select": "*",
        "source": f"eq.{source}",
        "barcode": "is.null",
        "limit": "1000",
    }
    rows = requests.get(base, headers=headers, params=params, timeout=30)
    rows.raise_for_status()
    want = dedupe_key(candidate)
    for row in rows.json():
        if dedupe_key(row) == want:
            return row
    return None


def upsert_candidate(
    url: str, key: str, candidate: dict, *, dry_run: bool, force: bool
) -> tuple[str, dict | None]:
    """Insert or merge a candidate into product_staging.

    Returns (action, staging_row) where staging_row is the stored row (with its
    id) so the caller can optionally auto-approve it. In dry-run nothing is
    written and staging_row is None.
    """
    if dry_run:
        return "inserted", None  # caller does not write in dry-run

    existing = _find_existing(url, key, candidate)
    headers = common._supabase_headers(key)
    base = f"{url}/rest/v1/product_staging"

    if existing is None:
        payload = _scored_insert_payload(candidate)
        resp = requests.post(base, headers=headers, json=payload, timeout=30)
        if not resp.ok:
            _log_staging_error(resp, payload, candidate, "POST")
        resp.raise_for_status()
        return "inserted", _first_row(resp)

    if existing.get("status") in ("approved", "rejected") and not force:
        return "skipped", existing

    merged = merge_fill_missing(existing, candidate)
    # Don't downgrade a human 'approved'/'rejected' even with --force unless asked;
    # force lets us overwrite content but we still re-stamp computed status only
    # for non-terminal rows.
    update = {
        k: v for k, v in merged.items()
        if k not in ("id", "created_at") and k in _STAGING_COLUMNS
    }
    resp = requests.patch(
        base,
        headers=headers,
        params={"id": f"eq.{existing['id']}"},
        json=update,
        timeout=30,
    )
    if not resp.ok:
        _log_staging_error(resp, update, candidate, "PATCH")
    resp.raise_for_status()
    return "updated", (_first_row(resp) or existing)


def _first_row(resp) -> dict | None:
    """Return the first row from a PostgREST representation response, or None."""
    try:
        data = resp.json()
    except ValueError:
        return None
    if isinstance(data, list):
        return data[0] if data else None
    if isinstance(data, dict):
        return data
    return None


# ── Optional auto-approval (opt-in) ──────────────────────────────────────────
# Mirrors the Dart ProductStagingApprovalRepository so manual (admin button) and
# auto approval behave identically: same no-barcode eligibility, same fill-missing
# products upsert deduped by barcode→source_url, same staging flip to 'approved'.
# Auto-approval is opt-in (CLI flag), real-mode only, and web_scraper:* only.

def auto_approve_block_reason(row: dict, min_score: int) -> str | None:
    """Return why a staged row may NOT be auto-approved, or None when eligible.

    Conservative: web_scraper:* sources only, status pending, quality >= min,
    and all reliable fields present. Never invents a barcode.
    """
    source = str(row.get("source") or "")
    if not source.startswith(f"{SOURCE_PREFIX}:"):
        return "ineligible_source"
    if (row.get("status") or "pending") != "pending":
        return "not_pending"
    if int(row.get("quality_score") or 0) < min_score:
        return "score_too_low"
    if not _has_text(row.get("name")) or not _has_text(row.get("brand")):
        return "missing_brand"
    if not (
        _has_text(row.get("image_front_url"))
        or _has_text(row.get("image_front_storage_path"))
    ):
        return "missing_image"
    if not _has_text(row.get("ingredients_text")):
        return "missing_ingredients"
    ing = row.get("ingredients_text")
    if ingredient_parser.is_junk(ing) or ingredient_parser.is_suspicious(ing):
        return "suspicious_ingredients"
    if not _has_nutrition(row.get("nutrition_json")):
        return "missing_nutrition"
    if not _has_text(row.get("source_url")):
        return "missing_source_url"
    return None


def approval_dedupe_key(row: dict) -> tuple[str, str]:
    """(column, value) used to dedupe a product: barcode if present, else source_url."""
    barcode = (row.get("barcode") or "").strip()
    if barcode:
        return ("barcode", barcode)
    return ("source_url", (row.get("source_url") or "").strip())


# products columns filled from a staged candidate (mirror of Dart insert map).
def _product_insert_map(row: dict) -> dict:
    payload: dict = {
        "barcode": (row.get("barcode") or "").strip() or None,
        "name": _resolve_text(row.get("name")) or "İsimsiz Ürün",
        "verification_status": "pending",
        "source": row.get("source"),
    }
    image = _resolve_text(row.get("image_front_url")) or _resolve_text(
        row.get("image_front_storage_path")
    )
    nutrition = row.get("nutrition_json")
    optional = {
        "brand": _resolve_text(row.get("brand")),
        "image_url": image,
        "ingredients_text": _resolve_text(row.get("ingredients_text")),
        "nutrition_text": json.dumps(nutrition) if nutrition else None,
        "source_url": _resolve_text(row.get("source_url")),
        "category_tags": row.get("category_tags") or None,
        "search_keywords": row.get("search_keywords") or None,
    }
    for k, v in optional.items():
        if v:
            payload[k] = v
    return payload


def _product_enrich_patch(existing: dict, row: dict) -> dict:
    """Fill only null/empty fields on an existing product (never overwrite)."""
    patch: dict = {}
    insert_map = _product_insert_map(row)
    fillable = [
        "name", "brand", "image_url", "ingredients_text", "nutrition_text",
        "source", "source_url", "category_tags", "search_keywords",
    ]
    for field in fillable:
        if field not in insert_map:
            continue
        cur = existing.get(field)
        empty = cur is None or cur == "" or cur == [] or cur == {}
        if empty:
            patch[field] = insert_map[field]
    return patch


def approve_staged_row(url: str, key: str, row: dict) -> tuple[str, str | None]:
    """Approve one staged row: upsert products (dedupe), flip staging to approved.

    Returns (action, error). action is 'approved_inserted' / 'approved_updated';
    on failure ('failed', reason). Never raises.
    """
    headers = common._supabase_headers(key)
    products = f"{url}/rest/v1/products"
    staging = f"{url}/rest/v1/product_staging"
    column, value = approval_dedupe_key(row)
    if not value:
        return "failed", "no_dedupe_key"

    try:
        existing = requests.get(
            products,
            headers=headers,
            params={"select": "*", column: f"eq.{value}", "limit": "1"},
            timeout=30,
        )
        existing.raise_for_status()
        existing_rows = existing.json()

        if not existing_rows:
            resp = requests.post(
                products, headers=headers, json=_product_insert_map(row), timeout=30
            )
            resp.raise_for_status()
            action = "approved_inserted"
        else:
            patch = _product_enrich_patch(existing_rows[0], row)
            if patch:
                resp = requests.patch(
                    products,
                    headers=headers,
                    params={column: f"eq.{value}"},
                    json=patch,
                    timeout=30,
                )
                resp.raise_for_status()
            action = "approved_updated"

        # Flip the staging row to approved (audit trail preserved, never deleted).
        flip = requests.patch(
            staging,
            headers=headers,
            params={"id": f"eq.{row['id']}"},
            json={"status": "approved"},
            timeout=30,
        )
        flip.raise_for_status()
        return action, None
    except requests.RequestException as exc:
        return "failed", f"http_error: {exc}"


def _resolve_text(value) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


# ── Run loop ─────────────────────────────────────────────────────────────────

def _report_no_links(url: str, stats: dict) -> None:
    """Print a short, actionable reason when a category yields no product links."""
    print(f"Category page fetched but no product detail links found.\n  url={url}")
    print(
        f"  href_links={stats.get('pattern_link_count', 0)} "
        f"script_candidates={stats.get('script_product_url_count', 0)} "
        f"json_candidates={stats.get('json_product_url_count', 0)} "
        f"scripts={stats.get('script_count', 0)} "
        f"html_length={stats.get('html_length', 0)}"
    )
    patterns = stats.get("configured_product_link_patterns") or []
    api_hints = stats.get("api_endpoint_hints") or []
    print(f"  configured_product_link_patterns={patterns}")
    if api_hints:
        print(f"  api_endpoint_hints={api_hints[:5]}")
    print(
        "  -> Category page appears client-rendered or API-backed. "
        "Add a source-specific API adapter or product_urls "
        "(or check product_link_patterns)."
    )


def _report_adapter(debug: dict) -> None:
    """Print a short summary when a source-specific adapter ran."""
    print(f"adapter_used={debug.get('adapter_used')}")
    print(f"adapter_product_urls={debug.get('product_count', 0)}")
    print(f"adapter_endpoint={debug.get('endpoint_called')}")
    if "migros_store_product_count" in debug:
        print(f"migros_store_product_count={debug.get('migros_store_product_count')}")
        print(f"migros_prettyname_url_count={debug.get('migros_prettyname_url_count')}")
        print(f"page_count={debug.get('page_count')} hit_count={debug.get('hit_count')}")
        print(f"fetched_pages={debug.get('fetched_pages')}")
        print(f"urls_per_page={debug.get('urls_per_page')}")
        print(f"pagination_param_used={debug.get('pagination_param_used')}")
        if "dynamic_brand_count" in debug:
            print(f"dynamic_brand_count={debug.get('dynamic_brand_count')}")
            print(f"first_20_dynamic_brands={debug.get('first_20_dynamic_brands')}")
    print(f"adapter_errors={debug.get('errors', [])}")
    print(f"adapter_warnings={debug.get('warnings', [])}")


class ScrapeRun:
    def __init__(self) -> None:
        self.candidates: list[dict] = []
        self.skipped: list[dict] = []
        self.errors: list[dict] = []
        self.source_stats: dict[str, dict[str, int]] = {}

    def stat(self, source_id: str, key: str) -> None:
        s = self.source_stats.setdefault(
            source_id, {"pages": 0, "candidates": 0, "errors": 0}
        )
        s[key] = s.get(key, 0) + 1


def run_scrape(
    work_items: list[tuple],
    *,
    limit: int,
    delay: float,
    timeout: float,
    fetcher: Fetcher | None = None,
) -> ScrapeRun:
    """Crawl work items and collect candidates.

    work_items: list of (mode, url, category, source_id, opts) where mode is
    'product' (direct page) or 'category' (discover links then scrape each).
    `opts` is a discovery-options dict (link selectors / patterns / excludes /
    the source object for adapter fallback). `fetcher` may be injected for tests.
    """
    run = ScrapeRun()
    if fetcher is None:
        fetcher = Fetcher(delay=delay, timeout=timeout)
    budget = limit

    for mode, url, category, source_id, opts in work_items:
        if budget <= 0:
            break
        opts = opts or {}
        if mode == "category":
            page = fetcher.get(url)
            run.stat(source_id, "pages")
            if not page.ok or not page.html:
                run.errors.append({"url": url, "error": page.error or "fetch failed"})
                run.stat(source_id, "errors")
                continue
            soup = extractors.make_soup(page.html)
            links, stats = extractors.discover_with_stats(
                soup,
                page.final_url or url,
                link_selector=opts.get("link_selector", ""),
                product_link_selector=opts.get("product_link_selector", ""),
                product_link_patterns=opts.get("product_link_patterns"),
                exclude_link_patterns=opts.get("exclude_link_patterns"),
                limit=budget,
            )
            # Fallback: an opt-in source-specific adapter for API-backed pages.
            adapter_handled = False
            url_metadata: dict = {}
            src = opts.get("source")
            if not links and src is not None:
                adapter = source_adapters.get_adapter(
                    getattr(src, "adapter", "") or src.id
                )
                if adapter is not None and adapter.can_handle(src, url):
                    adapter_handled = True
                    a_urls, a_debug = adapter.discover_product_urls(
                        fetcher, src, url, category, budget
                    )
                    stats["adapter"] = a_debug
                    _report_adapter(a_debug)
                    links = a_urls
                    url_metadata = a_debug.get("url_metadata") or {}

            if not links:
                run.skipped.append(
                    {"url": url, "reason": "no product links found", "debug": stats}
                )
                if not adapter_handled:
                    _report_no_links(url, stats)
            for link in links:
                if budget <= 0:
                    break
                _scrape_one(
                    fetcher, run, link, source_id, category,
                    api_metadata=url_metadata.get(link),
                )
                budget -= 1
        else:  # product
            _scrape_one(fetcher, run, url, source_id, category)
            budget -= 1

    return run


def _scrape_one(
    fetcher: Fetcher,
    run: ScrapeRun,
    url: str,
    source_id: str,
    category: str | None,
    api_metadata: dict | None = None,
) -> None:
    run.stat(source_id, "pages")
    candidate, error = scrape_product_page(
        fetcher, url, source_id, category=category, api_metadata=api_metadata
    )
    if candidate is None:
        run.errors.append({"url": url, "error": error or "unknown"})
        run.stat(source_id, "errors")
        return
    run.candidates.append(candidate)
    run.stat(source_id, "candidates")


def utc_timestamp() -> str:
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
