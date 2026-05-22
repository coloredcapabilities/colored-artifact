#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="${SCRIPT_DIR}/../ccc"
ARCH="${ARCH:-riscv64-purecap}"

if [ ! -f "${SCRIPT_DIR}/libredwg/programs/dwgrewrite" ]; then
    cd /tmp
    git clone https://github.com/LibreDWG/libredwg.git libredwg-build
    cd libredwg-build
    git checkout f2dea29

    autoreconf -fi

    # Init submodules for jsmn (needed by write support)
    git submodule update --init

    CC="${CCC} ${ARCH}" \
    CFLAGS="-O2 -g -Wno-error" \
    ./configure --host=riscv64-unknown-freebsd \
        --disable-shared --enable-static \
        --disable-dxf \
        --without-pcre2

    make -j"$(nproc)" -C src
    make -j"$(nproc)" -C programs dwgrewrite

    # Move built tree
    rm -rf "${SCRIPT_DIR}/libredwg"
    mv /tmp/libredwg-build "${SCRIPT_DIR}/libredwg"
fi

echo ""
echo "Build complete:"
file "${SCRIPT_DIR}/libredwg/programs/dwgrewrite"
