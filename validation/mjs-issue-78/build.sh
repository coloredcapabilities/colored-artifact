#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="${SCRIPT_DIR}/../ccc"
ARCH="${ARCH:-riscv64-purecap}"

if [ ! -d "${SCRIPT_DIR}/mjs" ]; then
    cd /tmp
    rm -rf mjs-issue78
    git clone https://github.com/cesanta/mjs.git mjs-issue78
    cd mjs-issue78
    git checkout 9eae0e6
    # CHERI purecap port. mjs stores heap pointers as 48-bit ints inside
    # 64-bit NaN-boxed values and rebuilds them with integer->pointer casts,
    # which are untagged on purecap. Unpatched, mjs tag-faults on the FIRST
    # object access for any input (a false positive) and never reaches the
    # real CVE use-after-free. The patch recovers full capabilities for
    # object pointers (get_ptr side-table), preserves tags in the GC mark
    # bits, and rebuilds the string-GC slot chain. All changes are guarded by
    # __CHERI_PURE_CAPABILITY__, so a native build is unaffected.
    git apply "${SCRIPT_DIR}/cheri-port.patch"
    ${CCC} ${ARCH} -DMJS_MAIN mjs.c -g -o mjs-bin
    mv /tmp/mjs-issue78 "${SCRIPT_DIR}/mjs"
else
    cd "${SCRIPT_DIR}/mjs"
    ${CCC} ${ARCH} -DMJS_MAIN mjs.c -g -o mjs-bin
fi

echo ""
echo "Build complete:"
file "${SCRIPT_DIR}/mjs/mjs-bin"
