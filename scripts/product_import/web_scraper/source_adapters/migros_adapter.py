#!/usr/bin/env python3
"""Migros source adapter: conservative API-backed category discovery.

Migros category pages are client-rendered — the served HTML contains no product
URLs (verified). This adapter discovers product detail URLs ONLY from:

  1. a configured `adapter_config.api_url_template` (the supported path), or
  2. a product-listing API endpoint already visible in the category page HTML.

It does NOT guess endpoints, does NOT brute-force, and does NOT use browser
automation. If neither a template nor a visible endpoint is available it fails
gracefully with a clear warning.

Migros stores the product detail slug in `storeProductInfos[*].prettyName`
(e.g. "namet-7-24-hindi-salam-60-g-p-d749eb") rather than a url/href/seoUrl
field, so this adapter builds detail URLs from that field explicitly — only when
prettyName contains the "-p-" product marker, and never from a product name.
"""
from __future__ import annotations

import re
from typing import TYPE_CHECKING

from .. import extractors
from .base_adapter import SourceAdapter

if TYPE_CHECKING:
    from ..base import Fetcher
    from ..source_config import Source


class MigrosAdapter(SourceAdapter):
    source_id = "migros"

    def can_handle(self, source: "Source", category_url: str) -> bool:
        if not super().can_handle(source, category_url):
            return False
        # Extra safety: only act on migros.com.tr URLs.
        host = (category_url or "") + " " + (getattr(source, "base_url", "") or "")
        return "migros.com.tr" in host.lower()

    def discover_product_urls(
        self,
        fetcher: "Fetcher",
        source: "Source",
        category_url: str,
        category: str | None,
        limit: int,
    ) -> tuple[list[str], dict]:
        debug = self.new_debug(category_url, self.source_id)
        cfg = getattr(source, "adapter_config", None) or {}

        template = str(cfg.get("api_url_template") or "").strip()
        category_id = str(cfg.get("category_id") or "").strip() or _category_id(category_url)
        category_slug = _category_slug(category_url)
        page_param = str(cfg.get("page_param") or "page").strip()
        try:
            max_pages = int(cfg.get("max_pages", source.max_pages_per_category or 1))
        except (TypeError, ValueError):
            max_pages = 1
        max_pages = max(1, max_pages)

        # No template configured → look for a product-listing endpoint that is
        # ALREADY present in the page HTML (never guess one).
        if not template:
            template = self._endpoint_from_html(fetcher, category_url, debug)

        if not template:
            debug["warnings"].append(
                "Adapter migros enabled but no API endpoint configured or discoverable."
            )
            return [], debug

        patterns = getattr(source, "product_link_patterns", None)
        excludes = getattr(source, "exclude_link_patterns", None)
        base_url = getattr(source, "base_url", "") or category_url

        # Migros-specific debug fields.
        debug["migros_store_product_count"] = 0
        debug["migros_prettyname_url_count"] = 0
        debug["first_5_prettyname_urls"] = []
        debug["page_count"] = None
        debug["hit_count"] = None
        debug["fetched_pages"] = []
        debug["urls_per_page"] = {}
        debug["pagination_param_used"] = None
        debug["url_metadata"] = {}  # per-URL API metadata for brand/name/image fallback
        debug["dynamic_brand_count"] = 0
        debug["first_20_dynamic_brands"] = []

        headers = _migros_headers(category_url)
        has_page_placeholder = "{page}" in template

        collected: list[str] = []
        seen: set[str] = set()
        seen_pretty: set[str] = set()
        url_metadata: dict = {}  # accumulated across all pages
        dynamic_brands_seen: set[str] = set()  # brand facets accumulated across pages

        def render(page: int) -> str:
            return _render_template(
                template,
                category_id=category_id,
                category_slug=category_slug,
                category_url=category_url,
                page=page,
                page_param=page_param,
            )

        def absorb(page: int, fetched: dict) -> int:
            """Record a fetched page's products into the running collection."""
            pretty = fetched["pretty_urls"]
            debug["migros_store_product_count"] += fetched["store_count"]
            debug["migros_prettyname_url_count"] += len(pretty)
            for u in pretty[:5]:
                if len(debug["first_5_prettyname_urls"]) < 5:
                    debug["first_5_prettyname_urls"].append(u)
            debug["raw_count"] += len(fetched["page_urls"])
            debug["fetched_pages"].append(page)
            debug["urls_per_page"][page] = len(pretty)
            seen_pretty.update(pretty)
            # Accumulate per-URL API metadata (brand, name, image) for fallback.
            for u, meta in (fetched.get("url_metadata") or {}).items():
                url_metadata[u] = meta
            # Accumulate brand facets from this page's aggregationGroups.
            for b in fetched.get("dynamic_brands") or []:
                dynamic_brands_seen.add(b)
            new = 0
            for u in fetched["page_urls"]:
                if u not in seen:
                    seen.add(u)
                    collected.append(u)
                    new += 1
                if len(collected) >= limit:
                    break
            return new

        # ── Page 1 (the base endpoint that already works) ───────────────────────
        page1_endpoint = render(1)
        debug["endpoint_called"] = page1_endpoint
        first = self._fetch_page(
            fetcher, page1_endpoint, headers, base_url, patterns, excludes, limit, debug
        )
        if first is None or first["failed"]:
            debug["warnings"].append(
                "Adapter migros reached the endpoint but found no product URLs in the response."
            )
            debug["product_count"] = 0
            return [], debug

        search_info = first["search_info"] or {}
        page_count = _as_int(search_info.get("pageCount")) or 1
        debug["page_count"] = search_info.get("pageCount")
        debug["hit_count"] = search_info.get("hitCount")
        absorb(1, first)

        effective_max = min(max_pages, page_count)

        # ── Subsequent pages (only when needed) ─────────────────────────────────
        if len(collected) < limit and effective_max > 1:
            if has_page_placeholder:
                self._paginate_template(
                    fetcher, render, headers, base_url, patterns, excludes,
                    limit, effective_max, debug, absorb, seen_pretty, collected,
                )
            else:
                self._paginate_query_param(
                    fetcher, page1_endpoint, cfg, page_param, headers, base_url,
                    patterns, excludes, limit, effective_max, debug, absorb,
                    seen_pretty, collected,
                )

        if not collected:
            debug["warnings"].append(
                "Adapter migros reached the endpoint but found no product URLs in the response."
            )
        debug["product_count"] = len(collected)
        # Finalize dynamic brand data and thread into per-URL metadata.
        sorted_dynamic_brands = sorted(dynamic_brands_seen)
        debug["dynamic_brands"] = sorted_dynamic_brands
        debug["dynamic_brand_count"] = len(sorted_dynamic_brands)
        debug["first_20_dynamic_brands"] = sorted_dynamic_brands[:20]
        for meta in url_metadata.values():
            meta["category_dynamic_brands"] = sorted_dynamic_brands
        debug["url_metadata"] = url_metadata
        return collected[:limit], debug

    # ── pagination strategies ───────────────────────────────────────────────────

    def _paginate_template(
        self, fetcher, render, headers, base_url, patterns, excludes,
        limit, effective_max, debug, absorb, seen_pretty, collected,
    ) -> None:
        """Pagination when the template itself carries a `{page}` placeholder."""
        for page in range(2, effective_max + 1):
            if len(collected) >= limit:
                break
            fetched = self._fetch_page(
                fetcher, render(page), headers, base_url, patterns, excludes, limit, debug
            )
            if fetched is None or fetched["failed"]:
                if fetched and fetched["status"] in (401, 403, 429):
                    break
                continue
            new_pretty = [u for u in fetched["pretty_urls"] if u not in seen_pretty]
            if not new_pretty:
                break  # duplicate/empty page → stop (no infinite loop)
            absorb(page, fetched)

    def _paginate_query_param(
        self, fetcher, base_endpoint, cfg, page_param, headers, base_url,
        patterns, excludes, limit, effective_max, debug, absorb, seen_pretty,
        collected,
    ) -> None:
        """Pagination via a query parameter, detecting the working one on page 2.

        Migros' endpoint has no `{page}` placeholder, so the page is passed as a
        query param. We try a small list of public candidates and lock onto the
        one that actually returns *new* products (never looping on duplicates).
        """
        candidates: list[str] = []
        explicit = str(cfg.get("page_param") or "").strip()
        if explicit:
            candidates.append(explicit)
        for cand in ("sayfa", "page", "pageNumber", "pageNo"):
            if cand not in candidates:
                candidates.append(cand)

        param: str | None = None
        page = 2
        while len(collected) < limit and page <= effective_max:
            if param is None:
                # Detect the working pagination parameter on this page.
                detected = False
                for cand in candidates:
                    fetched = self._fetch_page(
                        fetcher, _with_query(base_endpoint, cand, page), headers,
                        base_url, patterns, excludes, limit, debug,
                    )
                    if fetched is None or fetched["failed"]:
                        if fetched and fetched["status"] in (401, 403, 429):
                            return
                        continue
                    new_pretty = [
                        u for u in fetched["pretty_urls"] if u not in seen_pretty
                    ]
                    if new_pretty:
                        param = cand
                        debug["pagination_param_used"] = cand
                        absorb(page, fetched)
                        detected = True
                        break
                if not detected:
                    debug["warnings"].append(
                        "Migros pagination parameter not found; only the first "
                        "page was collected."
                    )
                    return
            else:
                fetched = self._fetch_page(
                    fetcher, _with_query(base_endpoint, param, page), headers,
                    base_url, patterns, excludes, limit, debug,
                )
                if fetched is None or fetched["failed"]:
                    if fetched and fetched["status"] in (401, 403, 429):
                        return
                    page += 1
                    continue
                new_pretty = [
                    u for u in fetched["pretty_urls"] if u not in seen_pretty
                ]
                if not new_pretty:
                    break  # duplicate/empty page → stop
                absorb(page, fetched)
            page += 1

    def _fetch_page(
        self, fetcher, endpoint, headers, base_url, patterns, excludes, limit, debug
    ) -> dict | None:
        """Fetch one listing page → parsed products, or a failure marker."""
        data, result = fetcher.get_json(endpoint, headers=headers)
        if data is None:
            debug["errors"].append(
                {"endpoint": endpoint, "error": result.error or "no data",
                 "status": result.status}
            )
            return {"failed": True, "status": result.status}
        search_info = _search_info(data)
        store_infos = (search_info or {}).get("storeProductInfos") or []
        if not isinstance(store_infos, list):
            store_infos = []
        pretty_urls, url_meta = _urls_from_store_infos(store_infos, base_url, excludes)
        generic_urls = extractors.product_urls_from_json(
            data, base_url,
            product_link_patterns=patterns,
            exclude_link_patterns=excludes,
            limit=limit,
        )
        page_urls = pretty_urls + [u for u in generic_urls if u not in pretty_urls]
        return {
            "failed": False,
            "status": result.status,
            "search_info": search_info,
            "store_count": len(store_infos),
            "pretty_urls": pretty_urls,
            "page_urls": page_urls,
            "url_metadata": url_meta,
            "dynamic_brands": _extract_dynamic_brands(search_info or {}),
        }

    def _endpoint_from_html(self, fetcher: "Fetcher", category_url: str, debug: dict) -> str:
        """Return a product-listing API endpoint visible in the page HTML, else ''.

        Conservative: only same-host URLs that look like a product/catalog
        listing endpoint are accepted. Nothing is guessed.
        """
        page = fetcher.get(category_url)
        if not page.ok or not page.html:
            if page.error:
                debug["errors"].append({"endpoint": category_url, "error": page.error})
            return ""
        soup = extractors.make_soup(page.html)
        hints = extractors.collect_api_hints(soup, limit=20)
        for url in hints:
            folded = url.lower()
            if "migros.com.tr" in folded and any(
                tok in folded for tok in ("product", "catalog", "search", "storefront")
            ):
                debug["warnings"].append(f"using product-listing endpoint found in HTML: {url}")
                return url
        return ""


# ── helpers ──────────────────────────────────────────────────────────────────

def _migros_headers(category_url: str) -> dict[str, str]:
    """Safe public headers for the Migros storefront API (no cookies/secrets)."""
    return {
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "tr",
        "Referer": category_url or "https://www.migros.com.tr/",
        "X-FORWARDED-REST": "true",
        "X-PWA": "true",
        "X-Device-PWA": "true",
    }


def _search_info(data) -> dict | None:
    """Navigate to data.searchInfo (tolerating a wrapping `data` envelope)."""
    if not isinstance(data, dict):
        return None
    inner = data.get("data") if isinstance(data.get("data"), dict) else data
    if not isinstance(inner, dict):
        return None
    search_info = inner.get("searchInfo")
    return search_info if isinstance(search_info, dict) else None


def _as_int(value) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _with_query(endpoint: str, param: str, value: int) -> str:
    """Append `?param=value` (or `&param=value`) to an endpoint URL."""
    sep = "&" if "?" in endpoint else "?"
    return f"{endpoint}{sep}{param}={value}"


def _build_pretty_url(base_url: str, pretty_name: str) -> str:
    """Migros detail URL = base_url + '/' + product.prettyName. Never from name."""
    return base_url.rstrip("/") + "/" + pretty_name.lstrip("/")


_API_BACK_URL_SIGNALS = (
    "arka", "_back", "-back", "back_label", "backlabel",
    "label", "nutrition", "besin", "icindekiler", "ingredients",
)

_MIGROS_BASE = "https://www.migros.com.tr"


def _normalize_image_url(url: str) -> str:
    """Normalize a Migros image URL to absolute HTTPS.

    Handles protocol-relative (//cdn/img.jpg) and root-relative (/images/img.jpg)
    URLs that may appear in API responses or page HTML.
    """
    url = url.strip()
    if url.startswith("//"):
        return "https:" + url
    if url.startswith("/"):
        return _MIGROS_BASE + url
    return url


def _first_image_url(product: dict) -> str | None:
    """Extract the best front image URL from a Migros API product entry.

    Iterates the ``images`` array and returns the first URL whose path does
    not contain back-label / nutrition-label signals. Falls back to the very
    first URL in the array if every candidate looks like a label, so we never
    return ``None`` just because URL patterns are ambiguous.
    """
    images = product.get("images") or []
    first_url: str | None = None
    if isinstance(images, list):
        for img in images:
            if isinstance(img, dict):
                url = (img.get("url") or img.get("imageUrl") or img.get("src") or "").strip()
            elif isinstance(img, str):
                url = img.strip()
            else:
                url = ""
            if not url:
                continue
            if first_url is None:
                first_url = url
            url_lower = url.lower()
            if not any(sig in url_lower for sig in _API_BACK_URL_SIGNALS):
                return _normalize_image_url(url)
    if first_url:
        return _normalize_image_url(first_url)
    for key in ("imageUrl", "image_url", "photo", "thumbnail"):
        val = product.get(key)
        if val and isinstance(val, str) and val.strip():
            return _normalize_image_url(val.strip())
    return None


def _urls_from_store_infos(
    store_infos, base_url: str, exclude_link_patterns
) -> tuple[list[str], dict[str, dict]]:
    """Build product detail URLs from storeProductInfos[*].prettyName.

    Returns (url_list, url_metadata_dict) where url_metadata_dict maps each
    URL to a metadata snapshot {api_name, api_brand, api_category, api_sku,
    api_image_url} extracted from the API response.

    Only products whose `prettyName` contains '-p-' are used. IN_SALE products
    are ordered first; nothing is ever built from a product name.
    """
    excludes = tuple(exclude_link_patterns or [])
    in_sale: list[str] = []
    other: list[str] = []
    seen: set[str] = set()
    url_meta: dict[str, dict] = {}
    if not isinstance(store_infos, list):
        return [], {}
    for product in store_infos:
        if not isinstance(product, dict):
            continue
        pretty_name = product.get("prettyName")
        if not isinstance(pretty_name, str) or "-p-" not in pretty_name:
            continue
        url = _build_pretty_url(base_url, pretty_name.strip())
        folded = url.lower()
        if any(bad in folded for bad in excludes):
            continue
        if url in seen:
            continue
        seen.add(url)
        brand_obj = product.get("brand")
        api_brand = None
        if isinstance(brand_obj, dict):
            api_brand = (brand_obj.get("name") or "").strip() or None
        elif isinstance(brand_obj, str):
            api_brand = brand_obj.strip() or None
        cat_obj = product.get("category")
        api_category = None
        if isinstance(cat_obj, dict):
            api_category = (cat_obj.get("name") or "").strip() or None
        elif isinstance(cat_obj, str):
            api_category = cat_obj.strip() or None
        url_meta[url] = {
            "api_name": (product.get("name") or "").strip() or None,
            "api_brand": api_brand,
            "api_category": api_category,
            "api_sku": product.get("sku") or product.get("id") or None,
            "api_image_url": _first_image_url(product),
        }
        if str(product.get("status") or "").upper() == "IN_SALE":
            in_sale.append(url)
        else:
            other.append(url)
    return in_sale + other, url_meta


def _extract_dynamic_brands(search_info: dict) -> list[str]:
    """Extract brand names from searchInfo.aggregationGroups[type=BRAND].aggregationInfos."""
    groups = search_info.get("aggregationGroups") or []
    if not isinstance(groups, list):
        return []
    brand_group = next(
        (g for g in groups if isinstance(g, dict) and g.get("type") == "BRAND"), None
    )
    if brand_group is None:
        return []
    return [
        a["label"]
        for a in (brand_group.get("aggregationInfos") or [])
        if isinstance(a, dict) and isinstance(a.get("label"), str) and a["label"].strip()
    ]


def _category_id(category_url: str) -> str:
    """Migros category URLs end with '-c-<id>' (e.g. salam-c-112d6 → 112d6)."""
    m = re.search(r"-c-([a-z0-9]+)/?$", (category_url or "").lower())
    return m.group(1) if m else ""


def _category_slug(category_url: str) -> str:
    """The last path segment of the category URL.

    e.g. https://www.migros.com.tr/sucuk-c-404 → "sucuk-c-404"
    Used for the `{category_slug}` template placeholder. Never the bare category
    name (which would not resolve to a valid endpoint).
    """
    path = re.sub(r"^https?://[^/]+/", "", category_url or "").strip("/")
    if not path:
        return ""
    return path.split("/")[-1].split("?")[0]


def _render_template(
    template: str,
    *,
    category_id: str,
    category_slug: str,
    category_url: str,
    page: int,
    page_param: str,
) -> str:
    """Render an api_url_template with the supported placeholders."""
    rendered = (
        template.replace("{category_id}", category_id)
        .replace("{category_slug}", category_slug)
        .replace("{category_url}", category_url)
        .replace("{page}", str(page))
        .replace("{page_param}", page_param)
    )
    return rendered
