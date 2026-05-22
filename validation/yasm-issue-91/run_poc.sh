#!/bin/sh
# Run the yasm issue-91 UAF PoC on CheriBSD.
# On purecap CheriBSD, the UAF should trigger a SIGPROT (capability violation)
# instead of silently succeeding or causing memory corruption.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="${SCRIPT_DIR}/yasm/yasm"
ARGS="${SCRIPT_DIR}/poc"

echo "=== yasm issue-91: Use-After-Free ==="
echo "UAF at yasm_intnum_destroy (libyasm/intnum.c:415)"
echo ""

if [ ! -x "$BINARY" ]; then
    echo "ERROR: yasm binary not found. Run build.sh first."
    exit 1
fi

echo "Running PoC..."
"$BINARY" $ARGS 2>&1
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
