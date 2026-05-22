#!/bin/sh
# Run the bzip2 CVE-2016-3189 UAF PoC on CheriBSD.
# On purecap CheriBSD, the UAF should trigger a SIGPROT (capability violation)
# instead of silently succeeding or causing memory corruption.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="${SCRIPT_DIR}/bzip2/bzip2recover"
ARGS="${SCRIPT_DIR}/poc"

echo "=== CVE-2016-3189: bzip2 Use-After-Free ==="
echo "UAF at bsPutBit (bzip2recover.c:182)"
echo ""

if [ ! -x "$BINARY" ]; then
    echo "ERROR: bzip2recover binary not found. Run build.sh first."
    exit 1
fi

# Remove output file if it exists from previous run
rm -f rec00001poc.bz2

echo "Running PoC..."
"$BINARY" $ARGS 2>&1
ret=$?

echo ""
if [ $ret -eq 255 ]; then
    echo "RESULT: DETECTED (allocator abort — double-free/UAF caught)"
elif [ $ret -eq 0 ]; then
    # Check if output file was created (indicates vulnerability was prevented/bypassed)
    if [ -f "rec00001poc.bz2" ]; then
        echo "RESULT: PREVENT (output file created, UAF prevented)"
    else
        echo "RESULT: VULNERABLE (no crash — UAF went undetected)"
    fi
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
