#!/bin/sh
#
# Run all SPEC CPU2006 FPGA benchmarks used in the paper.
# Usage (on the FPGA / CheriBSD):
#   sh run_all_spec_fpga.sh [SPEC_BASE_DIR]
#
# SPEC_BASE_DIR defaults to the current working directory, e.g.:
#   sh run_all_spec_fpga.sh /bench/SPEC/CINT2006
#
# Each benchmark's results go into <bench>/<bench>_OUTPUT/
#   - .time files (timing from time -l)
#   - .mcs  files (hardware counters from minimal_count_stats)

SPEC_BASE=${1:-$(pwd)}

BENCHMARKS="
401.bzip2
445.gobmk
456.hmmer
458.sjeng
462.libquantum
464.h264ref
471.omnetpp
483.xalancbmk
"

echo "========================================"
echo "SPEC CPU2006 FPGA Benchmark Runner"
echo "Base directory: ${SPEC_BASE}"
echo "========================================"
echo ""

for bench in $BENCHMARKS; do
    script="${SPEC_BASE}/${bench}/${bench}.test.fpga.sh"

    if [ ! -f "$script" ]; then
        echo "[SKIP] ${bench} - script not found: ${script}"
        echo ""
        continue
    fi

    echo "========================================"
    echo "[RUN] ${bench}"
    echo "========================================"
    sh "$script"
    echo "[DONE] ${bench} - results in ${bench}/${bench}_OUTPUT/"
    echo ""
done

echo "========================================"
echo "All benchmarks finished."
echo "========================================"
