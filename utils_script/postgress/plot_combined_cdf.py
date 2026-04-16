#!/usr/bin/env python3
"""
Plot normalized CDF of per-transaction execution time from pgbench.
Combines all four runs from each scenario as described in the paper.

Usage:
    python3 plot_combined_cdf.py
"""

import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

# Paths to result directories
BASE_DIR = Path(__file__).parent
BASELINE_DIR = BASE_DIR / "baseline"
COLORED_DIR = BASE_DIR / "colored"
CORNU_DIR = BASE_DIR / "corn"


def read_pgbench_log(filename):
    """Read pgbench log file and return latencies in milliseconds.

    pgbench log format (with --log):
        client_id  transaction_no  time_us  script_no  epoch_s  epoch_us

    Column 3 (index 2) is the transaction latency in microseconds.
    """
    latencies = []
    with open(filename, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 3:
                latency_us = float(parts[2])
                latencies.append(latency_us / 1000.0)  # Convert to ms
    return latencies


def read_all_runs(directory):
    """Read and combine all pgbench log files from a directory."""
    all_latencies = []
    log_files = sorted(directory.glob("pgbench-log-*"))

    for log_file in log_files:
        latencies = read_pgbench_log(log_file)
        all_latencies.extend(latencies)
        print(f"  {log_file.name}: {len(latencies)} transactions")

    return all_latencies


def read_tps_from_run_files(directory):
    """Read TPS values from run-*.txt files in a directory.

    Parses lines like:
        tps = 1.980456 (including connections establishing)
        tps = 1.984627 (excluding connections establishing)

    Returns the average TPS (excluding connections establishing) across all runs.
    """
    import re

    tps_values = []
    run_files = sorted(directory.glob("run-*.txt"))

    for run_file in run_files:
        try:
            with open(run_file, 'r') as f:
                content = f.read()

            # Match "tps = X.XXX (excluding connections establishing)"
            match = re.search(r'tps\s*=\s*([\d.]+)\s*\(excluding connections establishing\)', content)
            if match:
                tps = float(match.group(1))
                tps_values.append(tps)
        except Exception as e:
            print(f"  Warning: Could not parse {run_file}: {e}")

    if tps_values:
        return np.mean(tps_values)
    return None


def plot_cdf_paper_style(scenarios, output_file='pgbench_cdf_combined.pdf'):
    """
    Plot normalized CDF matching the paper style:
    - X-axis: Transaction time in milliseconds (log scale)
    - Y-axis: CDF (0 to 1)
    - 90th and 99th percentiles marked with dotted grid lines
    - Optional revocation pause segments
    """
    # Use serif font for paper quality
    plt.rcParams['font.family'] = 'serif'
    plt.rcParams['font.size'] = 11

    fig, ax = plt.subplots(figsize=(8, 5))

    # Color scheme
    colors = {
        'Baseline': '#1f77b4',      # Blue
        'PICASSO': '#cc79a7',       # Pink
        'Cornucopia': '#0072b2',    # Blue
    }

    linestyles = {
        'Baseline': '-',
        'PICASSO': '-',
        'Cornucopia': '-',
    }

    stats = {}

    for name, latencies in scenarios.items():
        sorted_latencies = np.sort(latencies)
        # Normalized CDF: fraction of transactions completing in less than given time
        cdf = np.arange(1, len(sorted_latencies) + 1) / len(sorted_latencies)

        color = colors.get(name, 'gray')
        ls = linestyles.get(name, '-')

        ax.plot(sorted_latencies, cdf, label=name, color=color,
                linestyle=ls, linewidth=2)

        # Calculate percentiles
        p50 = np.percentile(latencies, 50)
        p90 = np.percentile(latencies, 90)
        p99 = np.percentile(latencies, 99)
        p999 = np.percentile(latencies, 99.9)

        stats[name] = {
            'count': len(latencies),
            'p50': p50,
            'p90': p90,
            'p99': p99,
            'p999': p999,
            'min': min(latencies),
            'max': max(latencies),
        }

    # Add 90th and 99th percentile grid lines (as described in paper)
    ax.axhline(y=0.90, color='gray', linestyle=':', linewidth=1.5)
    ax.axhline(y=0.99, color='gray', linestyle=':', linewidth=1.5)

    # Add text labels for percentile lines
    ax.text(ax.get_xlim()[0] * 1.05, 0.90, '90th', fontsize=9,
            verticalalignment='center', color='gray')
    ax.text(ax.get_xlim()[0] * 1.05, 0.99, '99th', fontsize=9,
            verticalalignment='center', color='gray')

    # Axis labels
    ax.set_xlabel('Transaction time / milliseconds', fontsize=12)
    ax.set_ylabel('CDF', fontsize=12)

    # Log scale for x-axis
    ax.set_xscale('log')

    # Y-axis from 0 to 1
    ax.set_ylim(0, 1.02)

    # Set reasonable x limits based on data
    all_latencies = [l for lats in scenarios.values() for l in lats]
    ax.set_xlim(left=min(all_latencies) * 0.9, right=max(all_latencies) * 1.1)

    # Grid
    ax.grid(True, which='both')

    # Legend
    ax.legend(loc='lower right', fontsize=10)

    # Remove top and right spines
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)

    plt.tight_layout()

    # Save as PDF and PNG
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"\nSaved: {output_file}")

    png_file = output_file.replace('.pdf', '.png')
    plt.savefig(png_file, dpi=300, bbox_inches='tight')
    print(f"Saved: {png_file}")

    plt.close()

    # Reset font
    plt.rcParams['font.family'] = 'sans-serif'

    return stats


def plot_cdf_tail_focus(scenarios, output_file='pgbench_cdf_tail.pdf'):
    """
    Plot CDF focused on tail latency (80th percentile and above).
    This matches the paper figure more closely.
    """
    plt.rcParams['font.family'] = 'serif'
    plt.rcParams['font.size'] = 11

    fig, ax = plt.subplots(figsize=(8, 5))

    colors = {
        'Baseline': '#fe6100',
        'PICASSO': '#cc79a7',
        'Cornucopia': '#0072b2',
    }

    for name, latencies in scenarios.items():
        sorted_latencies = np.sort(latencies)
        cdf = np.arange(1, len(sorted_latencies) + 1) / len(sorted_latencies)

        color = colors.get(name, 'gray')
        ax.plot(sorted_latencies, cdf, label=name, color=color, linewidth=2)

    # 90th and 99th percentile grid lines
    ax.axhline(y=0.90, color='gray', linestyle=':', linewidth=1.5)
    ax.axhline(y=0.99, color='gray', linestyle=':', linewidth=1.5)

    ax.set_xlabel('Transaction time / milliseconds', fontsize=12)
    ax.set_ylabel('CDF', fontsize=12)
    ax.set_xscale('log')

    # Focus on tail (80th percentile and above)
    ax.set_ylim(0.80, 1.005)

    all_latencies = [l for lats in scenarios.values() for l in lats]
    ax.set_xlim(left=np.percentile(all_latencies, 80) * 0.8)

    ax.grid(True,  which='both')
    ax.legend(loc='lower right', fontsize=10)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)

    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Saved: {output_file}")

    png_file = output_file.replace('.pdf', '.png')
    plt.savefig(png_file, dpi=300, bbox_inches='tight')
    print(f"Saved: {png_file}")

    plt.close()
    plt.rcParams['font.family'] = 'sans-serif'


def plot_latency_timeseries_paper(scenarios, output_file='pgbench_timeseries_paper.pdf',
                                   max_transactions=200):
    """Create publication-quality timeseries figure for academic paper - single plot."""

    # Use serif font for paper
    plt.rcParams['font.family'] = 'serif'
    plt.rcParams['font.size'] = 10

    fig, ax = plt.subplots(figsize=(6, 2.5))

    colors = {
        'Baseline': '#fe6100',
        'PICASSO': '#cc79a7',
        'Cornucopia': '#0072b2',
    }
    markers = {
        'Baseline': 's',      # square
        'PICASSO': '^',       # triangle up
        'Cornucopia': 'o',    # circle
    }
    default_colors = ['#fe6100', '#cc79a7', '#0072b2', '#e69f00', '#009e73']
    default_markers = ['s', '^', 'o', 'D', 'v']

    # Vertical offset to separate overlapping points (in ms)
    vertical_offsets = {
        'Baseline': 0,
        'PICASSO': 0,
        'Cornucopia': 0,
    }

    for i, (name, latencies) in enumerate(scenarios.items()):
        # Only first N transactions
        latencies_subset = latencies[:max_transactions]
        tx_nums = np.arange(1, len(latencies_subset) + 1)
        latencies_arr = np.array(latencies_subset)

        color = colors.get(name, default_colors[i % len(default_colors)])
        marker = markers.get(name, default_markers[i % len(default_markers)])
        v_offset = vertical_offsets.get(name, 0)

        # Convert ms to seconds
        latencies_sec = latencies_arr / 1000.0

        # Apply vertical offset to separate overlapping data (offset in seconds)
        latencies_offset = latencies_sec + v_offset / 1000.0

        # Separate normal and spike transactions (threshold in seconds)
        spike_threshold = 1.0  # 1 second
        spike_mask = latencies_sec > spike_threshold
        normal_mask = ~spike_mask
        spike_count = np.sum(spike_mask)

        # Plot normal transactions as scatter with different markers
        ax.scatter(tx_nums[normal_mask], latencies_offset[normal_mask],
                   s=20, color=color, marker=marker, label=name)

        # Plot spikes with same color but larger marker and dark edge
        if spike_count > 0:
            ax.scatter(tx_nums[spike_mask], latencies_offset[spike_mask],
                       s=60, color=color, marker=marker, edgecolors='black',
                       linewidths=1, zorder=5)

    ax.set_ylabel('Latency (s, log)', fontsize=11)
    ax.set_xlabel('Transaction Number', fontsize=11)
    ax.set_yscale('log')

    # Show plain decimal tick labels (0.4, 0.6, 1.0, ...) instead of 10^-1 notation
    from matplotlib.ticker import FuncFormatter
    ax.yaxis.set_major_formatter(FuncFormatter(lambda val, pos: f'{val:g}'))
    ax.yaxis.set_minor_formatter(FuncFormatter(lambda val, pos: f'{val:g}'))

    ax.grid(True, linestyle='-', linewidth=0.5, which='both')
    ax.set_xlim(0, max_transactions + 1)

    # Remove top and right spines for cleaner look
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)

    ax.legend(loc='upper right', fontsize=10)

    plt.tight_layout()

    plt.savefig(output_file, dpi=300, bbox_inches='tight', pad_inches=0.1)
    print(f"Saved paper figure to: {output_file}")

    # Also save as PNG
    png_file = output_file.replace('.pdf', '.png')
    plt.savefig(png_file, dpi=300, bbox_inches='tight', pad_inches=0.1)
    print(f"Saved paper figure to: {png_file}")
    plt.close()

    # Reset to default
    plt.rcParams['font.family'] = 'sans-serif'


def print_stats(stats):
    """Print statistics table."""
    print("\n" + "="*80)
    print("STATISTICS SUMMARY (all values in milliseconds)")
    print("="*80)

    print(f"\n{'Scenario':<15} {'Count':>8} {'Min':>10} {'P50':>10} {'P90':>10} {'P99':>10} {'P99.9':>10} {'Max':>10}")
    print("-"*80)

    for name, s in stats.items():
        print(f"{name:<15} {s['count']:>8} {s['min']:>10.2f} {s['p50']:>10.2f} "
              f"{s['p90']:>10.2f} {s['p99']:>10.2f} {s['p999']:>10.2f} {s['max']:>10.2f}")

    print()

    # Calculate overhead vs baseline
    if 'Baseline' in stats:
        baseline_p50 = stats['Baseline']['p50']
        baseline_p99 = stats['Baseline']['p99']

        print("Overhead vs Baseline:")
        print("-"*40)
        for name, s in stats.items():
            if name != 'Baseline':
                p50_overhead = ((s['p50'] / baseline_p50) - 1) * 100
                p99_overhead = ((s['p99'] / baseline_p99) - 1) * 100
                print(f"  {name}: P50 = {p50_overhead:+.1f}%, P99 = {p99_overhead:+.1f}%")
        print()


def generate_latex_table(stats, tps_data, output_file='pgbench_stats_table.tex'):
    """Generate a LaTeX table with TPS, percentile statistics and overhead percentages combined."""

    baseline = stats.get('Baseline', None)
    baseline_tps = tps_data.get('Baseline', None)

    latex = []
    latex.append(r"\begin{table}[htbp]")
    latex.append(r"\centering")
    latex.append(r"\caption{PostgreSQL pgbench: TPS and transaction latency percentiles (ms) with overhead vs.\ baseline}")
    latex.append(r"\label{tab:pgbench-latency}")
    latex.append(r"\begin{tabular}{lccccc}")
    latex.append(r"\toprule")
    latex.append(r"Scenario & TPS & P50 & P90 & P99 & P99.9 \\")
    latex.append(r"\midrule")

    for name, s in stats.items():
        tps = tps_data.get(name)
        tps_str = f"{tps:.2f}" if tps else "N/A"

        if name == 'Baseline' or baseline is None:
            # Baseline row: just raw numbers
            latex.append(f"{name} & {tps_str} & {s['p50']:.1f} & {s['p90']:.1f} & {s['p99']:.1f} & {s['p999']:.1f} \\\\")
        else:
            # Other rows: raw number (overhead%)
            if tps and baseline_tps:
                tps_oh = ((tps / baseline_tps) - 1) * 100
                tps_str = f"{tps:.2f} ({tps_oh:+.1f}\\%)"

            p50_oh = ((s['p50'] / baseline['p50']) - 1) * 100
            p90_oh = ((s['p90'] / baseline['p90']) - 1) * 100
            p99_oh = ((s['p99'] / baseline['p99']) - 1) * 100
            p999_oh = ((s['p999'] / baseline['p999']) - 1) * 100

            latex.append(f"{name} & {tps_str} & {s['p50']:.1f} ({p50_oh:+.1f}\\%) & "
                        f"{s['p90']:.1f} ({p90_oh:+.1f}\\%) & "
                        f"{s['p99']:.1f} ({p99_oh:+.1f}\\%) & "
                        f"{s['p999']:.1f} ({p999_oh:+.1f}\\%) \\\\")

    latex.append(r"\bottomrule")
    latex.append(r"\end{tabular}")
    latex.append(r"\end{table}")

    latex_str = "\n".join(latex)

    # Save to file
    with open(output_file, 'w') as f:
        f.write(latex_str)

    print(f"\nSaved LaTeX table to: {output_file}")
    print("\nLaTeX table content:")
    print("-" * 90)
    print(latex_str)
    print("-" * 90)

    return latex_str


def main():
    print("Loading pgbench transaction logs...")
    print()

    # Read all runs from each scenario
    scenarios = {}
    tps_data = {}

    print("Baseline (baseline_4):")
    if BASELINE_DIR.exists():
        scenarios['Baseline'] = read_all_runs(BASELINE_DIR)
        tps_data['Baseline'] = read_tps_from_run_files(BASELINE_DIR)
        print(f"  Total: {len(scenarios['Baseline'])} transactions from 4 runs")
        print(f"  TPS: {tps_data['Baseline']:.2f}\n" if tps_data['Baseline'] else "  TPS: N/A\n")
    else:
        print(f"  Directory not found: {BASELINE_DIR}\n")

    print("PICASSO:")
    if COLORED_DIR.exists():
        scenarios['PICASSO'] = read_all_runs(COLORED_DIR)
        tps_data['PICASSO'] = read_tps_from_run_files(COLORED_DIR)
        print(f"  Total: {len(scenarios['PICASSO'])} transactions from 4 runs")
        print(f"  TPS: {tps_data['PICASSO']:.2f}\n" if tps_data['PICASSO'] else "  TPS: N/A\n")
    else:
        print(f"  Directory not found: {COLORED_DIR}\n")

    print("Cornucopia:")
    if CORNU_DIR.exists():
        scenarios['Cornucopia'] = read_all_runs(CORNU_DIR)
        tps_data['Cornucopia'] = read_tps_from_run_files(CORNU_DIR)
        print(f"  Total: {len(scenarios['Cornucopia'])} transactions from 4 runs")
        print(f"  TPS: {tps_data['Cornucopia']:.2f}\n" if tps_data['Cornucopia'] else "  TPS: N/A\n")
    else:
        print(f"  Directory not found: {CORNU_DIR}\n")

    if not scenarios:
        print("No data found!")
        return

    # Plot full CDF (paper style)
    stats = plot_cdf_paper_style(scenarios,
                                  output_file=str(BASE_DIR / 'pgbench_cdf_combined.pdf'))

    # Plot tail-focused CDF
    plot_cdf_tail_focus(scenarios,
                        output_file=str(BASE_DIR / 'pgbench_cdf_tail.pdf'))

    # Plot timeseries (paper style)
    plot_latency_timeseries_paper(scenarios,
                                   output_file=str(BASE_DIR / 'pgbench_timeseries_paper.pdf'))

    # Print statistics
    print_stats(stats)

    # Print TPS summary
    print("\nTPS Summary:")
    print("-" * 40)
    for name, tps in tps_data.items():
        if tps:
            if name == 'Baseline':
                print(f"  {name}: {tps:.2f} TPS")
            else:
                baseline_tps = tps_data.get('Baseline')
                if baseline_tps:
                    overhead = ((tps / baseline_tps) - 1) * 100
                    print(f"  {name}: {tps:.2f} TPS ({overhead:+.1f}%)")
                else:
                    print(f"  {name}: {tps:.2f} TPS")
    print()

    # Generate LaTeX tables
    generate_latex_table(stats, tps_data, output_file=str(BASE_DIR / 'pgbench_stats_table.tex'))


if __name__ == '__main__':
    main()
