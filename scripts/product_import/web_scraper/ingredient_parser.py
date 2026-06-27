#!/usr/bin/env python3
"""Extract and lightly clean ingredients text from a product page.

Scraping stage policy: extract the raw ingredients text only. Do NOT parse it
into tokens, do NOT analyze risk, and NEVER invent missing ingredients — that
is the job of the deterministic Dart analysis engine after admin approval.

Cleaning here is conservative: strip a leading "İçindekiler:" label, collapse
whitespace, and drop obvious trailing marketing sentences. Turkish characters
are preserved verbatim.
"""
from __future__ import annotations

import html as _html
import re

# Labels that introduce an ingredients block (case-insensitive).
_INGREDIENT_LABELS = [
    "i̇çindekiler",
    "içindekiler",
    "icindekiler",
    "i̇çerik",
    "içerik",
    "icerik",
    "bileşenler",
    "bilesenler",
    "ingredients",
]

# Marketing/boilerplate sentences that sometimes get appended after the list.
_MARKETING_MARKERS = [
    "saklama koşulları",
    "saklama kosullari",
    "muhafaza ediniz",
    "son tüketim",
    "son tuketim",
    "tüketim tavsiyesi",
    "üretici",
    "uretici",
    "menşei",
    "mensei",
    "ithalatçı",
    "ithalatci",
    "alerjen uyarısı",  # keep allergen *content* but trim trailing boilerplate
    "www.",
    "http",
]

_MIN_LEN = 3

# Phrases that unambiguously indicate non-ingredient UI or policy content.
# These cannot appear in a real ingredients list; text containing them is
# actively cleared (ingredients_text → None) rather than just flagged.
_JUNK_PHRASES = [
    # Return / exchange policy text
    "iade koşulları",
    "iade kosullari",
    "iade sürecini",
    "iade surecini",
    "iade/değişim",
    "iade/degisim",
    "değişim kapsamı",
    "degisim kapsami",
    "nasıl başlatabilirim",
    "nasil baslatabilirim",
    "ücretsiz iade",
    "ucretsiz iade",
    # UI / cart / checkout
    "sepete ekle",
    "sipariş ver",
    "siparis ver",
    # Shipping / delivery
    "teslimat süresi",
    "teslimat ucreti",
    "teslimat ücreti",
    "kargo bedeli",
    "kargo ücreti",
    # Non-food product text
    "sarf malzeme",            # "bilgisayar sarf malzemeleri" → return policy
    "kapsamında değerlendiri",  # "iade/değişim kapsamında değerlendirilmemektedir"
    "kapsami degerlendiri",
    # Legal / cookie
    "javascript",
    "cookie",
    "çerez politik",
    "cerez politik",
]

# Public constants for ingredient_quality() return values.
INGREDIENT_QUALITY_OK = "ingredients_ok"
INGREDIENT_QUALITY_SUSPICIOUS = "ingredients_suspicious"
INGREDIENT_QUALITY_REJECTED_JUNK = "ingredients_rejected_as_junk"
INGREDIENT_QUALITY_MISSING = "ingredients_missing"


def _junk_fold(text: str) -> str:
    """Lowercase + fix Turkish İ so the combining-dot issue doesn't break matching.

    Python's str.lower() maps İ (U+0130) to i+combining-dot (U+0069+U+0307), which
    means plain-'i' substring searches would miss it. Replace İ with plain i first.
    """
    return text.replace("İ", "i").replace("I", "ı").lower()


def is_junk(text: str | None) -> bool:
    """Return True when [text] is clearly non-ingredient UI or policy content.

    Unlike `is_suspicious()`, junk text should be cleared entirely — the
    candidate's ingredients_text is set to None and the quality is set to
    `ingredients_rejected_as_junk`. The admin sees the field as empty rather
    than pre-populated with garbage.
    """
    t = (text or "").strip()
    if not t:
        return False
    folded = _junk_fold(t)
    return any(p in folded for p in _JUNK_PHRASES)


def ingredient_quality(text: str | None) -> str:
    """Classify ingredient text quality; returns one of the INGREDIENT_QUALITY_* constants."""
    t = (text or "").strip()
    if not t:
        return INGREDIENT_QUALITY_MISSING
    if is_junk(t):
        return INGREDIENT_QUALITY_REJECTED_JUNK
    if is_suspicious(t):
        return INGREDIENT_QUALITY_SUSPICIOUS
    return INGREDIENT_QUALITY_OK


def _strip_label(text: str) -> str:
    lowered = text.lower()
    for label in _INGREDIENT_LABELS:
        idx = lowered.find(label)
        if idx != -1:
            after = text[idx + len(label):]
            # drop a leading separator (":", "-", whitespace)
            after = re.sub(r"^\s*[:\-–—]?\s*", "", after)
            if len(after.strip()) >= _MIN_LEN:
                return after
    return text


def _trim_marketing(text: str) -> str:
    lowered = text.lower()
    cut = len(text)
    for marker in _MARKETING_MARKERS:
        idx = lowered.find(marker)
        if idx != -1:
            cut = min(cut, idx)
    return text[:cut]


def _strip_html(text: str) -> str:
    """Remove HTML tags/entities that leak in from embedded JSON or markup."""
    text = _html.unescape(text)
    text = re.sub(r"<[^>]*>", " ", text)  # well-formed tags
    # Stray/truncated tag fragments, e.g. "/strong>" or "br>".
    text = re.sub(
        r"(?i)<?/?(?:strong|br|p|div|span|b|i|em|ul|ol|li|table|tr|td|th)\s*/?>",
        " ",
        text,
    )
    return text


def is_suspicious(text: str | None) -> bool:
    """Lightweight quality check: does [text] look like a real ingredients list?

    Suspicious when: empty/too short (<20 meaningful chars), only a net-amount
    line, nutrition-table labels mixed in, obvious UI junk, or no separator
    with very few tokens. Mirrors the Dart admin-side heuristic.

    Suspicious text never auto-approves; it only lowers the quality score /
    flags the row for review — an admin can still correct and approve manually.
    """
    t = (text or "").strip()
    if len(t) < 20:
        return True
    folded = t.lower()
    if folded.startswith("net miktar"):
        return True
    if "besin değer" in folded or "besin deger" in folded:
        return True  # nutrition table text leaked into ingredients
    if any(junk in folded for junk in ("javascript", "cookie", "çerez politik")):
        return True  # obvious UI junk
    tokens = t.split()
    if "," not in t and ";" not in t and len(tokens) < 5:
        return True  # no separators and too few tokens for a packaged product
    return False


def clean_ingredients(raw: str | None) -> str | None:
    """Return cleaned ingredients text, or None when nothing usable remains."""
    if not raw:
        return None
    text = _strip_html(str(raw))
    text = _strip_label(text)
    text = _trim_marketing(text)
    # Collapse all whitespace (incl. newlines) to single spaces.
    text = re.sub(r"\s+", " ", text).strip()
    # Strip dangling separators left by trimming.
    text = re.sub(r"[\s;,.\-–—]+$", "", text).strip()
    if len(text) < _MIN_LEN:
        return None
    return text
