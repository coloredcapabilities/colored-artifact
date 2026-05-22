#!/bin/sh
# Run the nasm CVE-2017-10686 UAF PoC on CheriBSD.
# UAF at detoken (asm/preproc.c:1289) — accessing t->text after nasm_free().
# On purecap CheriBSD, the dangling pointer dereference should trigger
# a capability violation.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NASM="${SCRIPT_DIR}/nasm/nasm"
POC="${SCRIPT_DIR}/POC1"

echo "=== CVE-2017-10686: nasm Use-After-Free ==="
echo "UAF at detoken (asm/preproc.c:1289)"
echo ""

if [ ! -x "$NASM" ]; then
    echo "ERROR: nasm binary not found. Run build.sh first."
    exit 1
fi

echo "Running PoC..."
"$NASM" -f bin "$POC" -o /dev/null 2>&1
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
