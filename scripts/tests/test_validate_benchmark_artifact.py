import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "validate-benchmark-artifact.py"


def make_payload(*, classification: str = "official", include_metric: bool = True) -> dict:
    partial_reasons = [] if classification == "official" else ["required_metric_missing:open_latency_ms"]
    quality = "complete" if classification == "official" else "degraded"
    stats = {}
    if include_metric:
        stats["open_latency"] = {
            "n": 3,
            "median": 100.0,
            "mean": 101.0,
            "std": 1.0,
            "min": 99.0,
            "max": 103.0,
            "cv_pct": 1.0,
            "p25": 99.0,
            "p75": 103.0,
            "iqr": 4.0,
            "p95": 103.0,
            "p99": 103.0,
            "failure_rate_pct": 0.0,
            "failures": 0,
            "timeouts": 0,
        }
    return {
        "version": 4,
        "tool": "kern-bench",
        "timestamp": "2026-06-24T00:00:00Z",
        "suite": "benchmark_open_ready",
        "suite_kind": "cross_editor_open_only",
        "run_classification": classification,
        "run_quality": quality,
        "partial_reasons": partial_reasons,
        "environment": {},
        "preflight": {},
        "config": {
            "file": "test-fixtures/native-editor-benchmark.md",
            "file_bytes": 1024,
            "file_hash": "abc123",
            "required_metrics": ["open_latency_ms"],
        },
        "results": [
            {
                "editor": "Kern",
                "run_classification": classification,
                "run_quality": quality,
                "partial_reasons": partial_reasons,
                "runs": [{"run_index": 1, "open_latency_ms": 100.0}],
                "stats": stats,
            }
        ],
    }


class ValidateBenchmarkArtifactTests(unittest.TestCase):
    def run_validator(self, path: Path, *extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(SCRIPT), "--results", str(path), *extra],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_accepts_official_complete_artifact(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "results.json"
            path.write_text(json.dumps(make_payload()), encoding="utf-8")

            proc = self.run_validator(path)

            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("[PASS]", proc.stdout)

    def test_rejects_partial_artifact_by_default(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "results.json"
            path.write_text(json.dumps(make_payload(classification="partial")), encoding="utf-8")

            proc = self.run_validator(path)

            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("not official/complete", proc.stderr)

    def test_allows_partial_artifact_when_explicit(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "results.json"
            path.write_text(json.dumps(make_payload(classification="partial")), encoding="utf-8")

            proc = self.run_validator(path, "--allow-partial")

            self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_rejects_missing_required_metric_stats(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "results.json"
            path.write_text(json.dumps(make_payload(include_metric=False)), encoding="utf-8")

            proc = self.run_validator(path)

            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("required metric", proc.stderr)

    def test_rejects_missing_file_hash(self):
        payload = make_payload()
        payload["config"]["file_hash"] = ""
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "results.json"
            path.write_text(json.dumps(payload), encoding="utf-8")

            proc = self.run_validator(path)

            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("file_hash", proc.stderr)


if __name__ == "__main__":
    unittest.main()
