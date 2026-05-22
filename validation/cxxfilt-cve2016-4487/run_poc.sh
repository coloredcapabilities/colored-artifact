#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CXXFILT="${SCRIPT_DIR}/binutils/cxxfilt"

echo "=== CVE-2016-4487: cxxfilt Double-Free ==="
echo "DF at register_Btype (cplus-dem.c:4319)"
echo ""

if [ ! -x "$CXXFILT" ]; then
    echo "ERROR: cxxfilt binary not found. Run build.sh first."
    exit 1
fi

echo "Running PoC..."
echo '_Q10-__9cafebabe.' | "$CXXFILT" 2>&1
ret=$?

echo ""
if [ $ret -eq 255 ]; then
    echo "RESULT: DETECTED (allocator abort — double-free/UAF caught)"
elif [ $ret -eq 0 ]; then
    echo "RESULT: VULNERABLE (no crash — double-free went undetected)"
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
