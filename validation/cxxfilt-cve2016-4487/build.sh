#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="${SCRIPT_DIR}/../ccc"
ARCH="${ARCH:-riscv64-purecap}"

if [ ! -f "${SCRIPT_DIR}/binutils/cxxfilt" ]; then
    cd /tmp
    git clone https://sourceware.org/git/binutils-gdb.git cxxfilt-build
    cd cxxfilt-build
    git checkout 2c49145

    # Build libiberty (contains the vulnerable cplus-dem.c)
    cd libiberty
    sed -i '1i #include <limits.h>' fibheap.c
    sed -i '1i #include <fcntl.h>' pex-unix.c
    CC="${CCC} ${ARCH}" CFLAGS="-O2 -g -Wno-error" ./configure --host=riscv64-unknown-freebsd
    make -j"$(nproc)"
    cd ..

    # Build standalone cxxfilt driver against libiberty
    cat > cxxfilt-standalone.c << 'SRCEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "demangle.h"
int main(int argc, char **argv) {
    int flags = DMGL_PARAMS | DMGL_ANSI | DMGL_VERBOSE;
    char buf[32768];
    if (argc > 1) {
        for (int i = 1; i < argc; i++) {
            char *result = cplus_demangle(argv[i], flags);
            if (result) { printf("%s\n", result); free(result); }
            else printf("%s\n", argv[i]);
        }
    } else {
        while (fgets(buf, sizeof(buf), stdin)) {
            size_t len = strlen(buf);
            if (len > 0 && buf[len-1] == '\n') buf[len-1] = '\0';
            char *result = cplus_demangle(buf, flags);
            if (result) { printf("%s\n", result); free(result); }
            else printf("%s\n", buf);
        }
    }
    return 0;
}
SRCEOF

    ${CCC} ${ARCH} -O2 -g -Wno-error -I include \
        cxxfilt-standalone.c libiberty/libiberty.a -o cxxfilt
    mv /tmp/cxxfilt-build "${SCRIPT_DIR}/binutils"
fi

echo ""
echo "Build complete:"
file "${SCRIPT_DIR}/binutils/cxxfilt"
