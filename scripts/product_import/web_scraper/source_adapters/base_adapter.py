#!/usr/bin/env python3
"""Source-specific adapter interface for API-backed category discovery.

Generic discovery (href/script/embedded-JSON) covers static/SSR pages. Some
sites render their listings entirely client-side and expose products only via a
public API. An adapter lets such a source discover product detail URLs from a
*configured* (or HTML-visible) endpoint — opt-in, conservative, and polite.

Adapters NEVER:
  * brute-force or guess API endpoints,
  * bypass anti-bot protections or scrape authenticated pages,
  * build a product URL from a name alone,
  * write to `products` or auto-approve anything.

They only return candidate product detail URLs; the existing pipeline still
scrapes each page and stages the result in `product_staging` for admin review.
"""
from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:  # avoid import cycles at runtime
    from ..base import Fetcher
    from ..source_config import Source


class SourceAdapter:
    """Base class for source-specific product-URL discovery adapters."""

    #: registry key; must match the YAML `adapter:` value (and is matched
    #: against `source.adapter` / `source.id`).
    source_id: str = ""

    def can_handle(self, source: "Source", category_url: str) -> bool:
        """Whether this adapter should run for the given source/category URL.

        Adapters are opt-in: the source must explicitly name this adapter via
        its `adapter:` config field (falling back to a matching source id).
        """
        chosen = (getattr(source, "adapter", "") or source.id or "").lower()
        return chosen == self.source_id.lower()

    def discover_product_urls(
        self,
        fetcher: "Fetcher",
        source: "Source",
        category_url: str,
        category: str | None,
        limit: int,
    ) -> tuple[list[str], dict]:
        """Discover product detail URLs for a category.

        Returns (product_urls, debug_stats). `debug_stats` should include:
        adapter_used, endpoint_called, category_url, product_count, raw_count,
        errors, warnings.
        """
        raise NotImplementedError

    @staticmethod
    def new_debug(category_url: str, adapter_used: str) -> dict:
        """Build the standard debug_stats skeleton."""
        return {
            "adapter_used": adapter_used,
            "endpoint_called": None,
            "category_url": category_url,
            "product_count": 0,
            "raw_count": 0,
            "errors": [],
            "warnings": [],
        }
