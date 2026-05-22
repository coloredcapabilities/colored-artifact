#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHERI_SDK="${HOME}/cheri/output/sdk"
CHERI_SYSROOT="${CHERI_SDK}/sysroot-riscv64-purecap"

if [ ! -d "${SCRIPT_DIR}/libzip" ]; then
    cd /tmp
    wget -q https://libzip.org/download/libzip-1.2.0.tar.gz
    tar -xzf libzip-1.2.0.tar.gz
    cd libzip-1.2.0

    # Patch: add missing #include <unistd.h> for read()/close()
    if ! grep -q "unistd.h" lib/zip_random_unix.c; then
        sed -i '/#include <fcntl.h>/a #include <unistd.h>' lib/zip_random_unix.c
    fi

    cat > /tmp/cheri-toolchain.cmake << TCEOF
set(CMAKE_SYSTEM_NAME FreeBSD)
set(CMAKE_SYSTEM_PROCESSOR riscv64)
set(CMAKE_C_COMPILER "${CHERI_SDK}/bin/clang")
set(CMAKE_C_FLAGS_INIT "-target riscv64-unknown-freebsd -march=rv64gcxcheri -mabi=l64pc128d -mno-relax")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-fuse-ld=lld")
set(CMAKE_SYSROOT "${CHERI_SYSROOT}")
TCEOF

    # Force static library
    sed -i 's/ADD_LIBRARY(zip SHARED/ADD_LIBRARY(zip STATIC/' lib/CMakeLists.txt

    mkdir -p build && cd build
    cmake .. -DCMAKE_TOOLCHAIN_FILE=/tmp/cheri-toolchain.cmake \
        -DCMAKE_BUILD_TYPE=Release
    make -j"$(nproc)"
    cd /tmp
    mv libzip-1.2.0 "${SCRIPT_DIR}/libzip"
    rm -f libzip-1.2.0.tar.gz /tmp/cheri-toolchain.cmake
fi

echo ""
echo "Build complete:"
file "${SCRIPT_DIR}/libzip/build/src/ziptool"
