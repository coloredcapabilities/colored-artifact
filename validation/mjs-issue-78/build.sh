#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="${SCRIPT_DIR}/../ccc"
ARCH="${ARCH:-riscv64-purecap}"

if [ ! -d "${SCRIPT_DIR}/mjs" ]; then
    cd /tmp
    git clone https://github.com/cesanta/mjs.git mjs-issue78
    cd mjs-issue78
    git checkout 9eae0e6
    ${CCC} ${ARCH} -DMJS_MAIN mjs.c -g -o mjs-bin
    mv /tmp/mjs-issue78 "${SCRIPT_DIR}/mjs"
fi

echo ""
echo "Build complete:"
file "${SCRIPT_DIR}/mjs/mjs-bin"
