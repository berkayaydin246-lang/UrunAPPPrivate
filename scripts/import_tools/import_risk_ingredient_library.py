"""Import the packaged-food risk ingredient library into Supabase.

- Idempotent upserts
- Matches by canonical_name, aliases, and e_codes
- Supports the extended explanation columns used by the app
- Dry-run mode by default
"""

from __future__ import annotations

import argparse
import json
import os
import re
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from supabase import Client, create_client

load_dotenv()

ROOT = Path(__file__).resolve().parent
DEFAULT_SEED_FILE = ROOT / "risk_ingredient_library_seed.json"


def normalize_name(value: str) -> str:
    value = value.strip().lower()
    value = value.replace("İ", "i").replace("I", "ı")
    value = re.sub(r"\s+", " ", value)
    return value


def normalize_aliases(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for value in values:
        text = normalize_name(value)
        if not text or text in seen:
            continue
        seen.add(text)
        out.append(text)
    return out


@dataclass
class Stats:
    created: int = 0
    updated: int = 0
    skipped: int = 0
    errors: list[str] = field(default_factory=list)


class RiskIngredientLibraryImporter:
    def __init__(self, dry_run: bool = True):
        self.dry_run = dry_run
        self.stats = Stats()
        self.supabase: Client | None = None
        self.cache_by_name: dict[str, dict[str, Any]] = {}
        self.cache_by_e_code: dict[str, dict[str, Any]] = {}
        self.cache_by_alias: dict[str, dict[str, Any]] = {}

        if not dry_run:
            supabase_url = os.getenv("SUPABASE_URL")
            supabase_key = os.getenv("SUPABASE_ANON_KEY")
            if not supabase_url or not supabase_key:
                raise ValueError("SUPABASE_URL and SUPABASE_ANON_KEY must be set in .env")
            self.supabase = create_client(supabase_url, supabase_key)
            print("✓ Connected to Supabase")
        else:
            print("🔍 DRY-RUN MODE - No actual changes will be made")

    def load_cache(self) -> None:
        if self.dry_run or self.supabase is None:
            return
        response = self.supabase.table("ingredients").select(
            "id, name, normalized_name, aliases, e_code, ingredient_type, short_purpose, short_risk_summary, caution_groups, processing_role, risk_level"
        ).execute()
        for row in response.data:
            normalized = normalize_name(row.get("normalized_name") or row.get("name") or "")
            if normalized:
                self.cache_by_name[normalized] = row
            e_code = (row.get("e_code") or "").strip().upper()
            if e_code:
                self.cache_by_e_code[e_code] = row
            for alias in row.get("aliases") or []:
                alias_norm = normalize_name(alias)
                if alias_norm:
                    self.cache_by_alias[alias_norm] = row
        print(f"✓ Cached {len(response.data)} ingredients")

    def find_match(self, seed_item: dict[str, Any]) -> dict[str, Any] | None:
        canonical = normalize_name(seed_item["canonical_name"])
        if canonical in self.cache_by_name:
            return self.cache_by_name[canonical]

        for code in seed_item.get("e_codes") or []:
            code_norm = code.strip().upper()
            if code_norm in self.cache_by_e_code:
                return self.cache_by_e_code[code_norm]

        for alias in seed_item.get("aliases") or []:
            alias_norm = normalize_name(alias)
            if alias_norm in self.cache_by_name:
                return self.cache_by_name[alias_norm]
            if alias_norm in self.cache_by_alias:
                return self.cache_by_alias[alias_norm]

        return None

    def build_payload(self, seed_item: dict[str, Any]) -> dict[str, Any]:
        aliases = normalize_aliases([str(v) for v in seed_item.get("aliases") or []])
        e_codes = [str(v).strip().upper() for v in seed_item.get("e_codes") or [] if str(v).strip()]
        primary_e_code = e_codes[0] if e_codes else None

        payload: dict[str, Any] = {
            "name": seed_item["canonical_name"].strip(),
            "normalized_name": normalize_name(seed_item["canonical_name"]),
            "aliases": aliases or None,
            "e_code": primary_e_code,
            "category": seed_item.get("consumer_section"),
            "risk_level": seed_item.get("risk_level", "unknown"),
            "ingredient_type": seed_item.get("ingredient_type"),
            "short_purpose": seed_item.get("short_purpose"),
            "short_risk_summary": seed_item.get("short_risk_summary"),
            "caution_groups": seed_item.get("caution_groups") or None,
            "processing_role": seed_item.get("consumer_section"),
            "short_description": seed_item.get("ingredient_type"),
            "long_description": " ".join(
                part.strip()
                for part in [
                    seed_item.get("short_purpose", ""),
                    seed_item.get("short_risk_summary", ""),
                ]
                if part and part.strip()
            ) or None,
            "source_url": None,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "created_at": datetime.now(timezone.utc).isoformat(),
        }

        # Optional extended fields used by the library.
        for key in ["consumer_section", "risk_tags", "category_tags", "priority_score"]:
            if key in seed_item:
                payload[key] = seed_item[key]

        # Preserve additional e-codes as aliases for matching if the table only has a single e_code column.
        if len(e_codes) > 1:
            extra_aliases = aliases + e_codes[1:]
            payload["aliases"] = normalize_aliases(extra_aliases) or None

        return payload

    def upsert_one(self, seed_item: dict[str, Any]) -> None:
        if not seed_item.get("canonical_name"):
            self.stats.skipped += 1
            return

        payload = self.build_payload(seed_item)
        match = self.find_match(seed_item)

        if self.dry_run:
            action = "update" if match else "create"
            print(f"[DRY-RUN] Would {action}: {payload['name']}")
            if match:
                self.stats.updated += 1
            else:
                self.stats.created += 1
            return

        assert self.supabase is not None
        try:
            if match:
                self.supabase.table("ingredients").update(payload).eq("id", match["id"]).execute()
                self.stats.updated += 1
            else:
                self.supabase.table("ingredients").insert(payload).execute()
                self.stats.created += 1
        except Exception as exc:
            message = f"{payload['name']}: {exc}"
            self.stats.errors.append(message)
            self.stats.skipped += 1
            print(f"✗ {message}")

    def import_file(self, seed_file: Path) -> None:
        items = json.loads(seed_file.read_text(encoding="utf-8"))
        print(f"Loaded {len(items)} library entries from {seed_file.name}")
        if not self.dry_run:
            self.load_cache()

        for idx, item in enumerate(items, start=1):
            print(f"[{idx}/{len(items)}] {item.get('canonical_name', 'UNKNOWN')}", end=" ")
            self.upsert_one(item)
            print()
            if not self.dry_run and idx % 25 == 0:
                time.sleep(0.2)

        print("\nImport complete")
        print(f"Created: {self.stats.created}")
        print(f"Updated: {self.stats.updated}")
        print(f"Skipped: {self.stats.skipped}")
        print(f"Errors: {len(self.stats.errors)}")
        if self.stats.errors:
            print("\nErrors:")
            for err in self.stats.errors[:20]:
                print(f"- {err}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Import the risk ingredient library into Supabase")
    parser.add_argument("--real", action="store_true", help="Write changes to Supabase")
    parser.add_argument("--file", default=str(DEFAULT_SEED_FILE), help="Seed file path")
    args = parser.parse_args()

    importer = RiskIngredientLibraryImporter(dry_run=not args.real)
    importer.import_file(Path(args.file))


if __name__ == "__main__":
    main()
