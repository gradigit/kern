#!/bin/bash
# Measure Kern cold start timing (Release build)
# Runs N iterations, captures NSLog [Perf] lines, reports median

set -euo pipefail

KERN_APP="/Users/aaaaa/Library/Developer/Xcode/DerivedData/Kern-fmshysujrcibpcdmfoxzgubdswre/Build/Products/Release/Kern.app"
KERN_BIN="$KERN_APP/Contents/MacOS/Kern"
TEST_FILE="/Users/aaaaa/Projects/Kern/test-fixtures/stress-test.md"
ITERATIONS=${1:-5}
WAIT_SECONDS=8  # Time to wait for editor to fully load

echo "=== Kern Cold Start Benchmark (Release) ==="
echo "Binary: $KERN_BIN"
echo "Test file: $TEST_FILE"
echo "Iterations: $ITERATIONS"
echo ""

declare -a editor_ready_times
declare -a set_markdown_times

for i in $(seq 1 $ITERATIONS); do
    echo "--- Run $i of $ITERATIONS ---"

    # Kill any existing Kern
    pkill -x Kern 2>/dev/null || true
    sleep 1

    # Launch Kern with test file, capture stderr (NSLog goes to unified log)
    # Use open -a to simulate real user launch
    LOG_FILE="/tmp/kern-bench-$i.log"

    # Start log capture BEFORE launching
    log stream --predicate 'process == "Kern" AND eventMessage CONTAINS "[Perf]"' --style compact > "$LOG_FILE" 2>/dev/null &
    LOG_PID=$!
    sleep 0.5

    # Launch the app with the test file
    open "$KERN_APP" --args "$TEST_FILE"

    # Wait for editor to load
    sleep $WAIT_SECONDS

    # Stop log capture
    kill $LOG_PID 2>/dev/null || true
    wait $LOG_PID 2>/dev/null || true

    # Extract timing
    echo "Log output:"
    cat "$LOG_FILE"

    # Parse editorReady time
    er_time=$(grep -o 'editorReady at [0-9.]*ms' "$LOG_FILE" | head -1 | grep -o '[0-9.]*' || echo "")
    sm_time=$(grep -o 'setMarkdown complete at [0-9.]*ms' "$LOG_FILE" | head -1 | grep -o '[0-9.]*' || echo "")

    if [ -n "$er_time" ]; then
        echo "  editorReady: ${er_time}ms"
        editor_ready_times+=("$er_time")
    else
        echo "  editorReady: NOT FOUND"
    fi

    if [ -n "$sm_time" ]; then
        echo "  setMarkdown: ${sm_time}ms"
        set_markdown_times+=("$sm_time")
    else
        echo "  setMarkdown: NOT FOUND"
    fi

    echo ""

    # Kill Kern for next iteration
    pkill -x Kern 2>/dev/null || true
    sleep 1
done

echo "=== Results ==="
echo ""

# Sort and find median
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

echo "editorReady times: ${editor_ready_times[*]:-N/A}"
if [ ${#editor_ready_times[@]} -gt 0 ]; then
    median_er=$(sort_and_median "${editor_ready_times[@]}")
    echo "  Median: ${median_er}ms"
fi

echo ""
echo "setMarkdown times: ${set_markdown_times[*]:-N/A}"
if [ ${#set_markdown_times[@]} -gt 0 ]; then
    median_sm=$(sort_and_median "${set_markdown_times[@]}")
    echo "  Median: ${median_sm}ms"
fi

echo ""
echo "Comparison (Debug baseline pre-optimization):"
echo "  editorReady: ~530-600ms"
echo "  Phase A Debug: ~365ms"
echo ""
echo "Done."
