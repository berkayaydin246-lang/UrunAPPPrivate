#!/usr/bin/env python3
"""Score image candidates to pick a clean front/vitrine product image.

We never download large files to decide; scoring is URL/context based and an
optional cheap HEAD probe can refine dimensions. The goal is to prefer a
product-only packshot (white/simple background) over shelf photos, banners,
logos, category thumbnails and campaign art.
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field

# Positive URL hints (folded to lowercase before matching).
_GOOD_URL_HINTS = (
    "product", "urun", "/p/", "packshot", "front", "on-yuz", "onyuz",
    "ambalaj", "vitrin", "detail", "buyuk", "large", "original", "zoom",
)
# Negative URL hints — these strongly suggest NOT a clean packshot.
_BAD_URL_HINTS = (
    "banner", "logo", "shelf", "raf", "kategori", "category", "campaign",
    "kampanya", "thumb", "thumbnail", "icon", "sprite", "placeholder",
    "noimage", "no-image", "default", "avatar", "slider", "promo", "afis",
    "unknown", "question", "chef",
)
# URL patterns that indicate a back-of-pack / label image.
# Matched against the lowercased URL; back/label images should never be selected
# as image_front_url when a better (front) image is available.
_BACK_HINTS = (
    "back-label", "back_label", "backlabel",
    "back", "arka", "arka-yuz", "arka_yuz",
    "arka-etiket", "arka_etiket", "etiket", "label",
    "_2-", "_yan", "-yan",
)
_INGREDIENT_HINTS = ("icindekiler", "ingredients")
_NUTRITION_HINTS = (
    "besin", "nutrition", "deger", "nutrition-table", "nutrition_table",
)

# Heuristic small-image markers embedded in URLs, e.g. "_50x50", "100x100".
_SMALL_DIM_RE = re.compile(r"(\d{1,3})x(\d{1,3})")


@dataclass
class ImageCandidate:
    url: str
    in_schema: bool = False
    in_gallery: bool = False
    near_title: bool = False
    is_api_primary: bool = False   # first/primary image from the source's listing API
    gallery_index: int | None = None  # 0 = first in its source, None = position unknown
    source: str = "unknown"
    context_text: str | None = None
    width: int | None = None
    height: int | None = None
    score: int = 0
    reasons: list[str] = field(default_factory=list)


@dataclass
class ImageSelection:
    selected: ImageCandidate | None
    scored: list[ImageCandidate]
    quality: str
    confidence: str

    @property
    def selected_role(self) -> str:
        return classify_image_role(self.selected)


def _contains_token(haystack: str, token: str | None) -> bool:
    if not token:
        return False
    folded = re.sub(r"[^a-z0-9]+", "", _fold_text(token))
    if len(folded) < 3:
        return False
    return folded in re.sub(r"[^a-z0-9]+", "", haystack)


def _fold_text(text: str | None) -> str:
    if not text:
        return ""
    lowered = text.lower().translate(
        str.maketrans({
            "ç": "c",
            "ğ": "g",
            "ı": "i",
            "ö": "o",
            "ş": "s",
            "ü": "u",
        })
    )
    normalized = unicodedata.normalize("NFKD", lowered)
    return "".join(ch for ch in normalized if not unicodedata.combining(ch))


def _image_text(cand: ImageCandidate) -> str:
    return " ".join(part for part in (_fold_text(cand.url), _fold_text(cand.context_text)) if part)


def _contains_hint(text: str, hints: tuple[str, ...]) -> bool:
    return any(hint in text for hint in hints)


def score_image(
    cand: ImageCandidate,
    *,
    name: str | None = None,
    brand: str | None = None,
    barcode: str | None = None,
) -> ImageCandidate:
    """Compute and attach a deterministic score + reasons to [cand]."""
    score = 0
    reasons: list[str] = []
    url = (cand.url or "").strip()
    folded_url = _fold_text(url)
    folded = _image_text(cand)

    if not url or not url.lower().startswith(("http://", "https://")):
        cand.score = -1000
        cand.reasons = ["invalid_url"]
        return cand

    # Provenance.
    if cand.in_schema:
        score += 25
        reasons.append("+schema_image")
    if cand.in_gallery:
        score += 12
        reasons.append("+gallery")
    if cand.near_title:
        score += 8
        reasons.append("+near_title")
    if cand.source == "category_card":
        score += 10
        reasons.append("+category_card")
    elif cand.source == "embedded_json":
        score += 4
        reasons.append("+embedded_json")

    # API primary image: the listing API provides the canonical front packshot.
    if cand.is_api_primary:
        score += 30
        reasons.append("+api_primary")

    # Gallery position: first image in a source is almost always the front packshot.
    if cand.gallery_index is not None:
        if cand.gallery_index == 0:
            score += 20
            reasons.append("+first_in_source")
        else:
            score -= 10
            reasons.append("-later_in_gallery")

    # URL semantics.
    for hint in _GOOD_URL_HINTS:
        if hint in folded:
            score += 6
            reasons.append(f"+url:{hint}")
            break
    for hint in _BAD_URL_HINTS:
        if hint in folded:
            score -= 40
            reasons.append(f"-url:{hint}")
            break

    # Back/label image detection: these must not become image_front_url.
    if _contains_hint(folded, _INGREDIENT_HINTS):
        score -= 55
        reasons.append("-ingredients_label")
    elif _contains_hint(folded, _NUTRITION_HINTS):
        score -= 55
        reasons.append("-nutrition_label")
    elif _contains_hint(folded, _BACK_HINTS):
        score -= 50
        reasons.append("-back_label")

    # Name / brand / barcode appearing in the URL is a strong signal.
    if _contains_token(folded, name):
        score += 10
        reasons.append("+name_in_url")
    if _contains_token(folded, brand):
        score += 8
        reasons.append("+brand_in_url")
    if barcode and barcode in folded:
        score += 12
        reasons.append("+barcode_in_url")

    # File type — packshots are usually jpg/png/webp.
    if folded_url.endswith((".svg", ".gif")):
        score -= 15
        reasons.append("-vector_or_gif")

    # Dimensions: explicit, else parse from URL pattern.
    width, height = cand.width, cand.height
    if width is None or height is None:
        m = _SMALL_DIM_RE.search(folded_url)
        if m:
            width = width or int(m.group(1))
            height = height or int(m.group(2))
    if width and height:
        biggest = max(width, height)
        if biggest < 200:
            score -= 30
            reasons.append("-tiny")
        elif biggest >= 800:
            score += 15
            reasons.append("+high_res")
        elif biggest >= 400:
            score += 6
            reasons.append("+medium_res")

    cand.width, cand.height = width, height
    cand.score = score
    cand.reasons = reasons
    return cand


def pick_best_image(
    candidates: list[ImageCandidate],
    *,
    name: str | None = None,
    brand: str | None = None,
    barcode: str | None = None,
) -> tuple[ImageCandidate | None, list[ImageCandidate]]:
    """Score all candidates and return (best, all_scored_sorted_desc).

    Best is None when no candidate scores above a minimum usefulness bar.
    """
    scored: list[ImageCandidate] = []
    seen: set[str] = set()
    for cand in candidates:
        key = (cand.url or "").strip()
        if not key or key in seen:
            continue
        seen.add(key)
        scored.append(score_image(cand, name=name, brand=brand, barcode=barcode))

    scored.sort(key=lambda c: c.score, reverse=True)
    best = scored[0] if scored and scored[0].score > 0 else None
    return best, scored


def select_primary_image(
    candidates: list[ImageCandidate],
    *,
    name: str | None = None,
    brand: str | None = None,
    barcode: str | None = None,
) -> ImageSelection:
    """Pick a public/main product image with front-first, safe fallback rules."""
    _, scored = pick_best_image(candidates, name=name, brand=brand, barcode=barcode)

    def role_of(cand: ImageCandidate) -> str:
        return classify_image_role(cand)

    def is_label(cand: ImageCandidate) -> bool:
        return is_label_role(role_of(cand))

    api_primary = next((c for c in scored if c.is_api_primary and not is_label(c)), None)
    detail_first = next(
        (
            c
            for c in scored
            if c.source == "detail_gallery"
            and c.gallery_index == 0
            and not is_label(c)
        ),
        None,
    )
    front_like = next(
        (
            c
            for c in scored
            if not is_label(c) and (role_of(c) == "front" or c.score > 0)
        ),
        None,
    )
    non_label = next((c for c in scored if not is_label(c)), None)
    label_fallback = next((c for c in scored if is_label(c)), None)

    selected = api_primary or detail_first or front_like or non_label or label_fallback
    if selected is None:
        return ImageSelection(
            selected=None,
            scored=scored,
            quality="missing",
            confidence="none",
        )

    selected_role = role_of(selected)
    if is_label(selected):
        return ImageSelection(
            selected=selected,
            scored=scored,
            quality="only_back_available",
            confidence="low",
        )
    return ImageSelection(
        selected=selected,
        scored=scored,
        quality="front_selected",
        confidence=_selection_confidence(selected, selected_role),
    )


def _selection_confidence(cand: ImageCandidate, role: str) -> str:
    if role == "front" and (cand.is_api_primary or cand.gallery_index == 0):
        return "high"
    if role == "front" and cand.score >= 25:
        return "high"
    if cand.score >= 10:
        return "medium"
    return "low"


def classify_image_role(cand: ImageCandidate | None) -> str:
    """Return a human-readable role for a scored ImageCandidate.

    Roles: "front", "back_label", "nutrition_label", "ingredients_label",
    "unknown".
    Used for debug metadata and to identify secondary images to store as
    image_ingredients_url / image_nutrition_url.
    """
    if cand is None:
        return "unknown"
    folded = _image_text(cand)
    if _contains_hint(folded, _NUTRITION_HINTS):
        return "nutrition_label"
    if _contains_hint(folded, _INGREDIENT_HINTS):
        return "ingredients_label"
    if _contains_hint(folded, _BACK_HINTS):
        return "back_label"
    if cand.is_api_primary or cand.gallery_index == 0:
        return "front"
    if cand.score > 30:
        return "front"
    return "unknown"


def is_label_role(role: str) -> bool:
    return role in ("back_label", "nutrition_label", "ingredients_label")


def serialize_candidate(cand: ImageCandidate) -> dict:
    return {
        "url": cand.url,
        "index": cand.gallery_index,
        "source": cand.source,
        "score": cand.score,
        "reasons": cand.reasons,
        "role": classify_image_role(cand),
        "is_api_primary": cand.is_api_primary,
    }
