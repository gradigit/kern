#!/bin/bash
# Kern vs MarkText Benchmark Script
# Compares cold start, memory, tab switching, file open latency, and large file handling.
# Usage: ./scripts/benchmark.sh
#
# If MarkText is not installed, runs Kern-only benchmarks.
# To include MarkText, pass its .app path:
#   MARKTEXT_PATH="/path/to/MarkText.app" ./scripts/benchmark.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BENCHMARK_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kern-benchmark.XXXXXX")"

cleanup_benchmark_tmp_dir() {
    if [ -d "$BENCHMARK_TMP_DIR" ]; then
        find "$BENCHMARK_TMP_DIR" -depth -mindepth 1 -delete
        rmdir "$BENCHMARK_TMP_DIR" 2>/dev/null || true
    fi
}
trap cleanup_benchmark_tmp_dir EXIT

KERN_APP="Kern"
MARKTEXT_APP="MarkText"
STRESS_FILE="$REPO_ROOT/test-fixtures/stress-test.md"
LARGE_FILE="$BENCHMARK_TMP_DIR/kern-benchmark-large.md"
RESULTS_FILE="$BENCHMARK_TMP_DIR/kern-benchmark-results.md"
RUNS=3  # Number of iterations for averaged measurements

# High-res timestamp in seconds
now() {
    perl -MTime::HiRes=time -e 'printf "%.3f\n", time'
}

# Elapsed time between two timestamps
elapsed() {
    echo "scale=3; $2 - $1" | bc
}

# Average of space-separated values
average() {
    local vals="$1"
    local count=0
    local sum=0
    for v in $vals; do
        if [ "$v" != "timeout" ]; then
            sum=$(echo "scale=3; $sum + $v" | bc)
            count=$(( count + 1 ))
        fi
    done
    if [ "$count" -eq 0 ]; then
        echo "timeout"
    else
        echo "scale=3; $sum / $count" | bc
    fi
}

# Check if an app is installed / launchable
app_available() {
    local app_name="$1"
    open -Ra "$app_name" 2>/dev/null && return 0
    return 1
}

app_process_name() {
    basename "$1" .app
}

pid_file_for_app() {
    local process_name
    process_name=$(app_process_name "$1")
    printf '%s/owned-%s.pids\n' "$BENCHMARK_TMP_DIR" "$process_name"
}

current_app_pids() {
    local process_name
    process_name=$(app_process_name "$1")
    pgrep -x "$process_name" 2>/dev/null || true
}

ensure_app_idle_or_die() {
    local app_name="$1"
    local running
    running=$(current_app_pids "$app_name")
    if [ -n "$running" ]; then
        echo "ERROR: $app_name is already running; refusing broad benchmark cleanup." >&2
        exit 1
    fi
}

remember_owned_app_pids() {
    local app_name="$1"
    local before_pids="${2:-}"
    local pid_file tmp_file current_pids
    pid_file=$(pid_file_for_app "$app_name")
    tmp_file="$pid_file.tmp"
    : > "$tmp_file"
    current_pids=$(current_app_pids "$app_name")
    for pid in $current_pids; do
        if ! printf '%s\n' "$before_pids" | grep -qx "$pid"; then
            printf '%s\n' "$pid" >> "$tmp_file"
        fi
    done
    if [ ! -s "$tmp_file" ] && [ -z "$before_pids" ] && [ -n "$current_pids" ]; then
        printf '%s\n' "$current_pids" | head -n1 > "$tmp_file"
    fi
    if [ -f "$pid_file" ]; then
        cat "$pid_file" "$tmp_file" | awk 'NF' | sort -u > "$pid_file.merged"
        mv "$pid_file.merged" "$pid_file"
        rm -f "$tmp_file"
    else
        mv "$tmp_file" "$pid_file"
    fi
}

launch_app() {
    local app_name="$1"
    shift
    local before_pids
    before_pids=$(current_app_pids "$app_name")
    open -a "$app_name" "$@"
    sleep 0.1
    remember_owned_app_pids "$app_name" "$before_pids"
}

HAS_MARKTEXT=false

# Allow overriding MarkText path
if [ -n "${MARKTEXT_PATH:-}" ]; then
    if [ -d "$MARKTEXT_PATH" ]; then
        MARKTEXT_APP="$MARKTEXT_PATH"
        HAS_MARKTEXT=true
    else
        echo "WARNING: MARKTEXT_PATH=$MARKTEXT_PATH does not exist"
    fi
elif app_available "$MARKTEXT_APP"; then
    HAS_MARKTEXT=true
fi

# Generate large test file (~75KB)
generate_large_file() {
    echo "Generating large test file..."
    {
        echo "# Large Benchmark File"
        echo ""
        for i in $(seq 1 200); do
            echo "## Section $i"
            echo ""
            echo "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris."
            echo ""
            echo '```javascript'
            echo "function section${i}() {"
            echo "  const data = Array.from({ length: 100 }, (_, i) => i * $i);"
            echo "  return data.filter(x => x % 2 === 0).map(x => x * x);"
            echo "}"
            echo '```'
            echo ""
            if (( i % 10 == 0 )); then
                echo "| Col A | Col B | Col C |"
                echo "|-------|-------|-------|"
                echo "| $i | data | value |"
                echo "| $(( i + 1 )) | more | info |"
                echo ""
            fi
        done
    } > "$LARGE_FILE"
    local size
    size=$(wc -c < "$LARGE_FILE" | tr -d ' ')
    echo "  Generated: $LARGE_FILE (${size} bytes)"
}

# Get RSS memory in MB for a process (sums all matching PIDs)
get_rss_mb() {
    local app_name="$1"
    local process_name
    process_name=$(basename "$app_name" .app)
    local pids
    pids=$(pgrep -x "$process_name" 2>/dev/null || true)
    if [ -z "$pids" ]; then
        echo "0"
        return
    fi
    local total=0
    for pid in $pids; do
        local rss
        rss=$(ps -o rss= -p "$pid" 2>/dev/null || echo "0")
        rss=$(echo "$rss" | tr -d ' ')
        total=$(( total + rss ))
    done
    echo "scale=1; $total / 1024" | bc
}

# Wait for app window to appear, return time to first window
wait_for_window() {
    local app_name="$1"
    local process_name
    process_name=$(basename "$app_name" .app)
    local max_wait="${2:-10}"
    local start
    start=$(now)
    for _ in $(seq 1 $(( max_wait * 10 ))); do
        if osascript -e "tell application \"System Events\" to count windows of process \"$process_name\"" 2>/dev/null | grep -q '[1-9]'; then
            local end
            end=$(now)
            elapsed "$start" "$end"
            return 0
        fi
        sleep 0.1
    done
    echo "timeout"
    return 1
}

# Kill app gracefully
kill_app() {
    local app_name="$1"
    local pid_file owned_pids current_pids
    pid_file=$(pid_file_for_app "$app_name")
    [ -f "$pid_file" ] || return 0
    owned_pids=$(cat "$pid_file" 2>/dev/null || true)
    current_pids=$(current_app_pids "$app_name")
    for pid in $current_pids; do
        if printf '%s\n' "$owned_pids" | grep -qx "$pid"; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    sleep 1
    current_pids=$(current_app_pids "$app_name")
    for pid in $current_pids; do
        if printf '%s\n' "$owned_pids" | grep -qx "$pid"; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
    rm -f "$pid_file"
}

# ─── Benchmark: cold start ───────────────────────────────────────
benchmark_cold_start() {
    local app_name="$1"
    local file="$2"

    kill_app "$app_name"
    sleep 1

    launch_app "$app_name" "$file"
    local latency
    latency=$(wait_for_window "$app_name" 15)

    echo "$latency"
    kill_app "$app_name"
}

# ─── Benchmark: memory with N tabs ──────────────────────────────
benchmark_memory() {
    local app_name="$1"
    local n="$2"

    kill_app "$app_name"
    sleep 1

    # Create temp files
    local files=()
    for i in $(seq 1 "$n"); do
        local f
        f=$(mktemp "$BENCHMARK_TMP_DIR/kern-bench-${i}.XXXXXX.md")
        cp "$STRESS_FILE" "$f"
        files+=("$f")
    done

    # Open all files
    for f in "${files[@]}"; do
        launch_app "$app_name" "$f"
        sleep 0.5
    done
    sleep 3  # let everything settle

    local rss
    rss=$(get_rss_mb "$app_name")
    echo "$rss"

    kill_app "$app_name"

    for f in "${files[@]}"; do
        rm -f "$f"
    done
}

# ─── Benchmark: tab switch latency ──────────────────────────────
# Opens N tabs, then cycles through them with Ctrl+Tab and measures
# the time for the window title to change (indicating the new tab
# is active and rendered).
benchmark_tab_switch() {
    local app_name="$1"
    local n="$2"
    local process_name
    process_name=$(basename "$app_name" .app)

    kill_app "$app_name"
    sleep 1

    # Create and open N distinct files (different names so titles differ)
    local files=()
    for i in $(seq 1 "$n"); do
        local f
        f=$(mktemp "$BENCHMARK_TMP_DIR/kern-tabswitch-${i}.XXXXXX.md")
        echo "# Tab $i content" > "$f"
        echo "" >> "$f"
        echo "This is file $i for tab switch benchmark." >> "$f"
        files+=("$f")
    done

    for f in "${files[@]}"; do
        launch_app "$app_name" "$f"
        sleep 0.5
    done
    sleep 3  # let all tabs load

    # Get current window title
    local current_title
    current_title=$(osascript -e "tell application \"System Events\" to get name of front window of process \"$process_name\"" 2>/dev/null || echo "")

    # Cycle through tabs and measure title change time
    local times=""
    for _ in $(seq 1 "$n"); do
        local start
        start=$(now)

        # Send Ctrl+Tab to switch tab
        osascript -e "
            tell application \"System Events\"
                tell process \"$process_name\"
                    key code 48 using {control down}
                end tell
            end tell
        " 2>/dev/null

        # Wait for title to change (meaning new tab is active)
        local switched=false
        for _ in $(seq 1 50); do  # 5 second max
            local new_title
            new_title=$(osascript -e "tell application \"System Events\" to get name of front window of process \"$process_name\"" 2>/dev/null || echo "")
            if [ "$new_title" != "$current_title" ] && [ -n "$new_title" ]; then
                local end
                end=$(now)
                local t
                t=$(elapsed "$start" "$end")
                times="$times $t"
                current_title="$new_title"
                switched=true
                break
            fi
            sleep 0.1
        done

        if [ "$switched" = false ]; then
            # Title didn't change — might be same tab, or single tab
            # Still record the attempt time
            local end
            end=$(now)
            local t
            t=$(elapsed "$start" "$end")
            times="$times $t"
        fi

        sleep 0.2  # brief pause between switches
    done

    kill_app "$app_name"
    for f in "${files[@]}"; do
        rm -f "$f"
    done

    average "$times"
}

# ─── Benchmark: rapid tab cycling ────────────────────────────────
# Opens 10 tabs, fires Ctrl+Tab 20 times rapidly, measures total time
benchmark_rapid_cycle() {
    local app_name="$1"
    local process_name
    process_name=$(basename "$app_name" .app)

    kill_app "$app_name"
    sleep 1

    local files=()
    for i in $(seq 1 10); do
        local f="/tmp/kern-rapid-${i}.md"
        echo "# Rapid cycle file $i" > "$f"
        files+=("$f")
    done

    for f in "${files[@]}"; do
        launch_app "$app_name" "$f"
        sleep 0.3
    done
    sleep 3

    local start
    start=$(now)

    # Fire 20 rapid tab switches
    osascript -e "
        tell application \"System Events\"
            tell process \"$process_name\"
                repeat 20 times
                    key code 48 using {control down}
                    delay 0.15
                end repeat
            end tell
        end tell
    " 2>/dev/null

    sleep 1  # let final tab settle

    local end
    end=$(now)
    local total
    total=$(elapsed "$start" "$end")

    kill_app "$app_name"
    for f in "${files[@]}"; do
        rm -f "$f"
    done

    echo "$total"
}

# ─── Benchmark: new tab from open file ──────────────────────────
# App already running with a file, open another — measure time to window title change
benchmark_open_in_running() {
    local app_name="$1"
    local process_name
    process_name=$(basename "$app_name" .app)

    kill_app "$app_name"
    sleep 1

    # Open initial file
    local f1="/tmp/kern-running-1.md"
    local f2="/tmp/kern-running-2.md"
    echo "# File one" > "$f1"
    echo "# File two — opened into running app" > "$f2"

    launch_app "$app_name" "$f1"
    sleep 2

    local start
    start=$(now)
    launch_app "$app_name" "$f2"

    # Wait for title to change to file 2
    local got_it=false
    for _ in $(seq 1 100); do  # 10s max
        local title
        title=$(osascript -e "tell application \"System Events\" to get name of front window of process \"$process_name\"" 2>/dev/null || echo "")
        if echo "$title" | grep -qi "running-2\|File two"; then
            got_it=true
            break
        fi
        sleep 0.1
    done

    local end
    end=$(now)
    local t
    t=$(elapsed "$start" "$end")

    kill_app "$app_name"
    rm -f "$f1" "$f2"

    echo "$t"
}

# ─── Helpers for printing ────────────────────────────────────────
NA="n/a"

run_bench() {
    local label="$1"
    local bench_fn="$2"
    shift 2
    # remaining args are passed to bench_fn

    echo ""
    echo "--- ${label} ---"

    local kern_result
    kern_result=$($bench_fn "$KERN_APP" "$@")
    echo "  Kern:     ${kern_result}"

    local marktext_result
    if [ "$HAS_MARKTEXT" = true ]; then
        marktext_result=$($bench_fn "$MARKTEXT_APP" "$@")
        echo "  MarkText: ${marktext_result}"
    else
        marktext_result="$NA"
        echo "  MarkText: (skipped)"
    fi

    # Store in global vars for the results table
    local result_prefix="${3:-_DISCARD}"
    printf -v "${result_prefix}_KERN" '%s' "$kern_result"
    printf -v "${result_prefix}_MARKTEXT" '%s' "$marktext_result"
}

# ═════════════════════════════════════════════════════════════════
# Main
# ═════════════════════════════════════════════════════════════════
echo "================================================================="
echo "  Kern vs MarkText Benchmark"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Runs per measurement: $RUNS (where applicable)"
echo "================================================================="
echo ""

if [ "$HAS_MARKTEXT" = false ]; then
    echo "NOTE: MarkText not found. Running Kern-only benchmarks."
    echo "      To include MarkText, install it or set:"
    echo "      MARKTEXT_PATH=/path/to/MarkText.app ./scripts/benchmark.sh"
    echo ""
fi

ensure_app_idle_or_die "$KERN_APP"
if [ "$HAS_MARKTEXT" = true ]; then
    ensure_app_idle_or_die "$MARKTEXT_APP"
fi

generate_large_file

# ─── Cold start ──────────────────────────────────────────────────
echo ""
echo "--- Cold Start (stress test file) ---"
kern_cold_vals=""
for i in $(seq 1 "$RUNS"); do
    v=$(benchmark_cold_start "$KERN_APP" "$STRESS_FILE")
    kern_cold_vals="$kern_cold_vals $v"
    echo "  Kern run $i: ${v}s"
done
COLD_KERN=$(average "$kern_cold_vals")
echo "  Kern avg:   ${COLD_KERN}s"

if [ "$HAS_MARKTEXT" = true ]; then
    marktext_cold_vals=""
    for i in $(seq 1 "$RUNS"); do
        v=$(benchmark_cold_start "$MARKTEXT_APP" "$STRESS_FILE")
        marktext_cold_vals="$marktext_cold_vals $v"
        echo "  MarkText run $i: ${v}s"
    done
    COLD_MARKTEXT=$(average "$marktext_cold_vals")
    echo "  MarkText avg:   ${COLD_MARKTEXT}s"
else
    COLD_MARKTEXT="$NA"
fi

# ─── Large file open ─────────────────────────────────────────────
echo ""
echo "--- Large File Open (~75KB) ---"
kern_large_vals=""
for i in $(seq 1 "$RUNS"); do
    v=$(benchmark_cold_start "$KERN_APP" "$LARGE_FILE")
    kern_large_vals="$kern_large_vals $v"
    echo "  Kern run $i: ${v}s"
done
LARGE_KERN=$(average "$kern_large_vals")
echo "  Kern avg:   ${LARGE_KERN}s"

if [ "$HAS_MARKTEXT" = true ]; then
    marktext_large_vals=""
    for i in $(seq 1 "$RUNS"); do
        v=$(benchmark_cold_start "$MARKTEXT_APP" "$LARGE_FILE")
        marktext_large_vals="$marktext_large_vals $v"
        echo "  MarkText run $i: ${v}s"
    done
    LARGE_MARKTEXT=$(average "$marktext_large_vals")
    echo "  MarkText avg:   ${LARGE_MARKTEXT}s"
else
    LARGE_MARKTEXT="$NA"
fi

# ─── Open file into running app ──────────────────────────────────
echo ""
echo "--- Open File Into Running App ---"
OPEN_RUNNING_KERN=$(benchmark_open_in_running "$KERN_APP")
echo "  Kern:     ${OPEN_RUNNING_KERN}s"
if [ "$HAS_MARKTEXT" = true ]; then
    OPEN_RUNNING_MARKTEXT=$(benchmark_open_in_running "$MARKTEXT_APP")
    echo "  MarkText: ${OPEN_RUNNING_MARKTEXT}s"
else
    OPEN_RUNNING_MARKTEXT="$NA"
fi

# ─── Tab switch latency (5 tabs) ─────────────────────────────────
echo ""
echo "--- Tab Switch Latency (avg over 5 tabs) ---"
TAB5_KERN=$(benchmark_tab_switch "$KERN_APP" 5)
echo "  Kern:     ${TAB5_KERN}s"
if [ "$HAS_MARKTEXT" = true ]; then
    TAB5_MARKTEXT=$(benchmark_tab_switch "$MARKTEXT_APP" 5)
    echo "  MarkText: ${TAB5_MARKTEXT}s"
else
    TAB5_MARKTEXT="$NA"
fi

# ─── Tab switch latency (10 tabs — forces virtualization in Kern) ─
echo ""
echo "--- Tab Switch Latency (avg over 10 tabs, Kern virtualizes >5) ---"
TAB10_KERN=$(benchmark_tab_switch "$KERN_APP" 10)
echo "  Kern:     ${TAB10_KERN}s"
if [ "$HAS_MARKTEXT" = true ]; then
    TAB10_MARKTEXT=$(benchmark_tab_switch "$MARKTEXT_APP" 10)
    echo "  MarkText: ${TAB10_MARKTEXT}s"
else
    TAB10_MARKTEXT="$NA"
fi

# ─── Rapid tab cycling (20 switches across 10 tabs) ──────────────
echo ""
echo "--- Rapid Tab Cycling (20 switches across 10 tabs, total time) ---"
RAPID_KERN=$(benchmark_rapid_cycle "$KERN_APP")
echo "  Kern:     ${RAPID_KERN}s"
if [ "$HAS_MARKTEXT" = true ]; then
    RAPID_MARKTEXT=$(benchmark_rapid_cycle "$MARKTEXT_APP")
    echo "  MarkText: ${RAPID_MARKTEXT}s"
else
    RAPID_MARKTEXT="$NA"
fi

# ─── Memory with N tabs ──────────────────────────────────────────
run_memory_bench() {
    local n="$1"
    local label="$2"
    echo ""
    echo "--- Memory with ${label} ---"
    local kern_mem
    kern_mem=$(benchmark_memory "$KERN_APP" "$n")
    echo "  Kern:     ${kern_mem} MB"
    if [ "$HAS_MARKTEXT" = true ]; then
        local marktext_mem
        marktext_mem=$(benchmark_memory "$MARKTEXT_APP" "$n")
        echo "  MarkText: ${marktext_mem} MB"
    else
        local marktext_mem="$NA"
    fi
    printf -v "KERN_MEM_${n}" '%s' "$kern_mem"
    printf -v "MARKTEXT_MEM_${n}" '%s' "$marktext_mem"
}

run_memory_bench 1 "1 tab"
run_memory_bench 5 "5 tabs"
run_memory_bench 10 "10 tabs"
run_memory_bench 20 "20 tabs"

# ═════════════════════════════════════════════════════════════════
# Write results
# ═════════════════════════════════════════════════════════════════
cat > "$RESULTS_FILE" <<EOF
# Kern vs MarkText Benchmark Results

Date: $(date '+%Y-%m-%d %H:%M:%S')

## Cold Start & File Open

| Metric | Kern | MarkText |
|--------|------|----------|
| Cold start (avg of $RUNS) | ${COLD_KERN}s | ${COLD_MARKTEXT} |
| Large file ~75KB (avg of $RUNS) | ${LARGE_KERN}s | ${LARGE_MARKTEXT} |
| Open into running app | ${OPEN_RUNNING_KERN}s | ${OPEN_RUNNING_MARKTEXT} |

## Tab Switching

| Metric | Kern | MarkText |
|--------|------|----------|
| Avg switch, 5 tabs | ${TAB5_KERN}s | ${TAB5_MARKTEXT} |
| Avg switch, 10 tabs (virtualized) | ${TAB10_KERN}s | ${TAB10_MARKTEXT} |
| 20 rapid switches (total) | ${RAPID_KERN}s | ${RAPID_MARKTEXT} |

## Memory Usage (RSS)

| Tabs | Kern | MarkText |
|------|------|----------|
| 1 | ${KERN_MEM_1} MB | ${MARKTEXT_MEM_1} |
| 5 | ${KERN_MEM_5} MB | ${MARKTEXT_MEM_5} |
| 10 | ${KERN_MEM_10} MB | ${MARKTEXT_MEM_10} |
| 20 | ${KERN_MEM_20} MB | ${MARKTEXT_MEM_20} |
EOF

echo ""
echo "================================================================="
echo "  Results saved to: $RESULTS_FILE"
echo "================================================================="
echo ""

# Cleanup
rm -f "$LARGE_FILE"
