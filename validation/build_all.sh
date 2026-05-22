#!/bin/sh
# Build all CVE validation test cases for CheriBSD purecap.
#
# Usage:
#   ./build_all.sh          # build all
#   ./build_all.sh nasm lua # build only matching directories

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Prevent VS Code git credential helper from intercepting
unset GIT_ASKPASS
unset SSH_ASKPASS
export GIT_TERMINAL_PROMPT=1

DIRS="
bzip2-cve2016-3189
cxxfilt-cve2016-4487
libredwg-cve2022-35164
libzip-cve2019-17582
lua-cve2019-6706
mjs-issue-73
mjs-issue-78
nasm-cve2017-10686
nasm-cve2019-8343
nginx-cve2020-24346
yasm-issue-91
"

# Filter if arguments given
if [ $# -gt 0 ]; then
    FILTERED=""
    for arg in "$@"; do
        for d in $DIRS; do
            case "$d" in *"$arg"*) FILTERED="$FILTERED $d" ;; esac
        done
    done
    DIRS="$FILTERED"
fi

# Clean up leftover temp dirs from failed builds
rm -rf /tmp/libredwg-build /tmp/lua-cve2019 /tmp/libzip-1.2.0 \
       /tmp/libzip-1.2.0.tar.gz /tmp/cxxfilt-build /tmp/nasm-cve2019 \
       /tmp/nasm-build /tmp/cheri-toolchain.cmake /tmp/njs-cve2020 \
       /tmp/mjs-issue78 /tmp/recutils-1.8*

total=0
success=0
failed=""

echo "=== Building CVE Validation Suite ==="
echo ""

for name in $DIRS; do
    [ -z "$name" ] && continue
    dir="${SCRIPT_DIR}/${name}"

    if [ ! -x "${dir}/build.sh" ]; then
        echo "[SKIP] $name — no build.sh"
        continue
    fi

    total=$((total + 1))
    echo "[BUILD] $name ..."

    cd "$dir"
    if ./build.sh > "${dir}/build.log" 2>&1; then
        echo "  [OK]"
        success=$((success + 1))
    else
        echo "  [FAIL] see ${dir}/build.log"
        failed="${failed} ${name}"
    fi
done

echo ""
echo "=== Build Summary ==="
echo "Total: $total | Success: $success | Failed: $((total - success))"
if [ -n "$failed" ]; then
    echo ""
    echo "Failed:"
    for f in $failed; do
        echo "  - $f"
    done
fi
