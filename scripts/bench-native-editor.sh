#!/bin/bash
# bench-native-editor.sh — Run non-UI performance benchmarks for the native editor prototype.
#
# Usage:
#   ./scripts/bench-native-editor.sh
#
# Notes:
# - This runs XCTest perf tests only (no UI automation).
# - Results are written under bench-results/native-editor/<timestamp>/

set -euo pipefail
cd "$(dirname "$0")/.."

TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$(pwd)/bench-results/native-editor/$TS"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/kern-derived-data-bench}"

mkdir -p "$OUT_DIR"

echo "=== Kern Native Editor Benchmarks ==="
echo "Output: $OUT_DIR"
echo "DerivedData: $DERIVED_DATA_PATH"
echo ""

NEED_XCODEGEN=true
if [ -f "KernTextKit.xcodeproj/project.pbxproj" ] && [ "KernTextKit.xcodeproj/project.pbxproj" -nt "project.yml" ]; then
  NEED_XCODEGEN=false
fi

if [ "$NEED_XCODEGEN" = true ]; then
  echo "▸ Generating Xcode project (xcodegen)..."
  xcodegen 2>&1 | tail -1
else
  echo "▸ Skipping xcodegen (project up-to-date)."
fi

echo ""
echo "▸ Running performance tests (scheme: KernTextKit)..."

set +e
KERN_ENABLE_PERF_TESTS=1 xcodebuild \
  -project KernTextKit.xcodeproj \
  -scheme KernTextKit \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$OUT_DIR/KernTextKitPerf.xcresult" \
  test \
  -only-testing:KernTextKitTests/NativeMarkdownCodecPerformanceTests/testImportExportBenchmarkFilePerformance \
  -only-testing:KernTextKitTests/NativeEditorRenderPerformanceTests/testRenderBenchmarkFilePerformance \
  2>&1 | tee "$OUT_DIR/perf.log"
STATUS=${PIPESTATUS[0]}
set -e

if [ $STATUS -ne 0 ]; then
  echo "Perf tests failed (exit $STATUS). See: $OUT_DIR/perf.log" >&2
  exit $STATUS
fi

echo ""
echo "✓ Benchmarks completed"
echo "Result bundle: $OUT_DIR/KernTextKitPerf.xcresult"
