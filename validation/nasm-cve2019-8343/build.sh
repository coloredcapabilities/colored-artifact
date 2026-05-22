#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="${SCRIPT_DIR}/../ccc"
ARCH="${ARCH:-riscv64-purecap}"

if [ ! -d "${SCRIPT_DIR}/nasm" ]; then
    cd /tmp
    wget -q https://www.nasm.us/pub/nasm/releasebuilds/2.14.02/nasm-2.14.02.tar.gz
    tar -xzf nasm-2.14.02.tar.gz
    cd nasm-2.14.02
    # Bypass ANSI header check for cross-compilation
    sed -i 's/as_fn_error \$? "Standard (ANSI\/ISO C89) header files are required."/: #/' configure
    CC="${CCC} ${ARCH}" ./configure --host=riscv64-unknown-freebsd
    make nasm -j"$(nproc)"
    mv /tmp/nasm-2.14.02 "${SCRIPT_DIR}/nasm"
    cd /tmp && rm -f nasm-2.14.02.tar.gz
fi

echo ""
echo "Build complete:"
file "${SCRIPT_DIR}/nasm/nasm"
