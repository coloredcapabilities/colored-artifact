#!/bin/sh
# Collect Juliet test suite *.run result files from a running CheriBSD guest
# (QEMU or FPGA) and report PICASSO's UAF/double-free detection rate.
#
# Usage: collect_juliet_results.sh [user@host] [-p port]
#   Defaults: root@127.0.0.1 -p 10222 (matches transfer_juliet.sh)
#
# Each *.run line is "<testcase-path> <exit-code>" (written by juliet-run.sh,
# see transfer_juliet.sh). Detection convention (README.md "Juliet Test Suite"):
#   CWE415 double-free    bad.run  -> exit 255       = detected
#   CWE416 use-after-free bad.run  -> exit 162 (128+34 SIGPROT) = detected
#   good.run (both CWEs)           -> exit 0 (124 = harmless timeout) = clean

set -e

RESULTS_DIR="${RESULTS_DIR:-$(cd "$(dirname "$0")" && pwd)/juliet_results}"

SSH_TARGET="root@127.0.0.1"
SSH_PORT="${SSH_PORT:-10222}"
for arg in "$@"; do
    case "$arg" in
        -p) ;;
        [0-9]*) SSH_PORT="$arg" ;;
        *@*)    SSH_TARGET="$arg" ;;
    esac
done
SSH_OPTS="-p ${SSH_PORT}"
SCP_OPTS="-P ${SSH_PORT}"

mkdir -p "${RESULTS_DIR}/CWE415" "${RESULTS_DIR}/CWE416"

echo "[*] Collecting Juliet results from ${SSH_TARGET}:${SSH_PORT} ..."
for cwe in CWE415 CWE416; do
    for kind in good bad; do
        remote="/root/juliet-bin/${cwe}/${kind}.run"
        local="${RESULTS_DIR}/${cwe}/${kind}.run"
        if scp ${SCP_OPTS} "${SSH_TARGET}:${remote}" "${local}" 2>/dev/null; then
            echo "    [ok] ${cwe}/${kind}.run"
        else
            echo "    [--] ${cwe}/${kind}.run not found on guest"
            rm -f "${local}"
        fi
    done
done

# count_bad <file> <expected_exit_code> -> prints "total detected"
count_bad() {
    [ -f "$1" ] || { echo "0 0"; return; }
    # NB: the awk var can't be named "exp" — gawk reserves it as a builtin
    awk -v want="$2" '{total++; if ($NF==want) d++} END{printf "%d %d\n", total+0, d+0}' "$1"
}

# count_good <file> -> prints "total clean"  (clean = exit 0 or 124)
count_good() {
    [ -f "$1" ] || { echo "0 0"; return; }
    awk '{total++; if ($NF==0 || $NF==124) c++} END{printf "%d %d\n", total+0, c+0}' "$1"
}

pct() {
    awk -v n="$1" -v d="$2" 'BEGIN{ if (d>0) printf "%.1f%%", (n/d)*100; else printf "N/A" }'
}

set -- $(count_bad "${RESULTS_DIR}/CWE415/bad.run" 255)
b415_total=$1; b415_detected=$2

set -- $(count_bad "${RESULTS_DIR}/CWE416/bad.run" 162)
b416_total=$1; b416_detected=$2

set -- $(count_good "${RESULTS_DIR}/CWE415/good.run")
g415_total=$1; g415_clean=$2

set -- $(count_good "${RESULTS_DIR}/CWE416/good.run")
g416_total=$1; g416_clean=$2

total_bad=$((b415_total + b416_total))
total_detected=$((b415_detected + b416_detected))

echo ""
echo "=== PICASSO Juliet Detection Summary ==="
echo ""
printf "%-32s %-10s %-10s %s\n" "Test set (bad.run)" "Detected" "Total" "Rate"
printf '%s\n' "------------------------------------------------------------------"
printf "%-32s %-10s %-10s %s\n" "CWE415 double-free (exit 255)"    "$b415_detected" "$b415_total" "$(pct "$b415_detected" "$b415_total")"
printf "%-32s %-10s %-10s %s\n" "CWE416 use-after-free (exit 162)" "$b416_detected" "$b416_total" "$(pct "$b416_detected" "$b416_total")"
printf '%s\n' "------------------------------------------------------------------"
printf "%-32s %-10s %-10s %s\n" "PICASSO TOTAL" "$total_detected" "$total_bad" "$(pct "$total_detected" "$total_bad")"

echo ""
echo "=== False-positive check (good.run) ==="
printf "%-32s %-10s %-10s %s\n" "Test set (good.run)" "Clean" "Total" "Rate"
printf '%s\n' "------------------------------------------------------------------"
printf "%-32s %-10s %-10s %s\n" "CWE415 good.run" "$g415_clean" "$g415_total" "$(pct "$g415_clean" "$g415_total")"
printf "%-32s %-10s %-10s %s\n" "CWE416 good.run" "$g416_clean" "$g416_total" "$(pct "$g416_clean" "$g416_total")"

echo ""
echo "Raw .run files saved under: ${RESULTS_DIR}/"

if [ "$total_bad" -gt 0 ] && [ "$total_detected" -eq "$total_bad" ]; then
    echo ""
    echo "[OK] PICASSO detected 100% of CWE-415/416 bad-case vulnerabilities."
fi
