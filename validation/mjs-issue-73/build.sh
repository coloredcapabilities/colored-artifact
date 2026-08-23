#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="${SCRIPT_DIR}/../ccc"
ARCH="${ARCH:-riscv64-purecap}"

if [ ! -d "${SCRIPT_DIR}/mjs" ]; then
    git clone https://github.com/cesanta/mjs.git "${SCRIPT_DIR}/mjs"
    cd "${SCRIPT_DIR}/mjs"
    git checkout e4ea33a
    # CHERI purecap port. mjs stores heap pointers as 48-bit ints inside
    # 64-bit NaN-boxed values and rebuilds them with integer->pointer casts,
    # which are untagged on purecap. Unpatched, mjs tag-faults on the FIRST
    # object access for any input (a false positive) and never reaches the
    # real CVE use-after-free. The patch recovers full capabilities for
    # object pointers (get_ptr side-table), preserves tags in the GC mark
    # bits, and rebuilds the string-GC slot chain. All changes are guarded by
    # __CHERI_PURE_CAPABILITY__, so a native build is unaffected.
    git apply "${SCRIPT_DIR}/cheri-port.patch"
else
    cd "${SCRIPT_DIR}/mjs"
fi

"${CCC}" ${ARCH} -DMJS_MAIN mjs.c -g -o mjs-bin

echo ""
echo "Build complete:"
file "${SCRIPT_DIR}/mjs/mjs-bin"
