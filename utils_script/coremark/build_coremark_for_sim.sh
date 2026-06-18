#!/bin/sh
# Build CoreMark bare-metal ELFs for Bluespec simulation.
#
# Uses the blinded-cheri-sw coremark port which selects test.ld (base 0x80000000)
# when FPGA=0, making the ELFs compatible with elf_to_hex for simulation.
#
# Must be run where the CHERI SDK is available (e.g. inside picasso-qemu container).
#
# Usage:
#   BLINDED_SW_ROOT=~/cheri/blinded-cheri-sw ./build_coremark_for_sim.sh
#
# Pre-built ELFs are included under benchmarks/coremark/ — only run this script
# if you need to rebuild from source.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/benchmarks/coremark"
LOG_DIR="${SCRIPT_DIR}/build_logs"
mkdir -p "${OUT_DIR}" "${LOG_DIR}"

BLINDED_SW_ROOT="${BLINDED_SW_ROOT:-$HOME/cheri/blinded-cheri-sw}"

if [ ! -f "${BLINDED_SW_ROOT}/Makefile" ]; then
    echo "ERROR: blinded-cheri-sw not found at ${BLINDED_SW_ROOT}"
    echo "Set BLINDED_SW_ROOT or clone git@github.com:blindedcapabilities/blinded-cheri-sw.git"
    exit 1
fi

CORE_FILES="core_list_join.c core_main.c core_matrix.c core_state.c core_util.c"
COMMON_FLAGS="PORT_DIR=riscv-bare-metal GFE_TARGET=P3 FPGA=0 TOOLCHAIN=LLVM ITERATIONS=1"

build_coremark() {
    cheri_flag="$1"
    flavor="$2"
    out_elf="${OUT_DIR}/coremark_${flavor}.elf"
    log="${LOG_DIR}/build_${flavor}.log"

    printf "[*] Building CoreMark (%s)..." "$flavor"
    t0=$(date +%s)

    cd "${BLINDED_SW_ROOT}"
    make clean > /dev/null 2>&1 || true

    if make ${COMMON_FLAGS} CHERI="${cheri_flag}" CORE_FILES="${CORE_FILES}" OUT=coremark \
        > "${log}" 2>&1; then
        mv "${BLINDED_SW_ROOT}/coremark.elf" "${out_elf}"
        t1=$(date +%s)
        echo " done: ${out_elf}  (took $((t1 - t0))s)"
    else
        echo " FAILED"
        tail -20 "${log}"
        exit 1
    fi
}

echo "=== CoreMark build script ==="
build_coremark 0 "baseline"
build_coremark 1 "purecap"
echo "=== All builds finished ==="
