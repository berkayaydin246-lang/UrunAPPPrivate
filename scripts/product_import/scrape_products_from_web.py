#!/usr/bin/env python3
"""Automatic web product discovery / scraping → product_staging.

Crawls *configured* product sources (data/web_product_sources.yaml), extracts
product data (name, brand, image, ingredients, nutrition, category, optional
barcode), quality-scores it, and stages candidates in `product_staging` for
admin review. It NEVER writes to `products` and NEVER auto-approves.

Examples
--------
Dry run, all sources:
    python3 scripts/product_import/scrape_products_from_web.py \\
        --source all --limit 20 --dry-run

Real staging insert:
    python3 scripts/product_import/scrape_products_from_web.py \\
        --source all --limit 20 --real

A specific source + category:
    python3 scripts/product_import/scrape_products_from_web.py \\
        --source migros --category cips --limit 50 --dry-run

A single product URL:
    python3 scripts/product_import/scrape_products_from_web.py \\
        --url "https://example.com/product/..." --dry-run
"""
from __future__ import annotations

import os
import sys
import json
import argparse

# Allow running as a plain script: make scripts/product_import importable so the
# `web_scraper` package and `common` resolve regardless of CWD.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import common  # noqa: E402
from web_scraper import runner, source_config  # noqa: E402
from web_scraper.base import DEFAULT_DELAY_SECONDS, DEFAULT_TIMEOUT_SECONDS  # noqa: E402


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--source", default="all", help="Source id from the config, or 'all'")
    p.add_argument("--category", default=None, help="Restrict to a configured category (e.g. cips)")
    p.add_argument("--url", default=None, help="Scrape a single product URL directly")
    p.add_argument("--config", default=source_config.DEFAULT_CONFIG_PATH, help="Path to sources YAML")
    p.add_argument("--limit", type=int, default=20, help="Max pages to crawl this run")
    p.add_argument("--delay", type=float, default=DEFAULT_DELAY_SECONDS, help="Delay between requests (s)")
    p.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS, help="Per-request timeout (s)")
    p.add_argument("--min-quality", type=int, default=0, help="Skip candidates below this score")
    p.add_argument("--dry-run", action="store_true", help="Inspect only; write nothing")
    p.add_argument("--real", action="store_true", help="Write candidates to product_staging")
    p.add_argument("--force", action="store_true", help="Overwrite approved/rejected staging rows")
    p.add_argument(
        "--auto-approve-high-quality",
        action="store_true",
        help="Opt-in: auto-approve perfect web_scraper products into products "
        "(real mode only). Off by default.",
    )
    p.add_argument(
        "--auto-approve-min-score",
        type=int,
        default=100,
        help="Minimum quality_score required for auto-approval (default 100)",
    )
    return p.parse_args()


def build_work_items(args: argparse.Namespace) -> tuple[list[tuple], list[str]]:
    """Return (work_items, notices). work_items feed runner.run_scrape."""
    # Single direct URL mode — for testing/debugging only (Part 3, Mode B).
    if args.url:
        sid = "manual_url"
        return [("product", args.url, args.category, sid, {})], []

    sources = source_config.load_sources(args.config)
    selected = source_config.select_sources(sources, args.source)
    if not selected:
        return [], [f"No enabled source matched --source={args.source!r}."]

    items: list[tuple] = []
    for src in selected:
        opts = {**src.discovery_options(), "source": src}
        for url, category in src.usable_urls(args.category):
            mode = "category" if src.type == "category_pages" else "product"
            items.append((mode, url, category, src.id, opts))
    return items, []


def print_candidate(candidate: dict) -> None:
    nutrition = candidate.get("nutrition_json") or {}
    ing = candidate.get("ingredients_text") or ""
    payload = candidate.get("raw_source_payload") or {}
    ing_preview = (ing[:80] + "…") if len(ing) > 80 else ing
    # Compact nutrition preview, e.g. "energy_kcal=199.0 fat=15.0 ..."
    nutri_preview = " ".join(f"{k}={v}" for k, v in nutrition.items())
    if len(nutri_preview) > 120:
        nutri_preview = nutri_preview[:120] + "…"
    warnings = payload.get("nutrition_warnings") or []
    brand_method = candidate.get("brand_source_method") or "unknown"
    brand_raw = candidate.get("brand_raw")
    ing_quality = candidate.get("ingredient_quality") or payload.get("ingredients_quality") or "unknown"
    ing_source = (candidate.get("ingredients_source") or "").replace(
        "web_scraper:", ""
    ) or ("detail_section" if ing else "missing")
    brand_line = f"  brand={candidate.get('brand')} brand_source={brand_method}"
    if brand_raw:
        brand_line += f" api_brand={brand_raw}"
    print("[candidate]")
    print(f"  name={candidate.get('name')}")
    print(brand_line)
    print(f"  barcode={candidate.get('barcode')}")
    print(f"  category={candidate.get('category_suggestion')}")
    image_front_role = candidate.get("image_front_role") or payload.get("image_front_role") or "unknown"
    image_quality = candidate.get("image_quality") or payload.get("image_quality") or "unknown"
    image_cands = payload.get("image_candidates") or []
    best_cand = next((c for c in image_cands if c.get("url") == candidate.get("image_front_url")), None)
    image_idx = best_cand.get("index") if best_cand else None
    image_src = best_cand.get("source") if best_cand else "unknown"
    label_count = sum(
        1 for c in image_cands
        if c.get("role") in ("back_label", "nutrition_label", "ingredients_label")
        and c.get("url") != candidate.get("image_front_url")
    )
    img_line = (
        f"  image={'yes' if candidate.get('image_front_url') else 'no'} "
        f"score={payload.get('image_best_score', 0)} "
        f"role={image_front_role} quality={image_quality} "
        f"source={image_src} index={image_idx}"
    )
    if label_count:
        img_line += f" label_images={label_count}"
    if image_quality == "only_back_available":
        img_line += " warning=front_image_not_found"
    print(img_line)
    print(
        f"  ingredients={'yes' if ing else 'no'} "
        f"source={ing_source} quality={ing_quality} "
        f"len={len(ing)} preview={ing_preview!r}"
    )
    print(
        f"  nutrition={len(nutrition)} strategy={payload.get('nutrition_strategy')} "
        f"basis={payload.get('nutrition_basis')}"
    )
    print(f"  nutrition_json={{{nutri_preview}}}")
    if warnings:
        print(f"  nutrition_warnings={warnings}")
    print(f"  missing_fields={candidate.get('missing_fields')}")
    print(f"  quality_score={candidate.get('quality_score')}")
    print(f"  status={candidate.get('status')}")
    print(f"  source_url={candidate.get('source_url')}")


def write_log(run: "runner.ScrapeRun", real: bool, auto: dict | None = None) -> str:
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"web_scrape_{runner.utc_timestamp()}.json")
    report = {
        "mode": "real" if real else "dry-run",
        "candidates": run.candidates,
        "skipped": run.skipped,
        "errors": run.errors,
        "source_stats": run.source_stats,
    }
    if auto is not None:
        report["auto_approval"] = auto
    with open(path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    return path


def main() -> int:
    args = parse_args()
    real = bool(args.real) and not args.dry_run

    work_items, notices = build_work_items(args)
    for note in notices:
        print(note, file=sys.stderr)

    if not work_items:
        print(source_config.NO_SOURCES_MESSAGE)
        return 2

    print(
        f"Scraping {len(work_items)} source URL(s) — "
        f"mode={'REAL' if real else 'DRY-RUN'} limit={args.limit} delay={args.delay}s"
    )

    run = runner.run_scrape(
        work_items, limit=args.limit, delay=args.delay, timeout=args.timeout
    )

    # Apply min-quality gate before staging/printing as accepted.
    accepted = [c for c in run.candidates if c.get("quality_score", 0) >= args.min_quality]
    gated = len(run.candidates) - len(accepted)

    counts = {"inserted": 0, "updated": 0, "skipped": 0, "failed": 0}
    # Auto-approval is opt-in AND real-mode only (never writes in dry-run).
    auto_enabled = bool(args.auto_approve_high_quality) and real
    auto = {"attempted": 0, "approved": 0, "left_for_review": 0, "failed": 0}

    url = key = ""
    if real:
        url, key = common.load_supabase_env()

    for candidate in accepted:
        print_candidate(candidate)
        if not real:
            continue
        try:
            action, staging_row = runner.upsert_candidate(
                url, key, candidate, dry_run=False, force=args.force
            )
            counts[action] = counts.get(action, 0) + 1
        except Exception as exc:  # noqa: BLE001 - log and continue the batch
            counts["failed"] += 1
            run.errors.append({"url": candidate.get("source_url"), "error": str(exc)})
            print(f"  [error] staging failed: {exc}", file=sys.stderr)
            continue

        if not auto_enabled or staging_row is None:
            continue
        _maybe_auto_approve(
            url, key, staging_row, args.auto_approve_min_score, auto, run
        )

    log_path = write_log(run, real, auto if auto_enabled else None)

    print(
        f"\nDone. candidates={len(run.candidates)} accepted={len(accepted)} "
        f"gated_by_min_quality={gated} errors={len(run.errors)} "
        f"skipped_pages={len(run.skipped)}"
    )
    if real:
        print(
            f"Staging: inserted={counts['inserted']} updated={counts['updated']} "
            f"skipped={counts['skipped']} failed={counts['failed']}"
        )
        if auto_enabled:
            print(
                f"Auto-approval: attempted={auto['attempted']} "
                f"approved={auto['approved']} "
                f"left_for_review={auto['left_for_review']} failed={auto['failed']}"
            )
    else:
        print("Dry-run — nothing was written. Pass --real to stage candidates.")
    print(f"Run log: {log_path}")
    return 0


def _maybe_auto_approve(url, key, staging_row, min_score, auto, run) -> None:
    """Approve a staged row when eligible; tally + log the outcome."""
    reason = runner.auto_approve_block_reason(staging_row, min_score)
    if reason is not None:
        auto["left_for_review"] += 1
        run.skipped.append(
            {
                "url": staging_row.get("source_url"),
                "reason": "auto_approve_skipped",
                "detail": reason,
                "staging_id": staging_row.get("id"),
            }
        )
        return
    auto["attempted"] += 1
    action, error = runner.approve_staged_row(url, key, staging_row)
    if action == "failed":
        auto["failed"] += 1
        run.errors.append(
            {
                "url": staging_row.get("source_url"),
                "error": f"auto_approve_failed: {error}",
                "staging_id": staging_row.get("id"),
            }
        )
        print(f"  [warn] auto-approval failed: {error}", file=sys.stderr)
    else:
        auto["approved"] += 1
        print(f"  [auto-approved] {action} — {staging_row.get('name')}")


if __name__ == "__main__":
    raise SystemExit(main())
