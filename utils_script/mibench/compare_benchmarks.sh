#!/bin/bash
# Script to compare MiBench benchmark results between Baseline and PICASSO
# Usage: ./compare_benchmarks.sh [baseline_log] [picasso_log]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/bench_log"

# Default log files
BASELINE_LOG="${1:-${LOG_DIR}/mibench_baseline_log}"
PICASSO_LOG="${2:-${LOG_DIR}/mibench_picasso_log}"

# Output comparison file
COMPARISON_OUTPUT="${LOG_DIR}/mibench_comparison.txt"
LATEX_OUTPUT="${LOG_DIR}/mibench_comparison.tex"

# Check if log files exist
if [[ ! -f "$BASELINE_LOG" ]]; then
    echo "ERROR: Baseline log not found: $BASELINE_LOG"
    exit 1
fi

if [[ ! -f "$PICASSO_LOG" ]]; then
    echo "ERROR: PICASSO log not found: $PICASSO_LOG"
    exit 1
fi

echo "=============================================="
echo "MiBench Benchmark Comparison"
echo "=============================================="
echo ""
echo "Baseline log: $BASELINE_LOG"
echo "PICASSO log: $PICASSO_LOG"
echo ""

# Create comparison output
{
    printf "%-25s %15s %15s %15s %15s %10s %10s\n" \
        "Benchmark" "Base Cycles" "Base Instrs" "PIC Cycles" "PIC Instrs" "Cyc OH(%)" "Inst OH(%)"
    printf "%-25s %15s %15s %15s %15s %10s %10s\n" \
        "-------------------------" "---------------" "---------------" "---------------" "---------------" "----------" "----------"
} > "$COMPARISON_OUTPUT"

# Arrays to store totals
declare -A baseline_cycles
declare -A baseline_instrs
declare -A picasso_cycles
declare -A picasso_instrs

# Parse baseline log (handle files without trailing newline)
while IFS=',' read -r name cycles instrs || [[ -n "$name" ]]; do
    # Remove whitespace and .log extension
    name=$(echo "$name" | sed 's/\.log$//' | xargs)
    cycles=$(echo "$cycles" | xargs)
    instrs=$(echo "$instrs" | xargs)

    if [[ -n "$name" && "$cycles" =~ ^[0-9]+$ ]]; then
        baseline_cycles["$name"]=$cycles
        baseline_instrs["$name"]=$instrs
    fi
done < "$BASELINE_LOG"

# Parse picasso log (handle files without trailing newline)
while IFS=',' read -r name cycles instrs || [[ -n "$name" ]]; do
    # Remove whitespace and .log extension
    name=$(echo "$name" | sed 's/\.log$//' | xargs)
    cycles=$(echo "$cycles" | xargs)
    instrs=$(echo "$instrs" | xargs)

    if [[ -n "$name" && "$cycles" =~ ^[0-9]+$ ]]; then
        picasso_cycles["$name"]=$cycles
        picasso_instrs["$name"]=$instrs
    fi
done < "$PICASSO_LOG"

# Calculate totals
total_baseline_cycles=0
total_baseline_instrs=0
total_picasso_cycles=0
total_picasso_instrs=0

# Compare and generate output
for name in "${!baseline_cycles[@]}"; do
    bc=${baseline_cycles[$name]:-0}
    bi=${baseline_instrs[$name]:-0}
    oc=${picasso_cycles[$name]:-0}
    oi=${picasso_instrs[$name]:-0}

    # Calculate overhead percentages
    if [[ $bc -gt 0 ]]; then
        cyc_overhead=$(echo "scale=2; (($oc - $bc) * 100) / $bc" | bc 2>/dev/null || echo "N/A")
    else
        cyc_overhead="N/A"
    fi

    if [[ $bi -gt 0 ]]; then
        inst_overhead=$(echo "scale=2; (($oi - $bi) * 100) / $bi" | bc 2>/dev/null || echo "N/A")
    else
        inst_overhead="N/A"
    fi

    printf "%-25s %15d %15d %15d %15d %10s %10s\n" \
        "$name" "$bc" "$bi" "$oc" "$oi" "$cyc_overhead" "$inst_overhead" >> "$COMPARISON_OUTPUT"

    # Add to totals
    total_baseline_cycles=$((total_baseline_cycles + bc))
    total_baseline_instrs=$((total_baseline_instrs + bi))
    total_picasso_cycles=$((total_picasso_cycles + oc))
    total_picasso_instrs=$((total_picasso_instrs + oi))
done

# Calculate total overhead
if [[ $total_baseline_cycles -gt 0 ]]; then
    total_cyc_overhead=$(echo "scale=2; (($total_picasso_cycles - $total_baseline_cycles) * 100) / $total_baseline_cycles" | bc)
else
    total_cyc_overhead="N/A"
fi

if [[ $total_baseline_instrs -gt 0 ]]; then
    total_inst_overhead=$(echo "scale=2; (($total_picasso_instrs - $total_baseline_instrs) * 100) / $total_baseline_instrs" | bc)
else
    total_inst_overhead="N/A"
fi

{
    printf "%-25s %15s %15s %15s %15s %10s %10s\n" \
        "-------------------------" "---------------" "---------------" "---------------" "---------------" "----------" "----------"
    printf "%-25s %15d %15d %15d %15d %10s %10s\n" \
        "TOTAL" "$total_baseline_cycles" "$total_baseline_instrs" "$total_picasso_cycles" "$total_picasso_instrs" "$total_cyc_overhead" "$total_inst_overhead"
} >> "$COMPARISON_OUTPUT"

# Display results
cat "$COMPARISON_OUTPUT"

echo ""
echo "=============================================="
echo "Summary"
echo "=============================================="
echo "Total Baseline Cycles:    $total_baseline_cycles"
echo "Total PICASSO Cycles:    $total_picasso_cycles"
echo "Cycle Overhead:           ${total_cyc_overhead}%"
echo ""
echo "Total Baseline Instrs:    $total_baseline_instrs"
echo "Total PICASSO Instrs:    $total_picasso_instrs"
echo "Instruction Overhead:     ${total_inst_overhead}%"
echo ""
echo "Comparison saved to: $COMPARISON_OUTPUT"

# Generate LaTeX table
{
    echo "\\begin{table}[h]"
    echo "\\caption{PICASSO overhead on MiBench}\\label{tab:mibench}"
    echo "\\begin{tabular}{lrrr}"
    echo "\\toprule"
    echo "Benchmark & Baseline & PICASSO & Overhead (\\%) \\\\"
    echo "\\midrule"

    # Count benchmarks for average calculation
    bench_count=0
    total_overhead=0

    for name in "${!baseline_cycles[@]}"; do
        bc=${baseline_cycles[$name]:-0}
        oc=${picasso_cycles[$name]:-0}

        if [[ $bc -gt 0 ]]; then
            cyc_overhead=$(printf "%.2f" $(echo "scale=4; (($oc - $bc) * 100) / $bc" | bc 2>/dev/null) || echo "0.00")
        else
            cyc_overhead="0.00"
        fi

        # Clean name for LaTeX (replace underscores, remove .bin)
        latex_name=$(echo "$name" | sed 's/\.bin$//g' | sed 's/_/\\_/g')

        echo "$latex_name & $bc & $oc & ${cyc_overhead}\\% \\\\"

        # Accumulate for average
        bench_count=$((bench_count + 1))
        total_overhead=$(echo "$total_overhead + $cyc_overhead" | bc)
    done

    # Calculate average overhead
    if [[ $bench_count -gt 0 ]]; then
        avg_overhead=$(printf "%.2f" $(echo "scale=4; $total_overhead / $bench_count" | bc))
    else
        avg_overhead="0.00"
    fi

    echo "\\midrule"
    echo "Average & & & ${avg_overhead}\\% \\\\"
    echo "\\bottomrule"
    echo "\\end{tabular}"
    echo "\\end{table}"
} > "$LATEX_OUTPUT"

echo "LaTeX table saved to: $LATEX_OUTPUT"
