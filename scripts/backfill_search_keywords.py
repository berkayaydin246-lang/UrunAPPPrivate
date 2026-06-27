#!/usr/bin/env python3
"""
Backfill search_keywords/category_tags (and normalized_name) for existing products.

Usage:
    export SUPABASE_URL=https://your-project.supabase.co
    export SUPABASE_SERVICE_KEY=your-service-role-key
    python3 scripts/backfill_search_keywords.py [--dry-run]

Requirements:
    pip install requests python-dotenv

The script reads .env from the project root if the env vars are not set.
It processes products in batches of 200 and recomputes metadata for all rows.
Use --dry-run first to inspect what would change.
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
    print("ERROR: 'requests' package is required. Install with: pip install requests", file=sys.stderr)
    sys.exit(1)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("ERROR: SUPABASE_URL and SUPABASE_SERVICE_KEY must be set.", file=sys.stderr)
    sys.exit(1)

HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=minimal",
}


# ── Turkish character normalization ──────────────────────────────────────────

_TR_TO_ASCII = str.maketrans("çğıöşüâîûÇĞİÖŞÜ", "cgiousaiu" + "CGIOUS" + "A" + "I" + "U")


def to_searchable(text: str) -> str:
    return text.lower().translate(_TR_TO_ASCII)


_SYNONYMS: dict[str, list[str]] = {
    "gofret": ["wafer"],
    "wafer": ["gofret"],
    "çikolata": ["cikolata", "chocolate"],
    "cikolata": ["çikolata", "chocolate"],
    "chocolate": ["çikolata", "cikolata"],
    "çikolatalı": ["cikolatali"],
    "cikolatali": ["çikolatalı"],
    "bisküvi": ["biskuvi", "biscuit"],
    "biskuvi": ["bisküvi", "biscuit"],
    "biscuit": ["bisküvi", "biskuvi"],
    "içecek": ["icecek", "drink"],
    "icecek": ["içecek", "drink"],
    "süt": ["sut", "milk"],
    "sut": ["süt", "milk"],
    "milk": ["süt", "sut"],
    "peynir": ["cheese"],
    "cheese": ["peynir"],
    "yoğurt": ["yogurt"],
    "yogurt": ["yoğurt"],
    "makarna": ["pasta"],
    "pasta": ["makarna"],
    "snack": ["atıştırmalık", "atistirmalik"],
    "atistirmalik": ["snack", "atıştırmalık"],
    "dondurma": ["ice cream"],
    "kek": ["cake"],
    "cake": ["kek"],
}

_SNACK_TERMS = {
    "cips", "chips", "kraker", "cracker", "çubuk kraker", "cubuk kraker",
    "sticks", "doritos", "lays", "lay's", "pringles", "ruffles", "cheetos",
    "crax", "snack", "atistirmalik", "aperatif", "salty snack",
}
_SNACK_OFF_TAGS = {
    "en:snacks", "en:salty-snacks", "en:chips-and-fries", "en:crisps", "en:crackers",
}
_DAIRY_TERMS = {"sut", "süt", "milk", "ayran", "kefir", "dairy"}
_DAIRY_OFF_TAGS = {"en:dairies", "en:milks", "en:fermented-milk-products", "en:milk-products"}
_YOGURT_TERMS = {"yogurt", "yoğurt", "yoghurt", "peynir", "cheese", "labne", "lor", "kasar", "kaşar"}
_MEAT_TERMS = {
    "salam", "sucuk", "sosis", "jambon", "pastirma", "pastırma", "hindi",
    "dana", "tavuk", "meat", "processed meat", "sausage", "salami", "ham", "deli",
    "şarküteri", "sarkuteri",
}
_MEAT_OFF_TAGS = {
    "en:meats", "en:prepared-meats", "en:sausages", "en:salami", "en:hams",
    "en:poultry", "en:turkey", "en:chicken", "en:beef",
}
_CHOCOLATE_TERMS = {
    "cikolata", "çikolata", "chocolate", "cikolatali", "çikolatalı", "gofret", "wafer",
    "kakao", "cacao", "kinder", "milka", "twix", "snickers", "bounty", "ferrero",
    "albeni", "metro", "karam",
}
_CHOCOLATE_OFF_TAGS = {"en:chocolates", "en:chocolate-confectioneries", "en:wafers"}
_BISCUIT_TERMS = {"bisküvi", "biskuvi", "biscuit", "cookie", "kek", "cake", "muffin", "kurabiye", "petit"}
_BISCUIT_OFF_TAGS = {"en:biscuits", "en:cakes", "en:cookies"}
_SAUCE_TERMS = {"ketcap", "ketçap", "ketchup", "mayonez", "mayonnaise", "sos", "sauce", "hardal", "mustard", "bbq", "salca", "salça"}
_SAUCE_OFF_TAGS = {"en:sauces"}
_BEVERAGE_TERMS = {"icecek", "içecek", "drink", "beverage", "kola", "cola", "soda", "maden suyu", "çay", "cay", "kahve", "coffee", "ayran", "meyve suyu", "limonata"}
_BEVERAGE_OFF_TAGS = {"en:beverages"}
_ENERGY_TERMS = {"enerji icecegi", "enerji içeceği", "energy drink", "energy", "red bull", "redbull", "monster", "burn", "powerzone", "rockstar", "boost"}
_ENERGY_OFF_TAGS = {"en:energy-drinks"}
_FISH_TERMS = {"ton baligi", "ton balığı", "tuna", "sardalya", "sardine", "hamsi", "anchovy", "konserve balik", "konserve balık", "canned fish"}
_FISH_OFF_TAGS = {"en:fish-products", "en:tunas", "en:canned-fishes"}
_BREAKFAST_TERMS = {"kahvalti", "kahvaltı", "breakfast", "recel", "reçel", "jam", "bal", "honey", "pekmez", "tahin", "zeytin", "olive", "musli", "müsli", "cereal"}
_BREAKFAST_OFF_TAGS = {"en:breakfasts"}
_SPREAD_TERMS = {"findik ezmesi", "fındık ezmesi", "fistik ezmesi", "fıstık ezmesi", "peanut butter", "hazelnut", "nutella", "lotus", "spread"}
_SPREAD_OFF_TAGS = {"en:spreads"}
_READY_MEAL_TERMS = {"hazir yemek", "hazır yemek", "ready meal", "hazir corba", "hazır çorba", "soup", "noodle", "ramen", "konserve"}
_READY_MEAL_OFF_TAGS = {"en:ready-meals", "en:canned-foods"}
_BABY_TERMS = {"bebek", "baby", "cocuk", "çocuk", "child", "mama", "ek gida", "ek gıda", "junior", "infant"}
_BABY_OFF_TAGS = {"en:baby-foods"}
_DESSERT_TERMS = {"dondurma", "ice cream", "icecream", "tatli", "tatlı", "sweet", "dessert", "puding", "pudding", "helva", "lokum", "baklava"}
_DESSERT_OFF_TAGS = {"en:desserts", "en:ice-creams"}
_PROTEIN_TERMS = {"protein", "granola", "bar", "healthy", "fit", "diet", "light", "whey", "supplement"}
_PROTEIN_OFF_TAGS = {"en:protein-bars", "en:dietary-supplements"}

_STOP_WORDS = {"ve", "ile", "and", "the", "bir", "a", "an", "g", "ml", "kg", "lt", "gr", "cl"}

_SIZE_RE = re.compile(r"\b\d+[\.,]?\d*\s*(?:kg|gr|g|lt|l|ml|cl)\b", re.IGNORECASE)
_PRICE_RE = re.compile(r"\d+[\.,]?\d*\s*(?:₺|TL)\b", re.IGNORECASE)


def clean_display_name(raw: str) -> str:
    """Strip price/size/duplicate fragments from an OFF product name."""
    # Split on en-dash (–) or em-dash (—)
    for sep in ["–", "—"]:
        idx = raw.find(sep)
        if idx > 0:
            raw = raw[:idx].strip()
            break
    # Split on " - " (spaced hyphen)
    idx = raw.find(" - ")
    if idx > 0:
        raw = raw[:idx].strip()
    # Remove price and size
    raw = _PRICE_RE.sub("", raw)
    raw = _SIZE_RE.sub("", raw)
    raw = raw.strip(" \t\n\r-–—|,")
    raw = re.sub(r"\s{2,}", " ", raw).strip()
    # Title-case
    return " ".join(w.capitalize() for w in raw.split()) if raw else raw


def normalize_text(text: str) -> str:
    s = text.lower()
    s = s.translate(_TR_TO_ASCII)
    s = re.sub(r"[’'`´]", "", s)
    s = re.sub(r"[^a-z0-9\s]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def build_keywords(name: str, brand: str | None) -> list[str]:
    tokens: set[str] = set()
    if brand:
        b = brand.strip().lower()
        tokens.add(b)
        tokens.add(to_searchable(b))
    words = re.split(r"[\s\-–—,/|()]+", name.lower())
    for w in words:
        if len(w) < 2:
            continue
        tokens.add(w)
        asc = to_searchable(w)
        if asc != w:
            tokens.add(asc)
        tokens.update(_SYNONYMS.get(w, []))
        tokens.update(_SYNONYMS.get(asc, []))
    tokens.difference_update(_STOP_WORDS)
    return sorted(t for t in tokens if len(t) >= 2)


def classify_category_tags(
    *,
    name: str,
    brand: str | None,
    keywords: list[str],
    categories_text: str | None = None,
    categories_tags: list[str] | None = None,
) -> tuple[list[str], dict[str, int]]:
    text = normalize_text(" ".join([name, brand or "", categories_text or "", " ".join(keywords)]))
    tags = {normalize_text(t) for t in (categories_tags or [])}

    def has_any(terms: set[str], haystack: str = text) -> bool:
        return any(normalize_text(term) in haystack for term in terms)

    scores: dict[str, int] = {}

    def score(tag: str, value: int) -> None:
        scores[tag] = scores.get(tag, 0) + value

    # Meat
    meat_score = 0
    if tags & {normalize_text(t) for t in _MEAT_OFF_TAGS}:
        meat_score += 8
    if has_any(_MEAT_TERMS):
        meat_score += 5
    if normalize_text(brand or "") == "eti" and not has_any(_MEAT_TERMS):
        meat_score -= 20
    if has_any(_CHOCOLATE_TERMS | _BISCUIT_TERMS | _SAUCE_TERMS | _DAIRY_TERMS | _SNACK_TERMS):
        meat_score -= 20
    score("et_sarkuteri", meat_score)

    # Snacks
    snack_score = 0
    if tags & {normalize_text(t) for t in _SNACK_OFF_TAGS}:
        snack_score += 8
    if has_any(_SNACK_TERMS):
        snack_score += 5
    if has_any(_CHOCOLATE_TERMS | _BISCUIT_TERMS):
        snack_score += 2
    score("cips_kraker", snack_score)

    # Dairy / yogurt
    dairy_score = 0
    if tags & {normalize_text(t) for t in _DAIRY_OFF_TAGS}:
        dairy_score += 8
    if has_any(_DAIRY_TERMS | _YOGURT_TERMS):
        dairy_score += 5
    if has_any(_SNACK_TERMS | _SAUCE_TERMS):
        dairy_score -= 20
    score("sut_urunleri", dairy_score)

    yogurt_score = 0
    if tags & {normalize_text(t) for t in _DAIRY_OFF_TAGS | _YOGURT_TERMS}:
        yogurt_score += 8
    if has_any(_YOGURT_TERMS | _DAIRY_TERMS):
        yogurt_score += 5
    if has_any(_SNACK_TERMS | _SAUCE_TERMS):
        yogurt_score -= 20
    score("peynir_yogurt", yogurt_score)

    # Chocolate / wafer
    choco_score = 0
    if tags & {normalize_text(t) for t in _CHOCOLATE_OFF_TAGS}:
        choco_score += 8
    if has_any(_CHOCOLATE_TERMS):
        choco_score += 5
    if has_any(_MEAT_TERMS | _SAUCE_TERMS):
        choco_score -= 20
    score("cikolata_gofret", choco_score)

    # Biscuits / cakes
    biscuit_score = 0
    if tags & {normalize_text(t) for t in _BISCUIT_OFF_TAGS}:
        biscuit_score += 8
    if has_any(_BISCUIT_TERMS):
        biscuit_score += 5
    if has_any(_MEAT_TERMS | _SAUCE_TERMS):
        biscuit_score -= 20
    score("biskuvi_kek", biscuit_score)

    # Sauce
    sauce_score = 0
    if tags & {normalize_text(t) for t in _SAUCE_OFF_TAGS}:
        sauce_score += 8
    if has_any(_SAUCE_TERMS):
        sauce_score += 5
    score("soslar", sauce_score)

    # Drinks
    drink_score = 0
    if tags & {normalize_text(t) for t in _BEVERAGE_OFF_TAGS}:
        drink_score += 8
    if has_any(_BEVERAGE_TERMS):
        drink_score += 5
    score("icecekler", drink_score)

    energy_score = 0
    if tags & {normalize_text(t) for t in _ENERGY_OFF_TAGS}:
        energy_score += 8
    if has_any(_ENERGY_TERMS):
        energy_score += 5
    score("enerji_icecekleri", energy_score)

    fish_score = 0
    if tags & {normalize_text(t) for t in _FISH_OFF_TAGS}:
        fish_score += 8
    if has_any(_FISH_TERMS):
        fish_score += 5
    score("ton_konserve", fish_score)

    breakfast_score = 0
    if tags & {normalize_text(t) for t in _BREAKFAST_OFF_TAGS}:
        breakfast_score += 8
    if has_any(_BREAKFAST_TERMS):
        breakfast_score += 5
    score("kahvaltilik", breakfast_score)

    spread_score = 0
    if tags & {normalize_text(t) for t in _SPREAD_OFF_TAGS}:
        spread_score += 8
    if has_any(_SPREAD_TERMS):
        spread_score += 5
    score("findik_ezmesi", spread_score)

    ready_score = 0
    if tags & {normalize_text(t) for t in _READY_MEAL_OFF_TAGS}:
        ready_score += 8
    if has_any(_READY_MEAL_TERMS):
        ready_score += 5
    score("hazir_yemek", ready_score)

    baby_score = 0
    if tags & {normalize_text(t) for t in _BABY_OFF_TAGS}:
        baby_score += 8
    if has_any(_BABY_TERMS):
        baby_score += 5
    score("bebek_cocuk", baby_score)

    dessert_score = 0
    if tags & {normalize_text(t) for t in _DESSERT_OFF_TAGS}:
        dessert_score += 8
    if has_any(_DESSERT_TERMS):
        dessert_score += 5
    score("dondurma_tatli", dessert_score)

    protein_score = 0
    if tags & {normalize_text(t) for t in _PROTEIN_OFF_TAGS}:
        protein_score += 8
    if has_any(_PROTEIN_TERMS):
        protein_score += 5
    score("saglikli_protein", protein_score)

    snack_umbrella = max(snack_score, choco_score, biscuit_score, spread_score, protein_score)
    score("atistirmalik", snack_umbrella)

    accepted = [tag for tag, value in scores.items() if value >= 5]
    accepted.sort(key=lambda t: (-scores.get(t, 0), t))
    return accepted, scores


# ── Supabase helpers ──────────────────────────────────────────────────────────


def fetch_products(batch_size: int = 200, offset: int = 0) -> list[dict[str, Any]]:
    url = f"{SUPABASE_URL}/rest/v1/products"
    params = {
        "select": "id,name,brand,normalized_name,search_keywords,category_tags,ingredients_text,source_url",
        "order": "created_at.asc",
        "limit": str(batch_size),
        "offset": str(offset),
    }
    resp = requests.get(url, headers=HEADERS, params=params, timeout=30)
    resp.raise_for_status()
    return resp.json()


def patch_product(product_id: str, patch: dict[str, Any]) -> None:
    url = f"{SUPABASE_URL}/rest/v1/products?id=eq.{product_id}"
    resp = requests.patch(url, headers=HEADERS, json=patch, timeout=30)
    resp.raise_for_status()


# ── Main ──────────────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(description="Backfill search_keywords/category_tags for products.")
    parser.add_argument("--dry-run", action="store_true", help="Print changes without writing.")
    parser.add_argument("--batch-size", type=int, default=200)
    parser.add_argument("--limit", type=int, default=0, help="Stop after processing this many rows.")
    args = parser.parse_args()

    total_updated = 0
    offset = 0
    processed = 0

    diagnostics = {
        "wrong_meat": [],
        "wrong_dairy": [],
        "missing_meat": [],
        "missing_snack": [],
    }

    while True:
        rows = fetch_products(args.batch_size, offset)
        if not rows:
            break

        for row in rows:
            pid = row["id"]
            name = row.get("name") or ""
            brand = row.get("brand")
            current_tags = set(row.get("category_tags") or [])

            clean_name = clean_display_name(name)
            keywords = build_keywords(clean_name or name, brand)
            categories_text = row.get("categories_text") or row.get("categories")
            category_tags, scores = classify_category_tags(
                name=clean_name or name,
                brand=brand,
                keywords=keywords,
                categories_text=categories_text,
                categories_tags=row.get("category_tags") or [],
            )
            normalized = normalize_text(clean_name or name)

            patch: dict[str, Any] = {}
            if sorted(row.get("search_keywords") or []) != keywords:
                patch["search_keywords"] = keywords
            if sorted(row.get("category_tags") or []) != category_tags:
                patch["category_tags"] = category_tags
            if (row.get("normalized_name") or "").strip() != normalized:
                patch["normalized_name"] = normalized

            if not patch:
                if args.dry_run:
                    processed += 1
                continue

            if "et_sarkuteri" in current_tags and "et_sarkuteri" not in category_tags:
                diagnostics["wrong_meat"].append((name, brand, current_tags))
            if ("sut_urunleri" in current_tags or "peynir_yogurt" in current_tags) and not ({"sut_urunleri", "peynir_yogurt"} & set(category_tags)):
                diagnostics["wrong_dairy"].append((name, brand, current_tags))
            if not current_tags and "et_sarkuteri" in category_tags:
                diagnostics["missing_meat"].append((name, brand, category_tags))
            if not current_tags and "cips_kraker" in category_tags:
                diagnostics["missing_snack"].append((name, brand, category_tags))

            if args.dry_run:
                print(
                    f"[DRY] {pid[:8]}… name={name!r} → clean={clean_name!r} "
                    f"keywords={keywords[:6]}… category_tags={category_tags}"
                )
            else:
                patch_product(pid, patch)
                total_updated += 1

            processed += 1
            if args.limit and processed >= args.limit:
                break

        offset += len(rows)
        if len(rows) < args.batch_size:
            break
        if args.limit and processed >= args.limit:
            break

    if args.dry_run:
        print(f"\nDry run complete. {processed} rows inspected.")
        print(f"Wrong meat tags: {len(diagnostics['wrong_meat'])}")
        for name, brand, tags in diagnostics['wrong_meat'][:20]:
            print(f"  - et_sarkuteri rejected: {name!r} / {brand!r} tags={sorted(tags)}")
        print(f"Wrong dairy tags: {len(diagnostics['wrong_dairy'])}")
        for name, brand, tags in diagnostics['wrong_dairy'][:20]:
            print(f"  - dairy rejected: {name!r} / {brand!r} tags={sorted(tags)}")
        print(f"Missing meat tags: {len(diagnostics['missing_meat'])}")
        for name, brand, tags in diagnostics['missing_meat'][:20]:
            print(f"  - likely meat: {name!r} / {brand!r} → {tags}")
        print(f"Missing snack tags: {len(diagnostics['missing_snack'])}")
        for name, brand, tags in diagnostics['missing_snack'][:20]:
            print(f"  - likely snack: {name!r} / {brand!r} → {tags}")
    else:
        print(f"\nDone. Updated {total_updated} products.")


if __name__ == "__main__":
    main()
