#!/bin/bash
# measure-cold-start.sh — KernTextKit cold start timing (Release build)
#
# Measures time from process start to `applicationDidFinishLaunching end`.
#
# Usage:
#   ./scripts/measure-cold-start.sh [iterations] [wait_seconds]
#
# Notes:
# - This relies on NSLog "[Perf]" lines emitted by the app.
# - Requires the app to be built in Release at least once.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="KernTextKit"
PROCESS_NAME="KernTextKit"
ITERATIONS=${1:-5}
WAIT_SECONDS=${2:-4}

TEST_FILE="${TEST_FILE:-$(pwd)/test-fixtures/stress-test.md}"

APP_PATH="${APP_PATH:-}"
if [ -z "$APP_PATH" ]; then
  APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData/${APP_NAME}-*/Build/Products/Release/${APP_NAME}.app" -maxdepth 0 2>/dev/null | head -1 || true)"
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "ERROR: Cannot find ${APP_NAME}.app (Release) in DerivedData." >&2
  echo "       Build first: xcodebuild -project ${APP_NAME}.xcodeproj -scheme ${APP_NAME} -configuration Release build" >&2
  exit 1
fi

if [ ! -f "$TEST_FILE" ]; then
  echo "ERROR: TEST_FILE not found: $TEST_FILE" >&2
  exit 1
fi

echo "=== ${APP_NAME} Cold Start Benchmark (Release) ==="
echo "App: $APP_PATH"
echo "Test file: $TEST_FILE"
echo "Iterations: $ITERATIONS"
echo "Wait seconds: $WAIT_SECONDS"
echo ""

declare -a did_finish_times

sort_and_median() {
  local -a sorted
  IFS=$'\n' sorted=($(printf '%s\n' "$@" | sort -n))
  local count=${#sorted[@]}
  if [ $count -eq 0 ]; then
    echo "N/A"
    return
  fi
  local mid=$((count / 2))
  echo "${sorted[$mid]}"
}

for i in $(seq 1 "$ITERATIONS"); do
  echo "--- Run $i of $ITERATIONS ---"

  pkill -x "$PROCESS_NAME" 2>/dev/null || true
  sleep 1

  LOG_FILE="/tmp/kerntextkit-cold-start-$i.log"

  log stream --predicate "process == \"$PROCESS_NAME\" AND eventMessage CONTAINS \"[Perf]\"" --style compact > "$LOG_FILE" 2>/dev/null &
  LOG_PID=$!
  sleep 0.5

  open -n "$APP_PATH" --args "$TEST_FILE"
  sleep "$WAIT_SECONDS"

  kill "$LOG_PID" 2>/dev/null || true
  wait "$LOG_PID" 2>/dev/null || true

  # Extract the latest "applicationDidFinishLaunching end" timestamp.
  t=$(grep -o 'applicationDidFinishLaunching end at [0-9.]*ms' "$LOG_FILE" | tail -1 | grep -o '[0-9.]*' || true)
  if [ -n "$t" ]; then
    echo "  applicationDidFinishLaunching end: ${t}ms"
    did_finish_times+=("$t")
  else
    echo "  applicationDidFinishLaunching end: NOT FOUND"
  fi

  pkill -x "$PROCESS_NAME" 2>/dev/null || true
  sleep 1
  echo ""
done

echo "=== Results ==="
echo "applicationDidFinishLaunching end times: ${did_finish_times[*]:-N/A}"
if [ ${#did_finish_times[@]} -gt 0 ]; then
  median=$(sort_and_median "${did_finish_times[@]}")
  echo "  Median: ${median}ms"
fi

