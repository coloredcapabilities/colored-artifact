#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="${SCRIPT_DIR}/../ccc"
ARCH="${ARCH:-riscv64-purecap}"

if [ ! -d "${SCRIPT_DIR}/nasm" ]; then
    cd /tmp
    git clone https://github.com/netwide-assembler/nasm.git nasm-cve2017
    cd nasm-cve2017
    git checkout 7a81ead
    patch -p1 < "${SCRIPT_DIR}/patch.diff"
    # autogen.sh may not install config.guess/config.sub
    ./autogen.sh
    for f in config.guess config.sub; do
        if [ ! -f "$f" ]; then
            cp /usr/share/automake-*/$(basename $f) . 2>/dev/null || true
        fi
    done
    # Cross-compile configure cannot run test binaries — bypass ANSI header check
    sed -i 's/as_fn_error \$? "Standard (ANSI\/ISO C89) header files are required."/: #/' configure
    CC="${CCC} ${ARCH}" ./configure --host=riscv64-unknown-freebsd
    make nasm -j"$(nproc)"
    mv "${PWD}" "${SCRIPT_DIR}/nasm"
    cd /tmp
fi

echo ""
echo "Build complete:"
file "${SCRIPT_DIR}/nasm/nasm"
