#!/usr/bin/env python3
"""
SQLite Speedtest1 Benchmark Analyzer
Compares baseline, colored, and cornucopia results.
Generates overhead comparison figures.
"""

import re
import argparse
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path


def parse_speedtest_log(filepath):
    """Parse a SQLite speedtest1 log file and extract phase timings."""
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    phases = {}
    
    # Pattern to match phase lines like:
    # 100 - 50000 INSERTs into table with no index......................   49.047s
    pattern = r'(\d+)\s+-\s+(.+?)\.{2,}\s+([\d.]+)s'
    
    for match in re.finditer(pattern, content):
        phase_id = match.group(1)
        phase_name = match.group(2).strip()
        time_sec = float(match.group(3))
        phases[phase_id] = {
            'name': phase_name,
            'time': time_sec
        }
    
    # Extract TOTAL
    total_match = re.search(r'TOTAL\.{2,}\s+([\d.]+)s', content)
    if total_match:
        phases['TOTAL'] = {
            'name': 'TOTAL',
            'time': float(total_match.group(1))
        }
    
    # Extract maximum resident set size (memory)
    mem_match = re.search(r'(\d+)\s+maximum resident set size', content)
    if mem_match:
        phases['MEMORY'] = {
            'name': 'Maximum Resident Set Size',
            'value': int(mem_match.group(1))
        }
    
    # Extract cycles
    cycles_match = re.search(r'cycles:\s+(\d+)', content)
    if cycles_match:
        phases['CYCLES'] = {
            'name': 'Cycles',
            'value': int(cycles_match.group(1))
        }
    
    # Extract instructions
    instr_match = re.search(r'instructions:\s+(\d+)', content)
    if instr_match:
        phases['INSTRUCTIONS'] = {
            'name': 'Instructions',
            'value': int(instr_match.group(1))
        }
    
    # Extract real time (e.g., "5697.32 real")
    real_match = re.search(r'([\d.]+)\s+real', content)
    if real_match:
        phases['REAL_TIME'] = {
            'name': 'Real Time',
            'value': float(real_match.group(1))
        }
    
    # Extract user time
    user_match = re.search(r'([\d.]+)\s+user', content)
    if user_match:
        phases['USER_TIME'] = {
            'name': 'User Time',
            'value': float(user_match.group(1))
        }
    
    # Extract sys time
    sys_match = re.search(r'([\d.]+)\s+sys', content)
    if sys_match:
        phases['SYS_TIME'] = {
            'name': 'System Time',
            'value': float(sys_match.group(1))
        }
    perf_counters = []
    # Extract hardware performance counters
    #perf_counters = [
    #    # Branch and control flow
    #    ('redirect', 'Redirects'),
    #    ('branch', 'Branches'),
    #    ('jal', 'JAL Instructions'),
    #    ('jalr', 'JALR Instructions'),
    #    ('trap', 'Traps'),
        # Memory wait times
    #    ('load_wait', 'Load Wait Cycles'),
        # Capability tag operations
    #    ('cap_load_tag_set', 'Capability Load Tag Set'),
    #    ('cap_store_tag_set', 'Capability Store Tag Set'),
        # Instruction TLB and cache
    #    ('itlb_miss_wait', 'ITLB Miss Wait'),
    #    ('icache_load', 'ICache Loads'),
    #    ('icache_load_miss', 'ICache Load Misses'),
    #    ('icache_load_miss_wait', 'ICache Miss Wait'),
        # Data TLB
    #    ('dtlb_access', 'DTLB Accesses'),
    #    ('dtlb_miss', 'DTLB Misses'),
    #    ('dtlb_miss_wait', 'DTLB Miss Wait'),
        # Data cache
    #    ('dcache_load', 'DCache Loads'),
    #    ('dcache_load_miss', 'DCache Load Misses'),
    #    ('dcache_load_miss_wait', 'DCache Load Miss Wait'),
    #    ('dcache_store', 'DCache Stores'),
    #    ('dcache_store_miss', 'DCache Store Misses'),
        # Last-level cache
    #    ('llcache_load_miss', 'LLC Load Misses'),
    #    ('llcache_load_miss_wait', 'LLC Load Miss Wait'),
        # Tag cache
    #    ('tagcache_load', 'TagCache Loads'),
    #    ('tagcache_load_miss', 'TagCache Load Misses'),
    #    ('tagcache_store', 'TagCache Stores'),
    #    ('tagcache_store_miss', 'TagCache Store Misses'),
    #    ('tagcache_evict', 'TagCache Evictions'),
    #]

    for counter_key, counter_name in perf_counters:
        pattern = rf'{counter_key}:\s+(\d+)'
        match = re.search(pattern, content)
        if match:
            phases[counter_key.upper()] = {
                'name': counter_name,
                'value': int(match.group(1))
            }

    return phases


def calculate_overhead(baseline_time, other_time):
    """Calculate overhead as a factor (e.g., 1.05x means 5% overhead)."""
    if baseline_time != 0:
        return other_time / baseline_time
    return 1.0


def plot_stat_group(group_name, group_info, baseline, colored, cornucopia, cornucopia_rof, script_dir):
    """Plot a group of hardware stats as a bar chart showing overhead."""
    stats = group_info['stats']
    title = group_info['title']

    # Filter to stats that exist in all datasets
    valid_stats = []
    for stat_key, stat_label in stats:
        if stat_key in baseline and stat_key in colored and stat_key in cornucopia:
            valid_stats.append((stat_key, stat_label))

    if not valid_stats:
        return None

    fig, ax = plt.subplots(figsize=(6, 4))

    stat_labels = [label for _, label in valid_stats]
    x = np.arange(len(stat_labels))

    colored_oh = []
    cornucopia_oh = []
    cornucopia_rof_oh = []

    for stat_key, _ in valid_stats:
        b_val = baseline[stat_key]['value']
        c_val = colored[stat_key]['value']
        corn_val = cornucopia[stat_key]['value']

        colored_oh.append(calculate_overhead(b_val, c_val))
        cornucopia_oh.append(calculate_overhead(b_val, corn_val))

        if cornucopia_rof and stat_key in cornucopia_rof:
            rof_val = cornucopia_rof[stat_key]['value']
            cornucopia_rof_oh.append(calculate_overhead(b_val, rof_val))

    if cornucopia_rof and len(cornucopia_rof_oh) == len(valid_stats):
        width = 0.25
        bars1 = ax.bar(x - width, colored_oh, width, label='PICASSO', color='#cc79a7')
        bars2 = ax.bar(x, cornucopia_oh, width, label='Cornucupia', color='#0072b2')
        bars3 = ax.bar(x + width, cornucopia_rof_oh, width, label='Cornucupia (RoF)', color='#9b59b6', alpha=0.8)
    else:
        width = 0.25
        bars1 = ax.bar(x - width/2, colored_oh, width, label='PICASSO', color='#cc79a7')
        bars2 = ax.bar(x + width/2, cornucopia_oh, width, label='Cornucupia', color='#0072b2')
        bars3 = None

    # Add baseline reference line
    ax.axhline(y=1.0, color='black', linestyle='--', linewidth=1, label='Baseline (1.0x)')

    ax.set_ylabel('Overhead Factor', fontsize=12)
    ax.set_xticks(x)
    ax.set_xticklabels(stat_labels, rotation=45, ha='right')
    ax.legend()
    ax.grid(True, alpha=0.3, axis='y')
    ax.set_ylim(bottom=0.9)

    # Add value labels
    for bar in bars1:
        if bar.get_height() > 0:
            ax.annotate(f'{bar.get_height():.2f}x',
                        xy=(bar.get_x() + bar.get_width() / 2, bar.get_height()),
                        xytext=(0, 3),
                        textcoords='offset points',
                        ha='center', va='bottom', fontsize=8, rotation=90)

    for bar in bars2:
        if bar.get_height() > 0:
            ax.annotate(f'{bar.get_height():.2f}x',
                        xy=(bar.get_x() + bar.get_width() / 2, bar.get_height()),
                        xytext=(0, 3),
                        textcoords='offset points',
                        ha='center', va='bottom', fontsize=8, rotation=90)

    if bars3:
        for bar in bars3:
            if bar.get_height() > 0:
                ax.annotate(f'{bar.get_height():.2f}x',
                            xy=(bar.get_x() + bar.get_width() / 2, bar.get_height()),
                            xytext=(0, 3),
                            textcoords='offset points',
                            ha='center', va='bottom', fontsize=8, rotation=90)

    plt.tight_layout()
    png_path = script_dir / f'sqlite_{group_name}_stats.png'
    pdf_path = script_dir / f'sqlite_{group_name}_stats.pdf'
    plt.savefig(png_path, dpi=150, bbox_inches='tight')
    plt.savefig(pdf_path, bbox_inches='tight')
    plt.close(fig)

    return png_path, pdf_path


def plot_absolute_values(group_name, group_info, baseline, colored, cornucopia, cornucopia_rof, script_dir):
    """Plot absolute values for a group of hardware stats."""
    stats = group_info['stats']
    title = group_info['title']

    # Filter to stats that exist in all datasets
    valid_stats = []
    for stat_key, stat_label in stats:
        if stat_key in baseline and stat_key in colored and stat_key in cornucopia:
            valid_stats.append((stat_key, stat_label))

    if not valid_stats:
        return None

    fig, ax = plt.subplots(figsize=(12, 6))

    stat_labels = [label for _, label in valid_stats]
    x = np.arange(len(stat_labels))

    baseline_vals = [baseline[k]['value'] for k, _ in valid_stats]
    colored_vals = [colored[k]['value'] for k, _ in valid_stats]
    cornucopia_vals = [cornucopia[k]['value'] for k, _ in valid_stats]

    if cornucopia_rof:
        rof_vals = []
        for stat_key, _ in valid_stats:
            if stat_key in cornucopia_rof:
                rof_vals.append(cornucopia_rof[stat_key]['value'])
        if len(rof_vals) == len(valid_stats):
            width = 0.2
            ax.bar(x - 1.5*width, baseline_vals, width, label='Baseline', color='#3498db', edgecolor='black')
            ax.bar(x - 0.5*width, colored_vals, width, label='PICASSO', color='#2ecc71', edgecolor='black')
            ax.bar(x + 0.5*width, cornucopia_vals, width, label='Cornucopia', color='#e74c3c', edgecolor='black')
            ax.bar(x + 1.5*width, rof_vals, width, label='Cornucopia (RoF)', color='#9b59b6', edgecolor='black')
        else:
            width = 0.25
            ax.bar(x - width, baseline_vals, width, label='Baseline', color='#3498db', edgecolor='black')
            ax.bar(x, colored_vals, width, label='PICASSO', color='#2ecc71', edgecolor='black')
            ax.bar(x + width, cornucopia_vals, width, label='Cornucopia', color='#e74c3c', edgecolor='black')
    else:
        width = 0.25
        ax.bar(x - width, baseline_vals, width, label='Baseline', color='#3498db', edgecolor='black')
        ax.bar(x, colored_vals, width, label='PICASSO', color='#2ecc71', edgecolor='black')
        ax.bar(x + width, cornucopia_vals, width, label='Cornucopia', color='#e74c3c', edgecolor='black')

    ax.set_ylabel('Count', fontsize=12)
    ax.set_title(f'SQLite: {title} (Absolute Values)', fontsize=14, fontweight='bold')
    ax.set_xticks(x)
    ax.set_xticklabels(stat_labels, rotation=45, ha='right', fontsize=10)
    ax.legend(loc='upper right', fontsize=10)
    ax.grid(axis='y', alpha=0.3)

    # Use scientific notation for large values
    ax.ticklabel_format(style='scientific', axis='y', scilimits=(0, 0))

    plt.tight_layout()
    png_path = script_dir / f'sqlite_{group_name}_absolute.png'
    pdf_path = script_dir / f'sqlite_{group_name}_absolute.pdf'
    plt.savefig(png_path, dpi=150, bbox_inches='tight')
    plt.savefig(pdf_path, bbox_inches='tight')
    plt.close(fig)

    return png_path, pdf_path


def print_stat_group_table(group_name, group_info, baseline, colored, cornucopia, cornucopia_rof):
    """Print a formatted table for a group of hardware stats."""
    stats = group_info['stats']
    title = group_info['title']

    print(f"\n{title}:")
    if cornucopia_rof:
        print(f"  {'Stat':<25} {'Baseline':>18} {'PICASSO':>18} {'Cornucopia':>18} {'Corn-RoF':>18} {'PIC-OH':>10} {'Corn-OH':>10} {'RoF-OH':>10}")
        print(f"  {'-'*139}")
    else:
        print(f"  {'Stat':<25} {'Baseline':>18} {'PICASSO':>18} {'Cornucopia':>18} {'PIC-OH':>10} {'Corn-OH':>10}")
        print(f"  {'-'*109}")

    for stat_key, stat_label in stats:
        if stat_key in baseline and stat_key in colored and stat_key in cornucopia:
            b_val = baseline[stat_key]['value']
            c_val = colored[stat_key]['value']
            corn_val = cornucopia[stat_key]['value']
            c_oh = calculate_overhead(b_val, c_val)
            corn_oh = calculate_overhead(b_val, corn_val)

            if cornucopia_rof and stat_key in cornucopia_rof:
                rof_val = cornucopia_rof[stat_key]['value']
                rof_oh = calculate_overhead(b_val, rof_val)
                print(f"  {stat_label:<25} {b_val:>18,} {c_val:>18,} {corn_val:>18,} {rof_val:>18,} {c_oh:>9.2f}x {corn_oh:>9.2f}x {rof_oh:>9.2f}x")
            else:
                print(f"  {stat_label:<25} {b_val:>18,} {c_val:>18,} {corn_val:>18,} {c_oh:>9.2f}x {corn_oh:>9.2f}x")


def get_stat_groups():
    """Define groups of hardware stats for analysis."""
    return {
        'dcache': {
            'title': 'Data Cache Statistics',
            'stats': [
                ('DCACHE_LOAD', 'DCache Loads'),
                ('DCACHE_LOAD_MISS', 'DCache Load Misses'),
                ('DCACHE_LOAD_MISS_WAIT', 'DCache Load Miss Wait'),
                ('DCACHE_STORE', 'DCache Stores'),
                ('DCACHE_STORE_MISS', 'DCache Store Misses'),
            ]
        },
        'icache': {
            'title': 'Instruction Cache Statistics',
            'stats': [
                ('ICACHE_LOAD', 'ICache Loads'),
                ('ICACHE_LOAD_MISS', 'ICache Load Misses'),
                ('ICACHE_LOAD_MISS_WAIT', 'ICache Miss Wait'),
            ]
        },
        'tagcache': {
            'title': 'Tag Cache Statistics',
            'stats': [
                ('TAGCACHE_LOAD', 'TagCache Loads'),
                ('TAGCACHE_LOAD_MISS', 'TagCache Load Misses'),
                ('TAGCACHE_STORE', 'TagCache Stores'),
                ('TAGCACHE_STORE_MISS', 'TagCache Store Misses'),
                ('TAGCACHE_EVICT', 'TagCache Evictions'),
            ]
        },
        'tlb': {
            'title': 'TLB Statistics',
            'stats': [
                ('DTLB_ACCESS', 'DTLB Accesses'),
                ('DTLB_MISS', 'DTLB Misses'),
                ('DTLB_MISS_WAIT', 'DTLB Miss Wait'),
                ('ITLB_MISS_WAIT', 'ITLB Miss Wait'),
            ]
        },
        'branch': {
            'title': 'Branch and Control Flow',
            'stats': [
                ('REDIRECT', 'Redirects'),
                ('BRANCH', 'Branches'),
                ('JAL', 'JAL Instructions'),
                ('JALR', 'JALR Instructions'),
                ('TRAP', 'Traps'),
            ]
        },
        'capability': {
            'title': 'Capability Operations',
            'stats': [
                ('CAP_LOAD_TAG_SET', 'Cap Load Tag Set'),
                ('CAP_STORE_TAG_SET', 'Cap Store Tag Set'),
            ]
        },
        'llcache': {
            'title': 'Last-Level Cache Statistics',
            'stats': [
                ('LLCACHE_LOAD_MISS', 'LLC Load Misses'),
                ('LLCACHE_LOAD_MISS_WAIT', 'LLC Load Miss Wait'),
            ]
        },
        'wait': {
            'title': 'Wait Cycles',
            'stats': [
                ('LOAD_WAIT', 'Load Wait Cycles'),
            ]
        },
    }


def main():
    parser = argparse.ArgumentParser(
        description='SQLite Speedtest1 Benchmark Analyzer - Compares baseline, colored, and cornucopia results.'
    )
    parser.add_argument(
        '--rof', '--revoke-on-free',
        action='store_true',
        dest='include_rof',
        help='Include Cornucopia Revoke-on-Free results in the analysis (requires cornucupia_revoke_on_free.txt)'
    )
    args = parser.parse_args()

    script_dir = Path(__file__).parent

    # Define log files
    baseline_file = script_dir / 'baseline.txt'
    colored_file = script_dir / 'colored_paper.txt'
    cornucopia_file = script_dir / 'cornucupia_sqlite.txt'
    cornucopia_rof_file = script_dir / 'cornucupia_revoke_on_free.txt'

    # Parse all logs
    baseline = parse_speedtest_log(baseline_file)
    colored = parse_speedtest_log(colored_file)
    cornucopia = parse_speedtest_log(cornucopia_file)

    # Only include revoke-on-free if explicitly requested via --rof flag
    cornucopia_rof = None
    if args.include_rof:
        if cornucopia_rof_file.exists():
            cornucopia_rof = parse_speedtest_log(cornucopia_rof_file)
        else:
            print(f"Warning: --rof flag specified but {cornucopia_rof_file} not found. Skipping RoF analysis.")
    
    print("=" * 120)
    print(" SQLITE SPEEDTEST1 BENCHMARK ANALYSIS")
    print(" Baseline vs PICASSO vs Cornucopia vs Cornucopia (Revoke-on-Free)")
    print("=" * 120)
    
    # Print detailed comparison table
    if cornucopia_rof:
        print(f"\n{'Phase':<6} {'Description':<38} {'Baseline':>10} {'PICASSO':>10} {'Cornucopia':>11} {'Corn-RoF':>10} {'PIC-OH':>10} {'Corn-OH':>10} {'RoF-OH':>10}")
        print("-" * 136)
    else:
        print(f"\n{'Phase':<6} {'Description':<45} {'Baseline':>10} {'PICASSO':>10} {'Cornucopia':>10} {'PIC-OH':>10} {'Corn-OH':>10}")
        print("-" * 111)
    
    # Get only numeric phase IDs (exclude TOTAL, metrics, and hardware counters)
    phase_ids = sorted([p for p in baseline.keys() if p.isdigit()], key=lambda x: int(x))
    
    overhead_colored = []
    overhead_cornucopia = []
    overhead_cornucopia_rof = []
    phase_labels = []
    
    for phase_id in phase_ids:
        if phase_id in baseline and phase_id in colored and phase_id in cornucopia:
            b_time = baseline[phase_id]['time']
            c_time = colored[phase_id]['time']
            corn_time = cornucopia[phase_id]['time']
            
            c_oh = calculate_overhead(b_time, c_time)
            corn_oh = calculate_overhead(b_time, corn_time)
            
            name = baseline[phase_id]['name'][:38]
            
            if cornucopia_rof and phase_id in cornucopia_rof:
                rof_time = cornucopia_rof[phase_id]['time']
                rof_oh = calculate_overhead(b_time, rof_time)
                overhead_cornucopia_rof.append(rof_oh)
                print(f"{phase_id:<6} {name:<38} {b_time:>10.3f} {c_time:>10.3f} {corn_time:>11.3f} {rof_time:>10.3f} {c_oh:>9.2f}x {corn_oh:>9.2f}x {rof_oh:>9.2f}x")
            else:
                print(f"{phase_id:<6} {name:<45} {b_time:>10.3f} {c_time:>10.3f} {corn_time:>10.3f} {c_oh:>9.2f}x {corn_oh:>9.2f}x")
            
            overhead_colored.append(c_oh)
            overhead_cornucopia.append(corn_oh)
            phase_labels.append(f"{phase_id}")
    
    # Print TOTAL
    if cornucopia_rof:
        print("-" * 136)
    else:
        print("-" * 111)
    if 'TOTAL' in baseline and 'TOTAL' in colored and 'TOTAL' in cornucopia:
        b_total = baseline['TOTAL']['time']
        c_total = colored['TOTAL']['time']
        corn_total = cornucopia['TOTAL']['time']
        c_oh_total = calculate_overhead(b_total, c_total)
        corn_oh_total = calculate_overhead(b_total, corn_total)
        
        if cornucopia_rof and 'TOTAL' in cornucopia_rof:
            rof_total = cornucopia_rof['TOTAL']['time']
            rof_oh_total = calculate_overhead(b_total, rof_total)
            print(f"{'TOTAL':<6} {'':<38} {b_total:>10.3f} {c_total:>10.3f} {corn_total:>11.3f} {rof_total:>10.3f} {c_oh_total:>9.2f}x {corn_oh_total:>9.2f}x {rof_oh_total:>9.2f}x")
        else:
            print(f"{'TOTAL':<6} {'':<45} {b_total:>10.3f} {c_total:>10.3f} {corn_total:>10.3f} {c_oh_total:>9.2f}x {corn_oh_total:>9.2f}x")
    
    # Create figure with overhead comparison (wider for double column)
    fig, ax = plt.subplots(figsize=(12, 3))

    x = np.arange(len(phase_labels))

    if cornucopia_rof and len(overhead_cornucopia_rof) == len(phase_labels):
        width = 0.25
        bars1 = ax.bar(x - width, overhead_colored, width, label='PICASSO', color='#cc79a7', alpha=0.8)
        bars2 = ax.bar(x, overhead_cornucopia, width, label='Cornucupia', color='#0072b2', alpha=0.8)
        bars3 = ax.bar(x + width, overhead_cornucopia_rof, width, label='Cornucupia (RoF)', color='#9b59b6', alpha=0.8)
    else:
        width = 0.35
        bars1 = ax.bar(x - width/2, overhead_colored, width, label='PICASSO', color='#cc79a7', alpha=0.8)
        bars2 = ax.bar(x + width/2, overhead_cornucopia, width, label='Cornucupia', color='#0072b2', alpha=0.8)

    # Add baseline reference line
    ax.axhline(y=1.0, color='black', linestyle='--', linewidth=1, label='Baseline (1.0x)')

    # Add TOTAL overhead lines for PICASSO and Cornucopia
    if 'TOTAL' in baseline and 'TOTAL' in colored and 'TOTAL' in cornucopia:
        ax.axhline(y=c_oh_total, color='#cc79a7', linestyle=':', linewidth=2, alpha=0.5)
        ax.text(-1.8, c_oh_total, f'{c_oh_total:.2f}x',
                va='bottom', ha='left', fontsize=9, color='#cc79a7')
        ax.axhline(y=corn_oh_total, color='#0072b2', linestyle=':', linewidth=2, alpha=0.5)
        ax.text(-1.8, corn_oh_total, f'{corn_oh_total:.2f}x',
                va='bottom', ha='left', fontsize=8, color='#0072b2')
        if cornucopia_rof and 'TOTAL' in cornucopia_rof:
            ax.axhline(y=rof_oh_total, color='#9b59b6', linestyle=':', linewidth=2, alpha=0.5)
            ax.text(-1.8, rof_oh_total, f'{rof_oh_total:.2f}x',
                    va='bottom', ha='left', fontsize=8, color='#9b59b6')
    ax.set_xlabel('Phase ID', fontsize=12)
    ax.set_ylabel('Overhead Factor', fontsize=12)
    ax.set_xticks(x)
    ax.set_xticklabels(phase_labels, rotation=45, ha='right')
    ax.legend()
    ax.grid(True, alpha=0.3, axis='y')
    ax.set_ylim(bottom=0.9)

    # Add value labels on bars
    for bar in bars1:
        if bar.get_height() > 0:
            ax.annotate(f'{bar.get_height():.2f}x',
                        xy=(bar.get_x() + bar.get_width() / 2, bar.get_height()),
                        xytext=(0, 3),
                        textcoords='offset points',
                        ha='center', va='bottom', fontsize=8, rotation=90)

    for bar in bars2:
        if bar.get_height() > 0:
            ax.annotate(f'{bar.get_height():.2f}x',
                        xy=(bar.get_x() + bar.get_width() / 2, bar.get_height()),
                        xytext=(0, 3),
                        textcoords='offset points',
                        ha='center', va='bottom', fontsize=8, rotation=90)
    # Annotate RoF bars if present
    if cornucopia_rof and len(overhead_cornucopia_rof) == len(phase_labels):
        for bar in bars3:
            if bar.get_height() > 0:
                ax.annotate(f'{bar.get_height():.2f}x',
                            xy=(bar.get_x() + bar.get_width() / 2, bar.get_height()),
                            xytext=(0, 3),
                            textcoords='offset points',
                            ha='center', va='bottom', fontsize=8, rotation=90)
    
    plt.tight_layout()
    plt.savefig(script_dir / 'sqlite_overhead_comparison.png', dpi=150, bbox_inches='tight')
    plt.savefig(script_dir / 'sqlite_overhead_comparison.pdf', bbox_inches='tight', pad_inches=0.05)
    print(f"\n[+] Figure saved: {script_dir / 'sqlite_overhead_comparison.png'}")
    print(f"[+] Figure saved: {script_dir / 'sqlite_overhead_comparison.pdf'}")
    
    # Create a second figure with absolute times
    fig2, ax2 = plt.subplots(figsize=(18, 8))
    
    baseline_times = [baseline[p]['time'] for p in phase_ids if p in baseline]
    colored_times = [colored[p]['time'] for p in phase_ids if p in colored]
    cornucopia_times = [cornucopia[p]['time'] for p in phase_ids if p in cornucopia]
    
    if cornucopia_rof:
        cornucopia_rof_times = [cornucopia_rof[p]['time'] for p in phase_ids if p in cornucopia_rof]
        width = 0.2
        bars1 = ax2.bar(x - 1.5*width, baseline_times, width, label='Baseline', color='#3498db', edgecolor='black')
        bars2 = ax2.bar(x - 0.5*width, colored_times, width, label='PICASSO', color='#2ecc71', edgecolor='black')
        bars3 = ax2.bar(x + 0.5*width, cornucopia_times, width, label='Cornucopia', color='#e74c3c', edgecolor='black')
        bars4 = ax2.bar(x + 1.5*width, cornucopia_rof_times, width, label='Cornucopia (RoF)', color='#9b59b6', edgecolor='black')
    else:
        width = 0.25
        bars1 = ax2.bar(x - width, baseline_times, width, label='Baseline', color='#3498db', edgecolor='black')
        bars2 = ax2.bar(x, colored_times, width, label='PICASSO', color='#2ecc71', edgecolor='black')
        bars3 = ax2.bar(x + width, cornucopia_times, width, label='Cornucopia', color='#e74c3c', edgecolor='black')
    
    ax2.set_xlabel('Phase ID', fontsize=12)
    ax2.set_ylabel('Time (seconds)', fontsize=12)
    ax2.set_title('SQLite Speedtest1: Execution Time by Phase', fontsize=14, fontweight='bold')
    ax2.set_xticks(x)
    ax2.set_xticklabels(phase_labels, rotation=45, ha='right', fontsize=9)
    ax2.legend(loc='upper left', fontsize=11)
    ax2.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(script_dir / 'sqlite_time_comparison.png', dpi=150)
    plt.savefig(script_dir / 'sqlite_time_comparison.pdf', bbox_inches='tight')
    print(f"[+] Figure saved: {script_dir / 'sqlite_time_comparison.png'}")
    print(f"[+] Figure saved: {script_dir / 'sqlite_time_comparison.pdf'}")
    
    # Summary statistics
    print(f"\n{'='*120}")
    print(" SUMMARY STATISTICS")
    print(f"{'='*120}")
    print(f"\nTotal Execution Time:")
    print(f"  Baseline:           {b_total:>10.3f}s")
    print(f"  PICASSO:            {c_total:>10.3f}s  (Overhead: {c_oh_total:.2f}x)")
    print(f"  Cornucopia:         {corn_total:>10.3f}s  (Overhead: {corn_oh_total:.2f}x)")
    if cornucopia_rof and 'TOTAL' in cornucopia_rof:
        print(f"  Cornucopia (RoF):   {rof_total:>10.3f}s  (Overhead: {rof_oh_total:.2f}x)")
    
    # Memory comparison
    print(f"\nMemory Usage (Maximum Resident Set Size):")
    if 'MEMORY' in baseline and 'MEMORY' in colored and 'MEMORY' in cornucopia:
        b_mem = baseline['MEMORY']['value']
        c_mem = colored['MEMORY']['value']
        corn_mem = cornucopia['MEMORY']['value']
        c_mem_oh = calculate_overhead(b_mem, c_mem)
        corn_mem_oh = calculate_overhead(b_mem, corn_mem)
        
        print(f"  Baseline:           {b_mem:>10} KB")
        print(f"  PICASSO:            {c_mem:>10} KB  (Overhead: {c_mem_oh:.2f}x)")
        print(f"  Cornucopia:         {corn_mem:>10} KB  (Overhead: {corn_mem_oh:.2f}x)")
        if cornucopia_rof and 'MEMORY' in cornucopia_rof:
            rof_mem = cornucopia_rof['MEMORY']['value']
            rof_mem_oh = calculate_overhead(b_mem, rof_mem)
            print(f"  Cornucopia (RoF):   {rof_mem:>10} KB  (Overhead: {rof_mem_oh:.2f}x)")
    
    # Cycles comparison
    print(f"\nCycles:")
    if 'CYCLES' in baseline and 'CYCLES' in colored and 'CYCLES' in cornucopia:
        b_cyc = baseline['CYCLES']['value']
        c_cyc = colored['CYCLES']['value']
        corn_cyc = cornucopia['CYCLES']['value']
        c_cyc_oh = calculate_overhead(b_cyc, c_cyc)
        corn_cyc_oh = calculate_overhead(b_cyc, corn_cyc)
        
        print(f"  Baseline:           {b_cyc:>20,}")
        print(f"  PICASSO:            {c_cyc:>20,}  (Overhead: {c_cyc_oh:.2f}x)")
        print(f"  Cornucopia:         {corn_cyc:>20,}  (Overhead: {corn_cyc_oh:.2f}x)")
        if cornucopia_rof and 'CYCLES' in cornucopia_rof:
            rof_cyc = cornucopia_rof['CYCLES']['value']
            rof_cyc_oh = calculate_overhead(b_cyc, rof_cyc)
            print(f"  Cornucopia (RoF):   {rof_cyc:>20,}  (Overhead: {rof_cyc_oh:.2f}x)")
    
    # Instructions comparison
    print(f"\nInstructions:")
    if 'INSTRUCTIONS' in baseline and 'INSTRUCTIONS' in colored and 'INSTRUCTIONS' in cornucopia:
        b_ins = baseline['INSTRUCTIONS']['value']
        c_ins = colored['INSTRUCTIONS']['value']
        corn_ins = cornucopia['INSTRUCTIONS']['value']
        c_ins_oh = calculate_overhead(b_ins, c_ins)
        corn_ins_oh = calculate_overhead(b_ins, corn_ins)
        
        print(f"  Baseline:           {b_ins:>20,}")
        print(f"  PICASSO:            {c_ins:>20,}  (Overhead: {c_ins_oh:.2f}x)")
        print(f"  Cornucopia:         {corn_ins:>20,}  (Overhead: {corn_ins_oh:.2f}x)")
        if cornucopia_rof and 'INSTRUCTIONS' in cornucopia_rof:
            rof_ins = cornucopia_rof['INSTRUCTIONS']['value']
            rof_ins_oh = calculate_overhead(b_ins, rof_ins)
            print(f"  Cornucopia (RoF):   {rof_ins:>20,}  (Overhead: {rof_ins_oh:.2f}x)")
    
    # Real Time comparison
    print(f"\nReal Time:")
    if 'REAL_TIME' in baseline and 'REAL_TIME' in colored and 'REAL_TIME' in cornucopia:
        b_rt = baseline['REAL_TIME']['value']
        c_rt = colored['REAL_TIME']['value']
        corn_rt = cornucopia['REAL_TIME']['value']
        c_rt_oh = calculate_overhead(b_rt, c_rt)
        corn_rt_oh = calculate_overhead(b_rt, corn_rt)
        
        print(f"  Baseline:           {b_rt:>10.2f}s")
        print(f"  PICASSO:            {c_rt:>10.2f}s  (Overhead: {c_rt_oh:.2f}x)")
        print(f"  Cornucopia:         {corn_rt:>10.2f}s  (Overhead: {corn_rt_oh:.2f}x)")
        if cornucopia_rof and 'REAL_TIME' in cornucopia_rof:
            rof_rt = cornucopia_rof['REAL_TIME']['value']
            rof_rt_oh = calculate_overhead(b_rt, rof_rt)
            print(f"  Cornucopia (RoF):   {rof_rt:>10.2f}s  (Overhead: {rof_rt_oh:.2f}x)")
    
    # Create System Metrics Overhead Figure
    fig3, ax3 = plt.subplots(figsize=(6, 4))
    
    # Prepare data for the bar charts
    metrics_names = []
    colored_overheads_sys = []
    cornucopia_overheads_sys = []
    cornucopia_rof_overheads_sys = []
    
    system_metrics = [
        ('Cycles', 'CYCLES'),
        ('Instructions', 'INSTRUCTIONS'),
        ('Memory (RSS)', 'MEMORY'),
    ]
    
    for name, key in system_metrics:
        if key in baseline and key in colored and key in cornucopia:
            b_val = baseline[key]['value']
            c_val = colored[key]['value']
            corn_val = cornucopia[key]['value']
            metrics_names.append(name)
            colored_overheads_sys.append(calculate_overhead(b_val, c_val))
            cornucopia_overheads_sys.append(calculate_overhead(b_val, corn_val))
            if cornucopia_rof and key in cornucopia_rof:
                rof_val = cornucopia_rof[key]['value']
                cornucopia_rof_overheads_sys.append(calculate_overhead(b_val, rof_val))
    
    # Overhead comparison
    x = np.arange(len(metrics_names))
    
    if cornucopia_rof and len(cornucopia_rof_overheads_sys) == len(metrics_names):
        width = 0.25
        bars1 = ax3.bar(x - width, colored_overheads_sys, width, label='PICASSO', color='#cc79a7')
        bars2 = ax3.bar(x, cornucopia_overheads_sys, width, label='Cornucupia', color='#0072b2')
        bars3 = ax3.bar(x + width, cornucopia_rof_overheads_sys, width, label='Cornucupia (RoF)', color='#9b59b6')
    else:
        width = 0.25
        bars1 = ax3.bar(x - width/2, colored_overheads_sys, width, label='PICASSO', color='#cc79a7')
        bars2 = ax3.bar(x + width/2, cornucopia_overheads_sys, width, label='Cornucupia', color='#0072b2')

    # Add baseline reference line
    ax3.axhline(y=1.0, color='black', linestyle='--', linewidth=1, label='Baseline (1.0x)')

    ax3.set_ylabel('Overhead Factor', fontsize=12)
    ax3.set_xticks(x)
    ax3.set_xticklabels(metrics_names, rotation=0, ha='center')
    ax3.legend()
    ax3.grid(True, alpha=0.3, axis='y')
    ax3.set_ylim(bottom=0.9)

    # Add value labels on bars
    for bar in bars1:
        if bar.get_height() > 0:
            ax3.annotate(f'{bar.get_height():.2f}x',
                        xy=(bar.get_x() + bar.get_width() / 2, bar.get_height()),
                        xytext=(0, 3),
                        textcoords='offset points',
                        ha='center', va='bottom', fontsize=8, rotation=90)

    for bar in bars2:
        if bar.get_height() > 0:
            ax3.annotate(f'{bar.get_height():.2f}x',
                        xy=(bar.get_x() + bar.get_width() / 2, bar.get_height()),
                        xytext=(0, 3),
                        textcoords='offset points',
                        ha='center', va='bottom', fontsize=8, rotation=90)
    # Annotate RoF bars if present
    if cornucopia_rof and len(cornucopia_rof_overheads_sys) == len(metrics_names):
        for bar in bars3:
            if bar.get_height() > 0:
                ax3.annotate(f'{bar.get_height():.2f}x',
                            xy=(bar.get_x() + bar.get_width() / 2, bar.get_height()),
                            xytext=(0, 3),
                            textcoords='offset points',
                            ha='center', va='bottom', fontsize=8, rotation=90)
    
    plt.tight_layout()
    plt.savefig(script_dir / 'sqlite_system_metrics.png', dpi=150)
    plt.savefig(script_dir / 'sqlite_system_metrics.pdf', bbox_inches='tight')
    print(f"\n[+] Figure saved: {script_dir / 'sqlite_system_metrics.png'}")
    print(f"[+] Figure saved: {script_dir / 'sqlite_system_metrics.pdf'}")

    # Generate plots for hardware performance counter groups
    print(f"\n{'='*120}")
    #print(" HARDWARE PERFORMANCE COUNTER ANALYSIS")
    print(f"{'='*120}")

    stat_groups = get_stat_groups()
    for group_name, group_info in stat_groups.items():
        print(f"\nProcessing {group_info['title']}...")

        # Print table for this stat group
        print_stat_group_table(group_name, group_info, baseline, colored, cornucopia, cornucopia_rof)

        # Plot overhead comparison
        result = plot_stat_group(group_name, group_info, baseline, colored, cornucopia, cornucopia_rof, script_dir)
        if result:
            png_path, pdf_path = result
            print(f"  [+] Saved: {png_path.name}, {pdf_path.name}")

        # Plot absolute values
        result = plot_absolute_values(group_name, group_info, baseline, colored, cornucopia, cornucopia_rof, script_dir)
        if result:
            png_path, pdf_path = result
            print(f"  [+] Saved: {png_path.name}, {pdf_path.name}")

    print(f"\n{'='*120}")

    print(f"\nAverage Overhead per Phase:")
    print(f"  PICASSO:            {np.mean(overhead_colored):.2f}x")
    print(f"  Cornucopia:         {np.mean(overhead_cornucopia):.2f}x")
    if cornucopia_rof and len(overhead_cornucopia_rof) > 0:
        print(f"  Cornucopia (RoF):   {np.mean(overhead_cornucopia_rof):.2f}x")

    print(f"\nMax Overhead per Phase:")
    max_c_idx = np.argmax(overhead_colored)
    max_corn_idx = np.argmax(overhead_cornucopia)
    print(f"  PICASSO:            {overhead_colored[max_c_idx]:.2f}x (Phase {phase_labels[max_c_idx]})")
    print(f"  Cornucopia:         {overhead_cornucopia[max_corn_idx]:.2f}x (Phase {phase_labels[max_corn_idx]})")
    if cornucopia_rof and len(overhead_cornucopia_rof) > 0:
        max_rof_idx = np.argmax(overhead_cornucopia_rof)
        print(f"  Cornucopia (RoF):   {overhead_cornucopia_rof[max_rof_idx]:.2f}x (Phase {phase_labels[max_rof_idx]})")
    
    print(f"\n{'='*120}")
    print(" END OF REPORT")
    print(f"{'='*120}\n")
    
    plt.show()


if __name__ == "__main__":
    main()
