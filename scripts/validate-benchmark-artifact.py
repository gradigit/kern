#!/usr/bin/env python3
"""Validate kern-bench JSON artifacts before treating a run as usable evidence.

This is intentionally stricter than merely parsing JSON. A successful benchmark
process can still emit a partial/diagnostic report when required metrics are
missing, a roster is not claim-safe, or the run degraded. The wrapper uses this
script for artifact-packet runs so missing/stale/fallback-like evidence fails
loudly instead of being mistaken for a clean baseline.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate kern-bench JSON artifacts")
    parser.add_argument("--results", required=True, help="Path to kern-bench JSON report")
    parser.add_argument(
        "--allow-partial",
        action="store_true",
        help="Allow partial/degraded reports; still require parseable JSON and metric schema",
    )
    return parser.parse_args()


def fail(message: str) -> None:
    print(f"[FAIL] {message}", file=sys.stderr)
    sys.exit(1)


def metric_to_stats_key(metric: str) -> str:
    key = metric
    for suffix in ("_ms", "_mb", "_pct"):
        if key.endswith(suffix):
            key = key[: -len(suffix)]
            break
    return key


def load_payload(path: Path) -> dict[str, Any]:
    if not path.exists():
        fail(f"benchmark JSON artifact not found: {path}")
    if path.stat().st_size == 0:
        fail(f"benchmark JSON artifact is empty: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"unable to parse benchmark JSON artifact: {exc}")
    if not isinstance(payload, dict):
        fail("benchmark JSON root must be an object")
    return payload


def require_string(payload: dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        fail(f"benchmark JSON missing non-empty '{key}'")
    return value


def require_int(payload: dict[str, Any], key: str, *, minimum: int | None = None) -> int:
    value = payload.get(key)
    if not isinstance(value, int):
        fail(f"benchmark JSON missing integer '{key}'")
    if minimum is not None and value < minimum:
        fail(f"benchmark JSON '{key}' is below minimum {minimum}: {value}")
    return value


def validate_metric_stats(editor: str, stats: dict[str, Any], metric: str) -> None:
    stats_key = metric_to_stats_key(metric)
    metric_stats = stats.get(stats_key)
    if not isinstance(metric_stats, dict):
        available = ", ".join(sorted(stats.keys())) or "<none>"
        fail(f"{editor}: required metric '{metric}' missing in stats as '{stats_key}'. available: {available}")

    n = metric_stats.get("n")
    if not isinstance(n, int) or n <= 0:
        fail(f"{editor}:{stats_key} has invalid sample count: {n!r}")

    median = metric_stats.get("median")
    p95 = metric_stats.get("p95")
    if not isinstance(median, (int, float)) or median <= 0:
        fail(f"{editor}:{stats_key} has invalid median: {median!r}")
    if not isinstance(p95, (int, float)) or p95 <= 0:
        fail(f"{editor}:{stats_key} has invalid p95: {p95!r}")


def validate_payload(payload: dict[str, Any], *, allow_partial: bool) -> None:
    require_int(payload, "version", minimum=4)
    tool = require_string(payload, "tool")
    if tool != "kern-bench":
        fail(f"unexpected benchmark tool: {tool}")

    require_string(payload, "timestamp")
    require_string(payload, "suite")
    require_string(payload, "suite_kind")

    classification = require_string(payload, "run_classification")
    quality = require_string(payload, "run_quality")
    partial_reasons = payload.get("partial_reasons", [])
    if not isinstance(partial_reasons, list):
        fail("partial_reasons must be an array")
    if not allow_partial and (classification != "official" or quality != "complete" or partial_reasons):
        fail(
            "benchmark report is not official/complete: "
            f"classification={classification}, quality={quality}, partial_reasons={partial_reasons}"
        )

    config = payload.get("config")
    if not isinstance(config, dict):
        fail("benchmark JSON missing config object")
    if not isinstance(config.get("file_hash"), str) or not config["file_hash"]:
        fail("config.file_hash is missing; refusing stale/fallback-prone artifact")
    if not isinstance(config.get("file_bytes"), int) or config["file_bytes"] <= 0:
        fail("config.file_bytes must be a positive integer")

    required_metrics = config.get("required_metrics")
    if not isinstance(required_metrics, list) or not all(isinstance(m, str) for m in required_metrics):
        fail("config.required_metrics must be an array of strings")
    if not required_metrics:
        fail("config.required_metrics is empty")

    results = payload.get("results")
    if not isinstance(results, list) or not results:
        fail("benchmark JSON missing non-empty results array")

    for result in results:
        if not isinstance(result, dict):
            fail("each results entry must be an object")
        editor = result.get("editor")
        if not isinstance(editor, str) or not editor:
            fail("editor result missing editor name")
        result_classification = result.get("run_classification")
        result_quality = result.get("run_quality")
        result_partial_reasons = result.get("partial_reasons", [])
        if not isinstance(result_partial_reasons, list):
            fail(f"{editor}: partial_reasons must be an array")
        if not allow_partial and (
            result_classification != "official"
            or result_quality != "complete"
            or result_partial_reasons
        ):
            fail(
                f"{editor}: result is not official/complete: "
                f"classification={result_classification}, quality={result_quality}, "
                f"partial_reasons={result_partial_reasons}"
            )

        runs = result.get("runs")
        if not isinstance(runs, list) or not runs:
            fail(f"{editor}: missing non-empty runs array")
        stats = result.get("stats")
        if not isinstance(stats, dict):
            fail(f"{editor}: missing stats object")

        for metric in required_metrics:
            validate_metric_stats(editor, stats, metric)


def main() -> None:
    args = parse_args()
    payload = load_payload(Path(args.results))
    validate_payload(payload, allow_partial=args.allow_partial)
    print("[PASS] benchmark artifact is valid")


if __name__ == "__main__":
    main()
