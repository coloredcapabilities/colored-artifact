#!/bin/sh
# Run all CVE validation tests remotely on CheriBSD via SSH.
#
# Usage:
#   ./run_all_remote.sh [user@host] [-p port]
#   ./run_all_remote.sh root@127.0.0.1 -p 10003

set -e

while [ $# -gt 0 ]; do
    case "$1" in
        *@*)  SSH_USER="$(echo "$1" | cut -d@ -f1)"
              SSH_HOST="$(echo "$1" | cut -d@ -f2)"
              shift ;;
        -p)   SSH_PORT="$2"; shift 2 ;;
        -i)   SSH_KEY="$2"; shift 2 ;;
        *)    shift ;;
    esac
done

SSH_USER="${SSH_USER:-root}"
SSH_HOST="${SSH_HOST:-127.0.0.1}"
SSH_PORT="${SSH_PORT:-10003}"
REMOTE_DIR="/root/validation"

SSH_OPTS="-o StrictHostKeyChecking=no"
if [ -n "$SSH_KEY" ]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi

echo "=== Running CVE Validation Suite on ${SSH_USER}@${SSH_HOST}:${SSH_PORT} ==="
echo ""

ssh $SSH_OPTS -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}" << REMOTEEOF
for d in ${REMOTE_DIR}/*/; do
    echo "--- \$(basename \$d) ---"
    cd \$d && sh run.sh
    echo ""
done
REMOTEEOF
