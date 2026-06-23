import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "cross-editor-benchmark.sh"


def write_fake_kern_bench(path: Path, *, partial: bool = False) -> None:
    classification = "partial" if partial else "official"
    quality = "degraded" if partial else "complete"
    partial_reasons = ["required_metric_missing:open_latency_ms"] if partial else []
    source = f"""#!/usr/bin/env python3
import json
import sys
from pathlib import Path

args = sys.argv[1:]
json_path = None
markdown_path = None
for idx, arg in enumerate(args):
    if arg == "--json":
        json_path = Path(args[idx + 1])
    elif arg == "--markdown":
        markdown_path = Path(args[idx + 1])

payload = {{
    "version": 4,
    "tool": "kern-bench",
    "timestamp": "2026-06-24T00:00:00Z",
    "suite": "benchmark_open_ready",
    "suite_kind": "cross_editor_open_only",
    "run_classification": {classification!r},
    "run_quality": {quality!r},
    "partial_reasons": {partial_reasons!r},
    "environment": {{}},
    "preflight": {{}},
    "config": {{
        "file": "test-fixtures/native-editor-benchmark.md",
        "file_bytes": 1024,
        "file_hash": "abc123",
        "required_metrics": ["open_latency_ms"]
    }},
    "results": [
        {{
            "editor": "TextKit Baseline",
            "run_classification": {classification!r},
            "run_quality": {quality!r},
            "partial_reasons": {partial_reasons!r},
            "runs": [{{"run_index": 1, "open_latency_ms": 100.0}}],
            "stats": {{
                "open_latency": {{
                    "n": 1,
                    "median": 100.0,
                    "mean": 100.0,
                    "std": 0.0,
                    "min": 100.0,
                    "max": 100.0,
                    "cv_pct": 0.0,
                    "p25": 100.0,
                    "p75": 100.0,
                    "iqr": 0.0,
                    "p95": 100.0,
                    "p99": 100.0,
                    "failure_rate_pct": 0.0,
                    "failures": 0,
                    "timeouts": 0
                }}
            }}
        }}
    ]
}}
if json_path:
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(payload), encoding="utf-8")
if markdown_path:
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    markdown_path.write_text("# Fake summary\\n", encoding="utf-8")
print("fake kern-bench invoked")
"""
    path.write_text(source, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class CrossEditorBenchmarkWrapperTests(unittest.TestCase):
    def run_wrapper(self, fake_bin: Path, *args: str) -> subprocess.CompletedProcess[str]:
        env = dict(os.environ)
        env["KERN_BENCH_BIN"] = str(fake_bin)
        env.setdefault("LC_ALL", "C")
        return subprocess.run(
            [str(SCRIPT), *args],
            cwd=REPO_ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_preflight_artifact_dir_writes_packet_metadata_without_launching_editors(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            fake = root / "fake-kern-bench"
            artifact_dir = root / "packet"
            write_fake_kern_bench(fake)

            proc = self.run_wrapper(
                fake,
                "--suite",
                "benchmark_open_ready",
                "--editors",
                "TextKit Baseline",
                "--artifact-dir",
                str(artifact_dir),
                "--preflight-only",
            )

            self.assertEqual(proc.returncode, 0, proc.stderr)
            preflight = json.loads((artifact_dir / "preflight.json").read_text(encoding="utf-8"))
            self.assertEqual(preflight["suite"], "benchmark_open_ready")
            self.assertEqual(preflight["selected_editors"], "TextKit Baseline")
            self.assertTrue(preflight["strict_artifacts"])
            self.assertTrue((artifact_dir / "command.txt").exists())
            self.assertTrue((artifact_dir / "process-snapshot-before.txt").exists())
            self.assertTrue((artifact_dir / "raw.log").exists())

    def test_artifact_dir_validates_official_fake_results(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            fake = root / "fake-kern-bench"
            artifact_dir = root / "packet"
            write_fake_kern_bench(fake)

            proc = self.run_wrapper(
                fake,
                "--suite",
                "benchmark_open_ready",
                "--editors",
                "TextKit Baseline",
                "--artifact-dir",
                str(artifact_dir),
            )

            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertTrue((artifact_dir / "metrics-summary.json").exists())
            self.assertTrue((artifact_dir / "summary.md").exists())
            self.assertTrue((artifact_dir / "process-snapshot-after.txt").exists())
            self.assertIn("[PASS] benchmark artifact is valid", proc.stdout)

    def test_artifact_dir_rejects_partial_fake_results_by_default(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            fake = root / "fake-kern-bench"
            artifact_dir = root / "packet"
            write_fake_kern_bench(fake, partial=True)

            proc = self.run_wrapper(
                fake,
                "--suite",
                "benchmark_open_ready",
                "--editors",
                "TextKit Baseline",
                "--artifact-dir",
                str(artifact_dir),
            )

            self.assertNotEqual(proc.returncode, 0)
            combined = proc.stdout + proc.stderr
            self.assertIn("Benchmark artifact validation failed", combined)
            self.assertIn("not official/complete", combined)

    def test_allow_partial_artifacts_keeps_diagnostic_packet_non_fatal(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            fake = root / "fake-kern-bench"
            artifact_dir = root / "packet"
            write_fake_kern_bench(fake, partial=True)

            proc = self.run_wrapper(
                fake,
                "--suite",
                "benchmark_open_ready",
                "--editors",
                "TextKit Baseline",
                "--artifact-dir",
                str(artifact_dir),
                "--allow-partial-artifacts",
            )

            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertIn("[PASS] benchmark artifact is valid", proc.stdout)


if __name__ == "__main__":
    unittest.main()
