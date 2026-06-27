"""Validation checks for risk_ingredient_library_seed.json."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SEED_FILE = ROOT / "risk_ingredient_library_seed.json"

VALID_CONSUMER_SECTIONS = {
    "dikkat_edilecek_icerikler",
    "katki_ve_koruyucular",
    "seker_tatlandirici_sinyalleri",
    "yag_islenmislik_sinyalleri",
    "uyarici_icerikler",
    "olumlu_sinyaller",
}

VALID_RISK_LEVELS = {"low", "medium", "high", "unknown"}


def normalize_alias(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"\s+", " ", value)
    return value


def main() -> int:
    if not SEED_FILE.exists():
        print(f"ERROR: Seed file not found: {SEED_FILE}")
        return 1

    data = json.loads(SEED_FILE.read_text(encoding="utf-8"))
    errors: list[str] = []

    seen_canonical: set[str] = set()

    for idx, item in enumerate(data, start=1):
        name = str(item.get("canonical_name", "")).strip()
        if not name:
            errors.append(f"[{idx}] canonical_name missing")
            continue

        key = normalize_alias(name)
        if key in seen_canonical:
            errors.append(f"[{idx}] duplicate canonical_name: {name}")
        seen_canonical.add(key)

        section = item.get("consumer_section")
        if section not in VALID_CONSUMER_SECTIONS:
            errors.append(f"[{idx}] invalid consumer_section for {name}: {section}")

        risk_level = item.get("risk_level")
        if risk_level not in VALID_RISK_LEVELS:
            errors.append(f"[{idx}] invalid risk_level for {name}: {risk_level}")

        aliases = item.get("aliases") or []
        if not isinstance(aliases, list):
            errors.append(f"[{idx}] aliases must be list for {name}")
            aliases = []

        normalized = [normalize_alias(str(a)) for a in aliases if str(a).strip()]
        if len(normalized) != len(set(normalized)):
            errors.append(f"[{idx}] duplicate aliases for {name}")

    print(f"Entries: {len(data)}")
    if errors:
        print(f"Validation failed with {len(errors)} issue(s):")
        for err in errors[:100]:
            print(f"- {err}")
        if len(errors) > 100:
            print(f"... and {len(errors) - 100} more")
        return 1

    print("Validation OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
