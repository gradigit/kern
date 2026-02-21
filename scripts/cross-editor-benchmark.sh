#!/usr/bin/env bash
# cross-editor-benchmark.sh — Phase 1 cross-editor launch-time comparison
#
# Measures "time to window visible" for each editor by polling System Events.
# This is a rough wall-clock metric (~50ms resolution). For precise per-frame
# measurements, use the Phase 2 Swift CLI: scripts/kern-bench/
#
# Usage:
#   ./scripts/cross-editor-benchmark.sh [options] [file] [runs]
#   ./scripts/cross-editor-benchmark.sh test-fixtures/cross-editor-benchmark.md 30
#   ./scripts/cross-editor-benchmark.sh --cold --json results.json --runs 30
#   ./scripts/cross-editor-benchmark.sh --editors "Kern,Zed,Sublime Text"

set -euo pipefail
cd "$(dirname "$0")/.."

# ─── Defaults ──────────────────────────────────────────────────
FILE=""
RUNS=30
WARMUP_RUNS=3
MODE="warm"
JSON_PATH=""
EDITORS_FILTER=""
VERBOSE=false
SHUFFLE=false

# ─── Argument parsing ─────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cold)    MODE="cold"; shift ;;
        --warm)    MODE="warm"; shift ;;
        --json)    JSON_PATH="$2"; shift 2 ;;
        --runs)    RUNS="$2"; shift 2 ;;
        --warmup-runs) WARMUP_RUNS="$2"; shift 2 ;;
        --editors) EDITORS_FILTER="$2"; shift 2 ;;
        --shuffle) SHUFFLE=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --file)    FILE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [options] [file] [runs]"
            echo ""
            echo "Options:"
            echo "  --cold              Purge filesystem cache between runs (requires sudo)"
            echo "  --warm              Warmup runs before measuring (default)"
            echo "  --runs N            Number of iterations (default: 30)"
            echo "  --warmup-runs N     Number of warmup runs (default: 3)"
            echo "  --json PATH         Write JSON results to file"
            echo "  --editors LIST      Comma-separated editor names"
            echo "  --shuffle           Randomize editor order each round"
            echo "  --verbose, -v       Print per-run details"
            echo "  --file PATH         Test file to open"
            echo "  --help, -h          Show this help"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2; exit 1 ;;
        *)
            # Positional: first is file, second is runs
            if [[ -z "$FILE" ]]; then
                FILE="$1"
            elif [[ "$RUNS" == "30" ]]; then
                RUNS="$1"
            fi
            shift
            ;;
    esac
done

# Default file
if [[ -z "$FILE" ]]; then
    FILE="test-fixtures/cross-editor-benchmark.md"
fi

if [[ ! -f "$FILE" ]]; then
    echo "Error: File not found: $FILE"
    exit 1
fi

FILE_ABS="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"
FILE_SIZE=$(wc -c < "$FILE" | tr -d ' ')
FILE_LINES=$(wc -l < "$FILE" | tr -d ' ')
FILE_HASH=$(shasum -a 256 "$FILE" | cut -d' ' -f1)

# ─── Environment detection ────────────────────────────────────
CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')
MACOS=$(sw_vers -productVersion)
POWER="Unknown"
if pmset -g batt 2>/dev/null | grep -q "AC Power"; then
    POWER="AC"
elif pmset -g batt 2>/dev/null | grep -q "Battery"; then
    POWER="Battery"
fi

THERMAL_PCT=100
if pmset -g therm 2>/dev/null | grep -q "CPU_Speed_Limit"; then
    THERMAL_PCT=$(pmset -g therm 2>/dev/null | grep CPU_Speed_Limit | awk -F'=' '{print $2}' | tr -d ' ')
fi

# ─── Header ───────────────────────────────────────────────────
echo "=== Cross-Editor Benchmark (Phase 1: Window Detection) ==="
echo "File:    $FILE ($FILE_SIZE bytes, $FILE_LINES lines)"
echo "SHA256:  $FILE_HASH"
echo "Runs:    $RUNS per editor ($MODE, $WARMUP_RUNS warmup)"
echo "Date:    $(date '+%Y-%m-%d %H:%M:%S')"
echo "macOS:   $MACOS"
echo "Chip:    $CHIP"
echo "Power:   $POWER"
echo "Thermal: ${THERMAL_PCT}%"
echo ""

if [[ "$THERMAL_PCT" -lt 100 ]]; then
    echo "WARNING: CPU thermal throttle detected (${THERMAL_PCT}%). Results may be unreliable."
    echo ""
fi

if [[ "$POWER" == "Battery" ]]; then
    echo "WARNING: Running on battery. macOS may throttle CPU. Plug in for reliable results."
    echo ""
fi

# ─── Editor detection ─────────────────────────────────────────
# Format: "DisplayName|AppName|BundleID|ProcessName|Architecture|IsElectron|CLICmd|CleanArgs"
ALL_EDITORS=()

# Kern (always test if installed)
if [[ -d "/Applications/Kern.app" ]] || [[ -d "$HOME/Applications/Kern.app" ]]; then
    ALL_EDITORS+=("Kern|Kern|com.gradigit.kern|Kern|Native Swift + TextKit|0||")
fi

for candidate in \
    "TextEdit|TextEdit|com.apple.TextEdit|TextEdit|Native AppKit|0||" \
    "Sublime Text|Sublime Text|com.sublimetext.4|sublime_text|Native C++|0|subl|--safe-mode --new-window" \
    "Visual Studio Code|Visual Studio Code|com.microsoft.VSCode|Electron|Electron|1|code|--new-window --user-data-dir /tmp/vscode-bench --disable-extensions" \
    "Zed|Zed|dev.zed.Zed|zed|Native Rust + Metal|0||" \
    "Typora|Typora|abnerworks.Typora|Typora|Electron|1||" \
    "iA Writer|iA Writer|pro.writer.mac|iA Writer|Native AppKit|0||" \
    "MarkText|MarkText|com.github.marktext.marktext|MarkText|Electron|1||" \
; do
    app_name=$(echo "$candidate" | cut -d'|' -f2)
    if [[ -d "/Applications/${app_name}.app" ]] || [[ -d "/System/Applications/${app_name}.app" ]] || [[ -d "$HOME/Applications/${app_name}.app" ]]; then
        ALL_EDITORS+=("$candidate")
    fi
done

# Filter editors if --editors was specified.
EDITORS=()
if [[ -n "$EDITORS_FILTER" ]]; then
    IFS=',' read -ra FILTER_LIST <<< "$EDITORS_FILTER"
    for entry in "${ALL_EDITORS[@]}"; do
        display_name=$(echo "$entry" | cut -d'|' -f1)
        for filter in "${FILTER_LIST[@]}"; do
            filter_trimmed=$(echo "$filter" | xargs)
            if [[ "$display_name" == "$filter_trimmed" ]]; then
                EDITORS+=("$entry")
                break
            fi
        done
    done
else
    EDITORS=("${ALL_EDITORS[@]}")
fi

if [[ ${#EDITORS[@]} -eq 0 ]]; then
    echo "No editors found. Install at least one target editor."
    exit 1
fi

echo "Detected editors: ${#EDITORS[@]}"
for e in "${EDITORS[@]}"; do
    echo "  - $(echo "$e" | cut -d'|' -f1) ($(echo "$e" | cut -d'|' -f5))"
done
echo ""

# ─── Measurement functions ────────────────────────────────────

launch_editor() {
    local app_name="$1"
    local process_name="$2"
    local cli_cmd="$3"
    local clean_args="$4"
    local file="$5"

    if [[ -n "$cli_cmd" ]]; then
        # Launch via CLI (preferred for session-restore suppression).
        $cli_cmd $clean_args "$file" &>/dev/null &
    else
        open -a "$app_name" "$file"
    fi
}

kill_editor() {
    local process_name="$1"
    local bundle_id="$2"
    local is_electron="$3"

    # Phase 1: Graceful AppleScript quit.
    osascript -e "tell application id \"$bundle_id\" to quit" 2>/dev/null || true
    sleep 0.5

    # Phase 2: SIGTERM via bundle-safe killall (only for non-Electron, where
    # processName is unambiguous). For Electron apps, skip killall to avoid
    # killing Slack/Discord/etc.
    if [[ "$is_electron" != "1" ]]; then
        killall "$process_name" 2>/dev/null || true
    fi

    # Phase 3: Poll for death (up to 3 seconds).
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if ! pgrep -x "$process_name" &>/dev/null; then
            return 0
        fi
        sleep 0.1
        attempts=$((attempts + 1))
    done

    # Phase 4: SIGKILL escalation — process ignored SIGTERM.
    if [[ "$is_electron" != "1" ]]; then
        killall -9 "$process_name" 2>/dev/null || true
    else
        # For Electron, kill by PID found via bundle ID to avoid collateral.
        local pid
        pid=$(osascript -e "tell application \"System Events\" to unix id of first process whose bundle identifier is \"$bundle_id\"" 2>/dev/null || true)
        if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]]; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi
    sleep 0.2
}

measure_launch() {
    local app_name="$1"
    local process_name="$2"
    local cli_cmd="$3"
    local clean_args="$4"
    local file="$5"
    local bundle_id="$6"
    local is_electron="$7"

    # Kill any existing instance using the safe kill function.
    kill_editor "$process_name" "$bundle_id" "$is_electron"

    local start
    start=$(perl -MTime::HiRes=time -e 'printf "%.6f\n", time')

    launch_editor "$app_name" "$process_name" "$cli_cmd" "$clean_args" "$file"

    # Poll for window via System Events (up to 30s timeout).
    local elapsed=0
    while [[ $elapsed -lt 600 ]]; do
        if osascript -e "tell application \"System Events\" to exists window 1 of process \"$process_name\"" 2>/dev/null | grep -q "true"; then
            break
        fi
        sleep 0.05
        elapsed=$((elapsed + 1))
    done

    local end
    end=$(perl -MTime::HiRes=time -e 'printf "%.6f\n", time')

    # Calculate ms.
    local ms
    ms=$(perl -e "printf '%.1f', ($end - $start) * 1000")

    if [[ $elapsed -ge 600 ]]; then
        echo "TIMEOUT"
    else
        echo "$ms"
    fi

    # Clean up using the safe kill function.
    kill_editor "$process_name" "$bundle_id" "$is_electron"
}

measure_memory() {
    local process_name="$1"
    local is_electron="$2"

    # Try footprint first (needs same user or sudo).
    local phys_mb="null"
    if [[ "$is_electron" == "1" ]]; then
        # For Electron, sum child processes too.
        local footprint_output
        footprint_output=$(footprint -proc "$process_name" --targetChildren 2>/dev/null || true)
        if [[ -n "$footprint_output" ]]; then
            local bytes
            bytes=$(echo "$footprint_output" | grep -i "phys_footprint\|^total" | grep -oE '[0-9]+' | sort -rn | head -1)
            if [[ -n "$bytes" ]] && [[ "$bytes" -gt 1000000 ]]; then
                phys_mb=$(perl -e "printf '%.1f', $bytes / 1048576")
            fi
        fi
    else
        local footprint_output
        footprint_output=$(footprint -proc "$process_name" 2>/dev/null || true)
        if [[ -n "$footprint_output" ]]; then
            local bytes
            bytes=$(echo "$footprint_output" | grep -i "phys_footprint" | grep -oE '[0-9]+' | sort -rn | head -1)
            if [[ -n "$bytes" ]] && [[ "$bytes" -gt 1000000 ]]; then
                phys_mb=$(perl -e "printf '%.1f', $bytes / 1048576")
            fi
        fi
    fi

    # Always get RSS as fallback/cross-reference.
    local rss_kb=0
    local pids
    pids=$(pgrep -x "$process_name" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        for pid in $pids; do
            local kb
            kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || echo "0")
            rss_kb=$((rss_kb + kb))
        done
    fi
    local rss_mb
    rss_mb=$(perl -e "printf '%.1f', $rss_kb / 1024")

    echo "${phys_mb}|${rss_mb}"
}

# ─── Statistics (using Python, matching Swift: no outlier removal, R Type 7 percentiles, bootstrap CI) ─

compute_stats() {
    local values="$1"
    python3 -c "
import json, math, random, sys

vals = [float(x) for x in '''$values'''.split() if x != 'TIMEOUT']
if not vals:
    print(json.dumps({'n':0,'min':0,'max':0,'median':0,'mean':0,'std':0,
        'cv_pct':0,'p25':0,'p75':0,'iqr':0,'p95':0,'p99':0,
        'ci_lower':0,'ci_upper':0}))
    sys.exit(0)

vals.sort()
n = len(vals)

def pct_r7(s, p):
    if len(s) <= 1: return s[0] if s else 0.0
    idx = p * (len(s) - 1)
    lo, hi = int(math.floor(idx)), int(math.ceil(idx))
    if lo == hi: return s[lo]
    f = idx - lo
    return s[lo] * (1 - f) + s[hi] * f

median = pct_r7(vals, 0.5)
mean = sum(vals) / n
variance = sum((x - mean) ** 2 for x in vals) / max(n - 1, 1)
std = math.sqrt(variance)
cv = (std / mean * 100) if mean > 0 else 0
p25 = pct_r7(vals, 0.25)
p75 = pct_r7(vals, 0.75)

# Bootstrap 95% CI for median
rng = random.Random(42)
medians = []
for _ in range(10000):
    sample = sorted(rng.choices(vals, k=n))
    medians.append(pct_r7(sample, 0.5))
medians.sort()
ci_lo = pct_r7(medians, 0.025)
ci_hi = pct_r7(medians, 0.975)

print(json.dumps({
    'n': n,
    'min': round(min(vals), 2),
    'max': round(max(vals), 2),
    'median': round(median, 2),
    'mean': round(mean, 2),
    'std': round(std, 2),
    'cv_pct': round(cv, 1),
    'p25': round(p25, 2),
    'p75': round(p75, 2),
    'iqr': round(p75 - p25, 2),
    'p95': round(pct_r7(vals, 0.95), 2),
    'p99': round(pct_r7(vals, 0.99), 2),
    'ci_lower': round(ci_lo, 2),
    'ci_upper': round(ci_hi, 2),
}))
"
}

# ─── Main benchmark loop ─────────────────────────────────────
# Store results in temp files (bash 3.2 compatible — no associative arrays).
RESULTS_DIR=$(mktemp -d)
trap "rm -rf $RESULTS_DIR" EXIT

# Warmup (warm mode only).
if [[ "$MODE" == "warm" ]] && [[ "$WARMUP_RUNS" -gt 0 ]]; then
    echo "Warmup ($WARMUP_RUNS runs per editor)..."
    for entry in "${EDITORS[@]}"; do
        app_name=$(echo "$entry" | cut -d'|' -f2)
        bundle_id=$(echo "$entry" | cut -d'|' -f3)
        process_name=$(echo "$entry" | cut -d'|' -f4)
        is_electron=$(echo "$entry" | cut -d'|' -f6)
        cli_cmd=$(echo "$entry" | cut -d'|' -f7)
        clean_args=$(echo "$entry" | cut -d'|' -f8)
        for _ in $(seq 1 "$WARMUP_RUNS"); do
            measure_launch "$app_name" "$process_name" "$cli_cmd" "$clean_args" "$FILE_ABS" "$bundle_id" "$is_electron" > /dev/null 2>&1
        done
    done
    echo "Warmup complete."
    echo ""
fi

editor_index=0
for entry in "${EDITORS[@]}"; do
    display_name=$(echo "$entry" | cut -d'|' -f1)
    app_name=$(echo "$entry" | cut -d'|' -f2)
    bundle_id=$(echo "$entry" | cut -d'|' -f3)
    process_name=$(echo "$entry" | cut -d'|' -f4)
    architecture=$(echo "$entry" | cut -d'|' -f5)
    is_electron=$(echo "$entry" | cut -d'|' -f6)
    cli_cmd=$(echo "$entry" | cut -d'|' -f7)
    clean_args=$(echo "$entry" | cut -d'|' -f8)

    echo "--- $display_name ($architecture) ---"

    timing_values=""
    raw_runs=""

    for ((r=1; r<=RUNS; r++)); do
        # Cold mode: purge filesystem cache.
        if [[ "$MODE" == "cold" ]]; then
            purge 2>/dev/null || true
            sleep 2
        fi

        ms=$(measure_launch "$app_name" "$process_name" "$cli_cmd" "$clean_args" "$FILE_ABS" "$bundle_id" "$is_electron")
        timing_values="$timing_values $ms"

        # Collect raw values for JSON.
        if [[ "$ms" != "TIMEOUT" ]]; then
            if [[ -n "$raw_runs" ]]; then
                raw_runs="${raw_runs},${ms}"
            else
                raw_runs="${ms}"
            fi
        fi

        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Run $r: ${ms}ms"
        else
            printf "  Run %d: %sms\r" "$r" "$ms"
        fi
    done
    if [[ "$VERBOSE" != "true" ]]; then
        echo ""
    fi

    # Memory measurement (single run, app left open for 10s settle).
    killall "$process_name" 2>/dev/null || true
    sleep 1
    launch_editor "$app_name" "$process_name" "$cli_cmd" "$clean_args" "$FILE_ABS"
    sleep 10
    mem_result=$(measure_memory "$process_name" "$is_electron")
    phys_mb=$(echo "$mem_result" | cut -d'|' -f1)
    rss_mb=$(echo "$mem_result" | cut -d'|' -f2)
    killall "$process_name" 2>/dev/null || true
    sleep 1

    echo "  Memory: phys=${phys_mb}MB  rss=${rss_mb}MB"

    # Compute timing stats.
    timing_stats=$(compute_stats "$timing_values")
    timing_median=$(echo "$timing_stats" | python3 -c "import json,sys; print(json.load(sys.stdin)['median'])")
    timing_mean=$(echo "$timing_stats" | python3 -c "import json,sys; print(json.load(sys.stdin)['mean'])")
    timing_std=$(echo "$timing_stats" | python3 -c "import json,sys; print(json.load(sys.stdin)['std'])")
    timing_min=$(echo "$timing_stats" | python3 -c "import json,sys; print(json.load(sys.stdin)['min'])")
    timing_max=$(echo "$timing_stats" | python3 -c "import json,sys; print(json.load(sys.stdin)['max'])")
    timing_cv=$(echo "$timing_stats" | python3 -c "import json,sys; print(json.load(sys.stdin)['cv_pct'])")
    timing_n=$(echo "$timing_stats" | python3 -c "import json,sys; print(json.load(sys.stdin)['n'])")
    timing_p25=$(echo "$timing_stats" | python3 -c "import json,sys; print(json.load(sys.stdin)['p25'])")
    timing_p75=$(echo "$timing_stats" | python3 -c "import json,sys; print(json.load(sys.stdin)['p75'])")
    timing_p95=$(echo "$timing_stats" | python3 -c "import json,sys; print(json.load(sys.stdin)['p95'])")
    timing_ci_lo=$(echo "$timing_stats" | python3 -c "import json,sys; print(json.load(sys.stdin)['ci_lower'])")
    timing_ci_hi=$(echo "$timing_stats" | python3 -c "import json,sys; print(json.load(sys.stdin)['ci_upper'])")

    echo "  Timing: median=${timing_median}ms  p25=${timing_p25}ms  p75=${timing_p75}ms  p95=${timing_p95}ms  CI=[${timing_ci_lo}, ${timing_ci_hi}]  CV=${timing_cv}%  n=${timing_n}"

    # Save results to temp files.
    echo "${timing_stats}" > "$RESULTS_DIR/stats_${editor_index}"
    echo "${phys_mb}|${rss_mb}" > "$RESULTS_DIR/memory_${editor_index}"
    echo "${raw_runs}" > "$RESULTS_DIR/raw_runs_${editor_index}"

    editor_index=$((editor_index + 1))
    echo ""
done

# ─── Results table ────────────────────────────────────────────
echo "=== Results ==="
echo ""
printf "%-20s %10s %10s %10s %10s %8s %5s %10s %10s\n" \
    "Editor" "Median(ms)" "p25(ms)" "p75(ms)" "p95(ms)" "CV(%)" "n" "Phys(MB)" "RSS(MB)"
printf "%-20s %10s %10s %10s %10s %8s %5s %10s %10s\n" \
    "--------------------" "----------" "----------" "----------" "----------" "--------" "-----" "----------" "----------"

editor_index=0
for entry in "${EDITORS[@]}"; do
    display_name=$(echo "$entry" | cut -d'|' -f1)
    if [[ -f "$RESULTS_DIR/stats_${editor_index}" ]]; then
        stats_json=$(cat "$RESULTS_DIR/stats_${editor_index}")
        med=$(echo "$stats_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['median'])")
        p25=$(echo "$stats_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['p25'])")
        p75=$(echo "$stats_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['p75'])")
        p95=$(echo "$stats_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['p95'])")
        cv=$(echo "$stats_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['cv_pct'])")
        n=$(echo "$stats_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['n'])")
        IFS='|' read -r phys rss < "$RESULTS_DIR/memory_${editor_index}"
        printf "%-20s %10s %10s %10s %10s %8s %5s %10s %10s\n" \
            "$display_name" "$med" "$p25" "$p75" "$p95" "$cv" "$n" "$phys" "$rss"
    fi
    editor_index=$((editor_index + 1))
done

echo ""
echo "Note: Times measure process launch -> window visible (osascript polling, ~50ms resolution)."
echo "For precise render-complete timing, use: scripts/kern-bench/"

# ─── JSON output ──────────────────────────────────────────────
if [[ -n "$JSON_PATH" ]]; then
    # Capture end thermal.
    THERMAL_PCT_END=$(pmset -g therm 2>/dev/null | grep CPU_Speed_Limit | awk -F'=' '{print $2}' | tr -d ' ')
    if [[ -z "$THERMAL_PCT_END" ]]; then
        THERMAL_PCT_END=$THERMAL_PCT
    fi

    # Build JSON via Python, reading from temp result files.
    RESULTS_JSON=""
    editor_index=0
    for entry in "${EDITORS[@]}"; do
        display_name=$(echo "$entry" | cut -d'|' -f1)
        architecture=$(echo "$entry" | cut -d'|' -f5)
        if [[ -f "$RESULTS_DIR/stats_${editor_index}" ]]; then
            stats_json=$(cat "$RESULTS_DIR/stats_${editor_index}")
            IFS='|' read -r phys rss < "$RESULTS_DIR/memory_${editor_index}"
            raw_runs=$(cat "$RESULTS_DIR/raw_runs_${editor_index}")
            phys_val="$phys"
            if [[ "$phys_val" == "null" ]]; then
                phys_val="None"
            fi
            RESULTS_JSON="${RESULTS_JSON}
raw_runs_str = '${raw_runs}'
raw_vals = [float(x) for x in raw_runs_str.split(',') if x.strip()] if raw_runs_str.strip() else []
runs_list = [{'window_visible_ms': v, 'memory_phys_mb': ${phys_val}, 'memory_rss_mb': ${rss}} for v in raw_vals]
report['results'].append({
    'editor': '${display_name}',
    'architecture': '${architecture}',
    'runs': runs_list,
    'stats': {
        'window_visible': ${stats_json},
        'memory_phys_mb': ${phys_val},
        'memory_rss_mb': ${rss}
    }
})"
        fi
        editor_index=$((editor_index + 1))
    done

    python3 -c "
import json

report = {
    'version': 3,
    'tool': 'cross-editor-benchmark.sh',
    'timestamp': '$(date -u '+%Y-%m-%dT%H:%M:%SZ')',
    'environment': {
        'chip': '${CHIP}',
        'macos': '${MACOS}',
        'power': '${POWER}',
        'thermal_pct': ${THERMAL_PCT},
        'thermal_pct_end': ${THERMAL_PCT_END}
    },
    'config': {
        'file': '${FILE}',
        'file_bytes': ${FILE_SIZE},
        'file_lines': ${FILE_LINES},
        'file_hash': '${FILE_HASH}',
        'mode': '${MODE}',
        'runs': ${RUNS},
        'warmup_runs': ${WARMUP_RUNS},
        'editor_order': 'sequential'
    },
    'results': []
}
${RESULTS_JSON}
with open('${JSON_PATH}', 'w') as f:
    json.dump(report, f, indent=2)
print('JSON results written to: ${JSON_PATH}')
"
fi
