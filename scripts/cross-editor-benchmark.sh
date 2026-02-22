#!/usr/bin/env bash
# cross-editor-benchmark.sh — Stable entrypoint wrapper for kern-bench dual suites.

set -euo pipefail
cd "$(dirname "$0")/.."

SUITE="wow"
FILE=""
RUNS=""
WARMUP_RUNS=""
STARTUP_PROBES=""
MODE="warm"
JSON_PATH=""
MARKDOWN_PATH=""
EDITORS_FILTER=""
EDITOR_ARGS=()
EXPLICIT_ALL=false
TIMEOUT=""
RUN_TIMEOUT=""
SUITE_TIMEOUT=""
INTER_EDITOR_DELAY_MS=""
VERBOSE=false
NO_SCREENCAPTURE=false
ENABLE_FRAME_MONITOR=false
SAVE_DURABLE=false

cleanup_editors() {
  local app_names=("Kern" "Visual Studio Code" "Zed" "Sublime Text" "TextEdit")
  local process_names=("Kern" "Code" "zed" "sublime_text" "TextEdit")
  local bundle_ids=("com.gradigit.kern" "com.microsoft.VSCode" "dev.zed.Zed" "com.sublimetext.4" "com.apple.TextEdit")

  for name in "${app_names[@]}"; do
    /usr/bin/killall -9 "$name" >/dev/null 2>&1 || true
  done
  for pname in "${process_names[@]}"; do
    /usr/bin/pkill -9 -x "$pname" >/dev/null 2>&1 || true
  done
  for bid in "${bundle_ids[@]}"; do
    /usr/bin/pkill -9 -f "$bid" >/dev/null 2>&1 || true
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite) SUITE="$2"; shift 2 ;;
    --cold) MODE="cold"; shift ;;
    --warm) MODE="warm"; shift ;;
    --json) JSON_PATH="$2"; shift 2 ;;
    --markdown) MARKDOWN_PATH="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --warmup-runs) WARMUP_RUNS="$2"; shift 2 ;;
    --startup-probes) STARTUP_PROBES="$2"; shift 2 ;;
    --all) EXPLICIT_ALL=true; shift ;;
    --editors) EDITORS_FILTER="$2"; shift 2 ;;
    --editor) EDITOR_ARGS+=("$2"); shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --run-timeout) RUN_TIMEOUT="$2"; shift 2 ;;
    --suite-timeout) SUITE_TIMEOUT="$2"; shift 2 ;;
    --inter-editor-delay-ms) INTER_EDITOR_DELAY_MS="$2"; shift 2 ;;
    --save-durable) SAVE_DURABLE=true; shift ;;
    --no-screencapture) NO_SCREENCAPTURE=true; shift ;;
    --enable-frame-monitor) ENABLE_FRAME_MONITOR=true; shift ;;
    --verbose|-v) VERBOSE=true; shift ;;
    --file) FILE="$2"; shift 2 ;;
    --help|-h)
      cat <<'EOF'
Usage: ./scripts/cross-editor-benchmark.sh [options] [file]

Options:
  --suite wow           Benchmark suite (default: wow; real_use aliases to wow)
  --cold                Purge cache between measured runs
  --warm                Warm mode (default)
  --runs N              Measured run count
  --warmup-runs N       Warmup run count
  --startup-probes N    Cold+warm startup probes per editor (default: 0)
  --all                 Benchmark all installed roster editors (default behavior)
  --json PATH           Write JSON report
  --markdown PATH       Write markdown report
  --editors LIST        Comma-separated roster editor names
  --timeout SEC         Per-stage timeout
  --run-timeout SEC     Per editor-run timeout budget
  --suite-timeout SEC   Overall suite timeout budget
  --inter-editor-delay-ms N
                        Delay between editors in a round (default: 0)
  --save-durable      Collect durable-save metric (disabled by default)
  --no-screencapture    Disable ScreenCaptureKit
  --enable-frame-monitor
                        Enable optional first-paint/render-stable probes
  --verbose, -v         Verbose output
  --file PATH           Benchmark fixture file

Policy:
  - Locked roster v1: Kern, VS Code, Zed, Sublime Text, TextEdit
  - Partial runs are not eligible for README/social headline claims
EOF
      exit 0
      ;;
    -* )
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$FILE" ]]; then
        FILE="$1"
      elif [[ -z "$RUNS" ]]; then
        RUNS="$1"
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$FILE" ]]; then
  FILE="test-fixtures/cross-editor-benchmark.md"
fi
if [[ ! -f "$FILE" ]]; then
  echo "Error: file not found: $FILE" >&2
  exit 1
fi

case "$SUITE" in
  wow)
    ;;
  real_use|real-use|realuse)
    echo "Note: --suite $SUITE is deprecated; using wow single-suite mode."
    SUITE="wow"
    ;;
  *)
    echo "Error: --suite must be wow" >&2
    exit 1
    ;;
esac

if [[ ! -x "scripts/kern-bench/.build/release/kern-bench" ]]; then
  echo "Building kern-bench..."
  (cd scripts/kern-bench && swift build -c release)
fi

CMD=("scripts/kern-bench/.build/release/kern-bench" "--suite" "$SUITE" "--file" "$FILE")

if [[ "$MODE" == "cold" ]]; then
  CMD+=("--cold")
else
  CMD+=("--warm")
fi

if [[ -n "$RUNS" ]]; then CMD+=("--runs" "$RUNS"); fi
if [[ -n "$WARMUP_RUNS" ]]; then CMD+=("--warmup-runs" "$WARMUP_RUNS"); fi
if [[ -n "$STARTUP_PROBES" ]]; then CMD+=("--startup-probes" "$STARTUP_PROBES"); fi
if [[ -n "$JSON_PATH" ]]; then
  mkdir -p "$(dirname "$JSON_PATH")"
  CMD+=("--json" "$JSON_PATH")
fi
if [[ -n "$MARKDOWN_PATH" ]]; then
  mkdir -p "$(dirname "$MARKDOWN_PATH")"
  CMD+=("--markdown" "$MARKDOWN_PATH")
fi
if [[ -n "$TIMEOUT" ]]; then CMD+=("--timeout" "$TIMEOUT"); fi
if [[ -n "$RUN_TIMEOUT" ]]; then CMD+=("--run-timeout" "$RUN_TIMEOUT"); fi
if [[ -n "$SUITE_TIMEOUT" ]]; then CMD+=("--suite-timeout" "$SUITE_TIMEOUT"); fi
if [[ -n "$INTER_EDITOR_DELAY_MS" ]]; then CMD+=("--inter-editor-delay-ms" "$INTER_EDITOR_DELAY_MS"); fi
if [[ "$SAVE_DURABLE" == true ]]; then CMD+=("--save-durable"); fi
if [[ "$NO_SCREENCAPTURE" == true ]]; then CMD+=("--no-screencapture"); fi
if [[ "$ENABLE_FRAME_MONITOR" == true ]]; then CMD+=("--enable-frame-monitor"); fi
if [[ "$VERBOSE" == true ]]; then CMD+=("--verbose"); fi

if [[ ${#EDITOR_ARGS[@]} -gt 0 ]]; then
  for editor in "${EDITOR_ARGS[@]}"; do
    CMD+=("--editor" "$editor")
  done
elif [[ -n "$EDITORS_FILTER" ]]; then
  IFS=',' read -ra EDITOR_LIST <<< "$EDITORS_FILTER"
  for editor in "${EDITOR_LIST[@]}"; do
    trimmed="$(echo "$editor" | xargs)"
    if [[ -n "$trimmed" ]]; then
      CMD+=("--editor" "$trimmed")
    fi
  done
elif [[ "$EXPLICIT_ALL" == true ]]; then
  CMD+=("--all")
else
  CMD+=("--all")
fi

trap cleanup_editors INT TERM ERR

echo "=== Cross-Editor Benchmark Wrapper ==="
echo "Suite: $SUITE"
echo "File:  $FILE"
echo "Mode:  $MODE"
echo "Policy: locked roster v1; Official vs Partial classification enforced"
echo "Claims: README/social headline claims require Official runs"
echo ""

set +e
"${CMD[@]}"
status=$?
set -e

if /usr/bin/pgrep -f "com.gradigit.kern|com.microsoft.VSCode|dev.zed.Zed|com.sublimetext.4|com.apple.TextEdit" >/dev/null 2>&1; then
  cleanup_editors
fi

exit "$status"
