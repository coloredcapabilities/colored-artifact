#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="${SCRIPT_DIR}/../ccc"
ARCH="${ARCH:-riscv64-purecap}"

if [ ! -d "${SCRIPT_DIR}/yasm" ]; then
    git clone https://github.com/yasm/yasm.git "${SCRIPT_DIR}/yasm"
fi

cd "${SCRIPT_DIR}/yasm"
git stash 2>/dev/null || true
git checkout 6caf151

# Generate configure without running it (autogen.sh runs configure at the end)
autoreconf -fi

# Workaround: configure checks ANSI headers by running a test binary — fails cross-compiling
sed -i 's/as_fn_error \$? "Standard (ANSI\/ISO C89) header files are required."/: #/' configure

CC="${CCC} ${ARCH}" ./configure --host=riscv64-unknown-freebsd

make -j"$(nproc)"

echo ""
echo "Build complete:"
file "${SCRIPT_DIR}/yasm/yasm"
