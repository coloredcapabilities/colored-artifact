#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="${SCRIPT_DIR}/../ccc"
ARCH="${ARCH:-riscv64-purecap}"

if [ ! -d "${SCRIPT_DIR}/mjs" ]; then
    git clone https://github.com/cesanta/mjs.git "${SCRIPT_DIR}/mjs"
fi

cd "${SCRIPT_DIR}/mjs"
git stash 2>/dev/null || true
git checkout e4ea33a

"${CCC}" ${ARCH} -DMJS_MAIN mjs.c -g -o mjs-bin

echo ""
echo "Build complete:"
file "${SCRIPT_DIR}/mjs/mjs-bin"
