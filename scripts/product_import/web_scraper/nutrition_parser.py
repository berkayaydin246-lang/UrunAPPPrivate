#!/usr/bin/env python3
"""Parse Turkish nutrition tables into the project's nutrition_json shape.

Output keys are the canonical keys consumed by the Flutter app
(`NutritionData.fromMap`): energy_kcal, fat, saturated_fat, carbohydrates,
sugars, fiber, proteins, salt, sodium. NOTE: the app's keys intentionally do
NOT carry a `_100g` suffix; values are understood to be per-100g/ml. We keep
that contract so scraped rows render in the existing product detail / admin UI
unchanged.

Deterministic only: we extract numbers that are present, convert obvious units,
and derive salt from sodium. We never invent missing values, and when a table
is clearly per-serving (not per-100g) we record a warning and skip normalization
rather than guess.
"""
from __future__ import annotations

import re

# label aliases (ASCII-folded, lowercase) → canonical field.
# Order matters: more specific labels are matched before generic ones so that
# "doymus yag" is not swallowed by "yag".
_LABELS: list[tuple[str, list[str]]] = [
    ("saturated_fat", ["doymus yag", "doymus", "saturated fat", "saturates"]),
    ("fat", ["yag", "fat", "toplam yag"]),
    ("sugars", ["seker", "sekerler", "sugars", "sugar"]),
    ("carbohydrates", ["karbonhidrat", "carbohydrate", "carbohydrates"]),
    ("fiber", ["lif", "fibre", "fiber", "diyet lifi"]),
    ("proteins", ["protein", "proteins"]),
    ("salt", ["tuz", "salt"]),
    ("sodium", ["sodyum", "sodium"]),
    ("energy_kcal", ["enerji", "kalori", "energy", "calories"]),
]

# Per-serving indicators (avoid normalizing per-serving data as if per-100g).
_PER_SERVING_HINTS = ("porsiyon", "servis", "per serving", "serving", "adet")
# Per-100 markers. "100 g / ml", "100 g/ml", "100g/ml" all contain one of these.
_PER_100_HINTS = ("100 g", "100g", "100 ml", "100ml", "100 gr", "100gr", "per 100")


def _ascii_fold(text: str) -> str:
    table = str.maketrans(
        {
            "ç": "c", "Ç": "c", "ğ": "g", "Ğ": "g", "ı": "i", "İ": "i",
            "ö": "o", "Ö": "o", "ş": "s", "Ş": "s", "ü": "u", "Ü": "u",
            "â": "a", "î": "i", "û": "u",
        }
    )
    return text.translate(table).lower()


def _to_float(token: str) -> float | None:
    token = token.strip()
    if not token:
        return None
    if "," in token and "." in token:
        # Turkish thousands "." + decimal "," → 2.000,5 == 2000.5
        token = token.replace(".", "").replace(",", ".")
    else:
        # Lone comma is a decimal separator.
        token = token.replace(",", ".")
    m = re.search(r"-?\d+(?:\.\d+)?", token)
    if not m:
        return None
    try:
        return float(m.group(0))
    except ValueError:
        return None


def detect_basis(text: str) -> str:
    """Return 'per_100', 'per_serving' or 'unknown' for a nutrition block."""
    folded = _ascii_fold(text)
    has_100 = any(h in folded for h in _PER_100_HINTS)
    has_serving = any(h in folded for h in _PER_SERVING_HINTS)
    if has_100:
        return "per_100"
    if has_serving:
        return "per_serving"
    return "unknown"


def _blank_span(text: str, start: int, end: int) -> str:
    """Replace [start:end) with spaces so later labels can't re-match it."""
    return text[:start] + (" " * (end - start)) + text[end:]


def _consume_energy(working: str) -> tuple[float | None, str]:
    """Extract energy (prefer kcal over kJ) and blank the consumed span."""
    kcal = re.search(r"([\d.,]+)\s*(?:kcal|kkal)", working)
    if kcal:
        return _to_float(kcal.group(1)), _blank_span(working, kcal.start(), kcal.end())
    kj = re.search(r"([\d.,]+)\s*kj", working)
    if kj:
        val = _to_float(kj.group(1))
        energy = round(val / 4.184, 1) if val is not None else None
        return energy, _blank_span(working, kj.start(), kj.end())
    return None, working


def parse_nutrition(text: str | None) -> tuple[dict[str, float], list[str]]:
    """Parse a nutrition text block → (nutrition_json, warnings).

    Values are stored per 100g/ml. When the block is clearly per-serving we
    skip the values and return a warning so the admin can decide.

    Matching consumes (blanks out) each span as it is found, processing more
    specific labels first (e.g. "doymuş yağ" before "yağ"). This makes the
    parser robust to both multi-line tables and single-line inline tables.
    """
    warnings: list[str] = []
    if not text or not text.strip():
        return {}, warnings

    basis = detect_basis(text)
    if basis == "per_serving":
        warnings.append("nutrition_per_serving_not_normalized")
        return {}, warnings
    if basis == "unknown":
        warnings.append("nutrition_basis_unknown_assumed_per_100")

    working = _ascii_fold(text)
    out: dict[str, float] = {}

    # Energy first (special kJ/kcal handling).
    energy, working = _consume_energy(working)
    if energy is not None:
        out["energy_kcal"] = energy

    # Remaining fields, most-specific labels first (see _LABELS ordering).
    for field, aliases in _LABELS:
        if field == "energy_kcal":
            continue
        for alias in aliases:
            pattern = re.compile(
                r"(?<![a-z])" + re.escape(alias)
                + r"\s*[:\-]?\s*([\d.,]+)\s*(kcal|kkal|kj|mg|g|gr|ml)?"
            )
            m = pattern.search(working)
            if not m:
                continue
            value = _to_float(m.group(1))
            if value is None:
                continue
            unit = (m.group(2) or "").lower()
            if field in ("salt", "sodium") and unit == "mg":
                value = round(value / 1000.0, 4)
            out[field] = value
            working = _blank_span(working, m.start(), m.end())
            break

    # Derive salt from sodium (salt = sodium * 2.5) when salt absent.
    if "salt" not in out and "sodium" in out:
        out["salt"] = round(out["sodium"] * 2.5, 4)

    if not out:
        warnings.append("nutrition_no_values_found")
    return out, warnings


# ── Generic label classification + pair parsing ──────────────────────────────
# These power the multi-strategy extractor (HTML tables, div rows, embedded
# JSON) where each nutrient already arrives as a (label, value) pair. The text
# parser above stays as the last-resort fallback.

_VALUE_RE = re.compile(r"(-?[\d.,]+)\s*(kcal|kkal|kj|mg|gr|g|ml)?", re.IGNORECASE)


def classify_label(label: str | None, value: str | None = "") -> str | None:
    """Map a Turkish/English nutrient label to a canonical field, or None.

    `value` is consulted only to disambiguate energy (kJ vs kcal). Specific
    labels are checked before generic ones so "Doymuş yağ" never becomes "Yağ".
    Short ambiguous tokens (yağ/fat/lif/tuz/salt) require word boundaries so
    unrelated words (e.g. "Fatura", "Yağmur") are not misclassified.
    """
    s = _ascii_fold(label or "")
    v = _ascii_fold(value or "")
    if not s:
        return None
    if "doymus" in s:
        return "saturated_fat"
    if any(k in s for k in ("enerji", "kalori", "energy", "calor")):
        return "energy_kj" if ("kj" in s or "kj" in v) else "energy_kcal"
    if "seker" in s or "sugar" in s:
        return "sugars"
    if re.search(r"\blif\b", s) or "fibre" in s or "fiber" in s:
        return "fiber"
    if "karbonhidrat" in s or "carbohydr" in s:
        return "carbohydrates"
    if "protein" in s:
        return "proteins"
    if "sodyum" in s or "sodium" in s:
        return "sodium"
    if re.search(r"\btuz\b", s) or re.search(r"\bsalt\b", s):
        return "salt"
    if re.search(r"\byag\b", s) or re.search(r"\bfat\b", s):
        return "fat"
    return None


def parse_value(text: str | None) -> tuple[float | None, str | None]:
    """Parse a value cell like '15,0 g' / '199.0' / '400 mg' → (number, unit)."""
    if text is None:
        return None, None
    m = _VALUE_RE.search(str(text))
    if not m:
        return None, None
    return _to_float(m.group(1)), (m.group(2) or "").lower() or None


def parse_pairs(
    pairs: list[tuple[str, str]], basis_text: str = ""
) -> tuple[dict[str, float], list[str]]:
    """Build nutrition_json from (label, value) pairs from any site structure.

    Includes `energy_kj` when present; always derives `energy_kcal` from kJ when
    kcal is missing so the Flutter app (which reads energy_kcal) has a value.
    """
    warnings: list[str] = []
    combined = (basis_text or "") + " " + " ".join(f"{l} {v}" for l, v in pairs)
    basis = detect_basis(combined)
    if basis == "per_serving":
        warnings.append("nutrition_per_serving_not_normalized")
        return {}, warnings
    if basis == "unknown":
        warnings.append("nutrition_basis_unknown_assumed_per_100")

    out: dict[str, float] = {}
    for label, value in pairs:
        field = classify_label(label, value)
        if not field or field in out:
            continue
        num, unit = parse_value(value)
        if num is None:
            # value may be embedded in the label text ("Yağ 15 g")
            num, unit = parse_value(label)
        if num is None:
            continue
        if field in ("salt", "sodium") and unit == "mg":
            num = round(num / 1000.0, 4)
        out[field] = num

    if "energy_kcal" not in out and "energy_kj" in out:
        out["energy_kcal"] = round(out["energy_kj"] / 4.184, 1)
    if "salt" not in out and "sodium" in out:
        out["salt"] = round(out["sodium"] * 2.5, 4)

    if not out:
        warnings.append("nutrition_no_values_found")
    return out, warnings


def build_nutrition(
    pairs: list[tuple[str, str]] | None,
    *,
    basis_text: str = "",
    fallback_text: str = "",
) -> tuple[dict[str, float], list[str]]:
    """Preferred entry point: try structured pairs first, then text fallback."""
    if pairs:
        data, warnings = parse_pairs(pairs, basis_text)
        if data:
            return data, warnings
    if fallback_text and fallback_text.strip():
        return parse_nutrition(fallback_text)
    return {}, ["nutrition_no_values_found"]
