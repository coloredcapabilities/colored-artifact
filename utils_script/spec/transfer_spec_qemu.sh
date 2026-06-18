#!/bin/sh
# Transfer the prepared SPEC CPU2006 benchmark folders (already reduced via
# spec_folder_reduce_folder.sh and instrumented via automate.py -- same
# steps as the FPGA flow, unchanged) to a running CheriBSD QEMU guest, along
# with the existing run_all_spec_fpga.sh runner script (it's plain shell
# that just looks for <bench>/<bench>.test.fpga.sh and runs them -- nothing
# FPGA-specific about the script itself, so it works as-is under QEMU).
#
# Usage: transfer_spec_qemu.sh [user@host] [-p port]
#   Defaults: root@127.0.0.1 -p 10222 (matches transfer_juliet.sh)
#
# Environment:
#   SPEC_BUILD_DIR   cheribuild's build directory for spec2006-riscv64-purecap
#                     (default: $HOME/cheri/build/spec2006-riscv64-purecap-build)
#   REMOTE_SPEC_DIR  destination directory on the guest (default: /root/SPEC)

set -e

SPEC_BUILD_DIR="${SPEC_BUILD_DIR:-$HOME/cheri/build/spec2006-riscv64-purecap-build}"
SPEC_CINT="${SPEC_BUILD_DIR}/External_fpga/SPEC/CINT2006"
REMOTE_SPEC_DIR="${REMOTE_SPEC_DIR:-/root/SPEC}"

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

SSH_TARGET="root@127.0.0.1"
SSH_PORT="${SSH_PORT:-10222}"

for arg in "$@"; do
    case "$arg" in
        -p) ;;
        [0-9]*) SSH_PORT="$arg" ;;
        *@*)    SSH_TARGET="$arg" ;;
    esac
done

SSH_OPTS="-p ${SSH_PORT}"
SCP_OPTS="-r -P ${SSH_PORT}"

if [ ! -d "$SPEC_CINT" ]; then
    echo "ERROR: $SPEC_CINT not found."
    echo "Run spec_folder_reduce_folder.sh and automate.py first (see README.md)."
    exit 1
fi

echo "[*] Transferring SPEC CPU2006 to ${SSH_TARGET}:${SSH_PORT} ..."
ssh ${SSH_OPTS} "${SSH_TARGET}" mkdir -p "${REMOTE_SPEC_DIR}/CINT2006"

for bench in $BENCHMARKS; do
    src="${SPEC_CINT}/${bench}"
    if [ -d "$src" ]; then
        echo "  -> ${bench}"
        scp ${SCP_OPTS} "$src" "${SSH_TARGET}:${REMOTE_SPEC_DIR}/CINT2006/"
    else
        echo "  (skip) ${bench}: not found at ${src}"
    fi
done

scp ${SCP_OPTS} "$(dirname "$0")/run_all_spec_fpga.sh" "${SSH_TARGET}:${REMOTE_SPEC_DIR}/"

echo ""
echo "[OK] Done. SSH into the guest and run:"
echo "    ssh ${SSH_OPTS} ${SSH_TARGET}"
echo "    cd ${REMOTE_SPEC_DIR}/CINT2006"
echo "    sh ${REMOTE_SPEC_DIR}/run_all_spec_fpga.sh ${REMOTE_SPEC_DIR}/CINT2006"
