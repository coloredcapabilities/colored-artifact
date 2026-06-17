#!/bin/sh
# Build CoreMark bare-metal ELFs for Bluespec simulation.
#
# Requires the CHERI SDK with baremetal newlib/compiler-rt, built via cheribuild:
#   cd $CHERIBUILD
#   ./cheribuild.py newlib-baremetal-riscv64-purecap
#   ./cheribuild.py compiler-rt-builtins-baremetal-riscv64-purecap
#   ./cheribuild.py newlib-baremetal-riscv64
#   ./cheribuild.py compiler-rt-builtins-baremetal-riscv64
#
# If you don't want to build the SDK, pre-built ELFs are included under
#   benchmarks/coremark/ and run_coremark_for_sim.sh will use them directly.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/benchmarks/coremark"
BUILD_LOGS="${SCRIPT_DIR}/build_logs"

CHERI_ROOT="${CHERI_ROOT:-$HOME/cheri}"
SDK="${CHERI_ROOT}/output/sdk"
LLVM_BIN="${SDK}/bin"
SYSROOT_PURECAP="${SDK}/baremetal/baremetal-newlib-riscv64-purecap/riscv64-unknown-elf"
SYSROOT_BASELINE="${SDK}/baremetal/baremetal-newlib-riscv64/riscv64-unknown-elf"

# Coremark source — cloned from EEMBC
COREMARK_SRC="${CHERI_ROOT}/coremark"

mkdir -p "${OUT_DIR}" "${BUILD_LOGS}"

echo "=== CoreMark build script ==="

# Clone CoreMark source if not present
if [ ! -d "${COREMARK_SRC}" ]; then
    echo "[*] Cloning CoreMark source..."
    git clone https://github.com/eembc/coremark.git "${COREMARK_SRC}"
fi

# Build helper: compile CoreMark for a given target
build_coremark() {
    config="$1"     # "purecap" or "baseline"
    target="$2"     # riscv64
    march="$3"      # rv64gcxcheri or rv64gc
    mabi="$4"       # l64pc128 or lp64
    sysroot="$5"
    extra_flags="$6"
    out_elf="${OUT_DIR}/coremark_${config}.elf"
    log="${BUILD_LOGS}/build_${config}.log"

    printf "[*] Building CoreMark (%s)..." "$config"
    t0=$(date +%s)

    cd "${COREMARK_SRC}"
    COMMON_FLAGS="-mcmodel=medium -mno-relax \
        --sysroot=${sysroot} \
        -target ${target} -march=${march} -mabi=${mabi} \
        ${extra_flags} \
        -DCLOCKS_PER_SEC=25000000 -DUART_BAUD_RATE=115200 \
        -DPERFORMANCE_RUN=1 \
        -O3 -static -std=gnu99 -ffast-math \
        -fno-common -fno-builtin-printf -fno-builtin-memset \
        -I./riscv-common \
        -nostartfiles -lm -lc \
        -T ./riscv-common/p3_fpga.ld -fuse-ld=lld"

    SRCS="core_list_join.c core_main.c core_matrix.c core_state.c core_util.c \
          riscv-common/ee_printf.c riscv-common/syscalls.c riscv-common/start.S"

    # shellcheck disable=SC2086
    "${LLVM_BIN}/clang" ${COMMON_FLAGS} ${SRCS} -o "${out_elf}" > "${log}" 2>&1

    t1=$(date +%s)
    echo " done: ${out_elf}  (log: ${log}, took $((t1 - t0))s)"
}

build_coremark "baseline" "riscv64" "rv64gc" "lp64" \
    "${SYSROOT_BASELINE}" ""

build_coremark "purecap" "riscv64" "rv64gcxcheri" "l64pc128" \
    "${SYSROOT_PURECAP}" "-mno-xcheri-rvc"

echo "=== All builds finished successfully ==="
