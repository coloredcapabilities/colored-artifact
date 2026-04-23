#!/usr/bin/env python3
"""
QPS Latency Letter-Value Plot Analyzer
Shows letter-value plot (boxenplot) for 0 bytes payload - displays many quantiles.
"""

import json
from pathlib import Path
import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
import pandas as pd

def reconstruct_latencies_from_histogram(filepath):
    """Reconstruct individual latencies from histogram buckets."""
    try:
        with open(filepath, 'r') as f:
            data = json.load(f)

        latencies_data = data.get('latencies', {})
        buckets = latencies_data.get('bucket', [])
        resolution = data.get('scenario', {}).get('clientConfig', {}).get('histogramParams', {}).get('resolution', 0.01)

        # Reconstruct latencies from histogram
        latencies = []
        for i, count in enumerate(buckets):
            if count > 0:
                # Calculate bucket center value (in nanoseconds, convert to ms)
                bucket_val = (1 + resolution) ** i / 1e6  # Convert to ms
                latencies.extend([bucket_val] * count)

        return latencies if latencies else None
    except Exception as e:
        print(f"Warning: Could not reconstruct latencies from {filepath}: {e}")
        return None

def collect_all_runs(base_dir, config_name, byte_size):
    """Collect latencies from all runs for a given configuration and byte size."""
    config_dir = base_dir / config_name / byte_size
    all_latencies = []

    if not config_dir.exists():
        return all_latencies

    # Find all qps-result.json files (with .1, .2, .3 suffixes)
    for json_file in config_dir.glob("qps-result.json*"):
        if json_file.suffix == '.log':
            continue  # Skip .log files

        latencies = reconstruct_latencies_from_histogram(json_file)
        if latencies:
            all_latencies.extend(latencies)

    return all_latencies

def main():
    script_dir = Path(__file__).parent
    paper_dir = script_dir / "paper"

    configs = ['baseline_three', 'colored_three', 'corn_three']
    config_labels = ['Baseline', 'PICASSO', 'Cornucopia']
    byte_size = '0bytes'

    # Colors for each configuration (darker for inner percentiles)
    colors = ['#fe6100', '#cc79a7', '#0072b2']  # Baseline=orange, PICASSO=pink, Cornucopia=blue

    percentiles = [50, 90, 95, 99]

    print("=" * 80)
    print(" QPS Tail Latency Analysis (0 bytes) - Custom Percentile Plot")
    print("=" * 80)

    # Collect percentile data
    percentile_data = {}
    for config, label in zip(configs, config_labels):
        latencies = collect_all_runs(paper_dir, config, byte_size)
        if latencies:
            pcts = {p: np.percentile(latencies, p) for p in percentiles}
            percentile_data[label] = pcts
            print(f"{label}: p50={pcts[50]:.2f}ms, p90={pcts[90]:.2f}ms, "
                  f"p95={pcts[95]:.2f}ms, p99={pcts[99]:.2f}ms")
        else:
            print(f"{label}: No data")

    # Create custom letter-value style plot with specific percentiles
    fig, ax = plt.subplots(figsize=(6, 3))

    x_positions = np.arange(len(config_labels))
    width = 0.6

    # Draw nested boxes from outer (p99) to inner (p50)
    # Widths decrease for inner percentiles
    pct_widths = {99: width, 95: width * 0.7, 90: width * 0.5, 50: width * 0.3}
    pct_alphas = {99: 0.4, 95: 0.6, 90: 0.8, 50: 1.0}

    for i, (label, color) in enumerate(zip(config_labels, colors)):
        if label not in percentile_data:
            continue
        pcts = percentile_data[label]

        # Draw boxes from outer to inner
        for p in [99, 95, 90, 50]:
            w = pct_widths[p]
            alpha = pct_alphas[p]
            val = pcts[p]

            # Draw horizontal bar at percentile value
            ax.barh(i, val, height=w, left=0, color=color, alpha=alpha,
                   edgecolor='black', linewidth=0.5)

    # Add percentile value annotations
    for i, label in enumerate(config_labels):
        if label not in percentile_data:
            continue
        pcts = percentile_data[label]
        # Annotate p50 on the bar (offset to the right)
        ax.annotate(f'p50:{pcts[50]:.0f}', xy=(pcts[50], i),
                   xytext=(15, 0), textcoords='offset points',
                   va='center', fontsize=8)

    # Labels and formatting
    ax.set_yticks(x_positions)
    ax.set_yticklabels(config_labels)
    ax.set_xlabel('Latency (ms)', fontsize=12)
    ax.set_title('Tail Latency (0 bytes) - p50/p90/p95/p99', fontsize=12)
    ax.grid(True, alpha=0.3, axis='x')

    # Add legend for percentiles
    from matplotlib.patches import Patch
    legend_elements = [Patch(facecolor='gray', alpha=a, label=f'p{p}')
                       for p, a in [(50, 1.0), (90, 0.8), (95, 0.6), (99, 0.4)]]
    ax.legend(handles=legend_elements, loc='lower right', fontsize=8)

    plt.tight_layout()

    # Save figures
    output_png = script_dir / "qps_lettervalue_0bytes.png"
    output_pdf = script_dir / "qps_lettervalue_0bytes.pdf"
    plt.savefig(output_png, dpi=150, bbox_inches='tight', pad_inches=0.1)
    plt.savefig(output_pdf, bbox_inches='tight', pad_inches=0.1)
    plt.close()

    print(f"\nSaved plot to: {output_png}")
    print(f"Saved plot to: {output_pdf}")

    # Print QPS and Latency overhead for 0bytes and 1024bytes
    print("\n" + "=" * 80)
    print(" QPS and Latency Overhead Analysis")
    print("=" * 80)

    for byte_size, byte_label in [('0bytes', '0 bytes'), ('1024bytes', '1024 bytes')]:
        print(f"\n--- {byte_label} ---")

        # Collect QPS data
        qps_data = {}
        latency_data = {}
        for config, label in zip(configs, config_labels):
            config_dir = paper_dir / config / byte_size
            qps_values = []
            latencies_all = []

            for json_file in config_dir.glob("qps-result.json*"):
                if json_file.suffix == '.log':
                    # Parse .log file for QPS
                    try:
                        with open(json_file, 'r') as f:
                            data = json.load(f)
                            qps_values.append(data.get('qps', 0))
                    except:
                        pass
                else:
                    # Parse main json for latencies
                    lats = reconstruct_latencies_from_histogram(json_file)
                    if lats:
                        latencies_all.extend(lats)

            if qps_values:
                qps_data[label] = np.mean(qps_values)
            if latencies_all:
                latency_data[label] = {
                    'p50': np.percentile(latencies_all, 50),
                    'p90': np.percentile(latencies_all, 90),
                    'p95': np.percentile(latencies_all, 95),
                    'p99': np.percentile(latencies_all, 99)
                }

        # Print raw values
        print(f"\nRaw QPS values:")
        for label in config_labels:
            if label in qps_data:
                print(f"  {label}: {qps_data[label]:.2f} QPS")

        print(f"\nRaw Latency values (ms):")
        for label in config_labels:
            if label in latency_data:
                ld = latency_data[label]
                print(f"  {label}: p50={ld['p50']:.2f}, p90={ld['p90']:.2f}, p95={ld['p95']:.2f}, p99={ld['p99']:.2f}")

        # Calculate overhead relative to baseline
        if 'Baseline' in qps_data and 'Baseline' in latency_data:
            baseline_qps = qps_data['Baseline']
            baseline_lat = latency_data['Baseline']

            print(f"\nQPS Overhead (lower is worse):")
            for label in config_labels:
                if label in qps_data and label != 'Baseline':
                    overhead = qps_data[label] / baseline_qps
                    print(f"  {label}: {overhead:.3f}x ({(1-overhead)*100:.1f}% slower)")

            print(f"\nLatency Overhead (higher is worse):")
            for label in config_labels:
                if label in latency_data and label != 'Baseline':
                    ld = latency_data[label]
                    print(f"  {label}:")
                    print(f"    p50: {ld['p50']/baseline_lat['p50']:.3f}x")
                    print(f"    p90: {ld['p90']/baseline_lat['p90']:.3f}x")
                    print(f"    p95: {ld['p95']/baseline_lat['p95']:.3f}x")
                    print(f"    p99: {ld['p99']/baseline_lat['p99']:.3f}x")

def generate_latex_table(script_dir, paper_dir, configs, config_labels):
    """Generate LaTeX table with QPS and latency percentiles for all payload sizes."""

    byte_sizes = [('0bytes', '0 B'), ('1024bytes', '1024 B')]

    # Collect all data
    all_data = {}
    for byte_size, byte_label in byte_sizes:
        all_data[byte_size] = {'qps': {}, 'latency': {}}

        for config, label in zip(configs, config_labels):
            config_dir = paper_dir / config / byte_size
            qps_values = []
            latencies_all = []

            for json_file in config_dir.glob("qps-result.json*"):
                if json_file.suffix == '.log':
                    try:
                        with open(json_file, 'r') as f:
                            data = json.load(f)
                            qps_values.append(data.get('qps', 0))
                    except:
                        pass
                else:
                    lats = reconstruct_latencies_from_histogram(json_file)
                    if lats:
                        latencies_all.extend(lats)

            if qps_values:
                all_data[byte_size]['qps'][label] = np.mean(qps_values)
            if latencies_all:
                all_data[byte_size]['latency'][label] = {
                    'p50': np.percentile(latencies_all, 50),
                    'p90': np.percentile(latencies_all, 90),
                    'p95': np.percentile(latencies_all, 95),
                    'p99': np.percentile(latencies_all, 99)
                }

    # Generate LaTeX table
    latex = []
    latex.append(r"\begin{table}[htbp]")
    latex.append(r"\centering")
    latex.append(r"\caption{gRPC benchmark: QPS and latency percentiles with overhead vs.\ baseline}")
    latex.append(r"\label{tab:grpc-benchmark}")
    latex.append(r"\begin{tabular}{llccccc}")
    latex.append(r"\toprule")
    latex.append(r"Payload & Scenario & QPS & P50 (ms) & P90 (ms) & P95 (ms) & P99 (ms) \\")
    latex.append(r"\midrule")

    for byte_size, byte_label in byte_sizes:
        qps_data = all_data[byte_size]['qps']
        latency_data = all_data[byte_size]['latency']
        baseline_qps = qps_data.get('Baseline', 1)
        baseline_lat = latency_data.get('Baseline', {})

        first_row = True
        for label in config_labels:
            qps = qps_data.get(label)
            lat = latency_data.get(label)

            if qps is None or lat is None:
                continue

            row_label = byte_label if first_row else ""
            first_row = False

            if label == 'Baseline':
                latex.append(f"{row_label} & {label} & {qps:.2f} & "
                            f"{lat['p50']:.1f} & {lat['p90']:.1f} & "
                            f"{lat['p95']:.1f} & {lat['p99']:.1f} \\\\")
            else:
                qps_oh = ((qps / baseline_qps) - 1) * 100
                p50_oh = ((lat['p50'] / baseline_lat['p50']) - 1) * 100
                p90_oh = ((lat['p90'] / baseline_lat['p90']) - 1) * 100
                p95_oh = ((lat['p95'] / baseline_lat['p95']) - 1) * 100
                p99_oh = ((lat['p99'] / baseline_lat['p99']) - 1) * 100

                latex.append(f"{row_label} & {label} & {qps:.2f} ({qps_oh:+.1f}\\%) & "
                            f"{lat['p50']:.1f} ({p50_oh:+.1f}\\%) & "
                            f"{lat['p90']:.1f} ({p90_oh:+.1f}\\%) & "
                            f"{lat['p95']:.1f} ({p95_oh:+.1f}\\%) & "
                            f"{lat['p99']:.1f} ({p99_oh:+.1f}\\%) \\\\")

        if byte_size == '0bytes':
            latex.append(r"\midrule")

    latex.append(r"\bottomrule")
    latex.append(r"\end{tabular}")
    latex.append(r"\end{table}")

    latex_str = "\n".join(latex)

    # Save to file
    output_file = script_dir / "qps_benchmark_table.tex"
    with open(output_file, 'w') as f:
        f.write(latex_str)

    print("\n" + "=" * 80)
    print(" LaTeX Table Generated")
    print("=" * 80)
    print(f"\nSaved to: {output_file}")
    print("\nTable content:")
    print("-" * 80)
    print(latex_str)
    print("-" * 80)

    return latex_str


if __name__ == "__main__":
    main()

    # Generate LaTeX table
    script_dir = Path(__file__).parent
    paper_dir = script_dir / "paper"
    configs = ['baseline_three', 'colored_three', 'corn_three']
    config_labels = ['Baseline', 'PICASSO', 'Cornucopia']
    generate_latex_table(script_dir, paper_dir, configs, config_labels)
