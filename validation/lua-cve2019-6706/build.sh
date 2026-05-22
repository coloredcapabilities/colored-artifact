#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="${SCRIPT_DIR}/../ccc"
ARCH="${ARCH:-riscv64-purecap}"
CHERI_SDK="${HOME}/cheri/output/sdk"

if [ ! -d "${SCRIPT_DIR}/lua" ]; then
    cd /tmp
    git clone https://github.com/lua/lua.git lua-cve2019
    cd lua-cve2019
    git checkout af35c7f398
    make CC="${CCC} ${ARCH}" AR="${CHERI_SDK}/bin/llvm-ar rcu" RANLIB="${CHERI_SDK}/bin/llvm-ranlib" \
        MYCFLAGS="-DLUA_USE_POSIX -DLUA_USE_DLOPEN" MYLIBS="-ldl" -j"$(nproc)"
    mv /tmp/lua-cve2019 "${SCRIPT_DIR}/lua"
fi

echo ""
echo "Build complete:"
file "${SCRIPT_DIR}/lua/lua"
