#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="${SCRIPT_DIR}/../ccc"
ARCH="${ARCH:-riscv64-purecap}"

if [ ! -d "${SCRIPT_DIR}/bzip2" ]; then
    git clone https://github.com/libarchive/bzip2.git "${SCRIPT_DIR}/bzip2"
fi

cd "${SCRIPT_DIR}/bzip2"
git stash 2>/dev/null || true
git checkout 962d606

make clean 2>/dev/null || true
make CC="${CCC} ${ARCH}" AR="llvm-ar" RANLIB="llvm-ranlib" LDFLAGS="" -j"$(nproc)" || true

echo ""
echo "Build complete:"
file "${SCRIPT_DIR}/bzip2/bzip2recover"
