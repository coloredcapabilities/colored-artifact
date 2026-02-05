#!/usr/bin/env python3
"""
SPEC Benchmark Overhead Analyzer
Compares cycles across baseline, colored_paper, and cornucupia.
Calculates geomean for benchmarks with multiple inputs.
Generates overhead figure.
"""

import os
import re
import sys
from pathlib import Path
from collections import defaultdict
import matplotlib.pyplot as plt
import numpy as np

def parse_mcs_file(filepath):
    """Parse .mcs file and extract cycles."""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        match = re.search(r'cycles:\s+(\d+)', content)
        if match:
            return int(match.group(1))
    except Exception as e:
        print(f"Warning: Could not parse {filepath}: {e}")
    return None

def parse_mcs_file_tagcache(filepath):
    """Parse .mcs file and extract tagcache_load_miss."""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        match = re.search(r'tagcache_load_miss:\s+(\d+)', content)
        if match:
            return int(match.group(1))
    except Exception as e:
        print(f"Warning: Could not parse tagcache from {filepath}: {e}")
    return None

def parse_mcs_file_tagcache_load(filepath):
    """Parse .mcs file and extract tagcache_load (not tagcache_load_miss)."""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        # Match tagcache_load but not tagcache_load_miss
        match = re.search(r'tagcache_load:\s+(\d+)', content)
        if match:
            return int(match.group(1))
    except Exception as e:
        print(f"Warning: Could not parse tagcache_load from {filepath}: {e}")
    return None

def parse_mcs_file_tagcache_store(filepath):
    """Parse .mcs file and extract tagcache_store (not tagcache_store_miss)."""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        # Match tagcache_store but not tagcache_store_miss
        match = re.search(r'tagcache_store:\s+(\d+)', content)
        if match:
            return int(match.group(1))
    except Exception as e:
        print(f"Warning: Could not parse tagcache_store from {filepath}: {e}")
    return None

def parse_mcs_file_tagcache_store_miss(filepath):
    """Parse .mcs file and extract tagcache_store_miss."""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        match = re.search(r'tagcache_store_miss:\s+(\d+)', content)
        if match:
            return int(match.group(1))
    except Exception as e:
        print(f"Warning: Could not parse tagcache_store_miss from {filepath}: {e}")
    return None

def parse_mcs_file_dram_traffic(filepath):
    """Parse .mcs file and extract cumulative DRAM traffic.
    DRAM traffic = tagcache_load + tagcache_load_miss + tagcache_store + tagcache_store_miss
    """
    try:
        with open(filepath, 'r') as f:
            content = f.read()

        tagcache_load = 0
        tagcache_load_miss = 0
        tagcache_store = 0
        tagcache_store_miss = 0

        match = re.search(r'tagcache_load:\s+(\d+)', content)
        if match:
            tagcache_load = int(match.group(1))

        match = re.search(r'tagcache_load_miss:\s+(\d+)', content)
        if match:
            tagcache_load_miss = int(match.group(1))

        match = re.search(r'tagcache_store:\s+(\d+)', content)
        if match:
            tagcache_store = int(match.group(1))

        match = re.search(r'tagcache_store_miss:\s+(\d+)', content)
        if match:
            tagcache_store_miss = int(match.group(1))

        return tagcache_load + tagcache_load_miss + tagcache_store + tagcache_store_miss
    except Exception as e:
        print(f"Warning: Could not parse DRAM traffic from {filepath}: {e}")
    return None

def parse_time_file(filepath):
    """Parse .time file and extract maximum resident set size."""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        match = re.search(r'(\d+)\s+maximum resident set size', content)
        if match:
            return int(match.group(1))
    except Exception as e:
        print(f"Warning: Could not parse {filepath}: {e}")
    return None

def get_benchmark_cycles(benchmark_dir):
    """Get all cycle counts from a benchmark output directory."""
    cycles = []
    if not benchmark_dir.exists():
        return cycles

    for mcs_file in benchmark_dir.glob("*.mcs"):
        cycle_count = parse_mcs_file(mcs_file)
        if cycle_count is not None:
            cycles.append(cycle_count)
    return cycles

def get_benchmark_cycles_per_input(benchmark_dir):
    """Get cycle counts per input file from a benchmark output directory.
    Returns a dict mapping input_name -> cycles."""
    cycles = {}
    if not benchmark_dir.exists():
        return cycles

    for mcs_file in benchmark_dir.glob("*.mcs"):
        cycle_count = parse_mcs_file(mcs_file)
        if cycle_count is not None:
            # Use stem (filename without extension) as key
            input_name = mcs_file.stem
            cycles[input_name] = cycle_count
    return cycles

def get_benchmark_memory(benchmark_dir):
    """Get all memory (max RSS) values from a benchmark output directory."""
    memory_values = []
    if not benchmark_dir.exists():
        return memory_values

    for time_file in benchmark_dir.glob("*.time"):
        mem = parse_time_file(time_file)
        if mem is not None:
            memory_values.append(mem)
    return memory_values

def get_benchmark_memory_per_input(benchmark_dir):
    """Get memory (max RSS) per input file from a benchmark output directory.
    Returns a dict mapping input_name -> memory."""
    memory = {}
    if not benchmark_dir.exists():
        return memory

    for time_file in benchmark_dir.glob("*.time"):
        mem = parse_time_file(time_file)
        if mem is not None:
            # Use stem (filename without extension) as key
            input_name = time_file.stem
            memory[input_name] = mem
    return memory

def get_benchmark_tagcache_miss(benchmark_dir):
    """Get all tagcache_load_miss values from a benchmark output directory."""
    tagcache_values = []
    if not benchmark_dir.exists():
        return tagcache_values

    for mcs_file in benchmark_dir.glob("*.mcs"):
        tagcache = parse_mcs_file_tagcache(mcs_file)
        if tagcache is not None:
            tagcache_values.append(tagcache)
    return tagcache_values

def get_benchmark_tagcache_load(benchmark_dir):
    """Get all tagcache_load values from a benchmark output directory."""
    tagcache_values = []
    if not benchmark_dir.exists():
        return tagcache_values

    for mcs_file in benchmark_dir.glob("*.mcs"):
        tagcache = parse_mcs_file_tagcache_load(mcs_file)
        if tagcache is not None:
            tagcache_values.append(tagcache)
    return tagcache_values

def get_benchmark_tagcache_store(benchmark_dir):
    """Get all tagcache_store values from a benchmark output directory."""
    tagcache_values = []
    if not benchmark_dir.exists():
        return tagcache_values

    for mcs_file in benchmark_dir.glob("*.mcs"):
        tagcache = parse_mcs_file_tagcache_store(mcs_file)
        if tagcache is not None:
            tagcache_values.append(tagcache)
    return tagcache_values

def get_benchmark_dram_traffic(benchmark_dir):
    """Get all DRAM traffic values from a benchmark output directory.
    DRAM traffic = tagcache_load + tagcache_load_miss + tagcache_store + tagcache_store_miss
    """
    dram_values = []
    if not benchmark_dir.exists():
        return dram_values

    for mcs_file in benchmark_dir.glob("*.mcs"):
        dram = parse_mcs_file_dram_traffic(mcs_file)
        if dram is not None:
            dram_values.append(dram)
    return dram_values

def get_benchmark_dram_traffic_per_input(benchmark_dir):
    """Get DRAM traffic per input file from a benchmark output directory.
    Returns a dict mapping input_name -> dram_traffic.
    DRAM traffic = tagcache_load + tagcache_load_miss + tagcache_store + tagcache_store_miss
    """
    dram = {}
    if not benchmark_dir.exists():
        return dram

    for mcs_file in benchmark_dir.glob("*.mcs"):
        dram_val = parse_mcs_file_dram_traffic(mcs_file)
        if dram_val is not None:
            input_name = mcs_file.stem
            dram[input_name] = dram_val
    return dram

def geometric_mean(values):
    """Calculate geometric mean of a list of values."""
    if not values:
        return None
    log_sum = sum(np.log(v) for v in values if v > 0)
    return np.exp(log_sum / len(values))

def collect_all_benchmarks(base_dir):
    """Collect all benchmark results (cycles, memory, tagcache, dram_traffic) from a directory."""
    cycles_results = {}
    memory_results = {}
    tagcache_results = {}
    tagcache_load_results = {}
    tagcache_store_results = {}
    dram_traffic_results = {}
    if not base_dir.exists():
        return cycles_results, memory_results, tagcache_results, tagcache_load_results, tagcache_store_results, dram_traffic_results

    for bench_dir in base_dir.iterdir():
        if bench_dir.is_dir() and bench_dir.name.endswith('_OUTPUT'):
            # Extract benchmark name (e.g., "401.bzip2" from "401.bzip2_OUTPUT")
            bench_name = bench_dir.name.replace('_OUTPUT', '')

            # Cycles - use geometric mean if multiple inputs
            cycles = get_benchmark_cycles(bench_dir)
            if cycles:
                cycles_results[bench_name] = geometric_mean(cycles)

            # Memory - use total (sum) of max RSS across all inputs
            memory = get_benchmark_memory(bench_dir)
            if memory:
                memory_results[bench_name] = sum(memory)

            # Tagcache load miss - use total (sum) across all inputs
            tagcache = get_benchmark_tagcache_miss(bench_dir)
            if tagcache:
                tagcache_results[bench_name] = sum(tagcache)

            # Tagcache load - use total (sum) across all inputs
            tagcache_load = get_benchmark_tagcache_load(bench_dir)
            if tagcache_load:
                tagcache_load_results[bench_name] = sum(tagcache_load)

            # Tagcache store - use total (sum) across all inputs
            tagcache_store = get_benchmark_tagcache_store(bench_dir)
            if tagcache_store:
                tagcache_store_results[bench_name] = sum(tagcache_store)

            # DRAM traffic - use total (sum) across all inputs
            dram_traffic = get_benchmark_dram_traffic(bench_dir)
            if dram_traffic:
                dram_traffic_results[bench_name] = sum(dram_traffic)

    return cycles_results, memory_results, tagcache_results, tagcache_load_results, tagcache_store_results, dram_traffic_results

def main():
    script_dir = Path(__file__).parent

    # Define directories
    baseline_dir = script_dir / "baseline"
    colored_dir = script_dir / "colored_paper"
    cornucupia_dir = script_dir / "cornucupia"

    print("=" * 80)
    print(" SPEC Benchmark Cycle Analysis")
    print("=" * 80)
    print(f"\nBaseline dir:    {baseline_dir}")
    print(f"Colored dir:     {colored_dir}")
    print(f"Cornucupia dir:  {cornucupia_dir}")

    # Collect results (cycles, memory, tagcache, and dram_traffic)
    baseline_cycles, baseline_mem, baseline_tagcache, baseline_tagcache_load, baseline_tagcache_store, baseline_dram = collect_all_benchmarks(baseline_dir)
    colored_cycles, colored_mem, colored_tagcache, colored_tagcache_load, colored_tagcache_store, colored_dram = collect_all_benchmarks(colored_dir)
    cornucupia_cycles, cornucupia_mem, cornucupia_tagcache, cornucupia_tagcache_load, cornucupia_tagcache_store, cornucupia_dram = collect_all_benchmarks(cornucupia_dir)

    print(f"\nBaseline benchmarks:   {list(baseline_cycles.keys())}")
    print(f"PICASSO benchmarks:    {list(colored_cycles.keys())}")
    print(f"Cornucopia benchmarks: {list(cornucupia_cycles.keys())}")

    # Find common benchmarks (at least in baseline)
    all_benchmarks = sorted(baseline_cycles.keys())

    # Calculate cycle overheads
    print(f"\n{'='*80}")
    print(" CYCLES (Geometric Mean)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'Baseline':>15} {'PICASSO':>15} {'Cornucopia':>15}")
    print("-" * 80)

    cycle_overhead_data = {
        'benchmarks': [],
        'colored': [],
        'cornucupia': []
    }

    for bench in all_benchmarks:
        b_val = baseline_cycles.get(bench)
        c_val = colored_cycles.get(bench)
        corn_val = cornucupia_cycles.get(bench)

        b_str = f"{b_val:,.0f}" if b_val else "N/A"
        c_str = f"{c_val:,.0f}" if c_val else "N/A"
        corn_str = f"{corn_val:,.0f}" if corn_val else "N/A"

        print(f"{bench:<20} {b_str:>15} {c_str:>15} {corn_str:>15}")

        # Store overhead factors for plotting
        if b_val:
            cycle_overhead_data['benchmarks'].append(bench.split('.')[1] if '.' in bench else bench)
            cycle_overhead_data['colored'].append(c_val / b_val if c_val else None)
            cycle_overhead_data['cornucupia'].append(corn_val / b_val if corn_val else None)

    # Calculate and print cycle overhead factors
    print(f"\n{'='*80}")
    print(" CYCLE OVERHEAD FACTOR (vs Baseline)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'PICASSO':>15} {'Cornucopia':>15}")
    print("-" * 80)

    colored_cycle_overheads = []
    cornucupia_cycle_overheads = []

    for i, bench in enumerate(cycle_overhead_data['benchmarks']):
        c_ovh = cycle_overhead_data['colored'][i]
        corn_ovh = cycle_overhead_data['cornucupia'][i]

        c_str = f"{c_ovh:.3f}x" if c_ovh else "N/A"
        corn_str = f"{corn_ovh:.3f}x" if corn_ovh else "N/A"

        print(f"{bench:<20} {c_str:>15} {corn_str:>15}")

        if c_ovh:
            colored_cycle_overheads.append(c_ovh)
        if corn_ovh:
            cornucupia_cycle_overheads.append(corn_ovh)

    # Calculate geomean of cycle overheads
    print("-" * 80)
    if colored_cycle_overheads:
        geomean_colored = geometric_mean(colored_cycle_overheads)
        print(f"{'GEOMEAN':<20} {geomean_colored:.3f}x")
    if cornucupia_cycle_overheads:
        geomean_corn = geometric_mean(cornucupia_cycle_overheads)
        print(f"{'GEOMEAN':<20} {'':>15} {geomean_corn:.3f}x")

    # ==================== MEMORY ANALYSIS (Per-Input Geomean) ====================
    print(f"\n{'='*80}")
    print(" MEMORY - Maximum RSS (Per-Input Geomean Overhead)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'Baseline(sum)':>15} {'PICASSO(sum)':>15} {'Corn(sum)':>15}")
    print("-" * 80)

    memory_overhead_data = {
        'benchmarks': [],
        'colored': [],
        'cornucupia': []
    }

    for bench in all_benchmarks:
        # Print sum values for reference
        b_val = baseline_mem.get(bench)
        c_val = colored_mem.get(bench)
        corn_val = cornucupia_mem.get(bench)

        b_str = f"{b_val:,}" if b_val else "N/A"
        c_str = f"{c_val:,}" if c_val else "N/A"
        corn_str = f"{corn_val:,}" if corn_val else "N/A"

        print(f"{bench:<20} {b_str:>15} {c_str:>15} {corn_str:>15}")

        # Calculate per-input geomean overhead
        baseline_bench_dir = baseline_dir / f"{bench}_OUTPUT"
        colored_bench_dir = colored_dir / f"{bench}_OUTPUT"
        cornucupia_bench_dir = cornucupia_dir / f"{bench}_OUTPUT"

        baseline_mem_per_input = get_benchmark_memory_per_input(baseline_bench_dir)
        colored_mem_per_input = get_benchmark_memory_per_input(colored_bench_dir)
        cornucupia_mem_per_input = get_benchmark_memory_per_input(cornucupia_bench_dir)

        # Calculate per-input overheads for PICASSO
        colored_input_overheads = []
        for input_name, b_mem in baseline_mem_per_input.items():
            c_mem = colored_mem_per_input.get(input_name)
            if c_mem and b_mem:
                colored_input_overheads.append(c_mem / b_mem)

        # Calculate per-input overheads for Cornucopia
        cornucupia_input_overheads = []
        for input_name, b_mem in baseline_mem_per_input.items():
            corn_mem = cornucupia_mem_per_input.get(input_name)
            if corn_mem and b_mem:
                cornucupia_input_overheads.append(corn_mem / b_mem)

        # Store geomean of per-input overheads
        if baseline_mem_per_input:
            memory_overhead_data['benchmarks'].append(bench.split('.')[1] if '.' in bench else bench)
            memory_overhead_data['colored'].append(geometric_mean(colored_input_overheads) if colored_input_overheads else None)
            memory_overhead_data['cornucupia'].append(geometric_mean(cornucupia_input_overheads) if cornucupia_input_overheads else None)

    # Calculate and print memory overhead factors (per-input geomean)
    print(f"\n{'='*80}")
    print(" MEMORY OVERHEAD FACTOR (Per-Input Geomean vs Baseline)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'PICASSO':>15} {'Cornucopia':>15}")
    print("-" * 80)

    colored_mem_overheads = []
    cornucupia_mem_overheads = []

    for i, bench in enumerate(memory_overhead_data['benchmarks']):
        c_ovh = memory_overhead_data['colored'][i]
        corn_ovh = memory_overhead_data['cornucupia'][i]

        c_str = f"{c_ovh:.3f}x" if c_ovh else "N/A"
        corn_str = f"{corn_ovh:.3f}x" if corn_ovh else "N/A"

        print(f"{bench:<20} {c_str:>15} {corn_str:>15}")

        if c_ovh:
            colored_mem_overheads.append(c_ovh)
        if corn_ovh:
            cornucupia_mem_overheads.append(corn_ovh)

    # Calculate geomean of memory overheads (geomean of geomeans)
    print("-" * 80)
    if colored_mem_overheads:
        geomean_colored_mem = geometric_mean(colored_mem_overheads)
        print(f"{'GEOMEAN':<20} {geomean_colored_mem:.3f}x")
    if cornucupia_mem_overheads:
        geomean_corn_mem = geometric_mean(cornucupia_mem_overheads)
        print(f"{'GEOMEAN':<20} {'':>15} {geomean_corn_mem:.3f}x")

    # ==================== TAGCACHE LOAD MISS ANALYSIS ====================
    print(f"\n{'='*80}")
    print(" TAGCACHE LOAD MISS (Total)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'Baseline':>15} {'PICASSO':>15} {'Cornucopia':>15}")
    print("-" * 80)

    tagcache_overhead_data = {
        'benchmarks': [],
        'colored': [],
        'cornucupia': []
    }

    for bench in all_benchmarks:
        b_val = baseline_tagcache.get(bench)
        c_val = colored_tagcache.get(bench)
        corn_val = cornucupia_tagcache.get(bench)

        b_str = f"{b_val:,}" if b_val else "N/A"
        c_str = f"{c_val:,}" if c_val else "N/A"
        corn_str = f"{corn_val:,}" if corn_val else "N/A"

        print(f"{bench:<20} {b_str:>15} {c_str:>15} {corn_str:>15}")

        # Store overhead factors for plotting
        if b_val:
            bench_short = bench.split('.')[1] if '.' in bench else bench
            tagcache_overhead_data['benchmarks'].append(bench_short)
            tagcache_overhead_data['colored'].append(c_val / b_val if c_val else None)
            tagcache_overhead_data['cornucupia'].append(corn_val / b_val if corn_val else None)

    # Calculate and print tagcache overhead factors
    print(f"\n{'='*80}")
    print(" TAGCACHE LOAD MISS OVERHEAD FACTOR (vs Baseline)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'PICASSO':>15} {'Cornucopia':>15}")
    print("-" * 80)

    colored_tagcache_overheads = []
    cornucupia_tagcache_overheads = []

    for i, bench in enumerate(tagcache_overhead_data['benchmarks']):
        c_ovh = tagcache_overhead_data['colored'][i]
        corn_ovh = tagcache_overhead_data['cornucupia'][i]

        c_str = f"{c_ovh:.2f}x" if c_ovh else "N/A"
        corn_str = f"{corn_ovh:.2f}x" if corn_ovh else "N/A"

        print(f"{bench:<20} {c_str:>15} {corn_str:>15}")

        if c_ovh:
            colored_tagcache_overheads.append(c_ovh)
        if corn_ovh:
            cornucupia_tagcache_overheads.append(corn_ovh)

    # Calculate geomean of tagcache overheads
    print("-" * 80)
    if colored_tagcache_overheads:
        geomean_colored_tagcache = geometric_mean(colored_tagcache_overheads)
        print(f"{'GEOMEAN':<20} {geomean_colored_tagcache:.2f}x")
    if cornucupia_tagcache_overheads:
        geomean_corn_tagcache = geometric_mean(cornucupia_tagcache_overheads)
        print(f"{'GEOMEAN':<20} {'':>15} {geomean_corn_tagcache:.2f}x")

    # ==================== TAGCACHE LOAD ANALYSIS ====================
    print(f"\n{'='*80}")
    print(" TAGCACHE LOAD (Total)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'Baseline':>15} {'PICASSO':>15} {'Cornucopia':>15}")
    print("-" * 80)

    tagcache_load_overhead_data = {
        'benchmarks': [],
        'colored': [],
        'cornucupia': []
    }

    for bench in all_benchmarks:
        b_val = baseline_tagcache_load.get(bench)
        c_val = colored_tagcache_load.get(bench)
        corn_val = cornucupia_tagcache_load.get(bench)

        b_str = f"{b_val:,}" if b_val else "N/A"
        c_str = f"{c_val:,}" if c_val else "N/A"
        corn_str = f"{corn_val:,}" if corn_val else "N/A"

        print(f"{bench:<20} {b_str:>15} {c_str:>15} {corn_str:>15}")

        # Store overhead factors for plotting
        if b_val:
            bench_short = bench.split('.')[1] if '.' in bench else bench
            tagcache_load_overhead_data['benchmarks'].append(bench_short)
            tagcache_load_overhead_data['colored'].append(c_val / b_val if c_val else None)
            tagcache_load_overhead_data['cornucupia'].append(corn_val / b_val if corn_val else None)

    # Calculate and print tagcache load overhead factors
    print(f"\n{'='*80}")
    print(" TAGCACHE LOAD OVERHEAD FACTOR (vs Baseline)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'PICASSO':>15} {'Cornucopia':>15}")
    print("-" * 80)

    colored_tagcache_load_overheads = []
    cornucupia_tagcache_load_overheads = []

    for i, bench in enumerate(tagcache_load_overhead_data['benchmarks']):
        c_ovh = tagcache_load_overhead_data['colored'][i]
        corn_ovh = tagcache_load_overhead_data['cornucupia'][i]

        c_str = f"{c_ovh:.2f}x" if c_ovh else "N/A"
        corn_str = f"{corn_ovh:.2f}x" if corn_ovh else "N/A"

        print(f"{bench:<20} {c_str:>15} {corn_str:>15}")

        if c_ovh:
            colored_tagcache_load_overheads.append(c_ovh)
        if corn_ovh:
            cornucupia_tagcache_load_overheads.append(corn_ovh)

    # Calculate geomean of tagcache load overheads
    print("-" * 80)
    if colored_tagcache_load_overheads:
        geomean_colored_tagcache_load = geometric_mean(colored_tagcache_load_overheads)
        print(f"{'GEOMEAN':<20} {geomean_colored_tagcache_load:.2f}x")
    if cornucupia_tagcache_load_overheads:
        geomean_corn_tagcache_load = geometric_mean(cornucupia_tagcache_load_overheads)
        print(f"{'GEOMEAN':<20} {'':>15} {geomean_corn_tagcache_load:.2f}x")

    # ==================== TAGCACHE STORE ANALYSIS ====================
    print(f"\n{'='*80}")
    print(" TAGCACHE STORE (Total)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'Baseline':>15} {'PICASSO':>15} {'Cornucopia':>15}")
    print("-" * 80)

    tagcache_store_overhead_data = {
        'benchmarks': [],
        'colored': [],
        'cornucupia': []
    }

    for bench in all_benchmarks:
        b_val = baseline_tagcache_store.get(bench)
        c_val = colored_tagcache_store.get(bench)
        corn_val = cornucupia_tagcache_store.get(bench)

        b_str = f"{b_val:,}" if b_val else "N/A"
        c_str = f"{c_val:,}" if c_val else "N/A"
        corn_str = f"{corn_val:,}" if corn_val else "N/A"

        print(f"{bench:<20} {b_str:>15} {c_str:>15} {corn_str:>15}")

        # Store overhead factors for plotting
        if b_val:
            bench_short = bench.split('.')[1] if '.' in bench else bench
            tagcache_store_overhead_data['benchmarks'].append(bench_short)
            tagcache_store_overhead_data['colored'].append(c_val / b_val if c_val else None)
            tagcache_store_overhead_data['cornucupia'].append(corn_val / b_val if corn_val else None)

    # Calculate and print tagcache store overhead factors
    print(f"\n{'='*80}")
    print(" TAGCACHE STORE OVERHEAD FACTOR (vs Baseline)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'PICASSO':>15} {'Cornucopia':>15}")
    print("-" * 80)

    colored_tagcache_store_overheads = []
    cornucupia_tagcache_store_overheads = []

    for i, bench in enumerate(tagcache_store_overhead_data['benchmarks']):
        c_ovh = tagcache_store_overhead_data['colored'][i]
        corn_ovh = tagcache_store_overhead_data['cornucupia'][i]

        c_str = f"{c_ovh:.2f}x" if c_ovh else "N/A"
        corn_str = f"{corn_ovh:.2f}x" if corn_ovh else "N/A"

        print(f"{bench:<20} {c_str:>15} {corn_str:>15}")

        if c_ovh:
            colored_tagcache_store_overheads.append(c_ovh)
        if corn_ovh:
            cornucupia_tagcache_store_overheads.append(corn_ovh)

    # Calculate geomean of tagcache store overheads
    print("-" * 80)
    if colored_tagcache_store_overheads:
        geomean_colored_tagcache_store = geometric_mean(colored_tagcache_store_overheads)
        print(f"{'GEOMEAN':<20} {geomean_colored_tagcache_store:.2f}x")
    if cornucupia_tagcache_store_overheads:
        geomean_corn_tagcache_store = geometric_mean(cornucupia_tagcache_store_overheads)
        print(f"{'GEOMEAN':<20} {'':>15} {geomean_corn_tagcache_store:.2f}x")

    # ==================== TAGCACHE TOTAL (LOAD + STORE) ANALYSIS ====================
    print(f"\n{'='*80}")
    print(" TAGCACHE TOTAL (Load + Store)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'Baseline':>15} {'PICASSO':>15} {'Cornucopia':>15}")
    print("-" * 80)

    tagcache_total_overhead_data = {
        'benchmarks': [],
        'colored': [],
        'cornucupia': []
    }

    for bench in all_benchmarks:
        b_load = baseline_tagcache_load.get(bench, 0)
        b_store = baseline_tagcache_store.get(bench, 0)
        c_load = colored_tagcache_load.get(bench, 0)
        c_store = colored_tagcache_store.get(bench, 0)
        corn_load = cornucupia_tagcache_load.get(bench, 0)
        corn_store = cornucupia_tagcache_store.get(bench, 0)

        b_val = b_load + b_store if (b_load or b_store) else None
        c_val = c_load + c_store if (c_load or c_store) else None
        corn_val = corn_load + corn_store if (corn_load or corn_store) else None

        b_str = f"{b_val:,}" if b_val else "N/A"
        c_str = f"{c_val:,}" if c_val else "N/A"
        corn_str = f"{corn_val:,}" if corn_val else "N/A"

        print(f"{bench:<20} {b_str:>15} {c_str:>15} {corn_str:>15}")

        # Store overhead factors for plotting
        if b_val:
            bench_short = bench.split('.')[1] if '.' in bench else bench
            tagcache_total_overhead_data['benchmarks'].append(bench_short)
            tagcache_total_overhead_data['colored'].append(c_val / b_val if c_val else None)
            tagcache_total_overhead_data['cornucupia'].append(corn_val / b_val if corn_val else None)

    # Calculate and print tagcache total overhead factors
    print(f"\n{'='*80}")
    print(" TAGCACHE TOTAL OVERHEAD FACTOR (vs Baseline)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'PICASSO':>15} {'Cornucopia':>15}")
    print("-" * 80)

    colored_tagcache_total_overheads = []
    cornucupia_tagcache_total_overheads = []

    for i, bench in enumerate(tagcache_total_overhead_data['benchmarks']):
        c_ovh = tagcache_total_overhead_data['colored'][i]
        corn_ovh = tagcache_total_overhead_data['cornucupia'][i]

        c_str = f"{c_ovh:.2f}x" if c_ovh else "N/A"
        corn_str = f"{corn_ovh:.2f}x" if corn_ovh else "N/A"

        print(f"{bench:<20} {c_str:>15} {corn_str:>15}")

        if c_ovh:
            colored_tagcache_total_overheads.append(c_ovh)
        if corn_ovh:
            cornucupia_tagcache_total_overheads.append(corn_ovh)

    # Calculate geomean of tagcache total overheads
    print("-" * 80)
    if colored_tagcache_total_overheads:
        geomean_colored_tagcache_total = geometric_mean(colored_tagcache_total_overheads)
        print(f"{'GEOMEAN':<20} {geomean_colored_tagcache_total:.2f}x")
    if cornucupia_tagcache_total_overheads:
        geomean_corn_tagcache_total = geometric_mean(cornucupia_tagcache_total_overheads)
        print(f"{'GEOMEAN':<20} {'':>15} {geomean_corn_tagcache_total:.2f}x")

    # ==================== DRAM TRAFFIC ANALYSIS (Per-Input Geomean) ====================
    print(f"\n{'='*80}")
    print(" DRAM TRAFFIC - Per-Input Geomean Overhead")
    print(" (tagcache_load + tagcache_load_miss + tagcache_store + tagcache_store_miss)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'Baseline(sum)':>15} {'PICASSO(sum)':>15} {'Corn(sum)':>15}")
    print("-" * 80)

    dram_overhead_data = {
        'benchmarks': [],
        'colored': [],
        'cornucupia': []
    }

    for bench in all_benchmarks:
        # Print sum values for reference
        b_val = baseline_dram.get(bench)
        c_val = colored_dram.get(bench)
        corn_val = cornucupia_dram.get(bench)

        b_str = f"{b_val:,}" if b_val else "N/A"
        c_str = f"{c_val:,}" if c_val else "N/A"
        corn_str = f"{corn_val:,}" if corn_val else "N/A"

        print(f"{bench:<20} {b_str:>15} {c_str:>15} {corn_str:>15}")

        # Calculate per-input geomean overhead
        baseline_bench_dir = baseline_dir / f"{bench}_OUTPUT"
        colored_bench_dir = colored_dir / f"{bench}_OUTPUT"
        cornucupia_bench_dir = cornucupia_dir / f"{bench}_OUTPUT"

        baseline_dram_per_input = get_benchmark_dram_traffic_per_input(baseline_bench_dir)
        colored_dram_per_input = get_benchmark_dram_traffic_per_input(colored_bench_dir)
        cornucupia_dram_per_input = get_benchmark_dram_traffic_per_input(cornucupia_bench_dir)

        # Calculate per-input overheads for PICASSO
        colored_input_overheads = []
        for input_name, b_dram in baseline_dram_per_input.items():
            c_dram = colored_dram_per_input.get(input_name)
            if c_dram and b_dram:
                colored_input_overheads.append(c_dram / b_dram)

        # Calculate per-input overheads for Cornucopia
        cornucupia_input_overheads = []
        for input_name, b_dram in baseline_dram_per_input.items():
            corn_dram = cornucupia_dram_per_input.get(input_name)
            if corn_dram and b_dram:
                cornucupia_input_overheads.append(corn_dram / b_dram)

        # Store geomean of per-input overheads
        if baseline_dram_per_input:
            dram_overhead_data['benchmarks'].append(bench.split('.')[1] if '.' in bench else bench)
            dram_overhead_data['colored'].append(geometric_mean(colored_input_overheads) if colored_input_overheads else None)
            dram_overhead_data['cornucupia'].append(geometric_mean(cornucupia_input_overheads) if cornucupia_input_overheads else None)

    # Calculate and print DRAM traffic overhead factors (per-input geomean)
    print(f"\n{'='*80}")
    print(" DRAM TRAFFIC OVERHEAD FACTOR (Per-Input Geomean vs Baseline)")
    print(f"{'='*80}")
    print(f"{'Benchmark':<20} {'PICASSO':>15} {'Cornucopia':>15}")
    print("-" * 80)

    colored_dram_overheads = []
    cornucupia_dram_overheads = []

    for i, bench in enumerate(dram_overhead_data['benchmarks']):
        c_ovh = dram_overhead_data['colored'][i]
        corn_ovh = dram_overhead_data['cornucupia'][i]

        c_str = f"{c_ovh:.3f}x" if c_ovh else "N/A"
        corn_str = f"{corn_ovh:.3f}x" if corn_ovh else "N/A"

        print(f"{bench:<20} {c_str:>15} {corn_str:>15}")

        if c_ovh:
            colored_dram_overheads.append(c_ovh)
        if corn_ovh:
            cornucupia_dram_overheads.append(corn_ovh)

    # Calculate geomean of DRAM traffic overheads (geomean of geomeans)
    print("-" * 80)
    if colored_dram_overheads:
        geomean_colored_dram = geometric_mean(colored_dram_overheads)
        print(f"{'GEOMEAN':<20} {geomean_colored_dram:.3f}x")
    if cornucupia_dram_overheads:
        geomean_corn_dram = geometric_mean(cornucupia_dram_overheads)
        print(f"{'GEOMEAN':<20} {'':>15} {geomean_corn_dram:.3f}x")

    # Generate plots
    plot_overhead_figure(cycle_overhead_data, script_dir, "cycles")
    plot_overhead_figure(memory_overhead_data, script_dir, "memory")
    plot_overhead_figure(tagcache_overhead_data, script_dir, "tagcache")
    plot_overhead_figure(tagcache_load_overhead_data, script_dir, "tagcache_load")
    plot_overhead_figure(tagcache_store_overhead_data, script_dir, "tagcache_store")
    plot_overhead_figure(tagcache_total_overhead_data, script_dir, "tagcache_total")
    plot_overhead_figure(dram_overhead_data, script_dir, "dram_traffic")

    # ==================== INDIVIDUAL INPUT ANALYSIS (gobmk and bzip2) ====================
    print(f"\n{'='*80}")
    print(" INDIVIDUAL INPUT OVERHEAD ANALYSIS")
    print(f"{'='*80}")

    # Collect per-input data for gobmk and bzip2
    for bench_name, bench_full in [("gobmk", "445.gobmk"), ("bzip2", "401.bzip2")]:
        print(f"\n{'-'*40}")
        print(f" {bench_name.upper()} Individual Input Overheads")
        print(f"{'-'*40}")

        baseline_bench_dir = baseline_dir / f"{bench_full}_OUTPUT"
        colored_bench_dir = colored_dir / f"{bench_full}_OUTPUT"
        cornucupia_bench_dir = cornucupia_dir / f"{bench_full}_OUTPUT"

        baseline_per_input = get_benchmark_cycles_per_input(baseline_bench_dir)
        colored_per_input = get_benchmark_cycles_per_input(colored_bench_dir)
        cornucupia_per_input = get_benchmark_cycles_per_input(cornucupia_bench_dir)

        if not baseline_per_input:
            print(f"  No baseline data found for {bench_name}")
            continue

        print(f"\n{'Input':<20} {'Baseline':>15} {'PICASSO':>15} {'Cornucopia':>15} {'PICASSO OH':>12} {'Corn OH':>12}")
        print("-" * 90)

        individual_overhead_data = {
            'inputs': [],
            'colored': [],
            'cornucupia': []
        }

        colored_overheads = []
        cornucupia_overheads = []

        for input_name in sorted(baseline_per_input.keys()):
            b_val = baseline_per_input.get(input_name)
            c_val = colored_per_input.get(input_name)
            corn_val = cornucupia_per_input.get(input_name)

            b_str = f"{b_val:,.0f}" if b_val else "N/A"
            c_str = f"{c_val:,.0f}" if c_val else "N/A"
            corn_str = f"{corn_val:,.0f}" if corn_val else "N/A"

            c_ovh = c_val / b_val if (c_val and b_val) else None
            corn_ovh = corn_val / b_val if (corn_val and b_val) else None

            c_ovh_str = f"{c_ovh:.3f}x" if c_ovh else "N/A"
            corn_ovh_str = f"{corn_ovh:.3f}x" if corn_ovh else "N/A"

            print(f"{input_name:<20} {b_str:>15} {c_str:>15} {corn_str:>15} {c_ovh_str:>12} {corn_ovh_str:>12}")

            # Store for plotting
            individual_overhead_data['inputs'].append(input_name)
            individual_overhead_data['colored'].append(c_ovh)
            individual_overhead_data['cornucupia'].append(corn_ovh)

            if c_ovh:
                colored_overheads.append(c_ovh)
            if corn_ovh:
                cornucupia_overheads.append(corn_ovh)

        # Calculate geomean
        print("-" * 90)
        geomean_colored_ind = geometric_mean(colored_overheads) if colored_overheads else None
        geomean_corn_ind = geometric_mean(cornucupia_overheads) if cornucupia_overheads else None

        if geomean_colored_ind:
            print(f"{'GEOMEAN':<20} {'':>15} {'':>15} {'':>15} {geomean_colored_ind:.3f}x")
        if geomean_corn_ind:
            print(f"{'GEOMEAN':<20} {'':>15} {'':>15} {'':>15} {'':>12} {geomean_corn_ind:.3f}x")

        # Generate individual input plot with geomean
        plot_individual_overhead_figure(
            individual_overhead_data,
            geomean_colored_ind,
            geomean_corn_ind,
            script_dir,
            bench_name,
            "cycles"
        )

    # ==================== INDIVIDUAL MEMORY INPUT ANALYSIS (gobmk and bzip2) ====================
    print(f"\n{'='*80}")
    print(" INDIVIDUAL INPUT MEMORY OVERHEAD ANALYSIS")
    print(f"{'='*80}")

    # Collect per-input memory data for gobmk and bzip2
    for bench_name, bench_full in [("gobmk", "445.gobmk"), ("bzip2", "401.bzip2")]:
        print(f"\n{'-'*40}")
        print(f" {bench_name.upper()} Individual Input Memory Overheads")
        print(f"{'-'*40}")

        baseline_bench_dir = baseline_dir / f"{bench_full}_OUTPUT"
        colored_bench_dir = colored_dir / f"{bench_full}_OUTPUT"
        cornucupia_bench_dir = cornucupia_dir / f"{bench_full}_OUTPUT"

        baseline_mem_per_input = get_benchmark_memory_per_input(baseline_bench_dir)
        colored_mem_per_input = get_benchmark_memory_per_input(colored_bench_dir)
        cornucupia_mem_per_input = get_benchmark_memory_per_input(cornucupia_bench_dir)

        if not baseline_mem_per_input:
            print(f"  No baseline memory data found for {bench_name}")
            continue

        print(f"\n{'Input':<20} {'Baseline':>15} {'PICASSO':>15} {'Cornucopia':>15} {'PICASSO OH':>12} {'Corn OH':>12}")
        print("-" * 90)

        individual_mem_overhead_data = {
            'inputs': [],
            'colored': [],
            'cornucupia': []
        }

        colored_mem_overheads_ind = []
        cornucupia_mem_overheads_ind = []

        for input_name in sorted(baseline_mem_per_input.keys()):
            b_val = baseline_mem_per_input.get(input_name)
            c_val = colored_mem_per_input.get(input_name)
            corn_val = cornucupia_mem_per_input.get(input_name)

            b_str = f"{b_val:,}" if b_val else "N/A"
            c_str = f"{c_val:,}" if c_val else "N/A"
            corn_str = f"{corn_val:,}" if corn_val else "N/A"

            c_ovh = c_val / b_val if (c_val and b_val) else None
            corn_ovh = corn_val / b_val if (corn_val and b_val) else None

            c_ovh_str = f"{c_ovh:.3f}x" if c_ovh else "N/A"
            corn_ovh_str = f"{corn_ovh:.3f}x" if corn_ovh else "N/A"

            print(f"{input_name:<20} {b_str:>15} {c_str:>15} {corn_str:>15} {c_ovh_str:>12} {corn_ovh_str:>12}")

            # Store for plotting
            individual_mem_overhead_data['inputs'].append(input_name)
            individual_mem_overhead_data['colored'].append(c_ovh)
            individual_mem_overhead_data['cornucupia'].append(corn_ovh)

            if c_ovh:
                colored_mem_overheads_ind.append(c_ovh)
            if corn_ovh:
                cornucupia_mem_overheads_ind.append(corn_ovh)

        # Calculate geomean
        print("-" * 90)
        geomean_colored_mem_ind = geometric_mean(colored_mem_overheads_ind) if colored_mem_overheads_ind else None
        geomean_corn_mem_ind = geometric_mean(cornucupia_mem_overheads_ind) if cornucupia_mem_overheads_ind else None

        if geomean_colored_mem_ind:
            print(f"{'GEOMEAN':<20} {'':>15} {'':>15} {'':>15} {geomean_colored_mem_ind:.3f}x")
        if geomean_corn_mem_ind:
            print(f"{'GEOMEAN':<20} {'':>15} {'':>15} {'':>15} {'':>12} {geomean_corn_mem_ind:.3f}x")

        # Generate individual memory input plot with geomean
        plot_individual_overhead_figure(
            individual_mem_overhead_data,
            geomean_colored_mem_ind,
            geomean_corn_mem_ind,
            script_dir,
            bench_name,
            "memory"
        )

def plot_overhead_figure(data, output_dir, metric_type="cycles"):
    """Generate bar chart of overhead factors with broken y-axis for outliers."""
    benchmarks = data['benchmarks']
    colored = data['colored']
    cornucupia = data['cornucupia']

    # External data from another university (Cornucopia double-core configuration)
    external_data_cycles = {
        'omnetpp': 1.9  # Cornucopia double-core result from external source
    }
    external_data_tagcache = {
        'omnetpp': 327  # Cornucopia double-core tagcache_load_miss overhead from external source
    }
    # External geomean for Cornucopia 2-core (cycles)
    external_geomean_cycles = 1.08

    if metric_type == "cycles":
        external_data = external_data_cycles
    elif metric_type == "tagcache":
        external_data = external_data_tagcache
    else:
        external_data = {}

    # Filter out None values for plotting
    plot_benchmarks = []
    plot_colored = []
    plot_cornucupia = []
    plot_external = []  # For external data (Cornucopia double-core)

    for i, bench in enumerate(benchmarks):
        if colored[i] is not None or cornucupia[i] is not None:
            plot_benchmarks.append(bench)
            plot_colored.append(colored[i] if colored[i] else 0)
            plot_cornucupia.append(cornucupia[i] if cornucupia[i] else 0)
            # Add external data for cycles/tagcache and matching benchmarks
            if bench in external_data:
                plot_external.append(external_data[bench])
            else:
                plot_external.append(0)

    if not plot_benchmarks:
        print(f"\nNo {metric_type} data to plot!")
        return

    # Calculate geomean for PICASSO and Cornucopia
    valid_colored = [v for v in plot_colored if v > 0]
    valid_cornucupia = [v for v in plot_cornucupia if v > 0]
    geomean_colored = geometric_mean(valid_colored) if valid_colored else 0
    geomean_cornucupia = geometric_mean(valid_cornucupia) if valid_cornucupia else 0

    # Add geomean to the plot data
    plot_benchmarks.append('geomean')
    plot_colored.append(geomean_colored)
    plot_cornucupia.append(geomean_cornucupia)
    # Add external geomean for cycles, 0 otherwise
    if metric_type == "cycles":
        plot_external.append(external_geomean_cycles)
    else:
        plot_external.append(0)

    x = np.arange(len(plot_benchmarks))

    # Adjust width based on whether we have external data
    has_external = any(v > 0 for v in plot_external)
    # Use consistent width (0.25) for cycles and memory for visual consistency
    if metric_type in ["cycles", "memory"]:
        width = 0.25
    else:
        width = 0.25 if has_external else 0.35

    geomean_idx = len(plot_benchmarks) - 1

    # Check if we need broken y-axis (for metrics with outliers)
    outlier_threshold = 5.0  # Values above this are considered outliers
    all_values = plot_colored + plot_cornucupia + plot_external
    max_val = max(v for v in all_values if v > 0)
    has_outliers = max_val > outlier_threshold and metric_type in ["tagcache", "tagcache_load", "tagcache_store", "tagcache_total", "dram_traffic"]

    # Labels and formatting
    metric_labels = {
        "cycles": "Cycles",
        "memory": "Max RSS",
        "tagcache": "Tagcache Load Miss",
        "tagcache_load": "Tagcache Load",
        "tagcache_store": "Tagcache Store",
        "tagcache_total": "Tagcache Total (Load + Store)",
        "dram_traffic": "DRAM Traffic"
    }
    metric_label = metric_labels.get(metric_type, metric_type)

    if has_outliers:
        # Create broken y-axis figure with two subplots
        fig_width = max(4, len(plot_benchmarks) * 0.6)
        fig, (ax_top, ax_bottom) = plt.subplots(2, 1, sharex=True, figsize=(fig_width, 5),
                                                  gridspec_kw={'height_ratios': [1, 3], 'hspace': 0.05})

        # Find outlier range
        outlier_min = max_val * 0.85
        outlier_max = max_val * 1.15

        # Bottom plot: normal range (0.9 to outlier_threshold)
        ax_bottom.set_ylim(0.9, outlier_threshold)
        # Top plot: outlier range
        ax_top.set_ylim(outlier_min, outlier_max)

        # Plot bars on both axes
        if has_external:
            bars1_bottom = ax_bottom.bar(x - width, plot_colored, width, label='PICASSO', color='#cc79a7')
            bars2_bottom = ax_bottom.bar(x, plot_cornucupia, width, label='Cornucopia', color='#0072b2')
            bars3_bottom = ax_bottom.bar(x + width, plot_external, width, label='Cornucopia 2-core',
                                         color='#e69f00', edgecolor='black', linewidth=0.5)
            bars1_top = ax_top.bar(x - width, plot_colored, width, color='#cc79a7')
            bars2_top = ax_top.bar(x, plot_cornucupia, width, color='#0072b2')
            bars3_top = ax_top.bar(x + width, plot_external, width, color='#e69f00',
                                   edgecolor='black', linewidth=0.5)
        else:
            bars1_bottom = ax_bottom.bar(x - width/2, plot_colored, width, label='PICASSO', color='#cc79a7')
            bars2_bottom = ax_bottom.bar(x + width/2, plot_cornucupia, width, label='Cornucopia', color='#0072b2')
            bars1_top = ax_top.bar(x - width/2, plot_colored, width, color='#cc79a7')
            bars2_top = ax_top.bar(x + width/2, plot_cornucupia, width, color='#0072b2')

        # Add baseline reference line at 1.0 (only on bottom)
        ax_bottom.axhline(y=1.0, color='black', linestyle='--', linewidth=1, label='Baseline (1.0x)')

        # Add vertical separator before geomean
        ax_bottom.axvline(x=geomean_idx - 0.5, color='gray', linestyle=':', linewidth=1.5)
        ax_top.axvline(x=geomean_idx - 0.5, color='gray', linestyle=':', linewidth=1.5)

        # Highlight geomean bars
        bars1_bottom[geomean_idx].set_edgecolor('black')
        bars1_bottom[geomean_idx].set_linewidth(2)
        bars2_bottom[geomean_idx].set_edgecolor('black')
        bars2_bottom[geomean_idx].set_linewidth(2)

        # Hide spines between the two axes
        ax_top.spines['bottom'].set_visible(False)
        ax_bottom.spines['top'].set_visible(False)
        ax_top.tick_params(bottom=False)

        # Add diagonal break marks
        d = 0.015  # Size of diagonal lines
        kwargs = dict(transform=ax_top.transAxes, color='k', clip_on=False, linewidth=1)
        ax_top.plot((-d, +d), (-d, +d), **kwargs)
        ax_top.plot((1 - d, 1 + d), (-d, +d), **kwargs)
        kwargs.update(transform=ax_bottom.transAxes)
        ax_bottom.plot((-d, +d), (1 - d, 1 + d), **kwargs)
        ax_bottom.plot((1 - d, 1 + d), (1 - d, 1 + d), **kwargs)

        # Grid
        ax_bottom.grid(True, alpha=0.3, axis='y')
        ax_top.grid(True, alpha=0.3, axis='y')

        # Labels
        ax_bottom.set_xticks(x)
        ax_bottom.set_xticklabels(plot_benchmarks, rotation=45, ha='right')
        ax_bottom.legend(loc='upper left')

        # Y-axis label in the middle
        fig.text(0.02, 0.5, f'Overhead Factor ({metric_label})', va='center', rotation='vertical', fontsize=12)

        # Add value labels on bars (bottom axis for normal values, top axis for outliers)
        for i in range(len(plot_benchmarks)):
            # PICASSO bars
            val = plot_colored[i]
            if val > 0:
                is_geomean = (i == geomean_idx)
                if val > outlier_threshold:
                    # Label on top axis
                    bar = bars1_top[i]
                    ax_top.annotate(f'{val:.1f}x',
                                   xy=(bar.get_x() + bar.get_width()/2, val),
                                   xytext=(0, 3), textcoords='offset points',
                                   ha='center', va='bottom', fontsize=8, rotation=90,
                                   fontweight='bold')
                else:
                    bar = bars1_bottom[i]
                    ax_bottom.annotate(f'{val:.2f}x',
                                      xy=(bar.get_x() + bar.get_width()/2, val),
                                      xytext=(0, 3), textcoords='offset points',
                                      ha='center', va='bottom', fontsize=8, rotation=90,
                                      fontweight='bold' if is_geomean else 'normal')

            # Cornucopia bars
            val = plot_cornucupia[i]
            if val > 0:
                is_geomean = (i == geomean_idx)
                if val > outlier_threshold:
                    bar = bars2_top[i]
                    ax_top.annotate(f'{val:.1f}x',
                                   xy=(bar.get_x() + bar.get_width()/2, val),
                                   xytext=(0, 3), textcoords='offset points',
                                   ha='center', va='bottom', fontsize=8, rotation=90,
                                   fontweight='bold')
                else:
                    bar = bars2_bottom[i]
                    ax_bottom.annotate(f'{val:.2f}x',
                                      xy=(bar.get_x() + bar.get_width()/2, val),
                                      xytext=(0, 3), textcoords='offset points',
                                      ha='center', va='bottom', fontsize=8, rotation=90,
                                      fontweight='bold' if is_geomean else 'normal')

            # External bars (if present)
            if has_external:
                val = plot_external[i]
                if val > 0:
                    is_geomean = (i == geomean_idx)
                    if val > outlier_threshold:
                        bar = bars3_top[i]
                        ax_top.annotate(f'{val:.1f}x',
                                       xy=(bar.get_x() + bar.get_width()/2, val),
                                       xytext=(0, 3), textcoords='offset points',
                                       ha='center', va='bottom', fontsize=8, rotation=90,
                                       fontweight='bold')
                    else:
                        bar = bars3_bottom[i]
                        ax_bottom.annotate(f'{val:.2f}x',
                                          xy=(bar.get_x() + bar.get_width()/2, val),
                                          xytext=(0, 3), textcoords='offset points',
                                          ha='center', va='bottom', fontsize=8, rotation=90,
                                          fontweight='bold' if is_geomean else 'normal')

        ax_bottom.set_xlim(-0.5, len(plot_benchmarks) - 0.5)

    else:
        # Standard single-axis plot (no outliers)
        fig_width = max(4, len(plot_benchmarks) * 0.6)
        fig, ax = plt.subplots(figsize=(fig_width, 4))

        # Plot bars
        if has_external:
            bars1 = ax.bar(x - width, plot_colored, width, label='PICASSO', color='#cc79a7')
            bars2 = ax.bar(x, plot_cornucupia, width, label='Cornucopia', color='#0072b2')
            bars3 = ax.bar(x + width, plot_external, width,
                           label='Cornucopia 2-core',
                           color='#e69f00',
                           edgecolor='black', linewidth=0.5)
        else:
            bars1 = ax.bar(x - width/2, plot_colored, width, label='PICASSO', color='#cc79a7')
            bars2 = ax.bar(x + width/2, plot_cornucupia, width, label='Cornucopia', color='#0072b2')

        # Add baseline reference line at 1.0
        ax.axhline(y=1.0, color='black', linestyle='--', linewidth=1, label='Baseline (1.0x)')

        # Add vertical separator before geomean
        ax.axvline(x=geomean_idx - 0.5, color='gray', linestyle=':', linewidth=1.5)

        # Highlight geomean bars with different edge
        bars1[geomean_idx].set_edgecolor('black')
        bars1[geomean_idx].set_linewidth(2)
        bars2[geomean_idx].set_edgecolor('black')
        bars2[geomean_idx].set_linewidth(2)
        if has_external:
            bars3[geomean_idx].set_edgecolor('black')
            bars3[geomean_idx].set_linewidth(2)

        ax.set_ylabel(f'Overhead Factor ({metric_label})', fontsize=12)
        ax.set_xticks(x)
        ax.set_xticklabels(plot_benchmarks, rotation=45, ha='right')
        ax.legend()
        ax.grid(True, alpha=0.3, axis='y')

        # Set y-axis limits
        ax.set_ylim(bottom=0.9)
        if metric_type in ["cycles", "memory"]:
            ax.set_ylim(top=2.6)  # Fixed y-axis max for cycles and memory

        # Add value labels on bars
        for i, bar in enumerate(bars1):
            if bar.get_height() > 0:
                actual_val = plot_colored[i]
                is_geomean = (i == geomean_idx)
                ax.annotate(f'{actual_val:.2f}x',
                           xy=(bar.get_x() + bar.get_width()/2, bar.get_height()),
                           xytext=(0, 3), textcoords='offset points',
                           ha='center', va='bottom', fontsize=8, rotation=90,
                           fontweight='bold' if is_geomean else 'normal')

        for i, bar in enumerate(bars2):
            if bar.get_height() > 0:
                actual_val = plot_cornucupia[i]
                is_geomean = (i == geomean_idx)
                ax.annotate(f'{actual_val:.2f}x',
                           xy=(bar.get_x() + bar.get_width()/2, bar.get_height()),
                           xytext=(0, 3), textcoords='offset points',
                           ha='center', va='bottom', fontsize=8, rotation=90,
                           fontweight='bold' if is_geomean else 'normal')

        if has_external:
            for i, bar in enumerate(bars3):
                if bar.get_height() > 0:
                    actual_val = plot_external[i]
                    is_geomean = (i == geomean_idx)
                    ax.annotate(f'{actual_val:.2f}x',
                               xy=(bar.get_x() + bar.get_width()/2, bar.get_height()),
                               xytext=(0, 3), textcoords='offset points',
                               ha='center', va='bottom', fontsize=8, rotation=90,
                               fontweight='bold' if is_geomean else 'normal')

        ax.set_xlim(-0.5, len(plot_benchmarks) - 0.5)

    # Compact layout with reduced margins
    plt.tight_layout(pad=0.1)

    # Save figures
    output_png = output_dir / f"spec_{metric_type}_overhead.png"
    output_pdf = output_dir / f"spec_{metric_type}_overhead.pdf"
    plt.savefig(output_png, dpi=150, bbox_inches='tight')
    plt.savefig(output_pdf, bbox_inches='tight', pad_inches=0.001)
    plt.close()

    print(f"\nSaved {metric_type} plot to: {output_png}")
    print(f"Saved {metric_type} plot to: {output_pdf}")

def plot_individual_overhead_figure(data, geomean_colored, geomean_cornucupia, output_dir, bench_name, metric_type="cycles"):
    """Generate bar chart of individual input overhead factors with geomean."""
    inputs = data['inputs']
    colored = data['colored']
    cornucupia = data['cornucupia']

    # Filter out None values and prepare for plotting
    plot_inputs = []
    plot_colored = []
    plot_cornucupia = []

    for i, inp in enumerate(inputs):
        if colored[i] is not None or cornucupia[i] is not None:
            plot_inputs.append(inp)
            plot_colored.append(colored[i] if colored[i] else 0)
            plot_cornucupia.append(cornucupia[i] if cornucupia[i] else 0)

    if not plot_inputs:
        print(f"\nNo {metric_type} data to plot for {bench_name}!")
        return

    # Add geomean as the last bar
    plot_inputs.append('geomean')
    plot_colored.append(geomean_colored if geomean_colored else 0)
    plot_cornucupia.append(geomean_cornucupia if geomean_cornucupia else 0)

    x = np.arange(len(plot_inputs))
    width = 0.35

    fig, ax = plt.subplots(figsize=(10, 5))

    # Plot bars
    bars1 = ax.bar(x - width/2, plot_colored, width, label='PICASSO', color='#cc79a7')
    bars2 = ax.bar(x + width/2, plot_cornucupia, width, label='Cornucopia', color='#0072b2')

    # Add baseline reference line at 1.0
    ax.axhline(y=1.0, color='black', linestyle='--', linewidth=1, label='Baseline (1.0x)')

    # Add vertical separator before geomean
    geomean_idx = len(plot_inputs) - 1
    ax.axvline(x=geomean_idx - 0.5, color='gray', linestyle=':', linewidth=1.5)

    # Labels and formatting
    metric_labels = {
        "cycles": "Cycles",
        "memory": "Max RSS (KB)"
    }
    metric_label = metric_labels.get(metric_type, metric_type)
    ax.set_ylabel(f'Overhead Factor ({metric_label})', fontsize=12)
    ax.set_xlabel('Input', fontsize=12)
    ax.set_title(f'{bench_name.upper()} Individual Input {metric_label} Overheads', fontsize=14)
    ax.set_xticks(x)
    ax.set_xticklabels(plot_inputs, rotation=45, ha='right')
    ax.legend(loc='upper left')
    ax.grid(True, alpha=0.3, axis='y')

    # Set y-axis limits
    ax.set_ylim(bottom=0.9)

    # Add value labels on bars
    for i, bar in enumerate(bars1):
        if bar.get_height() > 0:
            label = f'{plot_colored[i]:.2f}x'
            ax.annotate(label,
                       xy=(bar.get_x() + bar.get_width()/2, bar.get_height()),
                       xytext=(0, 3), textcoords='offset points',
                       ha='center', va='bottom', fontsize=7, rotation=90,
                       fontweight='bold' if i == geomean_idx else 'normal')

    for i, bar in enumerate(bars2):
        if bar.get_height() > 0:
            label = f'{plot_cornucupia[i]:.2f}x'
            ax.annotate(label,
                       xy=(bar.get_x() + bar.get_width()/2, bar.get_height()),
                       xytext=(0, 3), textcoords='offset points',
                       ha='center', va='bottom', fontsize=7, rotation=90,
                       fontweight='bold' if i == geomean_idx else 'normal')

    # Highlight geomean bars with different edge
    bars1[geomean_idx].set_edgecolor('black')
    bars1[geomean_idx].set_linewidth(2)
    bars2[geomean_idx].set_edgecolor('black')
    bars2[geomean_idx].set_linewidth(2)

    plt.tight_layout()

    # Save figures
    output_png = output_dir / f"spec_{bench_name}_individual_{metric_type}_overhead.png"
    output_pdf = output_dir / f"spec_{bench_name}_individual_{metric_type}_overhead.pdf"
    plt.savefig(output_png, dpi=150)
    plt.savefig(output_pdf)
    plt.close()

    print(f"\nSaved {bench_name} individual {metric_type} plot to: {output_png}")
    print(f"Saved {bench_name} individual {metric_type} plot to: {output_pdf}")

if __name__ == "__main__":
    main()