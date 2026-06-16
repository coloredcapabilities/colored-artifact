#!/bin/sh
# Transfer pre-built Juliet binaries to a running CheriBSD guest (QEMU or FPGA)
# and create the required /tmp/in.txt stdin fixture.
#
# Usage: transfer_juliet.sh [user@host] [-p port]
#   Defaults: root@127.0.0.1 -p 10222

set -e

CHERI_ROOT="${CHERI_ROOT:-$HOME/cheri}"
JULIET_DIR="${CHERI_ROOT}/juliet-test-suite"

# Parse args: collect ssh/scp target and port
SSH_TARGET="root@127.0.0.1"
SSH_PORT="${SSH_PORT:-10222}"

for arg in "$@"; do
    case "$arg" in
        -p) ;;          # handled by next iteration
        [0-9]*)         SSH_PORT="$arg" ;;
        *@*)            SSH_TARGET="$arg" ;;
    esac
done

SCP_OPTS="-r -P ${SSH_PORT}"
SSH_OPTS="-p ${SSH_PORT}"

echo "[*] Transferring Juliet test suite to ${SSH_TARGET}:${SSH_PORT} ..."
ssh ${SSH_OPTS} "${SSH_TARGET}" mkdir -p /root/juliet-bin
scp ${SCP_OPTS} \
    "${JULIET_DIR}/bin/CWE415" \
    "${JULIET_DIR}/bin/CWE416" \
    "${JULIET_DIR}/juliet-run.sh" \
    "${SSH_TARGET}:/root/juliet-bin/"

echo "[*] Creating /tmp/in.txt on guest ..."
ssh ${SSH_OPTS} "${SSH_TARGET}" "printf '%0.sA' \$(seq 1 366) > /tmp/in.txt"

echo ""
echo "[✓] Done. SSH into the guest and run:"
echo "    ssh ${SSH_OPTS} ${SSH_TARGET}"
echo "    cd /root/juliet-bin"
echo "    sh juliet-run.sh 415 1s"
echo "    sh juliet-run.sh 416 1s"
