#!/usr/bin/env python3
"""Source registry: read configured product sources from YAML.

Nothing is hardcoded. The scraper only ever visits URLs that an operator has
explicitly placed in `data/web_product_sources.yaml`. If that file has no
usable URLs, the runner refuses to crawl and prints a clear message.

Config shape (see data/web_product_sources.example.yaml):

    sources:
      - id: official_brand
        enabled: true
        type: product_pages          # product_pages | category_pages
        base_url: ""
        product_urls: []             # for type: product_pages
        category_urls:               # for type: category_pages
          - category: cips
            url: ""
        link_selector: ""            # optional CSS selector for product links
        notes: "..."
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field

try:
    import yaml
except ImportError as exc:  # pragma: no cover - environment guard
    raise SystemExit(
        "ERROR: PyYAML is required for the web scraper. "
        "Install with: pip install pyyaml"
    ) from exc


DEFAULT_CONFIG_PATH = "data/web_product_sources.yaml"

NO_SOURCES_MESSAGE = (
    "No product source URLs configured. "
    "Add category/product URLs to data/web_product_sources.yaml."
)


@dataclass
class CategoryUrl:
    category: str
    url: str


@dataclass
class Source:
    id: str
    enabled: bool = True
    type: str = "product_pages"  # product_pages | category_pages
    base_url: str = ""
    product_urls: list[str] = field(default_factory=list)
    category_urls: list[CategoryUrl] = field(default_factory=list)
    link_selector: str = ""
    product_link_selector: str = ""
    product_link_patterns: list[str] = field(default_factory=list)
    exclude_link_patterns: list[str] = field(default_factory=list)
    max_pages_per_category: int = 1
    next_page_selector: str = ""  # reserved for future pagination (TODO)
    adapter: str = ""  # opt-in source-specific adapter id (e.g. "migros")
    adapter_config: dict = field(default_factory=dict)
    notes: str = ""

    def discovery_options(self) -> dict:
        """Discovery knobs passed to extractors.discover_product_links."""
        return {
            "link_selector": self.link_selector,
            "product_link_selector": self.product_link_selector,
            "product_link_patterns": self.product_link_patterns,
            "exclude_link_patterns": self.exclude_link_patterns,
        }

    @property
    def safe_id(self) -> str:
        """Filesystem/storage-safe variant of the source id."""
        return "".join(c if c.isalnum() or c in ("-", "_") else "_" for c in self.id)

    def usable_urls(self, category: str | None = None) -> list[tuple[str, str | None]]:
        """Return (url, category) pairs this source can crawl.

        For product_pages sources each product URL is a direct candidate.
        For category_pages sources each category URL is a discovery page.
        When [category] is given, only matching category entries are returned.
        """
        pairs: list[tuple[str, str | None]] = []
        if self.type == "category_pages":
            for cat in self.category_urls:
                if not cat.url.strip():
                    continue
                if category and cat.category.strip().lower() != category.strip().lower():
                    continue
                pairs.append((cat.url.strip(), cat.category.strip() or None))
        else:  # product_pages
            if category:
                # product_pages have no category dimension to filter on.
                return []
            for url in self.product_urls:
                if url.strip():
                    pairs.append((url.strip(), None))
        return pairs


def _coerce_category_urls(raw: object) -> list[CategoryUrl]:
    out: list[CategoryUrl] = []
    if isinstance(raw, list):
        for item in raw:
            if isinstance(item, dict):
                url = str(item.get("url") or "").strip()
                cat = str(item.get("category") or "").strip()
                if url or cat:
                    out.append(CategoryUrl(category=cat, url=url))
    return out


def _coerce_str_list(raw: object) -> list[str]:
    if isinstance(raw, list):
        return [str(x).strip() for x in raw if str(x).strip()]
    if isinstance(raw, str) and raw.strip():
        return [raw.strip()]
    return []


def load_sources(path: str = DEFAULT_CONFIG_PATH) -> list[Source]:
    """Load and validate sources from YAML. Missing file → empty list."""
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    raw_sources = data.get("sources") if isinstance(data, dict) else None
    if not isinstance(raw_sources, list):
        return []

    sources: list[Source] = []
    for raw in raw_sources:
        if not isinstance(raw, dict):
            continue
        sid = str(raw.get("id") or "").strip()
        if not sid:
            continue
        try:
            max_pages = int(raw.get("max_pages_per_category", 1) or 1)
        except (TypeError, ValueError):
            max_pages = 1
        sources.append(
            Source(
                id=sid,
                enabled=bool(raw.get("enabled", True)),
                type=str(raw.get("type") or "product_pages").strip(),
                base_url=str(raw.get("base_url") or "").strip(),
                product_urls=_coerce_str_list(raw.get("product_urls")),
                category_urls=_coerce_category_urls(raw.get("category_urls")),
                link_selector=str(raw.get("link_selector") or "").strip(),
                product_link_selector=str(raw.get("product_link_selector") or "").strip(),
                product_link_patterns=_coerce_str_list(raw.get("product_link_patterns")),
                exclude_link_patterns=_coerce_str_list(raw.get("exclude_link_patterns")),
                max_pages_per_category=max(1, max_pages),
                next_page_selector=str(raw.get("next_page_selector") or "").strip(),
                adapter=str(raw.get("adapter") or "").strip(),
                adapter_config=(
                    raw.get("adapter_config")
                    if isinstance(raw.get("adapter_config"), dict)
                    else {}
                ),
                notes=str(raw.get("notes") or "").strip(),
            )
        )
    return sources


def select_sources(
    sources: list[Source], source_filter: str | None
) -> list[Source]:
    """Filter to enabled sources matching --source (or all when 'all'/None)."""
    enabled = [s for s in sources if s.enabled]
    if not source_filter or source_filter.lower() == "all":
        return enabled
    wanted = source_filter.strip().lower()
    return [s for s in enabled if s.id.lower() == wanted]


def has_usable_urls(
    sources: list[Source], category: str | None = None
) -> bool:
    return any(s.usable_urls(category) for s in sources)
