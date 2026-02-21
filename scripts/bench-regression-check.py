#!/usr/bin/env python3
"""
bench-regression-check.py — Detect performance regressions between benchmark runs.

Uses Mann-Whitney U test (primary) and bootstrap CI for difference in medians (secondary).
Requires v3 JSON with raw run data for proper statistical tests. Falls back to threshold
comparison for v1/v2 with a warning.

Usage:
    python3 scripts/bench-regression-check.py --baseline baseline.json --latest latest.json
    python3 scripts/bench-regression-check.py --baseline baseline.json --latest latest.json --threshold 5

Supports v1, v2, and v3 JSON formats.
"""

import argparse
import json
import math
import random
import sys
from pathlib import Path


def load_report(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# R Type 7 percentile (matches Swift implementation)
# ---------------------------------------------------------------------------

def percentile_r7(sorted_vals: list[float], p: float) -> float:
    """R Type 7 linear interpolation percentile (same as numpy default)."""
    n = len(sorted_vals)
    if n == 0:
        return 0.0
    if n == 1:
        return sorted_vals[0]
    index = p * (n - 1)
    lower = int(math.floor(index))
    upper = int(math.ceil(index))
    if lower == upper:
        return sorted_vals[lower]
    frac = index - lower
    return sorted_vals[lower] * (1 - frac) + sorted_vals[upper] * frac


# ---------------------------------------------------------------------------
# Statistics (matching Swift: no outlier removal, full percentiles, bootstrap CI)
# ---------------------------------------------------------------------------

def compute_stats(values: list[float]) -> dict:
    """Compute stats matching the Swift Stats struct (no outlier removal)."""
    if not values:
        return {"n": 0, "median": 0, "mean": 0, "std": 0, "min": 0, "max": 0,
                "cv_pct": 0, "p25": 0, "p75": 0, "iqr": 0, "p95": 0, "p99": 0,
                "ci_lower": 0, "ci_upper": 0}

    s = sorted(values)
    n = len(s)
    mean = sum(s) / n
    variance = sum((x - mean) ** 2 for x in s) / max(n - 1, 1)
    std = math.sqrt(variance)
    cv = (std / mean * 100) if mean > 0 else 0

    p25 = percentile_r7(s, 0.25)
    p75 = percentile_r7(s, 0.75)
    ci_lo, ci_hi = bootstrap_median_ci(s, resamples=10_000, seed=42)

    return {
        "n": n,
        "min": round(min(s), 2),
        "max": round(max(s), 2),
        "median": round(percentile_r7(s, 0.5), 2),
        "mean": round(mean, 2),
        "std": round(std, 2),
        "cv_pct": round(cv, 1),
        "p25": round(p25, 2),
        "p75": round(p75, 2),
        "iqr": round(p75 - p25, 2),
        "p95": round(percentile_r7(s, 0.95), 2),
        "p99": round(percentile_r7(s, 0.99), 2),
        "ci_lower": round(ci_lo, 2),
        "ci_upper": round(ci_hi, 2),
    }


def bootstrap_median_ci(sorted_vals: list[float], resamples: int = 10_000, seed: int = 42) -> tuple[float, float]:
    """Bootstrap 95% CI for the median using percentile method."""
    if len(sorted_vals) < 2:
        val = sorted_vals[0] if sorted_vals else 0
        return (val, val)

    rng = random.Random(seed)
    n = len(sorted_vals)
    medians = []
    for _ in range(resamples):
        sample = sorted(rng.choices(sorted_vals, k=n))
        medians.append(percentile_r7(sample, 0.5))
    medians.sort()
    return (percentile_r7(medians, 0.025), percentile_r7(medians, 0.975))


# ---------------------------------------------------------------------------
# Mann-Whitney U test (stdlib implementation, normal approximation for n >= 20)
# ---------------------------------------------------------------------------

def mann_whitney_u(x: list[float], y: list[float]) -> tuple[float, float]:
    """
    Mann-Whitney U test. Returns (U statistic, two-sided p-value).
    Uses normal approximation with continuity correction for n >= 20.
    For small n, returns U and approximate p via normal approximation with a warning.
    """
    nx, ny = len(x), len(y)
    if nx == 0 or ny == 0:
        return (0.0, 1.0)

    # Rank all values together.
    combined = [(val, "x") for val in x] + [(val, "y") for val in y]
    combined.sort(key=lambda t: t[0])
    n = nx + ny

    # Assign ranks (handle ties by averaging).
    ranks = [0.0] * n
    i = 0
    while i < n:
        j = i
        while j < n and combined[j][0] == combined[i][0]:
            j += 1
        avg_rank = (i + j + 1) / 2.0  # 1-indexed average rank
        for k in range(i, j):
            ranks[k] = avg_rank
        i = j

    # Sum ranks for group x.
    r1 = sum(ranks[k] for k in range(n) if combined[k][1] == "x")
    u1 = r1 - nx * (nx + 1) / 2
    u2 = nx * ny - u1
    u = min(u1, u2)

    # Normal approximation.
    mu = nx * ny / 2
    # Tie correction.
    tie_counts = {}
    for r in ranks:
        tie_counts[r] = tie_counts.get(r, 0) + 1
    tie_correction = sum(t ** 3 - t for t in tie_counts.values()) / (12 * (n * (n - 1)))
    sigma = math.sqrt(nx * ny * ((n + 1) / 12 - tie_correction))

    if sigma == 0:
        return (u, 1.0)

    # Continuity correction.
    z = (abs(u1 - mu) - 0.5) / sigma
    # Two-sided p-value from standard normal.
    p = 2 * _norm_sf(z)
    return (u, p)


def _norm_sf(z: float) -> float:
    """Survival function (1 - CDF) for standard normal using error function approximation."""
    return 0.5 * math.erfc(z / math.sqrt(2))


def bootstrap_difference_ci(x: list[float], y: list[float], resamples: int = 10_000, seed: int = 42) -> tuple[float, float]:
    """Bootstrap 95% CI for the difference in medians (y - x)."""
    if not x or not y:
        return (0.0, 0.0)

    rng = random.Random(seed)
    diffs = []
    for _ in range(resamples):
        sx = sorted(rng.choices(x, k=len(x)))
        sy = sorted(rng.choices(y, k=len(y)))
        diffs.append(percentile_r7(sy, 0.5) - percentile_r7(sx, 0.5))
    diffs.sort()
    return (percentile_r7(diffs, 0.025), percentile_r7(diffs, 0.975))


# ---------------------------------------------------------------------------
# Metric extraction
# ---------------------------------------------------------------------------

TIMING_KEYS = ["window_visible", "first_paint", "render_stable"]
MEMORY_KEYS = ["memory_phys", "memory_rss"]


def extract_raw_runs(result: dict, metric_key: str) -> list[float]:
    """Extract raw run values for a given metric from v3 JSON."""
    runs = result.get("runs", [])
    ms_key = metric_key + "_ms" if metric_key in TIMING_KEYS else metric_key + "_mb"
    return [r[ms_key] for r in runs if ms_key in r and r[ms_key] is not None]


def extract_metrics(result: dict) -> dict[str, dict]:
    """Extract all metrics from a result entry, regardless of JSON version."""
    metrics = {}
    stats = result.get("stats", {})

    for key in TIMING_KEYS:
        if key in stats and stats[key] is not None:
            metrics[key] = stats[key]

    for key in MEMORY_KEYS:
        if key in stats and stats[key] is not None:
            metrics[key] = stats[key]

    # Phase 1 may have memory as simple values.
    if "memory_phys_mb" in stats and stats["memory_phys_mb"] is not None:
        metrics["memory_phys"] = {"median": stats["memory_phys_mb"], "std": 0}
    if "memory_rss_mb" in stats and stats["memory_rss_mb"] is not None:
        metrics["memory_rss"] = {"median": stats["memory_rss_mb"], "std": 0}

    return metrics


def check_regression_statistical(
    metric_name: str,
    baseline_runs: list[float],
    latest_runs: list[float],
    threshold_pct: float,
    min_abs_threshold_ms: float = 50.0,
) -> tuple[str, str, dict]:
    """
    Statistical regression check using Mann-Whitney U and bootstrap CI.

    Regression gate: p < 0.05 AND |median difference| > max(threshold%, min_abs_threshold_ms).

    Returns (status, message, details_dict).
    """
    b_sorted = sorted(baseline_runs)
    l_sorted = sorted(latest_runs)
    b_median = percentile_r7(b_sorted, 0.5)
    l_median = percentile_r7(l_sorted, 0.5)

    if b_median == 0:
        return "OK", f"{metric_name}: no baseline data", {}

    pct_change = ((l_median - b_median) / b_median) * 100
    effect_size_ms = l_median - b_median

    u_stat, p_value = mann_whitney_u(baseline_runs, latest_runs)
    ci_lo, ci_hi = bootstrap_difference_ci(baseline_runs, latest_runs)

    details = {
        "mann_whitney_u": round(u_stat, 2),
        "mann_whitney_p": round(p_value, 6),
        "bootstrap_ci_lower": round(ci_lo, 2),
        "bootstrap_ci_upper": round(ci_hi, 2),
        "effect_size_ms": round(effect_size_ms, 2),
        "baseline_median": round(b_median, 2),
        "latest_median": round(l_median, 2),
        "pct_change": round(pct_change, 1),
    }

    abs_threshold = max(b_median * threshold_pct / 100, min_abs_threshold_ms)

    if p_value < 0.05 and effect_size_ms > abs_threshold:
        return "REGRESSION", (
            f"{metric_name}: {b_median:.1f} -> {l_median:.1f} "
            f"(+{pct_change:.1f}%, p={p_value:.4f}, "
            f"delta={effect_size_ms:.1f}ms, CI=[{ci_lo:.1f}, {ci_hi:.1f}])"
        ), details

    if p_value < 0.05 and effect_size_ms < -abs_threshold:
        return "IMPROVEMENT", (
            f"{metric_name}: {b_median:.1f} -> {l_median:.1f} "
            f"({pct_change:.1f}%, p={p_value:.4f})"
        ), details

    return "OK", (
        f"{metric_name}: {b_median:.1f} -> {l_median:.1f} "
        f"({pct_change:+.1f}%, p={p_value:.4f})"
    ), details


def check_regression_threshold(
    metric_name: str,
    baseline: dict,
    latest: dict,
    threshold_pct: float,
) -> tuple[str, str, dict]:
    """
    Legacy threshold-based regression check for v1/v2 without raw run data.
    """
    b_median = baseline.get("median", 0)
    l_median = latest.get("median", 0)
    b_std = baseline.get("std", 0)

    if b_median == 0:
        return "OK", f"{metric_name}: no baseline data", {}

    pct_change = ((l_median - b_median) / b_median) * 100

    details = {
        "baseline_median": round(b_median, 2),
        "latest_median": round(l_median, 2),
        "pct_change": round(pct_change, 1),
    }

    if pct_change > threshold_pct and (l_median - b_median) > 2 * b_std:
        return "REGRESSION", (
            f"{metric_name}: {b_median:.1f} -> {l_median:.1f} "
            f"(+{pct_change:.1f}%, >{threshold_pct}% threshold, "
            f"delta={l_median - b_median:.1f} > 2*std={2 * b_std:.1f}) "
            f"[legacy threshold check — provide v3 JSON for Mann-Whitney U test]"
        ), details

    if pct_change < -threshold_pct:
        return "IMPROVEMENT", (
            f"{metric_name}: {b_median:.1f} -> {l_median:.1f} ({pct_change:.1f}%)"
        ), details

    return "OK", (
        f"{metric_name}: {b_median:.1f} -> {l_median:.1f} ({pct_change:+.1f}%)"
    ), details


def print_ascii_comparison(editor: str, baseline_metrics: dict, latest_metrics: dict):
    """Print a simple ASCII bar comparison."""
    for key in TIMING_KEYS:
        if key in baseline_metrics and key in latest_metrics:
            b = baseline_metrics[key].get("median", 0)
            l = latest_metrics[key].get("median", 0)
            max_val = max(b, l, 1)
            b_bar = int(b / max_val * 40)
            l_bar = int(l / max_val * 40)
            label = key.replace("_", " ").title()
            print(f"  {label}:")
            print(f"    baseline: {'█' * b_bar} {b:.0f}ms")
            print(f"    latest:   {'█' * l_bar} {l:.0f}ms")


def check_environment_compat(baseline: dict, latest: dict):
    """Warn if environment differs between baseline and latest."""
    b_env = baseline.get("environment", {})
    l_env = latest.get("environment", {})

    warnings = []
    if b_env.get("chip") != l_env.get("chip"):
        warnings.append(f"  Hardware mismatch: {b_env.get('chip')} vs {l_env.get('chip')}")
    if b_env.get("power") != l_env.get("power"):
        warnings.append(f"  Power source differs: {b_env.get('power')} vs {l_env.get('power')}")
    b_thermal = b_env.get("thermal_pct", 100)
    l_thermal = l_env.get("thermal_pct", 100)
    if b_thermal < 100 or l_thermal < 100:
        warnings.append(f"  Thermal throttling: baseline={b_thermal}%, latest={l_thermal}%")

    if warnings:
        print("WARNING: Environment differences detected:")
        for w in warnings:
            print(w)
        print()


def main():
    parser = argparse.ArgumentParser(description="Check for benchmark regressions (v3: Mann-Whitney U)")
    parser.add_argument("--baseline", required=True, help="Path to baseline JSON")
    parser.add_argument("--latest", required=True, help="Path to latest JSON")
    parser.add_argument(
        "--threshold",
        type=float,
        default=5.0,
        help="Regression threshold percentage (default: 5)",
    )
    parser.add_argument(
        "--min-abs-ms",
        type=float,
        default=50.0,
        help="Minimum absolute difference in ms to flag (default: 50)",
    )
    parser.add_argument("--json", help="Output results as JSON to this path")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show all metrics")
    args = parser.parse_args()

    if not Path(args.baseline).exists():
        print(f"Error: Baseline file not found: {args.baseline}", file=sys.stderr)
        sys.exit(1)
    if not Path(args.latest).exists():
        print(f"Error: Latest file not found: {args.latest}", file=sys.stderr)
        sys.exit(1)

    baseline = load_report(args.baseline)
    latest = load_report(args.latest)

    b_version = baseline.get("version", 1)
    l_version = latest.get("version", 1)

    print(f"Baseline: {args.baseline} (v{b_version})")
    print(f"Latest:   {args.latest} (v{l_version})")
    print(f"Threshold: {args.threshold}% / {args.min_abs_ms}ms minimum")

    use_statistical = b_version >= 3 and l_version >= 3
    if not use_statistical:
        print(f"WARNING: v{b_version}/v{l_version} JSON lacks raw run data. "
              f"Using legacy threshold check. Provide v3 JSON for Mann-Whitney U test.")
    print()

    # Environment compatibility check.
    check_environment_compat(baseline, latest)

    # Index results by editor name.
    baseline_by_editor = {r["editor"]: r for r in baseline.get("results", [])}
    latest_by_editor = {r["editor"]: r for r in latest.get("results", [])}

    regressions = []
    improvements = []
    stable = []
    json_results = []

    # Check common editors.
    for editor_name in sorted(set(baseline_by_editor) & set(latest_by_editor)):
        b_result = baseline_by_editor[editor_name]
        l_result = latest_by_editor[editor_name]

        b_metrics = extract_metrics(b_result)
        l_metrics = extract_metrics(l_result)

        print(f"--- {editor_name} ---")

        if args.verbose:
            print_ascii_comparison(editor_name, b_metrics, l_metrics)

        for metric_name in sorted(set(b_metrics) & set(l_metrics)):
            if use_statistical:
                # Extract raw runs for statistical test.
                b_runs = extract_raw_runs(b_result, metric_name)
                l_runs = extract_raw_runs(l_result, metric_name)

                if b_runs and l_runs:
                    status, message, details = check_regression_statistical(
                        metric_name, b_runs, l_runs, args.threshold, args.min_abs_ms
                    )
                else:
                    # Fall back to threshold if raw runs not available for this metric.
                    status, message, details = check_regression_threshold(
                        metric_name, b_metrics[metric_name], l_metrics[metric_name], args.threshold
                    )
            else:
                status, message, details = check_regression_threshold(
                    metric_name, b_metrics[metric_name], l_metrics[metric_name], args.threshold
                )

            if status == "REGRESSION":
                regressions.append((editor_name, message))
                print(f"  *** REGRESSION *** {message}")
            elif status == "IMPROVEMENT":
                improvements.append((editor_name, message))
                print(f"  IMPROVED {message}")
            else:
                stable.append((editor_name, message))
                if args.verbose:
                    print(f"  OK {message}")

            json_result = {
                "editor": editor_name,
                "metric": metric_name,
                "status": status.lower(),
            }
            json_result.update(details)
            json_results.append(json_result)

        print()

    # Check editors only in latest (new editors).
    for editor_name in sorted(set(latest_by_editor) - set(baseline_by_editor)):
        print(f"NEW: {editor_name} (no baseline for comparison)")
        print()

    # Summary.
    print("=== Summary ===")
    print(f"  Regressions:  {len(regressions)}")
    print(f"  Improvements: {len(improvements)}")
    print(f"  Stable:       {len(stable)}")
    print()

    if regressions:
        print("REGRESSIONS DETECTED:")
        for editor, msg in regressions:
            print(f"  [{editor}] {msg}")
        print()

    if improvements:
        print("Improvements:")
        for editor, msg in improvements:
            print(f"  [{editor}] {msg}")
        print()

    # JSON output.
    if args.json:
        output = {
            "baseline": args.baseline,
            "latest": args.latest,
            "baseline_version": b_version,
            "latest_version": l_version,
            "threshold_pct": args.threshold,
            "min_abs_ms": args.min_abs_ms,
            "statistical_test": "mann_whitney_u" if use_statistical else "legacy_threshold",
            "regressions": len(regressions),
            "improvements": len(improvements),
            "stable": len(stable),
            "results": json_results,
        }
        with open(args.json, "w") as f:
            json.dump(output, f, indent=2)
        print(f"JSON results written to: {args.json}")

    # Exit code: 1 if any regressions found.
    sys.exit(1 if regressions else 0)


if __name__ == "__main__":
    main()
