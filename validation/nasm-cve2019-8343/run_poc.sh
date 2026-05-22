#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NASM="${SCRIPT_DIR}/nasm/nasm"
POC="${SCRIPT_DIR}/poc.asm"

echo "=== CVE-2019-8343: nasm Use-After-Free ==="
echo "UAF at paste_tokens (asm/preproc.c:3820)"
echo ""

if [ ! -x "$NASM" ]; then
    echo "ERROR: nasm binary not found. Run build.sh first."
    exit 1
fi

echo "Running PoC..."
"$NASM" "$POC" 2>&1
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
