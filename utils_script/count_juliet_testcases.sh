#!/bin/sh
# Count Juliet CWE-415/416 test cases at each stage of the pipeline: source
# test case names vs actually-built binaries. Run this on the HOST/container
# where utils_script/juliet_install.sh was run (NOT inside the QEMU/FPGA
# guest) -- it reads $CHERI_ROOT/juliet-test-suite directly, no SSH needed.
#
# Use this to isolate whether a shortfall (e.g. fewer entries in a collected
# *.run file than expected) happened at build time (binary never got built)
# or later, at transfer/run time.
#
# Usage: count_juliet_testcases.sh

set -e

CHERI_ROOT="${CHERI_ROOT:-$HOME/cheri}"
JULIET_DIR="${CHERI_ROOT}/juliet-test-suite"

if [ ! -d "$JULIET_DIR" ]; then
    echo "ERROR: $JULIET_DIR not found. Run utils_script/juliet_install.sh first."
    exit 1
fi

# count_source_names <testcases_dir> -> unique test-case count
# Mirrors CMakeLists.txt's own logic for deriving one test case per source
# group: EXECUTABLE_NAME = ^CWE[0-9]+_.+__.+_[0-9][0-9], excluding Windows-only
# sources (w32/wchar_t), which CMakeLists.txt also excludes from the build.
count_source_names() {
    [ -d "$1" ] || { echo 0; return; }
    find "$1" -type f \( -name 'CWE*.c' -o -name 'CWE*.cpp' \) 2>/dev/null \
        | grep -viE 'w32|wchar_t' \
        | xargs -n1 basename 2>/dev/null \
        | grep -oE '^CWE[0-9]+_.+__.+_[0-9][0-9]' \
        | sort -u | wc -l | tr -d ' '
}

# count_bin <dir> -> number of files (built executables) in it
count_bin() {
    [ -d "$1" ] || { echo 0; return; }
    find "$1" -type f 2>/dev/null | wc -l | tr -d ' '
}

echo "=== Juliet CWE-415/416 Test Case Counts ==="
echo ""
printf "%-10s %-12s %-12s %-12s\n" "CWE" "Source" "Built good" "Built bad"
printf '%s\n' "------------------------------------------------------------"

total_src=0
total_good=0
total_bad=0

for pair in "CWE415_Double_Free:CWE415" "CWE416_Use_After_Free:CWE416"; do
    src_subdir="${pair%%:*}"
    label="${pair##*:}"

    src_count=$(count_source_names "${JULIET_DIR}/testcases/${src_subdir}")
    good_count=$(count_bin "${JULIET_DIR}/bin/${label}/good")
    bad_count=$(count_bin "${JULIET_DIR}/bin/${label}/bad")

    printf "%-10s %-12s %-12s %-12s\n" "$label" "$src_count" "$good_count" "$bad_count"

    total_src=$((total_src + src_count))
    total_good=$((total_good + good_count))
    total_bad=$((total_bad + bad_count))
done

printf '%s\n' "------------------------------------------------------------"
printf "%-10s %-12s %-12s %-12s\n" "TOTAL" "$total_src" "$total_good" "$total_bad"

echo ""
echo "Source = unique test-case names found under testcases/ (one good + one"
echo "bad executable expected per name). Built good/bad = files actually"
echo "produced under bin/<CWE>/{good,bad}/. A gap between Source and Built"
echo "means some test cases failed to compile -- check the make log."
