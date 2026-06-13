#!/bin/bash
# Script to run MiBench benchmarks for both Baseline and PICASSO simulators
# Usage: ./run_mibench.sh [--baseline-only|--picasso-only]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/bench_log"
TOOOBA_ROOT="${TOOOBA_ROOT:-/home/ubuntu/cheri/Toooba}"
BUILD_DIR="${TOOOBA_ROOT}/builds/RV64ACDFIMSUxCHERI_Toooba_bluesim"

# Simulator paths
SIM_BASELINE="${SIM_BASELINE:-${BUILD_DIR}/exe_HW_sim_baseline}"
SIM_PICASSO="${SIM_PICASSO:-${BUILD_DIR}/exe_HW_sim}"

# Output log files
BASELINE_LOG="${LOG_DIR}/mibench_baseline_log"
PICASSO_LOG="${LOG_DIR}/mibench_picasso_log"

# Function to run benchmarks and extract results
run_benchmarks() {
    local simulator="$1"
    local output_log="$2"
    local sim_name="$3"
    local logs_dir="${BUILD_DIR}/Logs_${sim_name}"

    echo "========================================"
    echo "Running benchmarks with $sim_name"
    echo "========================================"

    cd "$BUILD_DIR"

    # Clean previous logs
    rm -rf "$logs_dir"
    mkdir -p "$logs_dir"

    # Run Run_benchmarks.py directly (the Makefile's benchmarks target
    # ignores LOGS_DIR/SIM_EXE_FILE and always uses ./exe_HW_sim and ./Logs)
    "${TOOOBA_ROOT}/Tests/Run_benchmarks.py" "$simulator" "${TOOOBA_ROOT}" "$logs_dir" || true

    # Extract results from logs using report_log.sh format
    echo "Extracting results..."
    > "$output_log"

    for logfile in "$logs_dir"/*.bin.log; do
        if [[ -f "$logfile" ]]; then
            # Extract cycles and instructions from instret line
            result=$(tac "$logfile" | grep -m 1 "instret" | sed 's/^instret:\([[:digit:]]*\).*   \([[:digit:]]*\)$/\2, \1/g' 2>/dev/null || echo "0, 0")
            echo "$(basename "$logfile"), $result" >> "$output_log"
        fi
    done

    echo "Results saved to: $output_log"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    local errors=0

    if [[ ! -d "$BUILD_DIR" ]]; then
        echo "ERROR: Build directory not found at $BUILD_DIR"
        errors=1
    fi

    if [[ ! -x "$SIM_BASELINE" ]]; then
        echo "ERROR: Baseline simulator not found at $SIM_BASELINE"
        errors=1
    fi

    if [[ ! -x "$SIM_PICASSO" ]]; then
        echo "ERROR: PICASSO simulator not found at $SIM_PICASSO"
        errors=1
    fi

    if [[ $errors -eq 1 ]]; then
        echo ""
        echo "Please set environment variables or adjust paths:"
        echo "  TOOOBA_ROOT, SIM_BASELINE, SIM_PICASSO"
        exit 1
    fi
}

# Main
main() {
    echo "MiBench Benchmark Runner"
    echo "========================"
    echo ""

    # Parse arguments
    local run_baseline=1
    local run_picasso=1

    while [[ $# -gt 0 ]]; do
        case $1 in
            --baseline-only)
                run_picasso=0
                shift
                ;;
            --picasso-only)
                run_baseline=0
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--baseline-only|--picasso-only]"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    check_prerequisites

    # Create log directory if needed
    mkdir -p "$LOG_DIR"

    # Run benchmarks
    if [[ $run_baseline -eq 1 ]]; then
        run_benchmarks "$SIM_BASELINE" "$BASELINE_LOG" "baseline"
    fi

    if [[ $run_picasso -eq 1 ]]; then
        run_benchmarks "$SIM_PICASSO" "$PICASSO_LOG" "picasso"
    fi

    echo "========================================"
    echo "All benchmarks completed!"
    echo "========================================"
    echo ""

    if [[ $run_baseline -eq 1 && $run_picasso -eq 1 ]]; then
        "${SCRIPT_DIR}/compare_benchmarks.sh" "$BASELINE_LOG" "$PICASSO_LOG"
    else
        echo "To compare results, run:"
        echo "  ./compare_benchmarks.sh"
    fi
}

main "$@"
