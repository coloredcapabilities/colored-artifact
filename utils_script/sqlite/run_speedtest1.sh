#!/bin/sh
# Build, transfer, run, and collect SQLite's speedtest1 benchmark on a
# running CheriBSD QEMU guest, and report the Cornucopia/MRS revocation
# counters (revoke counter / alloc counter).
#
# IMPORTANT: the revoke/alloc counters only exist if the running CheriBSD
# kernel/userspace was built with patches/mrs_base_revoke_count.patch applied,
# and only print at process exit if CC_DEBUG is set in the environment. They
# are only meaningful for the Cornucopia baseline configuration (standard
# CHERI purecap + MRS software quarantine/revocation) -- PICASSO doesn't go
# through MRS's app_quarantine_revoke_async path at all, so it won't print
# these counters even with CC_DEBUG set.
#
# Usage: run_speedtest1.sh [user@host] [-p port] [--no-build]
#   Defaults: root@127.0.0.1 -p 10222 (matches transfer_juliet.sh)
#   --no-build skips the cheribuild step (use an already-built speedtest1)
#
# Environment:
#   CHERIBUILD        path to cheribuild checkout (default: $HOME/cheri/cheribuild)
#   CHERI_ROOT         path to cheribuild source/output root (default: $HOME/cheri)
#   SQLITE_BUILD_DIR   cheribuild's build directory for sqlite-riscv64-purecap
#                       (default: $CHERI_ROOT/build/sqlite-riscv64-purecap-build,
#                       confirmed via `cheribuild.py sqlite-riscv64-purecap --dump-configuration`)
#   SPEEDTEST1_BIN     path to the built speedtest1 binary on the HOST
#                       (default: $SQLITE_BUILD_DIR/speedtest1)

set -e

CHERIBUILD="${CHERIBUILD:-$HOME/cheri/cheribuild}"
CHERI_ROOT="${CHERI_ROOT:-$HOME/cheri}"
SQLITE_BUILD_DIR="${SQLITE_BUILD_DIR:-${CHERI_ROOT}/build/sqlite-riscv64-purecap-build}"
SPEEDTEST1_BIN="${SPEEDTEST1_BIN:-${SQLITE_BUILD_DIR}/speedtest1}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/speedtest1_logs"

SSH_TARGET="root@127.0.0.1"
SSH_PORT="${SSH_PORT:-10222}"
DO_BUILD=1

for arg in "$@"; do
    case "$arg" in
        -p) ;;
        --no-build) DO_BUILD=0 ;;
        [0-9]*) SSH_PORT="$arg" ;;
        *@*)    SSH_TARGET="$arg" ;;
    esac
done

SSH_OPTS="-p ${SSH_PORT}"
SCP_OPTS="-P ${SSH_PORT}"

if [ "$DO_BUILD" -eq 1 ]; then
    echo "[*] Building SQLite (cheribuild sqlite-riscv64-purecap) ..."
    (cd "$CHERIBUILD" && ./cheribuild.py sqlite-riscv64-purecap -d)
    # speedtest1 isn't part of cheribuild's default build target -- it must
    # be built explicitly from within the configured build directory.
    echo "[*] Building speedtest1 (make speedtest1 in $SQLITE_BUILD_DIR) ..."
    (cd "$SQLITE_BUILD_DIR" && make speedtest1)
fi

if [ ! -f "$SPEEDTEST1_BIN" ]; then
    echo "ERROR: speedtest1 binary not found at $SPEEDTEST1_BIN"
    echo "Set SPEEDTEST1_BIN to override, or pass --no-build after building it yourself."
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
