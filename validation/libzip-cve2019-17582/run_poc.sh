#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPTOOL="${SCRIPT_DIR}/libzip/build/src/ziptool"
POC="${SCRIPT_DIR}/poc"

echo "=== CVE-2019-17582: libzip Use-After-Free ==="
echo "UAF at _zip_buffer_free (zip_buffer.c:53)"
echo ""

if [ ! -x "$ZIPTOOL" ]; then
    echo "ERROR: ziptool binary not found. Run build.sh first."
    exit 1
fi

echo "Running PoC..."
"$ZIPTOOL" "$POC" cat index 2>&1
ret=$?

echo ""
if [ $ret -eq 255 ]; then
    echo "RESULT: DETECTED (allocator abort — double-free/UAF caught)"
elif [ $ret -eq 0 ]; then
    echo "RESULT: VULNERABLE (no crash — UAF went undetected)"
elif [ $ret -gt 128 ]; then
    sig=$((ret - 128))
    echo "RESULT: DETECTED (killed by signal $sig)"
    case $sig in
        10) echo "  -> SIGBUS: likely CHERI capability violation" ;;
        11) echo "  -> SIGSEGV: memory fault" ;;
        34) echo "  -> SIGPROT: CHERI capability fault" ;;
        6)  echo "  -> SIGABRT: assertion/abort" ;;
        *)  echo "  -> signal $sig" ;;
    esac
else
    echo "RESULT: CRASHED (exit code $ret)"
fi
