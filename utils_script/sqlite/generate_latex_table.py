#!/usr/bin/env python3
"""
Generate LaTeX table from SQLite speedtest1 benchmark results.
Compares Colored and Cornucopia overhead factors vs Baseline.
Uses booktabs for professional table formatting.
"""

import re
from pathlib import Path

def parse_speedtest_file(filepath):
    """Parse speedtest1 output file and extract test names and times."""
    results = {}
    try:
        with open(filepath, 'r') as f:
            for line in f:
                # Match lines like: " 100 - 50000 INSERTs into table with no index......................   49.047s"
                match = re.match(r'\s*(\d+)\s*-\s*(.+?)\.*\s+([\d.]+)s\s*$', line)
                if match:
                    test_id = match.group(1)
                    test_name = match.group(2).strip()
                    time_sec = float(match.group(3))
                    results[test_id] = {'name': test_name, 'time': time_sec}
                # Match TOTAL line
                elif 'TOTAL' in line:
                    match = re.search(r'([\d.]+)s', line)
                    if match:
                        results['TOTAL'] = {'name': 'TOTAL', 'time': float(match.group(1))}
    except Exception as e:
        print(f"Warning: Could not parse {filepath}: {e}")
    return results

def generate_latex_table(baseline, colored, cornucopia):
    """Generate LaTeX table with booktabs."""

    # LaTeX table header
    latex = r"""\begin{table}[htbp]
\centering
\caption{SQLite Speedtest1 Benchmark Results}
\label{tab:sqlite-benchmark}
\begin{tabular}{@{}llrrrrr@{}}
\toprule
ID & Benchmark & \multicolumn{2}{c}{Colored} & \multicolumn{2}{c}{Cornucopia} \\
\cmidrule(lr){3-4} \cmidrule(lr){5-6}
 & & Time (s) & Overhead & Time (s) & Overhead \\
\midrule
"""

    # Sort test IDs numerically
    test_ids = sorted([k for k in baseline.keys() if k != 'TOTAL'], key=lambda x: int(x))

    for test_id in test_ids:
        base_data = baseline.get(test_id)
        color_data = colored.get(test_id)
        corn_data = cornucopia.get(test_id)

        if not base_data:
            continue

        # Escape underscores and special chars for LaTeX
        name = base_data['name'].replace('_', r'\_').replace('&', r'\&')
        # Truncate long names
        if len(name) > 45:
            name = name[:42] + '...'

        base_time = base_data['time']

        # Colored
        if color_data:
            color_time = color_data['time']
            color_overhead = color_time / base_time
            color_time_str = f"{color_time:.2f}"
            color_overhead_str = f"{color_overhead:.2f}$\\times$"
        else:
            color_time_str = "N/A"
            color_overhead_str = "N/A"

        # Cornucopia
        if corn_data:
            corn_time = corn_data['time']
            corn_overhead = corn_time / base_time
            corn_time_str = f"{corn_time:.2f}"
            corn_overhead_str = f"{corn_overhead:.2f}$\\times$"
        else:
            corn_time_str = "N/A"
            corn_overhead_str = "N/A"

        latex += f"{test_id} & {name} & {color_time_str} & {color_overhead_str} & {corn_time_str} & {corn_overhead_str} \\\\\n"

    # Add TOTAL row
    latex += r"\midrule" + "\n"
    if 'TOTAL' in baseline:
        base_total = baseline['TOTAL']['time']
        color_total = colored.get('TOTAL', {}).get('time')
        corn_total = cornucopia.get('TOTAL', {}).get('time')

        if color_total:
            color_overhead = color_total / base_total
            color_str = f"{color_total:.2f} & {color_overhead:.2f}$\\times$"
        else:
            color_str = "N/A & N/A"

        if corn_total:
            corn_overhead = corn_total / base_total
            corn_str = f"{corn_total:.2f} & {corn_overhead:.2f}$\\times$"
        else:
            corn_str = "N/A & N/A"

        latex += f"& \\textbf{{TOTAL}} & {color_str} & {corn_str} \\\\\n"

    # LaTeX table footer
    latex += r"""\bottomrule
\end{tabular}
\end{table}
"""

    return latex

def main():
    script_dir = Path(__file__).parent

    baseline_file = script_dir / 'baseline.txt'
    colored_file = script_dir / 'colored_paper.txt'
    cornucopia_file = script_dir / 'cornucupia_sqlite.txt'

    print(f"Reading baseline:   {baseline_file}")
    print(f"Reading colored:    {colored_file}")
    print(f"Reading cornucopia: {cornucopia_file}")

    baseline = parse_speedtest_file(baseline_file)
    colored = parse_speedtest_file(colored_file)
    cornucopia = parse_speedtest_file(cornucopia_file)

    print(f"\nBaseline tests:   {len(baseline)}")
    print(f"Colored tests:    {len(colored)}")
    print(f"Cornucopia tests: {len(cornucopia)}")

    latex_table = generate_latex_table(baseline, colored, cornucopia)

    # Save to file
    output_file = script_dir / 'sqlite_benchmark_table.tex'
    with open(output_file, 'w') as f:
        f.write(latex_table)

    print(f"\nLaTeX table saved to: {output_file}")
    print("\n" + "="*60)
    print(latex_table)

if __name__ == "__main__":
    main()
