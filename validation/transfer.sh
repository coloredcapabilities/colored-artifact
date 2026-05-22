#!/bin/sh
# Transfer binaries, PoC files, and run scripts to CheriBSD QEMU.
# After transfer, SSH in and run tests manually.
#
# Usage:
#   ./transfer.sh [user@host] [-p port]
#   ./transfer.sh root@127.0.0.1 -p 10003

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

SSH_BASE="-o StrictHostKeyChecking=no"
if [ -n "$SSH_KEY" ]; then
    SSH_BASE="$SSH_BASE -i $SSH_KEY"
fi
SSH_CMD="ssh -n $SSH_BASE -p ${SSH_PORT} ${SSH_USER}@${SSH_HOST}"
SCP_CMD="scp $SSH_BASE -P ${SSH_PORT}"
SCP_TARGET="${SSH_USER}@${SSH_HOST}"

# ---------------------------------------------------------------------------
# CVE registry: name|binary_path|poc_files|binary_name|run_command
# ---------------------------------------------------------------------------
CVES_FILE=$(mktemp /tmp/cheri-cves-XXXXXX)
cat > "$CVES_FILE" << 'EOF'
bzip2-cve2016-3189|bzip2/bzip2recover|poc|bzip2recover|$BIN $POC
cxxfilt-cve2016-4487|binutils/cxxfilt|poc|cxxfilt|echo '_Q10-__9cafebabe.' | $BIN
libredwg-cve2022-35164|libredwg/programs/dwgrewrite|poc|dwgrewrite|$BIN $POC
libzip-cve2019-17582|libzip/build/src/ziptool|poc|ziptool|$BIN $POC cat index
lua-cve2019-6706|lua/lua|poc.lua|lua|$BIN $POC
mjs-issue-73|mjs/mjs-bin|poc.js|mjs-bin|$BIN -f $POC
mjs-issue-78|mjs/mjs-bin|poc.js|mjs-bin|$BIN -f $POC
nasm-cve2017-10686|nasm/nasm|POC1,POC12,POC3,POC4|nasm|$BIN -f bin $POC -o /dev/null
nasm-cve2019-8343|nasm/nasm|poc.asm|nasm|$BIN $POC
nginx-cve2020-24346|njs/build/njs|poc.js|njs|$BIN $POC
yasm-issue-91|yasm/yasm|poc|yasm|$BIN $POC
EOF

# ---------------------------------------------------------------------------
# Package
# ---------------------------------------------------------------------------
STAGING=$(mktemp -d /tmp/cheri-staging-XXXXXX)
PAYLOAD="/tmp/cheri-payload-$$.tar.gz"
trap 'rm -rf "$STAGING" "$CVES_FILE" "$PAYLOAD"' EXIT

echo "[*] Packaging binaries and PoC files..."

total=0
skipped=""
while IFS='|' read -r name bin_rel poc_list bin_name run_cmd; do
    [ -z "$name" ] && continue

    bin_path="${SCRIPT_DIR}/${name}/${bin_rel}"
    if [ ! -f "$bin_path" ]; then
        skipped="${skipped} ${name}"
        continue
    fi

    mkdir -p "${STAGING}/${name}"
    cp "$bin_path" "${STAGING}/${name}/${bin_name}"

    OLDIFS="$IFS"
    IFS=','
    for poc in $poc_list; do
        if [ -f "${SCRIPT_DIR}/${name}/${poc}" ]; then
            cp "${SCRIPT_DIR}/${name}/${poc}" "${STAGING}/${name}/${poc}"
        fi
    done
    IFS="$OLDIFS"

    first_poc="$(echo "$poc_list" | cut -d',' -f1)"
    second_poc="$(echo "$poc_list" | cut -d',' -f2 -s)"

    cat > "${STAGING}/${name}/run.sh" << RUNEOF
#!/bin/sh
cd "\$(dirname "\$0")"
BIN="./${bin_name}"
POC="./${first_poc}"
POC2="./${second_poc}"
chmod +x "\$BIN"
echo "=== ${name} ==="
echo "Running: ${run_cmd}"
echo ""
${run_cmd} 2>&1
ret=\$?
echo ""
if [ \$ret -eq 255 ]; then
    echo "RESULT: DETECTED (allocator abort — double-free/UAF caught)"
elif [ \$ret -eq 0 ]; then
    echo "RESULT: VULNERABLE (exit 0)"
elif [ \$ret -gt 128 ]; then
    sig=\$((ret - 128))
    echo "RESULT: DETECTED (signal \$sig)"
else
    echo "RESULT: CRASHED (exit \$ret)"
fi
RUNEOF
    chmod +x "${STAGING}/${name}/run.sh"
    total=$((total + 1))
done < "$CVES_FILE"

echo "[+] Packaged ${total} test cases"
if [ -n "$skipped" ]; then
    echo "[!] Skipped (binary not found):${skipped}"
fi

# ---------------------------------------------------------------------------
# Transfer
# ---------------------------------------------------------------------------
echo ""
echo "[*] Connecting to ${SSH_USER}@${SSH_HOST}:${SSH_PORT}..."
$SSH_CMD "rm -rf ${REMOTE_DIR} && mkdir -p ${REMOTE_DIR}"

tar -czf "$PAYLOAD" -C "${STAGING}" .
echo "[*] Transferring (~$(du -sh "$PAYLOAD" | cut -f1))..."
$SCP_CMD "$PAYLOAD" "${SCP_TARGET}:${REMOTE_DIR}/payload.tar.gz"
$SSH_CMD "cd ${REMOTE_DIR} && tar -xzf payload.tar.gz && rm payload.tar.gz && chmod -R +x ."

echo "[+] Transfer complete to ${REMOTE_DIR}"
echo ""
echo "Now SSH in and run tests:"
echo "  ssh ${SSH_USER}@${SSH_HOST} -p ${SSH_PORT}"
echo ""
echo "Then on CheriBSD:"
echo "  cd ${REMOTE_DIR}"
echo ""

# Print cheat sheet
while IFS='|' read -r name bin_rel poc_list bin_name run_cmd; do
    [ -z "$name" ] && continue
    [ ! -f "${SCRIPT_DIR}/${name}/${bin_rel}" ] && continue
    echo "  cd ${REMOTE_DIR}/${name} && sh run.sh"
done < "$CVES_FILE"

echo ""
echo "Or run all at once:"
echo "  for d in ${REMOTE_DIR}/*/; do echo \"--- \$(basename \$d) ---\"; cd \$d && sh run.sh; echo; done"
