#!/usr/bin/env python3
"""Extract structured + semi-structured product data from a product page.

Layers, in order of trust:
  1. JSON-LD schema.org/Product   (name, brand, image, gtin/sku, description, category)
  2. OpenGraph / meta tags        (og:title, og:image, og:description)
  3. HTML labeled sections        (Turkish labels: İçindekiler, Besin Değerleri, ...)

Everything is best-effort and tolerant: a missing layer never raises.
Requires BeautifulSoup (bs4).
"""
from __future__ import annotations

import json
import re
from urllib.parse import urljoin

try:
    from bs4 import BeautifulSoup
except ImportError as exc:  # pragma: no cover - environment guard
    raise SystemExit(
        "ERROR: beautifulsoup4 is required for the web scraper. "
        "Install with: pip install beautifulsoup4"
    ) from exc

from .nutrition_parser import classify_label


# Turkish (and English) section labels we look for in visible text.
SECTION_LABELS: dict[str, list[str]] = {
    "ingredients": ["içindekiler", "i̇çindekiler", "içerik", "bileşenler", "ingredients"],
    "nutrition": [
        "besin değerleri", "besin degerleri", "besin bilgileri",
        "beslenme bilgileri", "nutrition", "nutritional"
    ],
    "allergens": ["alerjen", "alerjenler", "alerji", "allergen"],
    "product_info": ["ürün bilgileri", "urun bilgileri", "ürün açıklaması"],
    "net_quantity": ["net miktar", "net ağırlık", "net agirlik"],
}

# schema.org gtin/barcode-ish keys, most specific first.
_GTIN_KEYS = ["gtin13", "gtin14", "gtin12", "gtin8", "gtin", "barcode", "sku", "mpn"]


def make_soup(html: str) -> BeautifulSoup:
    return BeautifulSoup(html, "html.parser")


# ── JSON-LD ──────────────────────────────────────────────────────────────────

def _iter_jsonld_objects(soup: BeautifulSoup):
    for tag in soup.find_all("script", attrs={"type": "application/ld+json"}):
        raw = tag.string or tag.get_text() or ""
        raw = raw.strip()
        if not raw:
            continue
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, ValueError):
            continue
        # Could be an object, a list, or a {"@graph": [...]} wrapper.
        if isinstance(data, dict) and "@graph" in data:
            for node in data.get("@graph") or []:
                if isinstance(node, dict):
                    yield node
        elif isinstance(data, list):
            for node in data:
                if isinstance(node, dict):
                    yield node
        elif isinstance(data, dict):
            yield data


def _is_product(node: dict) -> bool:
    t = node.get("@type")
    if isinstance(t, list):
        return any(str(x).lower() == "product" for x in t)
    return str(t).lower() == "product"


def find_product_jsonld(soup: BeautifulSoup) -> dict | None:
    for node in _iter_jsonld_objects(soup):
        if _is_product(node):
            return node
    return None


def _coerce_name(value: object) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    if isinstance(value, dict):
        name = value.get("name")
        if isinstance(name, str) and name.strip():
            return name.strip()
    return None


def _jsonld_images(node: dict) -> list[str]:
    image = node.get("image")
    urls: list[str] = []
    if isinstance(image, str):
        urls.append(image)
    elif isinstance(image, list):
        for item in image:
            if isinstance(item, str):
                urls.append(item)
            elif isinstance(item, dict) and isinstance(item.get("url"), str):
                urls.append(item["url"])
    elif isinstance(image, dict) and isinstance(image.get("url"), str):
        urls.append(image["url"])
    return [u.strip() for u in urls if u and u.strip()]


def _jsonld_barcode(node: dict) -> str | None:
    for key in _GTIN_KEYS:
        val = node.get(key)
        if isinstance(val, (str, int)):
            digits = re.sub(r"\D", "", str(val))
            if 8 <= len(digits) <= 14:
                return digits
    return None


def extract_jsonld(soup: BeautifulSoup) -> dict:
    """Return a normalized dict from schema.org/Product, or {} when absent."""
    node = find_product_jsonld(soup)
    if not node:
        return {}
    brand = _coerce_name(node.get("brand"))
    category = node.get("category")
    return {
        "name": _coerce_name(node.get("name")),
        "brand": brand,
        "images": _jsonld_images(node),
        "barcode": _jsonld_barcode(node),
        "description": (node.get("description") or "").strip() or None
        if isinstance(node.get("description"), str)
        else None,
        "category": category.strip() if isinstance(category, str) and category.strip() else None,
    }


# ── OpenGraph / meta ─────────────────────────────────────────────────────────

def extract_meta(soup: BeautifulSoup) -> dict:
    """Return og:/twitter:/meta fields useful for product candidates."""
    def meta(*keys: str) -> str | None:
        for key in keys:
            tag = soup.find("meta", attrs={"property": key}) or soup.find(
                "meta", attrs={"name": key}
            )
            if tag and tag.get("content") and tag["content"].strip():
                return tag["content"].strip()
        return None

    title_tag = soup.find("title")
    return {
        "og_title": meta("og:title", "twitter:title"),
        "og_image": meta("og:image", "og:image:url", "twitter:image"),
        "og_description": meta("og:description", "twitter:description", "description"),
        "title": title_tag.get_text(strip=True) if title_tag else None,
    }


# ── Labeled visible-text sections ────────────────────────────────────────────

def _clean_text(node) -> str:
    return re.sub(r"[ \t]+", " ", node.get_text(" ", strip=True))


def extract_sections(soup: BeautifulSoup) -> dict[str, str]:
    """Find Turkish labeled blocks and return {section_key: nearby_text}.

    Strategy: locate an element whose own text starts with/contains a known
    label, then capture that element's text plus the next sibling block (where
    the value usually lives).
    """
    sections: dict[str, str] = {}
    full_text = soup.get_text("\n", strip=True)
    folded_full = full_text.lower()

    for key, labels in SECTION_LABELS.items():
        captured = _capture_section(soup, labels)
        if captured:
            sections[key] = captured
            continue
        # Fallback: slice the flat text after the label up to a blank-ish gap.
        for label in labels:
            idx = folded_full.find(label)
            if idx != -1:
                chunk = full_text[idx: idx + 600]
                sections[key] = re.sub(r"[ \t]+", " ", chunk).strip()
                break
    return sections


def _capture_section(soup: BeautifulSoup, labels: list[str]) -> str | None:
    for label in labels:
        # Find the smallest element whose text contains the label.
        for el in soup.find_all(
            string=re.compile(re.escape(label), re.IGNORECASE)
        ):
            parent = el.parent
            if parent is None:
                continue
            parts = [_clean_text(parent)]
            # Pull a couple of following blocks where the value usually sits.
            sib = parent.find_next_sibling()
            hops = 0
            while sib is not None and hops < 3:
                text = _clean_text(sib)
                if text:
                    parts.append(text)
                sib = sib.find_next_sibling()
                hops += 1
            joined = " ".join(p for p in parts if p).strip()
            if len(joined) > len(label) + 3:
                return joined
    return None


# ── Image gathering ──────────────────────────────────────────────────────────

def gather_gallery_images(soup: BeautifulSoup, base_url: str) -> list[str]:
    """Collect <img> sources likely to be product gallery/packshot images."""
    return [ref["url"] for ref in gather_gallery_image_refs(soup, base_url)]


def gather_gallery_image_refs(soup: BeautifulSoup, base_url: str) -> list[dict[str, str | None]]:
    """Collect image refs with lightweight context for image-role heuristics."""
    return _image_refs_from_tags(soup.find_all("img"), base_url)


def _image_refs_from_tags(tags, base_url: str) -> list[dict[str, str | None]]:
    urls: list[str] = []
    contexts: dict[str, str | None] = {}
    for img in tags:
        src = (
            img.get("src")
            or img.get("data-src")
            or img.get("data-zoom-image")
            or img.get("data-original")
        )
        if not src:
            continue
        url = urljoin(base_url, src.strip())
        urls.append(url)
        context = " ".join(
            part.strip()
            for part in (
                img.get("alt"),
                img.get("title"),
                img.get("aria-label"),
            )
            if isinstance(part, str) and part.strip()
        ).strip() or None
        if url not in contexts and context is not None:
            contexts[url] = context
    # Deduplicate, preserve order.
    seen: set[str] = set()
    out: list[dict[str, str | None]] = []
    for u in urls:
        if u not in seen:
            seen.add(u)
            out.append({"url": u, "context_text": contexts.get(u)})
    return out


def images_near_title(soup: BeautifulSoup, base_url: str) -> list[str]:
    """Images physically close to an <h1> (often the main packshot)."""
    return [ref["url"] for ref in images_near_title_refs(soup, base_url)]


def images_near_title_refs(soup: BeautifulSoup, base_url: str) -> list[dict[str, str | None]]:
    """Image refs physically close to an <h1> (often the main packshot)."""
    h1 = soup.find("h1")
    if h1 is None:
        return []
    container = h1.find_parent() or h1
    return _image_refs_from_tags(container.find_all("img"), base_url)


# ── Generic nutrition extraction (multi-strategy) ────────────────────────────
# Strategy order: (1) DOM scan of labeled elements (works for real <table>s,
# div/span rows, <dl> lists alike), (2) embedded JSON in <script> tags, then
# (3) a labeled-text fallback handled by the caller. We never execute scripts —
# only parse JSON that is safely loadable.

_VALUE_CELL_RE = re.compile(
    r"^\s*-?[\d.,]+\s*(?:kcal|kkal|kj|mg|gr|g|ml)?\s*$", re.IGNORECASE
)
_TRAILING_VALUE_RE = re.compile(
    r"([\d.,]+\s*(?:kcal|kkal|kj|mg|gr|g|ml)?)\s*$", re.IGNORECASE
)
# Tags that typically hold a single label or a single value (leaf-ish).
_CELL_TAGS = ["td", "th", "span", "div", "li", "p", "dt", "dd", "strong", "b"]


def _looks_like_value(text: str | None) -> bool:
    return bool(text) and bool(_VALUE_CELL_RE.match(text)) and any(
        ch.isdigit() for ch in text
    )


def _value_near(el) -> str | None:
    """Find a numeric value paired with a label element (sibling/co-child)."""
    sib = el.find_next_sibling()
    if sib is not None:
        text = sib.get_text(" ", strip=True)
        if _looks_like_value(text):
            return text
    parent = el.parent
    if parent is not None:
        for child in parent.find_all(recursive=False):
            if child is el:
                continue
            text = child.get_text(" ", strip=True)
            if _looks_like_value(text):
                return text
    return None


def _scan_labeled_pairs(soup: BeautifulSoup) -> list[tuple[str, str]]:
    """DOM-structure-agnostic scan: any small element whose text is a nutrient
    label, paired with a nearby numeric value. Covers tables, div rows and
    definition lists without hardcoding a site layout."""
    pairs: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for el in soup.find_all(_CELL_TAGS):
        text = el.get_text(" ", strip=True)
        if not text or len(text) > 48:
            continue
        if classify_label(text) is None:
            continue
        label = text
        value = _value_near(el)
        if value is None and any(ch.isdigit() for ch in text):
            # value embedded in the same cell, e.g. "Yağ 15 g"
            m = _TRAILING_VALUE_RE.search(text)
            if m:
                value = m.group(1)
                label = text[: m.start()].strip() or text
        if value is None:
            continue
        field = classify_label(label, value)
        key = (field or label, value.strip())
        if key in seen:
            continue
        seen.add(key)
        pairs.append((label.strip(), value.strip()))
    return pairs


def _json_nutrition_pairs(node, depth: int = 0) -> list[tuple[str, str]]:
    """Recursively pull nutrient (label, value) pairs from parsed JSON data."""
    pairs: list[tuple[str, str]] = []
    if depth > 8:
        return pairs
    if isinstance(node, dict):
        label = None
        for lk in ("label", "name", "key", "title", "displayName", "text"):
            if isinstance(node.get(lk), str):
                label = node[lk]
                break
        value = None
        for vk in ("value", "amount", "quantity", "val", "displayValue", "qty"):
            if node.get(vk) is not None and not isinstance(node.get(vk), (dict, list)):
                value = node[vk]
                break
        if label and value is not None and classify_label(label):
            pairs.append((label, str(value)))
        for k, v in node.items():
            if (
                isinstance(k, str)
                and not isinstance(v, (dict, list))
                and v is not None
                and classify_label(k)
            ):
                pairs.append((k, str(v)))
            pairs.extend(_json_nutrition_pairs(v, depth + 1))
    elif isinstance(node, list):
        for item in node:
            pairs.extend(_json_nutrition_pairs(item, depth + 1))
    return pairs


def _scripts_nutrition_pairs(soup: BeautifulSoup) -> list[tuple[str, str]]:
    """Parse <script> JSON (e.g. __NEXT_DATA__, application/json) for nutrition.

    Only safely JSON-loadable content is parsed; JavaScript is never executed.
    """
    pairs: list[tuple[str, str]] = []
    for script in soup.find_all("script"):
        raw = (script.string or script.get_text() or "").strip()
        if not raw:
            continue
        stype = (script.get("type") or "").lower()
        is_jsonish = (
            "json" in stype
            or script.get("id") == "__NEXT_DATA__"
            or raw[:1] in "{["
        )
        if not is_jsonish:
            continue
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, ValueError):
            continue
        pairs.extend(_json_nutrition_pairs(data))
    return pairs


# Nutrient keywords (ASCII-folded) used to recognize a nutrition block/table.
_NUTRIENT_KEYS = ("enerji", "kalori", "protein", "karbonhidrat", "yag", "seker", "tuz")


def _has_nutrient(text: str) -> bool:
    folded = text.lower().translate(
        str.maketrans({"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u"})
    )
    return any(k in folded for k in _NUTRIENT_KEYS)


def _nutrition_context_text(soup: BeautifulSoup) -> str:
    """Text of the actual nutrition table/region — basis + text fallback source.

    Reads the real nutrition `<table>` (or a div/section/dl block) that holds
    nutrient labels, so the per-100 header (e.g. "100 g / ml") is included for
    basis detection. Avoids `<style>/<script>` noise (those tags are not scanned).
    """
    parts: list[str] = []
    for table in soup.find_all("table"):
        txt = table.get_text(" ", strip=True)
        if txt and _has_nutrient(txt):
            parts.append(txt)
    if not parts:
        for el in soup.find_all(["section", "div", "ul", "dl"]):
            txt = el.get_text(" ", strip=True)
            if not txt or len(txt) > 2000:
                continue
            folded = txt.lower()
            if "besin değer" in folded or ("100" in txt and _has_nutrient(txt)):
                parts.append(txt)
                if len(parts) >= 3:
                    break
    if not parts:
        # Last resort: a flat-text window around a per-100 / heading marker.
        full = soup.get_text("\n", strip=True)
        folded = full.lower()
        for hint in ("100 g", "100g", "100 ml", "100ml", "besin değer"):
            idx = folded.find(hint)
            if idx != -1:
                return re.sub(
                    r"[ \t]+", " ", full[max(0, idx - 40): idx + 500]
                ).strip()
        return ""
    return " ".join(parts)[:2000]


def extract_nutrition(soup: BeautifulSoup) -> dict:
    """Run all nutrition strategies and return raw material for the parser.

    Returns {pairs, basis_text, fallback_text, strategy}. The caller passes this
    to nutrition_parser.build_nutrition.
    """
    dom_pairs = _scan_labeled_pairs(soup)
    json_pairs = _scripts_nutrition_pairs(soup)
    # DOM first (most precise), then JSON to fill any gaps; parser dedupes.
    pairs = dom_pairs + json_pairs
    context = _nutrition_context_text(soup)
    strategy = "dom" if dom_pairs else ("json" if json_pairs else "text")
    return {
        "pairs": pairs,
        "basis_text": context,
        "fallback_text": context,
        "strategy": strategy,
    }


# ── Generic ingredients extraction ───────────────────────────────────────────

def _json_ingredients(soup: BeautifulSoup) -> str | None:
    keys = ("icindekiler", "icerik", "ingredients", "bilesenler", "içindekiler")
    for script in soup.find_all("script"):
        raw = (script.string or script.get_text() or "").strip()
        if not raw or raw[:1] not in "{[":
            continue
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, ValueError):
            continue
        found = _walk_for_keys(data, keys)
        if found:
            return found
    return None


def _walk_for_keys(node, keys: tuple[str, ...], depth: int = 0) -> str | None:
    if depth > 8:
        return None
    if isinstance(node, dict):
        for k, v in node.items():
            kf = str(k).lower().replace("ç", "c").replace("ı", "i").replace("ş", "s")
            if isinstance(v, str) and v.strip() and any(key in kf for key in keys):
                if len(v.strip()) > 10:
                    return v.strip()
            res = _walk_for_keys(v, keys, depth + 1)
            if res:
                return res
    elif isinstance(node, list):
        for item in node:
            res = _walk_for_keys(item, keys, depth + 1)
            if res:
                return res
    return None


def extract_ingredients_text(soup: BeautifulSoup) -> str | None:
    """Generic ingredients extraction: labeled section, then embedded JSON."""
    cap = _capture_section(soup, SECTION_LABELS["ingredients"])
    if cap:
        return cap
    return _json_ingredients(soup)


# ── Breadcrumb category ──────────────────────────────────────────────────────

def extract_breadcrumb_category(soup: BeautifulSoup) -> str | None:
    """Most-specific category from a JSON-LD BreadcrumbList or HTML breadcrumb."""
    for node in _iter_jsonld_objects(soup):
        if str(node.get("@type", "")).lower() == "breadcrumblist":
            names: list[str] = []
            for item in node.get("itemListElement") or []:
                if not isinstance(item, dict):
                    continue
                name = item.get("name")
                if not name and isinstance(item.get("item"), dict):
                    name = item["item"].get("name")
                if isinstance(name, str) and name.strip():
                    names.append(name.strip())
            if len(names) >= 3:
                return names[-2]  # skip home + product → the category
            if len(names) == 2:
                return names[-1]

    bc = soup.find(attrs={"class": re.compile("breadcrumb", re.IGNORECASE)})
    if bc:
        links = [a.get_text(strip=True) for a in bc.find_all("a")]
        links = [l for l in links if l]
        if len(links) >= 3:
            return links[-2]
        if links:
            return links[-1]
    return None


# ── Product link discovery (category pages) ──────────────────────────────────

# Generic hints that a link points at a product detail page.
_PRODUCT_LINK_HINTS = ("/p/", "/product/", "/urun/", "/ürün/", "-p-", "/dp/", "/pr/")

# Links that are never product detail pages.
_DEFAULT_EXCLUDE = (
    "/sepet", "/cart", "/login", "/giris", "/uye", "/arama", "/search",
    "/yardim", "/help", "/kampanya", "/campaign", "/kategori", "/category",
    "/hesabim", "/account", "/favori", "javascript:", "mailto:", "tel:",
    ".css", ".js", ".png", ".jpg", ".jpeg", ".svg", ".gif", ".webp", ".pdf",
)


# JSON keys whose string values may hold a product detail URL/path.
_URL_KEYS = {
    "url", "slug", "seourl", "producturl", "link", "href",
    "canonicalurl", "path", "prettyname", "deeplink",
}
# Tokens that mark a string as an API/listing endpoint (logged, never called).
_API_HINT_TOKENS = (
    "product", "products", "catalog", "category", "search", "listing",
    "faceted", "graphql", "/api/",
)
# URL or path-like substrings inside script/HTML text.
_URLISH_RE = re.compile(
    r"""https?://[^\s"'<>\\)]+|/[A-Za-z0-9][A-Za-z0-9._~\-/%]{2,}""",
)


def _normalize_escapes(text: str) -> str:
    """Turn escaped JSON/URL slashes into plain '/': \\/, \\u002F, %2F."""
    return (
        text.replace("\\/", "/")
        .replace("\\u002F", "/")
        .replace("\\u002f", "/")
        .replace("%2F", "/")
        .replace("%2f", "/")
    )


def _passes(url: str, hints, excludes, *, require_hint: bool = True) -> bool:
    folded = url.lower()
    if any(bad in folded for bad in excludes):
        return False
    if require_hint:
        return any(hint in folded for hint in hints)
    return True


def _script_texts(soup: BeautifulSoup) -> list[str]:
    out: list[str] = []
    for script in soup.find_all("script"):
        raw = script.string or script.get_text() or ""
        if raw.strip():
            out.append(raw)
    return out


def _from_href(soup, base_url, selector, hints, excludes):
    links: list[str] = []
    if selector:
        anchors = [(el.get("href")) for el in soup.select(selector)]
        require_hint = False  # an explicit selector is the operator's intent
    else:
        anchors = [a["href"] for a in soup.find_all("a", href=True)]
        require_hint = True
    for href in anchors:
        if not href:
            continue
        url = urljoin(base_url, href.strip())
        if not url.startswith(("http://", "https://")):
            continue
        if _passes(url, hints, excludes, require_hint=require_hint):
            links.append(url)
    return links


def _from_script_text(soup, base_url, hints, excludes):
    """Strategy A: regex product paths/URLs out of script/HTML text."""
    links: list[str] = []
    blob = _normalize_escapes("\n".join(_script_texts(soup)))
    for m in _URLISH_RE.finditer(blob):
        token = m.group(0).rstrip('.,);"\'')
        url = urljoin(base_url, token)
        if not url.startswith(("http://", "https://")):
            continue
        if _passes(url, hints, excludes, require_hint=True):
            links.append(url)
    return links


def _looks_product_like(node: dict) -> bool:
    has_name = any(isinstance(node.get(k), str) and node.get(k) for k in ("name", "title"))
    has_id = any(node.get(k) for k in ("id", "code", "sku", "productid", "productId"))
    has_url = any(str(k).lower() in _URL_KEYS for k in node.keys())
    return has_name and has_id and has_url


def _collect_product_urls(node, base_url, hints, excludes, *, limit, links, seen):
    """Recursively walk parsed JSON collecting product detail URLs/slugs.

    A url-ish key (`url`/`slug`/`seoUrl`/`path`/…) on a product-like object
    (name + id + url) is trusted even without a product hint; other url-ish
    string values require a product hint. Never builds a URL from a name alone.
    """
    def consider(value, *, require_hint: bool) -> None:
        if not isinstance(value, str) or not value.strip():
            return
        norm = _normalize_escapes(value.strip())
        if not (norm.startswith("/") or norm.startswith("http")):
            return
        url = urljoin(base_url, norm)
        if not url.startswith(("http://", "https://")) or url in seen:
            return
        if _passes(url, hints, excludes, require_hint=require_hint):
            seen.add(url)
            links.append(url)

    def walk(node, depth=0):
        if depth > 12 or len(links) >= limit:
            return
        if isinstance(node, dict):
            product_like = _looks_product_like(node)
            for k, v in node.items():
                if isinstance(v, str) and str(k).lower() in _URL_KEYS:
                    consider(v, require_hint=not product_like)
                walk(v, depth + 1)
        elif isinstance(node, list):
            for item in node:
                walk(item, depth + 1)

    walk(node)
    return links


def product_urls_from_json(
    data,
    base_url: str,
    *,
    product_link_patterns: list[str] | None = None,
    exclude_link_patterns: list[str] | None = None,
    limit: int = 200,
) -> list[str]:
    """Public helper: collect product detail URLs from already-parsed JSON.

    Shared by the embedded-JSON discovery strategy and source-specific API
    adapters so both honor the same key set and pattern/exclude filtering.
    """
    hints = tuple(_PRODUCT_LINK_HINTS) + tuple(product_link_patterns or [])
    excludes = tuple(_DEFAULT_EXCLUDE) + tuple(exclude_link_patterns or [])
    return _collect_product_urls(
        data, base_url, hints, excludes, limit=limit, links=[], seen=set()
    )


def _from_embedded_json(soup, base_url, hints, excludes, *, limit):
    """Strategy B: parse embedded JSON safely and walk for product URLs/slugs."""
    links: list[str] = []
    seen: set[str] = set()
    for raw in _script_texts(soup):
        stripped = raw.strip()
        if stripped[:1] not in "{[":
            # tolerate "window.__X__ = {...};" wrappers
            m = re.search(r"=\s*(\{.*\})\s*;?\s*$", stripped, re.DOTALL)
            stripped = m.group(1) if m else ""
        if not stripped:
            continue
        try:
            data = json.loads(stripped)
        except (json.JSONDecodeError, ValueError):
            continue
        _collect_product_urls(
            data, base_url, hints, excludes, limit=limit, links=links, seen=seen
        )
    return links


def collect_api_hints(soup: BeautifulSoup, limit: int = 10) -> list[str]:
    """Collect possible API/listing endpoint URLs for the run log (never called)."""
    hints: list[str] = []
    seen: set[str] = set()
    blob = _normalize_escapes("\n".join(_script_texts(soup)))
    for m in re.finditer(r"https?://[^\s\"'<>\\)]+", blob):
        url = m.group(0)
        folded = url.lower()
        if any(tok in folded for tok in _API_HINT_TOKENS) and url not in seen:
            seen.add(url)
            hints.append(url)
            if len(hints) >= limit:
                break
    return hints


def discover_with_stats(
    soup: BeautifulSoup,
    base_url: str,
    *,
    link_selector: str = "",
    product_link_selector: str = "",
    product_link_patterns: list[str] | None = None,
    exclude_link_patterns: list[str] | None = None,
    limit: int = 100,
) -> tuple[list[str], dict]:
    """Discover product links via href → embedded JSON → script text.

    Returns (links, stats). `stats` powers the run-log debugging when a category
    page yields no product links (client-rendered / API-backed pages).
    """
    hints = tuple(_PRODUCT_LINK_HINTS) + tuple(product_link_patterns or [])
    excludes = tuple(_DEFAULT_EXCLUDE) + tuple(exclude_link_patterns or [])
    selector = product_link_selector or link_selector

    href_links = _from_href(soup, base_url, selector, hints, excludes)
    json_links = _from_embedded_json(soup, base_url, hints, excludes, limit=limit)
    script_links = _from_script_text(soup, base_url, hints, excludes)

    # Merge, preserve order, dedupe: href (most reliable) → JSON → script text.
    merged: list[str] = []
    seen: set[str] = set()
    for url in href_links + json_links + script_links:
        if url not in seen:
            seen.add(url)
            merged.append(url)
    merged = merged[:limit]

    stats = {
        "html_length": len(str(soup)),
        "href_link_count": len(soup.find_all("a", href=True)),
        "pattern_link_count": len(href_links),
        "script_count": len(soup.find_all("script")),
        "script_product_url_count": len(script_links),
        "json_product_url_count": len(json_links),
        "first_10_candidate_paths": merged[:10],
        "configured_product_link_patterns": list(product_link_patterns or []),
        "configured_exclude_link_patterns": list(exclude_link_patterns or []),
        "api_endpoint_hints": collect_api_hints(soup),
    }
    return merged, stats


def discover_product_links(
    soup: BeautifulSoup,
    base_url: str,
    *,
    link_selector: str = "",
    product_link_selector: str = "",
    product_link_patterns: list[str] | None = None,
    exclude_link_patterns: list[str] | None = None,
    limit: int = 100,
) -> list[str]:
    """Extract candidate product-detail links from a category/listing page.

    Strategies, in order (results merged + deduped):
      1. `<a href>` (configured CSS selector, else generic URL-shape hints).
      2. Embedded JSON (`__NEXT_DATA__`, `application/json`, `__INITIAL_STATE__`,
         `__NUXT__`, ld+json) walked for url/slug/seoUrl/path values — including
         escaped JSON (`\\/`, `\\u002F`, `%2F`).
      3. Product paths/URLs found in raw script text.

    Built-in + per-source exclude patterns drop cart/login/search/category and
    static-asset links. See `discover_with_stats` for the debug variant.
    """
    links, _stats = discover_with_stats(
        soup,
        base_url,
        link_selector=link_selector,
        product_link_selector=product_link_selector,
        product_link_patterns=product_link_patterns,
        exclude_link_patterns=exclude_link_patterns,
        limit=limit,
    )
    return links
