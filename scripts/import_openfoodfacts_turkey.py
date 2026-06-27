#!/usr/bin/env python3
"""Import Turkish Open Food Facts dump data into Supabase.

This script is dump-driven, not API-loop driven.
It supports JSONL and CSV OFF exports, filters Turkey food products,
computes search_keywords and category_tags deterministically, and upserts
products by barcode.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Iterable

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass

try:
    import requests
except ImportError:
    print("ERROR: 'requests' is required. Install with: pip install requests", file=sys.stderr)
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

_TR_TO_ASCII = str.maketrans("çğıöşüâîûÇĞİÖŞÜ", "cgiousaiu" + "CGIOUS" + "A" + "I" + "U")


def to_searchable(text: str) -> str:
    return text.lower().translate(_TR_TO_ASCII)


def normalize_text(text: str) -> str:
    s = to_searchable(text)
    s = re.sub(r"[’'`´]", "", s)
    s = re.sub(r"[^a-z0-9\s]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def clean_display_name(raw: str, brand: str | None = None) -> str:
    s = (raw or "").strip()
    if not s:
        return s
    s = re.sub(r"\s*[–—]\s*|\s+-\s+", " - ", s)
    parts = [p.strip() for p in re.split(r"\s*[–—]\s*|\s+-\s+", s) if p.strip()]
    cleaned: list[str] = []
    for part in parts:
        candidate = re.sub(r"\d+[\.,]?\d*\s*(?:₺|TL)", "", part, flags=re.IGNORECASE)
        candidate = candidate.replace("₺", "")
        candidate = re.sub(r"\b\d+[\.,]?\d*\s*(?:kg|gr|g|lt|l|ml|cl|kkal|kcal)\b", "", candidate, flags=re.IGNORECASE)
        candidate = re.sub(r"[\s\-|,]+$", "", candidate).strip()
        candidate = re.sub(r"\s{2,}", " ", candidate).strip()
        if not candidate:
            continue
        if brand and normalize_text(candidate) == normalize_text(brand):
            continue
        cleaned.append(candidate)
    if cleaned:
        cleaned.sort(key=len, reverse=True)
        s = cleaned[0]
    s = re.sub(r"\s{2,}", " ", s).strip()
    return " ".join(w[:1].upper() + w[1:] if w else w for w in s.split())


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

_STOP_WORDS = {"ve", "ile", "and", "the", "bir", "a", "an", "g", "ml", "kg", "lt", "gr", "cl"}


def split_words(s: str) -> list[str]:
    return [w for w in re.split(r"[\s\-–—,\/\|()]+", s) if w]


def build_keywords(name: str, brand: str | None, categories_tags: list[str] | None = None) -> list[str]:
    tokens: set[str] = set()
    if brand:
        b = brand.strip().lower()
        tokens.add(b)
        tokens.add(to_searchable(b))
    for word in split_words(name.lower()):
        if len(word) < 2:
            continue
        tokens.add(word)
        ascii_word = to_searchable(word)
        tokens.add(ascii_word)
        tokens.update(_SYNONYMS.get(word, []))
        tokens.update(_SYNONYMS.get(ascii_word, []))
    if categories_tags:
        for tag in categories_tags[:8]:
            cleaned = normalize_text(tag.replace("en:", "").replace("-", " "))
            for part in cleaned.split():
                if len(part) >= 3:
                    tokens.add(part)
    tokens.difference_update(_STOP_WORDS)
    return sorted(t for t in tokens if len(t) >= 2)


_SNACK_OFF_TAGS = {"en:snacks", "en:salty-snacks", "en:chips-and-fries", "en:crisps", "en:crackers"}
_DAIRY_OFF_TAGS = {"en:dairies", "en:milks", "en:fermented-milk-products", "en:milk-products"}
_YOGURT_OFF_TAGS = {"en:cheeses", "en:yogurts", "en:fermented-milk-products", "en:milk-products"}
_MEAT_OFF_TAGS = {"en:meats", "en:prepared-meats", "en:sausages", "en:salami", "en:hams", "en:poultry", "en:turkey", "en:chicken", "en:beef"}
_CHOCOLATE_OFF_TAGS = {"en:chocolates", "en:chocolate-confectioneries", "en:wafers"}
_BISCUIT_OFF_TAGS = {"en:biscuits", "en:cakes", "en:cookies"}
_SAUCE_OFF_TAGS = {"en:sauces"}
_BEVERAGE_OFF_TAGS = {"en:beverages"}
_ENERGY_OFF_TAGS = {"en:energy-drinks"}
_FISH_OFF_TAGS = {"en:fish-products", "en:tunas", "en:canned-fishes"}
_BREAKFAST_OFF_TAGS = {"en:breakfasts"}
_SPREAD_OFF_TAGS = {"en:spreads"}
_READY_MEAL_OFF_TAGS = {"en:ready-meals", "en:canned-foods"}
_BABY_OFF_TAGS = {"en:baby-foods"}
_DESSERT_OFF_TAGS = {"en:desserts", "en:ice-creams"}
_PROTEIN_OFF_TAGS = {"en:protein-bars", "en:dietary-supplements"}

_SNACK_TERMS = {"cips", "chips", "kraker", "cracker", "çubuk kraker", "cubuk kraker", "sticks", "doritos", "lays", "lay's", "pringles", "ruffles", "cheetos", "crax", "snack", "atistirmalik", "aperatif"}
_DAIRY_TERMS = {"sut", "süt", "milk", "ayran", "kefir", "dairy"}
_YOGURT_TERMS = {"yogurt", "yoğurt", "yoghurt", "peynir", "cheese", "labne", "lor", "kasar", "kaşar"}
_MEAT_TERMS = {"salam", "sucuk", "sosis", "jambon", "pastirma", "pastırma", "hindi", "dana", "tavuk", "meat", "sausage", "salami", "ham", "deli", "şarküteri", "sarkuteri"}
_CHOCOLATE_TERMS = {"cikolata", "çikolata", "chocolate", "cikolatali", "çikolatalı", "gofret", "wafer", "kakao", "cacao", "kinder", "milka", "twix", "snickers", "bounty", "ferrero", "albeni", "metro", "karam"}
_BISCUIT_TERMS = {"bisküvi", "biskuvi", "biscuit", "cookie", "kek", "cake", "muffin", "kurabiye", "petit"}
_SAUCE_TERMS = {"ketcap", "ketçap", "ketchup", "mayonez", "mayonnaise", "sos", "sauce", "hardal", "mustard", "bbq", "salca", "salça"}
_BEVERAGE_TERMS = {"icecek", "içecek", "drink", "beverage", "kola", "cola", "soda", "maden suyu", "çay", "cay", "kahve", "coffee", "ayran", "meyve suyu", "limonata"}
_ENERGY_TERMS = {"enerji icecegi", "enerji içeceği", "energy drink", "energy", "red bull", "redbull", "monster", "burn", "powerzone", "rockstar", "boost"}
_FISH_TERMS = {"ton baligi", "ton balığı", "tuna", "sardalya", "sardine", "hamsi", "anchovy", "konserve balik", "konserve balık", "canned fish"}
_BREAKFAST_TERMS = {"kahvalti", "kahvaltı", "breakfast", "recel", "reçel", "jam", "bal", "honey", "pekmez", "tahin", "zeytin", "olive", "musli", "müsli", "cereal"}
_SPREAD_TERMS = {"findik ezmesi", "fındık ezmesi", "fistik ezmesi", "fıstık ezmesi", "peanut butter", "hazelnut", "nutella", "lotus", "spread"}
_READY_MEAL_TERMS = {"hazir yemek", "hazır yemek", "ready meal", "hazir corba", "hazır çorba", "soup", "noodle", "ramen", "konserve"}
_BABY_TERMS = {"bebek", "baby", "cocuk", "çocuk", "child", "mama", "ek gida", "ek gıda", "junior", "infant"}
_DESSERT_TERMS = {"dondurma", "ice cream", "icecream", "tatli", "tatlı", "sweet", "dessert", "puding", "pudding", "helva", "lokum", "baklava"}
_PROTEIN_TERMS = {"protein", "granola", "bar", "healthy", "fit", "diet", "light", "whey", "supplement"}


def classify_category_tags(
    *,
    name: str,
    brand: str | None,
    keywords: list[str],
    categories_text: str | None = None,
    categories_tags: list[str] | None = None,
) -> list[str]:
    text = normalize_text(" ".join([name, brand or "", categories_text or "", " ".join(keywords)]))
    off_tags = {normalize_text(t) for t in (categories_tags or [])}

    def has_any(terms: set[str]) -> bool:
        return any(normalize_text(term) in text for term in terms)

    scores: dict[str, int] = {}

    def score(tag: str, value: int) -> None:
        scores[tag] = scores.get(tag, 0) + value

    # Meat
    meat_score = 0
    if off_tags & _MEAT_OFF_TAGS:
        meat_score += 8
    if has_any(_MEAT_TERMS):
        meat_score += 5
    if normalize_text(brand or "") == "eti" and not has_any(_MEAT_TERMS):
        meat_score -= 20
    if has_any(_CHOCOLATE_TERMS | _BISCUIT_TERMS | _SAUCE_TERMS | _DAIRY_TERMS | _SNACK_TERMS):
        meat_score -= 20
    score("et_sarkuteri", meat_score)

    snack_score = 0
    if off_tags & _SNACK_OFF_TAGS:
        snack_score += 8
    if has_any(_SNACK_TERMS):
        snack_score += 5
    if has_any(_CHOCOLATE_TERMS | _BISCUIT_TERMS):
        snack_score += 2
    score("cips_kraker", snack_score)

    dairy_score = 0
    if off_tags & _DAIRY_OFF_TAGS:
        dairy_score += 8
    if has_any(_DAIRY_TERMS | _YOGURT_TERMS):
        dairy_score += 5
    if has_any(_SNACK_TERMS | _SAUCE_TERMS):
        dairy_score -= 20
    score("sut_urunleri", dairy_score)

    yogurt_score = 0
    if off_tags & _YOGURT_OFF_TAGS:
        yogurt_score += 8
    if has_any(_YOGURT_TERMS | _DAIRY_TERMS):
        yogurt_score += 5
    if has_any(_SNACK_TERMS | _SAUCE_TERMS):
        yogurt_score -= 20
    score("peynir_yogurt", yogurt_score)

    choco_score = 0
    if off_tags & _CHOCOLATE_OFF_TAGS:
        choco_score += 8
    if has_any(_CHOCOLATE_TERMS):
        choco_score += 5
    if has_any(_MEAT_TERMS | _SAUCE_TERMS):
        choco_score -= 20
    score("cikolata_gofret", choco_score)

    biscuit_score = 0
    if off_tags & _BISCUIT_OFF_TAGS:
        biscuit_score += 8
    if has_any(_BISCUIT_TERMS):
        biscuit_score += 5
    if has_any(_MEAT_TERMS | _SAUCE_TERMS):
        biscuit_score -= 20
    score("biskuvi_kek", biscuit_score)

    sauce_score = 0
    if off_tags & _SAUCE_OFF_TAGS:
        sauce_score += 8
    if has_any(_SAUCE_TERMS):
        sauce_score += 5
    score("soslar", sauce_score)

    drink_score = 0
    if off_tags & _BEVERAGE_OFF_TAGS:
        drink_score += 8
    if has_any(_BEVERAGE_TERMS):
        drink_score += 5
    score("icecekler", drink_score)

    energy_score = 0
    if off_tags & _ENERGY_OFF_TAGS:
        energy_score += 8
    if has_any(_ENERGY_TERMS):
        energy_score += 5
    score("enerji_icecekleri", energy_score)

    fish_score = 0
    if off_tags & _FISH_OFF_TAGS:
        fish_score += 8
    if has_any(_FISH_TERMS):
        fish_score += 5
    score("ton_konserve", fish_score)

    breakfast_score = 0
    if off_tags & _BREAKFAST_OFF_TAGS:
        breakfast_score += 8
    if has_any(_BREAKFAST_TERMS):
        breakfast_score += 5
    score("kahvaltilik", breakfast_score)

    spread_score = 0
    if off_tags & _SPREAD_OFF_TAGS:
        spread_score += 8
    if has_any(_SPREAD_TERMS):
        spread_score += 5
    score("findik_ezmesi", spread_score)

    ready_score = 0
    if off_tags & _READY_MEAL_OFF_TAGS:
        ready_score += 8
    if has_any(_READY_MEAL_TERMS):
        ready_score += 5
    score("hazir_yemek", ready_score)

    baby_score = 0
    if off_tags & _BABY_OFF_TAGS:
        baby_score += 8
    if has_any(_BABY_TERMS):
        baby_score += 5
    score("bebek_cocuk", baby_score)

    dessert_score = 0
    if off_tags & _DESSERT_OFF_TAGS:
        dessert_score += 8
    if has_any(_DESSERT_TERMS):
        dessert_score += 5
    score("dondurma_tatli", dessert_score)

    protein_score = 0
    if off_tags & _PROTEIN_OFF_TAGS:
        protein_score += 8
    if has_any(_PROTEIN_TERMS):
        protein_score += 5
    score("saglikli_protein", protein_score)

    score("atistirmalik", max(snack_score, choco_score, biscuit_score, spread_score, protein_score))

    accepted = [tag for tag, value in scores.items() if value >= 5]
    accepted.sort(key=lambda t: (-scores.get(t, 0), t))
    return accepted


def is_turkey_product(row: dict[str, Any]) -> bool:
    countries = normalize_text(" ".join([
        str(row.get("countries") or ""),
        " ".join(row.get("countries_tags") or []),
    ]))
    return "turkey" in countries or "türkiye" in countries or "turkiye" in countries


_NON_FOOD_HINTS = ("cosmetic", "pet-food", "supplement", "household", "toothpaste", "drug", "pharmaceutical", "electronics", "toy")


def is_food_product(row: dict[str, Any]) -> bool:
    tags = normalize_text(" ".join(row.get("categories_tags") or []))
    if any(hint in tags for hint in _NON_FOOD_HINTS):
        return False
    return True


def pick_name(row: dict[str, Any]) -> str:
    candidates = [
        row.get("product_name_tr"),
        row.get("product_name"),
        row.get("abbreviated_product_name_tr"),
        row.get("generic_name_tr"),
        row.get("product_name_en"),
        row.get("generic_name"),
    ]
    for candidate in candidates:
        if isinstance(candidate, str) and candidate.strip():
            return clean_display_name(candidate, brand=row.get("brands"))
    return "Bilinmeyen Ürün"


def extract_ingredients_text(row: dict[str, Any]) -> str | None:
    for key in ("ingredients_text_tr", "ingredients_text", "ingredients_text_en"):
        value = row.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def upsert_product(product: dict[str, Any], *, dry_run: bool, backfill_existing: bool) -> tuple[str, str]:
    barcode = product["barcode"]
    lookup = requests.get(
        f"{SUPABASE_URL}/rest/v1/products",
        headers=HEADERS,
        params={"select": "id,verification_status", "barcode": f"eq.{barcode}"},
        timeout=30,
    )
    lookup.raise_for_status()
    existing = lookup.json()

    if dry_run:
        if existing:
            return ("update", existing[0]["id"])
        return ("insert", "dry-run")

    if existing:
        if not backfill_existing and existing[0].get("verification_status") == "verified":
            return ("skip", existing[0]["id"])
        product_id = existing[0]["id"]
        resp = requests.patch(
            f"{SUPABASE_URL}/rest/v1/products?id=eq.{product_id}",
            headers=HEADERS,
            json=product,
            timeout=30,
        )
        resp.raise_for_status()
        return ("update", product_id)

    resp = requests.post(
        f"{SUPABASE_URL}/rest/v1/products",
        headers=HEADERS,
        json=product,
        timeout=30,
    )
    resp.raise_for_status()
    return ("insert", barcode)


def iter_rows(path: Path, fmt: str) -> Iterable[dict[str, Any]]:
    if fmt == "jsonl":
        with path.open("r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue
    elif fmt == "csv":
        with path.open("r", encoding="utf-8", newline="") as fh:
            reader = csv.DictReader(fh)
            for row in reader:
                yield row
    elif fmt == "json":
        with path.open("r", encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, list):
            for row in data:
                if isinstance(row, dict):
                    yield row
    else:
        raise ValueError(f"Unsupported format: {fmt}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Import Turkish OFF dump into Supabase")
    parser.add_argument("--input", required=True, help="Path to OFF JSONL/CSV/JSON dump")
    parser.add_argument("--format", choices=["auto", "jsonl", "csv", "json"], default="auto")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--category", action="append", default=[])
    parser.add_argument("--only-with-image", action="store_true")
    parser.add_argument("--only-with-ingredients", action="store_true")
    parser.add_argument("--only-with-nutrition", action="store_true")
    parser.add_argument("--backfill-existing", action="store_true")
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
      print(f"Input file not found: {input_path}", file=sys.stderr)
      sys.exit(1)

    fmt = args.format
    if fmt == "auto":
        suffix = input_path.suffix.lower()
        if suffix == ".csv":
            fmt = "csv"
        elif suffix == ".jsonl":
            fmt = "jsonl"
        else:
            fmt = "json"

    processed = 0
    imported = 0
    updated = 0
    skipped = 0

    category_filter = set(args.category)

    for row in iter_rows(input_path, fmt):
        barcode = str(row.get("code") or row.get("barcode") or "").strip()
        if not barcode:
            continue
        if args.limit and processed >= args.limit:
            break
        processed += 1

        if not is_turkey_product(row):
            skipped += 1
            continue
        if not is_food_product(row):
            skipped += 1
            continue

        name = pick_name(row)
        brand = (row.get("brands") or None)
        if isinstance(brand, str):
            brand = brand.strip() or None
        ingredients_text = extract_ingredients_text(row)
        nutriments = row.get("nutriments") if isinstance(row.get("nutriments"), dict) else None
        image_url = row.get("image_front_url") or row.get("image_url") or row.get("image_front_small_url")
        categories_text = row.get("categories") if isinstance(row.get("categories"), str) else None
        categories_tags = row.get("categories_tags") if isinstance(row.get("categories_tags"), list) else None

        if args.only_with_image and not image_url:
            skipped += 1
            continue
        if args.only_with_ingredients and not ingredients_text:
            skipped += 1
            continue
        if args.only_with_nutrition and not nutriments:
            skipped += 1
            continue

        keywords = build_keywords(name, brand, categories_tags)
        category_tags = classify_category_tags(
            name=name,
            brand=brand,
            keywords=keywords,
            categories_text=categories_text,
            categories_tags=categories_tags,
        )

        if category_filter and not (category_filter & set(category_tags)):
            skipped += 1
            continue

        normalized_name = normalize_text(name)
        nutrition_text = json.dumps(nutriments) if nutriments else None
        verification_status = "pending" if (not ingredients_text and not image_url) else "imported"

        product = {
            "barcode": barcode,
            "name": name,
            "normalized_name": normalized_name,
            "brand": brand,
            "image_url": image_url,
            "ingredients_text": ingredients_text,
            "nutrition_text": nutrition_text,
            "source": "Open Food Facts Turkey Dump",
            "source_url": row.get("url"),
            "verification_status": verification_status,
            "search_keywords": keywords,
            "category_tags": category_tags,
        }

        action, _ = upsert_product(product, dry_run=args.dry_run, backfill_existing=args.backfill_existing)
        if action == "insert":
            imported += 1
        elif action == "update":
            updated += 1
        else:
            skipped += 1

        if args.dry_run:
            print(f"[DRY] {barcode} {name!r} -> tags={category_tags}")

    if args.dry_run:
        print(f"\nDry run complete. processed={processed} skipped={skipped}")
    else:
        print(f"\nDone. inserted={imported} updated={updated} skipped={skipped} processed={processed}")


if __name__ == "__main__":
    main()
