#!/bin/sh
# Run CoreMark through the baseline and PICASSO Bluespec simulators and
# print a performance summary table.
#
# Usage: ./run_coremark_for_sim.sh [--baseline-only | --picasso-only]
#
# Environment (all optional — defaults work inside the picasso Docker image):
#   TOOOBA_ROOT   path to Toooba checkout (default: ~/cheri/Toooba)
#   SIM_BASELINE  path to baseline simulator binary
#   SIM_PICASSO   path to PICASSO simulator binary
#   RUNS          number of runs to average (default: 3)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ELF_DIR="${SCRIPT_DIR}/benchmarks/coremark"
LOG_DIR="${SCRIPT_DIR}/logs"

TOOOBA_ROOT="${TOOOBA_ROOT:-$HOME/cheri/Toooba}"
BUILD_DIR="${TOOOBA_ROOT}/builds/RV64ACDFIMSUxCHERI_Toooba_bluesim"
ELF_TO_HEX="${TOOOBA_ROOT}/Tests/elf_to_hex/elf_to_hex"

SIM_BASELINE="${SIM_BASELINE:-${BUILD_DIR}/exe_HW_sim_baseline}"
SIM_PICASSO="${SIM_PICASSO:-${BUILD_DIR}/exe_HW_sim}"

RUNS="${RUNS:-3}"

run_baseline=1
run_picasso=1

for arg in "$@"; do
    case "$arg" in
        --baseline-only) run_picasso=0 ;;
        --picasso-only)  run_baseline=0 ;;
        --help|-h)
            echo "Usage: $0 [--baseline-only | --picasso-only]"
            exit 0
            ;;
    esac
done

# Check prerequisites
check_prereqs() {
    ok=1
    for tool in "$ELF_TO_HEX" "$SIM_BASELINE" "$SIM_PICASSO"; do
        [ -x "$tool" ] || { echo "ERROR: not found or not executable: $tool"; ok=0; }
    done
    for elf in "${ELF_DIR}/coremark_baseline.elf" "${ELF_DIR}/coremark_purecap.elf"; do
        [ -f "$elf" ] || { echo "ERROR: ELF not found: $elf"; ok=0; }
    done
    [ "$ok" -eq 1 ] || { echo ""; echo "Set TOOOBA_ROOT, SIM_BASELINE, or SIM_PICASSO as needed."; exit 1; }
}

# run_sim <sim_binary> <elf_file> <label>
# Runs RUNS times, extracts cycle count ("FAIL <N>") from each, returns the average via stdout.
run_sim() {
    sim="$1"
    elf="$2"
    label="$3"

    printf "[*] Running %s ..." "$label" >&2

    mkdir -p "${LOG_DIR}"
    # Simulator reads Mem.hex from its working directory (BUILD_DIR)
    "${ELF_TO_HEX}" "${elf}" "${BUILD_DIR}/Mem.hex" >&2

    total=0
    i=0
    while [ $i -lt "$RUNS" ]; do
        i=$((i + 1))
        log="${LOG_DIR}/${label}_run${i}.log"
        printf "[*] Running %s (run %d/%d) — log: %s\n" "$label" "$i" "$RUNS" "$log" >&2
        # Write directly to log file so output is inspectable while running
        (cd "$BUILD_DIR" && "${sim}" +tohost > "$log" 2>&1) || true
        # Toooba reports cycle count as "FAIL <N>" via the tohost exit mechanism
        ticks=$(grep -E "FAIL [0-9]+$" "$log" | tail -1 | awk '{print $2}')
        if [ -z "$ticks" ]; then
            printf 'ERROR: no cycle count in %s\n' "$log" >&2
            tail -20 "$log" >&2
            exit 1
        fi
        printf "    -> %s cycles\n" "$ticks" >&2
        total=$((total + ticks))
    done

    avg=$((total / RUNS))
    printf '%s' "$avg"
}

format_int() {
    # Insert thousands separators
    printf '%d' "$1" | sed ':a;s/\B[0-9]\{3\}\b/,&/;ta' 2>/dev/null || printf '%d' "$1"
}

check_prereqs

echo ""
echo "=== CoreMark Performance Summary (Bluespec simulation) ==="
echo ""

baseline_nocap_ticks=""
baseline_purecap_ticks=""
picasso_purecap_ticks=""

if [ "$run_baseline" -eq 1 ]; then
    baseline_nocap_ticks=$(run_sim "$SIM_BASELINE" "${ELF_DIR}/coremark_baseline.elf" "baseline/nocap")
    baseline_purecap_ticks=$(run_sim "$SIM_BASELINE" "${ELF_DIR}/coremark_purecap.elf" "baseline/purecap")
fi

if [ "$run_picasso" -eq 1 ]; then
    picasso_purecap_ticks=$(run_sim "$SIM_PICASSO" "${ELF_DIR}/coremark_purecap.elf" "picasso/purecap")
fi

echo ""
printf "%-28s %-16s %-16s %-12s %s\n" "Simulator" "Config" "Total ticks" "Delta" "Overhead"
printf '%s\n' "$(printf '%.0s-' $(seq 1 88))"

if [ "$run_baseline" -eq 1 ] && [ -n "$baseline_nocap_ticks" ]; then
    delta_purecap=$((baseline_purecap_ticks - baseline_nocap_ticks))
    pct_purecap=$(awk "BEGIN {printf \"%.2f\", ($delta_purecap / $baseline_nocap_ticks) * 100}")
    printf "%-28s %-16s %-16s %-12s %s\n" \
        "CHERI-Toooba (baseline)" "nocap" \
        "$(format_int "$baseline_nocap_ticks")" "-" "-"
    printf "%-28s %-16s %-16s %-12s %s\n" \
        "" "purecap" \
        "$(format_int "$baseline_purecap_ticks")" \
        "$(format_int "$delta_purecap")" "${pct_purecap}%"
fi

if [ "$run_picasso" -eq 1 ] && [ "$run_baseline" -eq 1 ] && [ -n "$picasso_purecap_ticks" ]; then
    delta_picasso=$((picasso_purecap_ticks - baseline_nocap_ticks))
    pct_picasso=$(awk "BEGIN {printf \"%.2f\", ($delta_picasso / $baseline_nocap_ticks) * 100}")
    printf "%-28s %-16s %-16s %-12s %s\n" \
        "CHERI-Toooba (PICASSO)" "purecap" \
        "$(format_int "$picasso_purecap_ticks")" \
        "$(format_int "$delta_picasso")" "${pct_picasso}%"
elif [ "$run_picasso" -eq 1 ] && [ -n "$picasso_purecap_ticks" ]; then
    printf "%-28s %-16s %-16s %-12s %s\n" \
        "CHERI-Toooba (PICASSO)" "purecap" \
        "$(format_int "$picasso_purecap_ticks")" "N/A" "N/A"
fi

echo ""
echo "Note: Simulation ticks differ from FPGA ticks (25 MHz clock). The overhead"
echo "percentage is what corresponds to Table 1 in the paper."
echo ""
