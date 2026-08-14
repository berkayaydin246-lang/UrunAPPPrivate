"""Thin subprocess bridge to the canonical Dart scoring lifecycle."""

from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse


@dataclass(frozen=True)
class ScoringLifecycleBridgeResult:
    succeeded: bool
    output: str = ""
    error: str | None = None


def run_product_scoring_lifecycle(
    product_id: str,
    trigger_source: str,
    *,
    timeout_seconds: int = 180,
) -> ScoringLifecycleBridgeResult:
    """Run canonical Dart scoring without exposing credentials in arguments."""
    environment = os.environ.copy()
    service_key = (
        environment.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
        or environment.get("SUPABASE_SERVICE_KEY", "").strip()
    )
    supabase_url = environment.get("SUPABASE_URL", "").strip()
    host = urlparse(supabase_url).hostname or ""
    suffix = ".supabase.co"
    if not service_key or not host.endswith(suffix):
        return ScoringLifecycleBridgeResult(
            succeeded=False,
            error="missing_scoring_lifecycle_environment",
        )
    project_ref = host[: -len(suffix)]
    environment["SUPABASE_SERVICE_ROLE_KEY"] = service_key
    root = Path(__file__).resolve().parents[2]
    command = [
        "dart",
        "run",
        "tool/product_scoring_lifecycle.dart",
        "--project-ref",
        project_ref,
        "--product-id",
        product_id,
        "--trigger-source",
        trigger_source,
        "--confirm-ingestion-scoring",
    ]
    try:
        completed = subprocess.run(
            command,
            cwd=root,
            env=environment,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return ScoringLifecycleBridgeResult(
            succeeded=False,
            error=type(error).__name__,
        )
    output = completed.stdout.strip()
    if completed.returncode != 0:
        error_line = completed.stderr.strip().splitlines()
        return ScoringLifecycleBridgeResult(
            succeeded=False,
            output=output,
            error=error_line[-1] if error_line else "lifecycle_process_failed",
        )
    return ScoringLifecycleBridgeResult(succeeded=True, output=output)


def print_scoring_lifecycle_result(
    product_id: str,
    result: ScoringLifecycleBridgeResult,
) -> None:
    status = "completed" if result.succeeded else "failed"
    print(f"  [scoring_{status}] product_id={product_id}")
    if result.output:
        for line in result.output.splitlines():
            print(f"    {line}")
    if result.error:
        print(f"    error={result.error}")
