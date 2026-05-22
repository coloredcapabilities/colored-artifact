#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DWGREWRITE="${SCRIPT_DIR}/libredwg/programs/dwgrewrite"
POC="${SCRIPT_DIR}/poc"

echo "=== CVE-2022-35164: libredwg Use-After-Free ==="
echo "UAF in dwg_decode_LWPOLYLINE_private"
echo ""

if [ ! -x "$DWGREWRITE" ]; then
    echo "ERROR: dwgrewrite binary not found. Run build.sh first."
    exit 1
fi

echo "Running PoC..."
"$DWGREWRITE" "$POC" /tmp/out.dwg 2>&1
ret=$?

rm -f /tmp/out.dwg

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
