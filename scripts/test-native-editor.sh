#!/bin/bash
# test-native-editor.sh — Run native-editor unit + UI tests and collect artifacts.
#
# Usage:
#   ./scripts/test-native-editor.sh [--unit-only] [--ui-only] [--skip-xcodegen] [--export-ui-attachments] [--exhaustive] [--snapshots] [--record-snapshots]
#
# Notes:
# - UI tests require the Mac to be unlocked and Xcode to have the necessary Automation permissions.
# - Results are written under test-results/native-editor/<timestamp>/

set -euo pipefail
cd "$(dirname "$0")/.."

RUN_UNIT=true
RUN_UI=true
SKIP_XCODEGEN=false
EXPORT_UI_ATTACHMENTS=false
ENABLE_EXHAUSTIVE=false
ENABLE_SNAPSHOTS=false
RECORD_SNAPSHOTS=false

for arg in "$@"; do
  case "$arg" in
    --unit-only) RUN_UI=false ;;
    --ui-only) RUN_UNIT=false ;;
    --skip-xcodegen) SKIP_XCODEGEN=true ;;
    --export-ui-attachments) EXPORT_UI_ATTACHMENTS=true ;;
    --exhaustive) ENABLE_EXHAUSTIVE=true ;;
    --snapshots) ENABLE_SNAPSHOTS=true ;;
    --record-snapshots) ENABLE_SNAPSHOTS=true; RECORD_SNAPSHOTS=true ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$(pwd)/test-results/native-editor/$TS"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/kern-derived-data-tests}"

mkdir -p "$OUT_DIR"

echo "=== Kern Native Editor Tests ==="
echo "Output: $OUT_DIR"
echo "DerivedData: $DERIVED_DATA_PATH"
echo ""
echo "Env toggles (optional):"
echo "  KERN_ENABLE_SNAPSHOT_TESTS=1   Run snapshot tests (otherwise skipped)"
echo "  KERN_RECORD_SNAPSHOTS=1        Record snapshot baselines (with snapshots enabled)"
echo "  KERN_ENABLE_EXHAUSTIVE_TESTS=1 Run exhaustive spec placeholders (otherwise skipped)"
echo "  KERN_ENABLE_PERF_TESTS=1       Run perf tests (otherwise skipped)"
echo "  KERN_EXPORT_UI_ATTACHMENTS=1   Always export UI attachments (otherwise only on failure)"
echo "  KERN_UI_SCREENSHOTS=always     Keep UI screenshots on success (default)"
echo "  KERN_UI_SCREENSHOTS=failure    Only keep UI screenshots on failure (faster)"
echo "  KERN_UI_SCREENSHOTS=off        Disable UI screenshots (fastest)"
echo "  KERN_UI_SCREENSHOT_DIR=/path   Write UI PNGs to disk (runner sets automatically)"
echo ""

UNIT_ENV=()
UI_ENV=()

if [ "$ENABLE_EXHAUSTIVE" = true ]; then
  UNIT_ENV+=("KERN_ENABLE_EXHAUSTIVE_TESTS=1")
  UI_ENV+=("KERN_ENABLE_EXHAUSTIVE_TESTS=1")
fi
if [ "$ENABLE_SNAPSHOTS" = true ]; then
  UNIT_ENV+=("KERN_ENABLE_SNAPSHOT_TESTS=1")
fi
if [ "$RECORD_SNAPSHOTS" = true ]; then
  UNIT_ENV+=("KERN_RECORD_SNAPSHOTS=1")
fi

NEED_XCODEGEN=true
if [ "$SKIP_XCODEGEN" = true ]; then
  NEED_XCODEGEN=false
fi
if [ -f "Kern.xcodeproj/project.pbxproj" ] && [ "Kern.xcodeproj/project.pbxproj" -nt "project.yml" ]; then
  NEED_XCODEGEN=false
fi

if [ "$NEED_XCODEGEN" = true ]; then
  echo "▸ Generating Xcode project (xcodegen)..."
  xcodegen 2>&1 | tail -1
else
  echo "▸ Skipping xcodegen (project up-to-date)."
fi

echo ""

if [ "$RUN_UNIT" = true ]; then
  echo "▸ Running unit tests (scheme: Kern)..."
  set +e
  if [ "${#UNIT_ENV[@]}" -gt 0 ]; then
    env "${UNIT_ENV[@]}" xcodebuild \
      -project Kern.xcodeproj \
      -scheme Kern \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      -resultBundlePath "$OUT_DIR/KernTests.xcresult" \
      test \
      2>&1 | tee "$OUT_DIR/unit.log"
  else
    xcodebuild \
      -project Kern.xcodeproj \
      -scheme Kern \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      -resultBundlePath "$OUT_DIR/KernTests.xcresult" \
      test \
      2>&1 | tee "$OUT_DIR/unit.log"
  fi
  UNIT_STATUS=${PIPESTATUS[0]}
  set -e
  if [ $UNIT_STATUS -ne 0 ]; then
    echo "Unit tests failed (exit $UNIT_STATUS). See: $OUT_DIR/unit.log" >&2
    exit $UNIT_STATUS
  fi
  echo "  ✓ Unit tests passed"
  echo ""
fi

if [ "$RUN_UI" = true ]; then
  echo "▸ Running UI tests (scheme: KernUI)..."
  echo "  Preflight: Ensure the Mac is unlocked and Automation permissions are granted."

  set +e
  UI_SCREENSHOT_DIR="$OUT_DIR/ui-screenshots"
  mkdir -p "$UI_SCREENSHOT_DIR"

  if [ "${#UI_ENV[@]}" -gt 0 ]; then
    env "${UI_ENV[@]}" KERN_UI_SCREENSHOT_DIR="$UI_SCREENSHOT_DIR" xcodebuild \
      -project Kern.xcodeproj \
      -scheme KernUI \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      -resultBundlePath "$OUT_DIR/KernUI.xcresult" \
      test \
      2>&1 | tee "$OUT_DIR/ui.log"
  else
    env KERN_UI_SCREENSHOT_DIR="$UI_SCREENSHOT_DIR" xcodebuild \
      -project Kern.xcodeproj \
      -scheme KernUI \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      -resultBundlePath "$OUT_DIR/KernUI.xcresult" \
      test \
      2>&1 | tee "$OUT_DIR/ui.log"
  fi
  UI_STATUS=${PIPESTATUS[0]}
  set -e

  if [ $UI_STATUS -ne 0 ]; then
    echo "UI tests failed (exit $UI_STATUS). See: $OUT_DIR/ui.log" >&2
  else
    echo "  ✓ UI tests passed"
  fi

  echo ""
  ALWAYS_EXPORT_ATTACHMENTS=false
  if [ "${KERN_EXPORT_UI_ATTACHMENTS:-}" = "1" ] || [ "$EXPORT_UI_ATTACHMENTS" = true ]; then
    ALWAYS_EXPORT_ATTACHMENTS=true
  fi

  if [ $UI_STATUS -ne 0 ] || [ "$ALWAYS_EXPORT_ATTACHMENTS" = true ]; then
    echo "▸ Exporting UI test attachments (screenshots/logs)..."
    ATT_DIR="$OUT_DIR/ui-attachments"
    mkdir -p "$ATT_DIR"
    xcrun xcresulttool export attachments \
      --path "$OUT_DIR/KernUI.xcresult" \
      --output-path "$ATT_DIR" \
      2>&1 | tee "$OUT_DIR/xcresult-attachments.log" >/dev/null || true
    echo "  Attachments: $ATT_DIR"
  else
    echo "▸ Skipping UI attachment export (set KERN_EXPORT_UI_ATTACHMENTS=1 or pass --export-ui-attachments)"
  fi

  if [ $UI_STATUS -ne 0 ]; then
    exit $UI_STATUS
  fi
fi

echo "All selected test suites completed."
