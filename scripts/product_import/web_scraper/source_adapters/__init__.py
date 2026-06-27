"""Source-specific adapters for API-backed category discovery.

Adapters are opt-in via the YAML `adapter:` field on a source. Generic
href/script/embedded-JSON discovery is always tried first; an adapter only runs
as a fallback when generic discovery finds nothing. See base_adapter.py.
"""
from __future__ import annotations

from .base_adapter import SourceAdapter
from .migros_adapter import MigrosAdapter

# Registry keyed by adapter id (matches YAML `adapter:` / source id).
_ADAPTERS: dict[str, SourceAdapter] = {
    MigrosAdapter.source_id: MigrosAdapter(),
}

__all__ = ["SourceAdapter", "MigrosAdapter", "get_adapter", "available_adapters"]


def get_adapter(name: str | None) -> SourceAdapter | None:
    """Return the registered adapter for `name` (case-insensitive), or None."""
    if not name:
        return None
    return _ADAPTERS.get(name.strip().lower())


def available_adapters() -> list[str]:
    return sorted(_ADAPTERS.keys())
