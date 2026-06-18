#!/bin/sh
# Transfer the pre-built speedtest1 binary to a running CheriBSD QEMU guest,
# run it, and report the Cornucopia/MRS revocation counters (revoke counter /
# alloc counter). speedtest1 is already built inside the picasso-qemu image
# (see Dockerfile.qemu) -- this script only transfers and runs it.
#
# IMPORTANT: the revoke/alloc counters only exist if the running CheriBSD
# kernel/userspace was built with patches/mrs_base_revoke_count.patch applied,
# and only print at process exit if CC_DEBUG is set in the environment. They
# are only meaningful for the Cornucopia baseline configuration (standard
# CHERI purecap + MRS software quarantine/revocation) -- PICASSO doesn't go
# through MRS's app_quarantine_revoke_async path at all, so it won't print
# these counters even with CC_DEBUG set.
#
# Usage: run_speedtest1.sh [user@host] [-p port]
#   Defaults: root@127.0.0.1 -p 10222 (matches transfer_juliet.sh)
#
# Environment:
#   CHERI_ROOT        path to cheribuild source/output root (default: $HOME/cheri)
#   SPEEDTEST1_BIN    path to the built speedtest1 binary on the HOST
#                      (default: $CHERI_ROOT/build/sqlite-riscv64-purecap-build/speedtest1,
#                      confirmed via `cheribuild.py sqlite-riscv64-purecap --dump-configuration`)

set -e

CHERI_ROOT="${CHERI_ROOT:-$HOME/cheri}"
SPEEDTEST1_BIN="${SPEEDTEST1_BIN:-${CHERI_ROOT}/build/sqlite-riscv64-purecap-build/speedtest1}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/speedtest1_logs"

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
SCP_OPTS="-P ${SSH_PORT}"

if [ ! -f "$SPEEDTEST1_BIN" ]; then
    echo "ERROR: speedtest1 binary not found at $SPEEDTEST1_BIN"
    echo "Set SPEEDTEST1_BIN to override (it should already be built inside picasso-qemu)."
    exit 1
fi

mkdir -p "$LOG_DIR"

echo "[*] Transferring speedtest1 to ${SSH_TARGET}:${SSH_PORT} ..."
ssh ${SSH_OPTS} "${SSH_TARGET}" mkdir -p /root/sqlite-bench
scp ${SCP_OPTS} "$SPEEDTEST1_BIN" "${SSH_TARGET}:/root/sqlite-bench/speedtest1"
ssh ${SSH_OPTS} "${SSH_TARGET}" chmod +x /root/sqlite-bench/speedtest1

echo "[*] Running speedtest1 on the guest (this can take a while) ..."
LOG_FILE="${LOG_DIR}/speedtest1_$(date +%Y%m%d_%H%M%S).log"
ssh ${SSH_OPTS} "${SSH_TARGET}" \
    'cd /root/sqlite-bench && CC_DEBUG=1 /usr/bin/time -l ./speedtest1' \
    > "$LOG_FILE" 2>&1 || true

echo "[*] Log saved to: $LOG_FILE"
echo ""
echo "=== Cornucopia/MRS Revocation Summary ==="

revoke=$(grep -oE 'revoke counter:[[:space:]]*[0-9]+' "$LOG_FILE" | grep -oE '[0-9]+$' | tail -1)
alloc=$(grep -oE 'alloc counter:[[:space:]]*[0-9]+' "$LOG_FILE" | grep -oE '[0-9]+$' | tail -1)
total=$(grep -oE 'TOTAL\.{2,}[[:space:]]*[0-9.]+s' "$LOG_FILE" | grep -oE '[0-9.]+' | tail -1)

if [ -n "$revoke" ]; then
    printf "Revoke counter: %s\n" "$revoke"
else
    echo "Revoke counter: not found"
    echo "  (kernel needs patches/mrs_base_revoke_count.patch applied, and"
    echo "   this only prints for the Cornucopia baseline config, not PICASSO)"
fi
[ -n "$alloc" ] && printf "Alloc counter:  %s\n" "$alloc"
[ -n "$total" ] && printf "Total time:     %ss\n" "$total"
