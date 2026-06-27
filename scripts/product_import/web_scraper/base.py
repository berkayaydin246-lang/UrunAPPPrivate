#!/usr/bin/env python3
"""HTTP fetching primitives for the web scraper: polite, rate-limited, safe.

This module deliberately does the minimum a respectful crawler should do:
  * a clear User-Agent identifying a local research/import tool,
  * a configurable delay between requests (default 1.5s),
  * a per-request timeout,
  * graceful handling of 403/blocked responses (skip, never retry-spam),
  * no cookie/session handling and no attempt to defeat anti-bot protections.

It does NOT download large binaries. `head` is provided for cheap metadata
probing (e.g. image size) but callers must opt in.
"""
from __future__ import annotations

import json
import time
from dataclasses import dataclass, field

try:
    import requests
except ImportError as exc:  # pragma: no cover - environment guard
    raise SystemExit(
        "ERROR: 'requests' is required. Install with: pip install requests"
    ) from exc


DEFAULT_DELAY_SECONDS = 1.5
DEFAULT_TIMEOUT_SECONDS = 15
MAX_HTML_BYTES = 3_000_000  # don't slurp unbounded pages

# A clear, honest User-Agent. We are a local catalog-building research tool.
USER_AGENT = (
    "FoodAnalyzerApp-WebDiscovery/0.1 "
    "(local product-staging research importer; contact: dev@example.com)"
)

# Status codes we treat as "blocked / give up politely" rather than retrying.
BLOCKED_STATUSES = {401, 403, 429, 451}


@dataclass
class FetchResult:
    """Outcome of a single GET. Exactly one of html / error is meaningful."""

    url: str
    status: int | None = None
    html: str | None = None
    ok: bool = False
    error: str | None = None
    final_url: str | None = None


@dataclass
class Fetcher:
    """A polite, rate-limited HTTP client shared across a scrape run."""

    delay: float = DEFAULT_DELAY_SECONDS
    timeout: float = DEFAULT_TIMEOUT_SECONDS
    user_agent: str = USER_AGENT
    _last_request_at: float = field(default=0.0, repr=False)
    _session: "requests.Session | None" = field(default=None, repr=False)

    def __post_init__(self) -> None:
        self._session = requests.Session()
        self._session.headers.update(
            {
                "User-Agent": self.user_agent,
                "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
                "Accept-Language": "tr,en;q=0.8",
            }
        )

    def _respect_rate_limit(self) -> None:
        elapsed = time.monotonic() - self._last_request_at
        wait = self.delay - elapsed
        if wait > 0:
            time.sleep(wait)
        self._last_request_at = time.monotonic()

    def get(self, url: str) -> FetchResult:
        """GET an HTML page politely. Never raises on HTTP/transport errors."""
        self._respect_rate_limit()
        try:
            resp = self._session.get(  # type: ignore[union-attr]
                url, timeout=self.timeout, allow_redirects=True, stream=True
            )
        except requests.RequestException as exc:
            return FetchResult(url=url, error=f"request_error: {exc}")

        status = resp.status_code
        if status in BLOCKED_STATUSES:
            resp.close()
            return FetchResult(
                url=url, status=status, error=f"blocked (status {status}) — skipping"
            )
        if status >= 400:
            resp.close()
            return FetchResult(url=url, status=status, error=f"http {status}")

        content_type = (resp.headers.get("Content-Type") or "").lower()
        if "html" not in content_type and "xml" not in content_type:
            # Not a page we can extract product data from.
            resp.close()
            return FetchResult(
                url=url, status=status, error=f"non-html content-type: {content_type}"
            )

        # Read at most MAX_HTML_BYTES so a misconfigured source can't blow up RAM.
        try:
            raw = resp.raw.read(MAX_HTML_BYTES + 1, decode_content=True)
        except Exception as exc:  # pragma: no cover - defensive
            resp.close()
            return FetchResult(url=url, status=status, error=f"read_error: {exc}")
        finally:
            resp.close()

        encoding = resp.encoding or "utf-8"
        try:
            html = raw.decode(encoding, errors="replace")
        except (LookupError, UnicodeDecodeError):
            html = raw.decode("utf-8", errors="replace")

        return FetchResult(
            url=url,
            status=status,
            html=html,
            ok=True,
            final_url=str(resp.url),
        )

    def get_json(self, url: str, headers: dict[str, str] | None = None):
        """GET a JSON endpoint politely. Returns (data | None, FetchResult).

        Used by source-specific adapters for API-backed listings. Same rate
        limiting / blocked-status handling as get(); never raises. `headers`
        adds safe public request headers (no cookies / no session secrets).
        """
        self._respect_rate_limit()
        request_headers = {"Accept": "application/json, text/plain, */*;q=0.8"}
        if headers:
            request_headers.update(headers)
        try:
            resp = self._session.get(  # type: ignore[union-attr]
                url,
                timeout=self.timeout,
                allow_redirects=True,
                headers=request_headers,
            )
        except requests.RequestException as exc:
            return None, FetchResult(url=url, error=f"request_error: {exc}")

        status = resp.status_code
        if status in BLOCKED_STATUSES:
            return None, FetchResult(
                url=url, status=status, error=f"blocked (status {status}) — skipping"
            )
        if status >= 400:
            return None, FetchResult(url=url, status=status, error=f"http {status}")

        try:
            data = resp.json()
        except ValueError:
            try:
                data = json.loads(resp.text)
            except (ValueError, json.JSONDecodeError):
                return None, FetchResult(
                    url=url, status=status, error="non-json response"
                )
        return data, FetchResult(url=url, status=status, ok=True, final_url=str(resp.url))

    def head(self, url: str) -> dict[str, str]:
        """Cheap metadata probe (headers only). Returns {} on any failure.

        Used only when a caller wants image content-length/type without
        downloading the body. Still rate limited.
        """
        self._respect_rate_limit()
        try:
            resp = self._session.head(  # type: ignore[union-attr]
                url, timeout=self.timeout, allow_redirects=True
            )
        except requests.RequestException:
            return {}
        if resp.status_code >= 400:
            return {}
        return {k.lower(): v for k, v in resp.headers.items()}
