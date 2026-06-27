#!/usr/bin/env python3
"""Fix Migros product images without touching product content fields.

This script re-fetches only image-related product data from Migros product
pages and updates either `products.image_url` or
`product_staging.image_front_url` when a clearly better front image is found.
It never re-scrapes or modifies ingredients, nutrition, name, brand, barcode,
category, source, status, or analysis fields.
"""
from __future__ import annotations

import argparse
import os
import sys
import re
from dataclasses import dataclass, replace
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import requests  # noqa: E402

import common  # noqa: E402
from web_scraper import image_scoring, runner, source_adapters, source_config  # noqa: E402
from web_scraper.base import Fetcher  # noqa: E402


LABEL_ROLES = ("back_label", "nutrition_label", "ingredients_label")
PRIMARY_FRONT_SOURCES = ("api_primary", "category_card")
TABLE_CHOICES = ("products", "product_staging", "both")
SUSPICIOUS_URL_SIGNALS = (
    # Back / side / label image patterns
    "_2-",
    "_yan",
    "-yan",
    "back",
    "arka",
    "label",
    "nutrition",
    "besin",
    "deger",
    "değer",
    "icindekiler",
    "içindekiler",
    "ingredients",
    # Generic placeholder / missing-image patterns
    "placeholder",
    "no-image",
    "noimage",
    "unknown",
    "question",
    "chef",
    # Migros non-product UI assets (icons, logos, marketing, editorial)
    "ne-pisirsem",
    "/assets/icons/",
    "/assets/logos/",
    "digital-magazine",
    "migroskop",
    "money-logo",
    "migros-tv-logo",
    "saglikli-yasam",
    "kadin-akademisi",
    "blindlook",
    "gidani-koru",
    "anne-bebek",
)
DB_SUSPICIOUS_FILTER_SIGNALS = (
    "_2-",
    "_yan",
    "-yan",
    "back",
    "arka",
    "label",
    "nutrition",
    "besin",
    "ingredients",
)


@dataclass(frozen=True)
class TableSpec:
    table: str
    image_field: str
    select_fields: str
    updated_stat: str


PRODUCT_SPEC = TableSpec(
    table="products",
    image_field="image_url",
    select_fields="id,name,brand,image_url,source,source_url,category_tags,updated_at",
    updated_stat="updated_products",
)
STAGING_SPEC = TableSpec(
    table="product_staging",
    image_field="image_front_url",
    select_fields=(
        "id,name,brand,image_front_url,image_source,source,source_url,"
        "category_tags,updated_at"
    ),
    updated_stat="updated_staging",
)
SPECS = {
    PRODUCT_SPEC.table: PRODUCT_SPEC,
    STAGING_SPEC.table: STAGING_SPEC,
}


@dataclass
class RepairDecision:
    status: str
    reason: str
    current_image_url: str | None
    current_image_role: str
    current_image_score: int
    new_image_url: str | None
    new_image_role: str
    new_image_score: int
    confidence: str
    selected_front_index: int | None = None
    selected_front_source: str | None = None
    fetched_image_count: int = 0
    patch: dict | None = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--table",
        choices=TABLE_CHOICES,
        default="products",
        help="Table to repair: products, product_staging, or both",
    )
    parser.add_argument("--limit", type=int, default=100, help="Max products to inspect")
    parser.add_argument("--offset", type=int, default=0, help="Offset for target rows")
    parser.add_argument("--dry-run", action="store_true", help="Inspect only; write nothing")
    parser.add_argument("--real", action="store_true", help="Write image-only updates")
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print current/fetched/selected/decision debug blocks for each row",
    )
    parser.add_argument(
        "--fix-suspicious-only",
        action="store_true",
        help="Only repair rows whose current image URL has suspicious back/side/label signals",
    )
    parser.add_argument(
        "--fix-missing-only",
        action="store_true",
        help="Only repair rows whose current image field is missing",
    )
    parser.add_argument(
        "--only-source-url",
        default=None,
        help="Process only the product with this exact Migros source_url",
    )
    parser.add_argument(
        "--sleep-seconds",
        type=float,
        default=0.3,
        help="Delay between HTTP requests to Migros",
    )
    parser.add_argument(
        "--only-if-current-looks-back",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=None,
        help="Optional override for Migros category API pages when preloading api_primary metadata",
    )
    parser.add_argument(
        "--source",
        default="web_scraper:migros",
        help="Products.source filter (default: web_scraper:migros)",
    )
    parser.add_argument(
        "--config",
        default=source_config.DEFAULT_CONFIG_PATH,
        help="Path to web source configuration YAML",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=15.0,
        help="Per-request timeout when fetching Migros pages",
    )
    return parser.parse_args()


def build_image_only_patch(
    image_url: str,
    *,
    image_field: str = "image_url",
    image_source: str | None = None,
    now: datetime | None = None,
) -> dict[str, str]:
    """Build an image-only update payload for the selected table."""
    if not image_url or not image_url.strip():
        raise ValueError("image_url is required")
    effective_now = (now or datetime.now(timezone.utc)).isoformat()
    patch = {
        image_field: image_url.strip(),
        "updated_at": effective_now,
    }
    if image_field == "image_front_url" and image_source:
        patch["image_source"] = image_source
    return patch


def fetch_target_rows(
    base_url: str,
    key: str,
    *,
    spec: TableSpec,
    source: str,
    limit: int,
    offset: int = 0,
    only_source_url: str | None = None,
    fix_suspicious_only: bool = False,
    fix_missing_only: bool = False,
) -> list[dict]:
    if only_source_url:
        params: dict[str, str] = {
            "select": spec.select_fields,
            "source": f"eq.{source}",
            "source_url": f"eq.{only_source_url}",
            "order": "updated_at.desc",
            "limit": "1",
        }
        resp = requests.get(
            f"{base_url}/rest/v1/{spec.table}",
            headers=common._supabase_headers(key),
            params=params,
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()

    params = {
        "select": spec.select_fields,
        "source": f"eq.{source}",
        "source_url": "not.is.null",
        "order": "updated_at.desc",
        "limit": str(limit),
    }
    if fix_missing_only:
        params[spec.image_field] = "is.null"
    if offset:
        params["offset"] = str(max(0, offset))
    resp = requests.get(
        f"{base_url}/rest/v1/{spec.table}",
        headers=common._supabase_headers(key),
        params=params,
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()


def get_image_field(table: str) -> str:
    if table == PRODUCT_SPEC.table:
        return PRODUCT_SPEC.image_field
    if table == STAGING_SPEC.table:
        return STAGING_SPEC.image_field
    raise ValueError(f"Unsupported table: {table}")


def build_suspicious_or_filter(table: str) -> str:
    image_field = get_image_field(table)
    conditions = ",".join(
        f"{image_field}.ilike.%{signal}%"
        for signal in DB_SUSPICIOUS_FILTER_SIGNALS
    )
    return f"({conditions})"


def apply_suspicious_filter(params: dict[str, str], table: str) -> dict[str, str]:
    params["or"] = build_suspicious_or_filter(table)
    return params


def fetch_all_migros_rows_for_table(
    base_url: str,
    key: str,
    table: str,
    *,
    source: str,
    page_size: int = 1000,
) -> list[dict]:
    """Page through every row for a Migros source in the given table.

    Returns all rows with a non-null source_url.  Suspicious filtering is
    deliberately NOT done here — the caller filters in Python after receiving
    the full set, so DB-level ILIKE/OR issues cannot affect the result.
    """
    spec = SPECS[table]
    all_rows: list[dict] = []
    offset = 0
    while True:
        params: dict[str, str] = {
            "select": spec.select_fields,
            "source": f"eq.{source}",
            "order": "updated_at.asc",
            "limit": str(page_size),
            "offset": str(offset),
        }
        resp = requests.get(
            f"{base_url}/rest/v1/{spec.table}",
            headers=common._supabase_headers(key),
            params=params,
            timeout=60,
        )
        resp.raise_for_status()
        rows = resp.json()
        # Python-side null source_url guard (belt-and-suspenders).
        all_rows.extend(r for r in rows if r.get("source_url"))
        if len(rows) < page_size:
            break
        offset += page_size
    return all_rows


def fetch_suspicious_rows_python_filtered(
    base_url: str,
    key: str,
    table: str,
    limit: int,
    offset: int = 0,
    *,
    source: str,
) -> list[dict]:
    """Fetch all Migros rows for *table*, filter suspicious ones in Python, paginate.

    DB-level ILIKE and OR filters are unreliable on Supabase Cloud (URL-encoding
    of `%` wildcards).  Fetching every row and filtering in Python is the only
    approach that is guaranteed to work regardless of client or server behaviour.

    Image field mapping:
      products        → image_url
      product_staging → image_front_url   (never product_staging.image_url)
    """
    image_field = get_image_field(table)
    all_rows = fetch_all_migros_rows_for_table(base_url, key, table, source=source)
    suspicious = [
        r for r in all_rows
        if is_suspicious_image_url(_resolve_text(r.get(image_field)))
    ]
    # Oldest-updated-at first so repeated runs process the longest-neglected rows.
    suspicious.sort(key=lambda r: str(r.get("updated_at") or ""))
    return suspicious[offset : offset + limit]


def _first_category_tag(row: dict) -> str | None:
    tags = row.get("category_tags")
    if isinstance(tags, list):
        for tag in tags:
            if isinstance(tag, str) and tag.strip():
                return tag.strip()
    return None


def _find_migros_source(config_path: str) -> source_config.Source | None:
    sources = source_config.select_sources(source_config.load_sources(config_path), "migros")
    return sources[0] if sources else None


def preload_api_metadata(
    fetcher: Fetcher,
    rows: list[dict],
    *,
    config_path: str,
    max_pages: int | None = None,
) -> dict[str, dict]:
    """Preload Migros category API metadata so api_primary images stay available."""
    src = _find_migros_source(config_path)
    adapter = source_adapters.get_adapter("migros")
    if src is None or adapter is None:
        return {}

    if max_pages is not None:
        src = replace(
            src,
            max_pages_per_category=max(1, max_pages),
            adapter_config={**src.adapter_config, "max_pages": max(1, max_pages)},
        )

    category_urls = {item.category: item.url for item in src.category_urls}
    categories = sorted(
        {tag for row in rows if (tag := _first_category_tag(row)) and tag in category_urls}
    )
    metadata: dict[str, dict] = {}
    for category in categories:
        category_url = category_urls[category]
        _, debug = adapter.discover_product_urls(
            fetcher,
            src,
            category_url,
            category,
            limit=5000,
        )
        metadata.update(debug.get("url_metadata") or {})
    return metadata


def _fallback_current_candidate(row: dict) -> dict | None:
    current_url = _resolve_text(row.get("_current_image_url"))
    if not current_url:
        return None
    scored = image_scoring.score_image(
        image_scoring.ImageCandidate(url=current_url, source="current_db"),
        name=_resolve_text(row.get("name")),
        brand=_resolve_text(row.get("brand")),
    )
    return image_scoring.serialize_candidate(scored)


def _candidate_for_url(image_report: dict, image_url: str | None) -> dict | None:
    if not image_url:
        return None
    for cand in image_report.get("image_candidates") or []:
        if cand.get("url") == image_url:
            return cand
    return None


def _score_of(candidate: dict | None) -> int:
    try:
        return int((candidate or {}).get("score") or 0)
    except (TypeError, ValueError):
        return 0


def _is_label_candidate(candidate: dict | None) -> bool:
    return ((candidate or {}).get("role") or "unknown") in LABEL_ROLES


def _fold_url(value: str | None) -> str:
    if not value:
        return ""
    return (
        value.lower()
        .replace("ç", "c")
        .replace("ğ", "g")
        .replace("ı", "i")
        .replace("ö", "o")
        .replace("ş", "s")
        .replace("ü", "u")
    )


def is_suspicious_image_url(image_url: str | None) -> bool:
    """Return True for back/side/label/placeholder/non-product asset image URLs.

    Two-stage check:
    1. Explicit signal patterns (back, label, placeholder, Migros UI asset names).
    2. Migros-domain check: any URL on migros.com.tr or migrosone.com that is NOT
       under the product CDN path images.migrosone.com/sanalmarket/product/ is a
       non-product asset (icon, logo, editorial image, etc.).
    """
    folded = _fold_url(image_url)
    if not folded:
        return False
    if any(signal in folded for signal in SUSPICIOUS_URL_SIGNALS):
        return True
    _on_migros_domain = "migros.com.tr" in folded or "migrosone.com" in folded
    if _on_migros_domain and "images.migrosone.com/sanalmarket/product/" not in folded:
        return True
    return False


def _candidate_url(candidate: dict | None) -> str | None:
    return _resolve_text((candidate or {}).get("url"))


def _candidate_role(candidate: dict | None) -> str:
    if candidate is None:
        return "unknown"
    role = str(candidate.get("role") or "unknown")
    if role in LABEL_ROLES:
        return role
    if is_suspicious_image_url(_candidate_url(candidate)):
        return "back_label"
    return role


def _selected_front_role(candidate: dict | None) -> str:
    if candidate is None:
        return "unknown"
    role = _candidate_role(candidate)
    source = str(candidate.get("source") or "unknown")
    index = candidate.get("index")
    score = _score_of(candidate)
    if role in LABEL_ROLES:
        return role
    if source in PRIMARY_FRONT_SOURCES and score > 0:
        return "front"
    if source == "detail_gallery" and index == 0 and score > 0:
        return "front"
    return role


def _selected_front_confidence(candidate: dict | None) -> str:
    if candidate is None:
        return "none"
    score = _score_of(candidate)
    source = str(candidate.get("source") or "unknown")
    index = candidate.get("index")
    role = _selected_front_role(candidate)
    if role in LABEL_ROLES or score <= 0 or is_suspicious_image_url(_candidate_url(candidate)):
        return "low"
    if source in PRIMARY_FRONT_SOURCES and score >= 15:
        return "high"
    if source == "detail_gallery" and index == 0 and score >= 10:
        return "high"
    if role == "front" and score >= 25:
        return "high"
    if score >= 10:
        return "medium"
    return "low"


def _select_repair_front_candidate(image_report: dict | None) -> dict | None:
    candidates = (image_report or {}).get("image_candidates") or []
    if not candidates:
        return None

    usable = [
        c
        for c in candidates
        if not _is_label_candidate(c)
        and not is_suspicious_image_url(_candidate_url(c))
        and _score_of(c) > 0
    ]
    if not usable:
        return None

    api_or_card = next(
        (c for c in usable if str(c.get("source") or "unknown") in PRIMARY_FRONT_SOURCES),
        None,
    )
    if api_or_card is not None:
        return api_or_card

    detail_first = next(
        (
            c
            for c in usable
            if str(c.get("source") or "unknown") == "detail_gallery"
            and c.get("index") == 0
        ),
        None,
    )
    if detail_first is not None:
        return detail_first

    explicit_front = next((c for c in usable if _selected_front_role(c) == "front"), None)
    if explicit_front is not None:
        return explicit_front

    return usable[0]


def plan_image_update(
    row: dict,
    image_report: dict | None,
    *,
    spec: TableSpec = PRODUCT_SPEC,
    require_current_suspicious: bool = False,
    require_current_missing: bool = False,
    now: datetime | None = None,
) -> RepairDecision:
    """Return a safe image-only decision for one products/product_staging row."""
    current_image_url = _resolve_text(row.get(spec.image_field))
    row = {**row, "_current_image_url": current_image_url}

    if require_current_suspicious and not is_suspicious_image_url(current_image_url):
        return RepairDecision(
            status="skipped_not_suspicious",
            reason=f"current {spec.image_field} is not suspicious",
            current_image_url=current_image_url,
            current_image_role="unknown",
            current_image_score=0,
            new_image_url=None,
            new_image_role="unknown",
            new_image_score=0,
            confidence="none",
        )

    if require_current_missing and current_image_url:
        return RepairDecision(
            status="skipped_not_missing",
            reason=f"current {spec.image_field} is present",
            current_image_url=current_image_url,
            current_image_role="unknown",
            current_image_score=0,
            new_image_url=None,
            new_image_role="unknown",
            new_image_score=0,
            confidence="none",
        )

    source_url = _resolve_text(row.get("source_url"))
    if not source_url:
        return RepairDecision(
            status="skipped_no_source_url",
            reason="product has no source_url",
            current_image_url=current_image_url,
            current_image_role="unknown",
            current_image_score=0,
            new_image_url=None,
            new_image_role="unknown",
            new_image_score=0,
            confidence="none",
        )

    selected_front = _select_repair_front_candidate(image_report)
    if selected_front is None:
        skip_status = (
            "skipped_no_images_found"
            if not ((image_report or {}).get("image_candidates") or [])
            else "skipped_low_confidence"
        )
        return RepairDecision(
            status=skip_status,
            reason="no confident front image found",
            current_image_url=current_image_url,
            current_image_role="unknown",
            current_image_score=0,
            new_image_url=None,
            new_image_role="unknown",
            new_image_score=0,
            confidence="none",
            fetched_image_count=len((image_report or {}).get("image_candidates") or []),
        )

    current_candidate = _candidate_for_url(image_report, current_image_url) or _fallback_current_candidate(row)
    current_role = _candidate_role(current_candidate)
    current_score = int((current_candidate or {}).get("score") or 0)

    new_image_url = _resolve_text(selected_front.get("url"))
    new_role = _selected_front_role(selected_front)
    new_score = _score_of(selected_front)
    confidence = _selected_front_confidence(selected_front)
    selected_front_index = (
        int(selected_front["index"])
        if selected_front is not None and selected_front.get("index") is not None
        else None
    )
    selected_front_source = (
        str(selected_front.get("source"))
        if selected_front is not None and selected_front.get("source") is not None
        else None
    )
    fetched_image_count = len(image_report.get("image_candidates") or [])

    if current_image_url == new_image_url:
        return RepairDecision(
            status="skipped_already_front",
            reason=f"current {spec.image_field} equals selected front image",
            current_image_url=current_image_url,
            current_image_role=current_role,
            current_image_score=current_score,
            new_image_url=new_image_url,
            new_image_role=new_role,
            new_image_score=new_score,
            confidence=confidence,
            selected_front_index=selected_front_index,
            selected_front_source=selected_front_source,
            fetched_image_count=fetched_image_count,
        )

    if new_role in LABEL_ROLES:
        return RepairDecision(
            status="skipped_low_confidence",
            reason="selected image is still a back/label fallback",
            current_image_url=current_image_url,
            current_image_role=current_role,
            current_image_score=current_score,
            new_image_url=new_image_url,
            new_image_role=new_role,
            new_image_score=new_score,
            confidence=confidence,
            selected_front_index=selected_front_index,
            selected_front_source=selected_front_source,
            fetched_image_count=fetched_image_count,
        )

    if confidence == "low":
        return RepairDecision(
            status="skipped_low_confidence",
            reason="selected image confidence is low",
            current_image_url=current_image_url,
            current_image_role=current_role,
            current_image_score=current_score,
            new_image_url=new_image_url,
            new_image_role=new_role,
            new_image_score=new_score,
            confidence=confidence,
            selected_front_index=selected_front_index,
            selected_front_source=selected_front_source,
            fetched_image_count=fetched_image_count,
        )

    patch = build_image_only_patch(
        new_image_url,
        image_field=spec.image_field,
        image_source="web_scraper:migros" if spec.table == "product_staging" else None,
        now=now,
    )
    return RepairDecision(
        status="would_update",
        reason="confident front image found",
        current_image_url=current_image_url,
        current_image_role=current_role,
        current_image_score=current_score,
        new_image_url=new_image_url,
        new_image_role=new_role,
        new_image_score=new_score,
        confidence=confidence,
        selected_front_index=selected_front_index,
        selected_front_source=selected_front_source,
        fetched_image_count=fetched_image_count,
        patch=patch,
    )


def apply_row_patch(
    base_url: str,
    key: str,
    *,
    spec: TableSpec,
    row_id: str,
    patch: dict,
) -> None:
    resp = requests.patch(
        f"{base_url}/rest/v1/{spec.table}",
        headers=common._supabase_headers(key),
        params={"id": f"eq.{row_id}"},
        json=patch,
        timeout=30,
    )
    resp.raise_for_status()


def _resolve_text(value) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def _print_update(label: str, row: dict, decision: RepairDecision, spec: TableSpec) -> None:
    print(f"[{label}]")
    print(f"table={spec.table}")
    print(f"id={row.get('id')}")
    print(f"name={row.get('name')}")
    print(f"source_url={row.get('source_url')}")
    if decision.current_image_url is not None:
        print(f"current_image_field={spec.image_field}")
        print(f"current_image_url={decision.current_image_url}")
        print(f"current_image_role={decision.current_image_role}")
    print(f"new_image_url={decision.new_image_url}")
    print(f"new_image_role={decision.new_image_role}")
    print(f"confidence={decision.confidence}")


def _print_targeted_dry_run_debug(
    row: dict,
    image_report: dict | None,
    decision: RepairDecision,
    spec: TableSpec,
) -> None:
    print("[current]")
    print(f"table={spec.table}")
    print(f"id={row.get('id')}")
    print(f"name={row.get('name')}")
    print(f"current_image_field={spec.image_field}")
    print(f"current_image_url={decision.current_image_url}")
    print(f"current_image_role={decision.current_image_role}")

    fetched = (image_report or {}).get("image_candidates") or []
    print("[fetched_images]")
    print(f"fetched_image_count={len(fetched)}")
    for i, cand in enumerate(fetched):
        print(
            f"index={cand.get('index') if cand.get('index') is not None else i} "
            f"role={_selected_front_role(cand)} "
            f"confidence={_selected_front_confidence(cand)} "
            f"source={cand.get('source')} score={cand.get('score')} "
            f"url={cand.get('url')}"
        )

    print("[selected_front]")
    print(f"url={decision.new_image_url}")
    print(f"role={decision.new_image_role}")
    print(f"confidence={decision.confidence}")
    print(f"reason={decision.reason}")
    print(f"selected_front_index={decision.selected_front_index}")
    print(f"selected_front_role={decision.new_image_role}")
    print(f"selected_front_source={decision.selected_front_source}")
    print(f"selected_front_confidence={decision.confidence}")
    print(f"selected_front_url={decision.new_image_url}")

    print("[decision]")
    print(f"decision={decision.status}")
    print(f"reason={decision.reason}")
    if decision.status == "would_update":
        print(f"old_image_url={decision.current_image_url}")
        print(f"new_image_url={decision.new_image_url}")


def _print_bulk_query_debug(spec: TableSpec, rows: list[dict], *, mode: str) -> None:
    print("[bulk_query_mode]")
    print(f"table={spec.table}")
    print(f"mode={mode}")
    print(f"image_field={spec.image_field}")
    print("expected_suspicious_filter_applied=true")
    for row in rows[:10]:
        current_image_url = _resolve_text(row.get(spec.image_field))
        print("[fetched_row]")
        print(f"id={row.get('id')}")
        print(f"name={row.get('name')}")
        print(f"current_image_url={current_image_url}")
        print(f"is_suspicious={is_suspicious_image_url(current_image_url)}")


def _bulk_query_non_suspicious_count(spec: TableSpec, rows: list[dict]) -> int:
    return sum(
        1
        for row in rows
        if not is_suspicious_image_url(_resolve_text(row.get(spec.image_field)))
    )


def _specs_for_table(table: str) -> list[TableSpec]:
    if table == "both":
        return [PRODUCT_SPEC, STAGING_SPEC]
    return [SPECS[table]]


def _normalize_source_url_arg(value: str | None) -> str | None:
    """Accept a plain URL, or a Markdown link accidentally pasted from chat."""
    text = _resolve_text(value)
    if not text:
        return None
    md = re.fullmatch(r"\[[^\]]+\]\((https?://[^)]+)\)", text)
    if md:
        return md.group(1)
    if text.startswith("[") and text.endswith("]"):
        text = text[1:-1].strip()
    return text


def _should_debug(args: argparse.Namespace) -> bool:
    return bool(args.verbose or args.only_source_url)


def main() -> int:
    args = parse_args()
    args.only_source_url = _normalize_source_url_arg(args.only_source_url)
    real = bool(args.real) and not args.dry_run
    debug_output = _should_debug(args)
    base_url, key = common.load_supabase_env()

    fetcher = Fetcher(delay=max(0.0, args.sleep_seconds), timeout=args.timeout)

    stats = {
        "checked": 0,
        "updated_products": 0,
        "updated_staging": 0,
        "skipped_no_source_url": 0,
        "skipped_no_images_found": 0,
        "skipped_already_front": 0,
        "skipped_low_confidence": 0,
        "skipped_not_suspicious": 0,
        "skipped_not_missing": 0,
        "would_update": 0,
        "failed": 0,
    }

    any_rows = False
    for spec in _specs_for_table(args.table):
        bulk_suspicious_mode = bool(args.fix_suspicious_only and not args.only_source_url)

        if bulk_suspicious_mode:
            # Fetch all rows then filter in Python — DB-level ilike/or filters
            # are unreliable on Supabase Cloud due to URL-encoding of wildcards.
            all_rows = fetch_all_migros_rows_for_table(
                base_url, key, spec.table, source=args.source
            )
            suspicious_all = [
                r for r in all_rows
                if is_suspicious_image_url(_resolve_text(r.get(spec.image_field)))
            ]
            suspicious_all.sort(key=lambda r: str(r.get("updated_at") or ""))
            rows = suspicious_all[args.offset : args.offset + args.limit]

            print("[bulk_python_filter_mode]")
            print(f"table={spec.table}")
            print(f"image_field={spec.image_field}")
            print(f"total_rows_fetched={len(all_rows)}")
            print(f"suspicious_rows_found={len(suspicious_all)}")
            print(f"selected_for_processing={len(rows)}")
            for _dbg_row in rows[:10]:
                _cur = _resolve_text(_dbg_row.get(spec.image_field))
                print("[fetched_row]")
                print(f"id={_dbg_row.get('id')}")
                print(f"name={_dbg_row.get('name')}")
                print(f"current_image_url={_cur}")
                print(f"is_suspicious={is_suspicious_image_url(_cur)}")
        else:
            rows = fetch_target_rows(
                base_url,
                key,
                spec=spec,
                source=args.source,
                limit=args.limit,
                offset=args.offset,
                only_source_url=args.only_source_url,
                fix_missing_only=args.fix_missing_only,
            )

        if not rows:
            print(f"No matching {spec.table} rows found.")
            continue
        any_rows = True

        api_metadata = preload_api_metadata(
            fetcher,
            rows,
            config_path=args.config,
            max_pages=args.max_pages,
        )

        for row in rows:
            stats["checked"] += 1
            source_url = _resolve_text(row.get("source_url"))

            pre_decision = plan_image_update(
                row,
                None,
                spec=spec,
                require_current_suspicious=bool(
                    args.fix_suspicious_only or args.only_if_current_looks_back
                ),
                require_current_missing=bool(args.fix_missing_only),
                now=datetime.now(timezone.utc),
            )
            if pre_decision.status in ("skipped_not_suspicious", "skipped_not_missing", "skipped_no_source_url"):
                stats[pre_decision.status] += 1
                if debug_output:
                    _print_targeted_dry_run_debug(row, None, pre_decision, spec)
                else:
                    print(
                        f"[{pre_decision.status}] table={spec.table} id={row.get('id')} "
                        f"name={row.get('name')} reason={pre_decision.reason}"
                    )
                continue

            try:
                image_report, error = runner.scrape_product_image_data(
                    fetcher,
                    source_url,
                    "migros",
                    api_metadata=api_metadata.get(source_url),
                )
            except Exception as exc:  # noqa: BLE001
                stats["failed"] += 1
                print(
                    f"[failed] table={spec.table} id={row.get('id')} "
                    f"source_url={source_url} error={exc}",
                    file=sys.stderr,
                )
                continue

            if error is not None:
                stats["failed"] += 1
                print(
                    f"[failed] table={spec.table} id={row.get('id')} "
                    f"source_url={source_url} error={error}",
                    file=sys.stderr,
                )
                continue

            decision = plan_image_update(
                row,
                image_report,
                spec=spec,
                require_current_suspicious=bool(
                    args.fix_suspicious_only or args.only_if_current_looks_back
                ),
                require_current_missing=bool(args.fix_missing_only),
                now=datetime.now(timezone.utc),
            )
            if debug_output:
                _print_targeted_dry_run_debug(row, image_report, decision, spec)

            if decision.status != "would_update":
                stats[decision.status] += 1
                if not debug_output:
                    print(
                        f"[{decision.status}] table={spec.table} id={row.get('id')} "
                        f"name={row.get('name')} reason={decision.reason}"
                    )
                continue

            if not real:
                stats["would_update"] += 1
                if not debug_output:
                    _print_update("would_update", row, decision, spec)
                continue

            try:
                apply_row_patch(
                    base_url,
                    key,
                    spec=spec,
                    row_id=row["id"],
                    patch=decision.patch or {},
                )
            except Exception as exc:  # noqa: BLE001
                stats["failed"] += 1
                print(
                    f"[failed] table={spec.table} id={row.get('id')} "
                    f"source_url={source_url} error={exc}",
                    file=sys.stderr,
                )
                continue

            stats[spec.updated_stat] += 1
            _print_update("updated", row, decision, spec)

    if not any_rows:
        return 0

    print(
        "Stats: "
        + " ".join(f"{key}={value}" for key, value in stats.items())
    )
    if not real:
        print("Dry-run complete. Pass --real to write image-only updates.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
