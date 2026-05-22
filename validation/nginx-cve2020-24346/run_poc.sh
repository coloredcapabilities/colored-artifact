#!/bin/sh
# Run the nginx njs CVE-2020-24346 UAF PoC on CheriBSD.
# UAF at njs_json_parse_iterator_call (src/njs_json.c:1030) — accessing
# a value pointer after njs_function_apply() caused a fast array to object
# conversion, freeing the original backing store.
# On purecap CheriBSD, the dangling pointer dereference should trigger
# a capability violation.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NJS="${SCRIPT_DIR}/njs/build/njs"
POC="${SCRIPT_DIR}/poc.js"

echo "=== CVE-2020-24346: nginx njs Use-After-Free ==="
echo "UAF at njs_json_parse_iterator_call (njs_json.c:1030)"
echo ""

if [ ! -x "$NJS" ]; then
    echo "ERROR: njs binary not found. Run build.sh first."
    exit 1
fi

echo "Running PoC..."
"$NJS" "$POC" 2>&1
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
