
# Bluespec Simulation (MiBench)

**Prerequisite:** Docker installed and the `picasso` image built — see
[README.md Getting Started](./README.md#getting-started) if you haven't done
this yet (`docker build --network=host -t picasso .`).

Start the container:

```sh
docker run -i -t picasso
```

## CoreMark (Quick Performance Check)

CoreMark is a single-threaded benchmark that gives a fast overhead estimate. Pre-built ELFs are included so no SDK build is required.

```sh
# Inside the Docker container
cd /home/ubuntu/bench/coremark
./run_coremark_for_sim.sh
```

This runs 3 iterations of each configuration through both simulators and prints a summary:

- **CHERI-Toooba (baseline) / nocap** — non-purecap baseline
- **CHERI-Toooba (baseline) / purecap** — CHERI purecap overhead (no colored capabilities)
- **CHERI-Toooba (PICASSO) / purecap** — full PICASSO overhead

The key figure is the PICASSO purecap overhead vs baseline — this corresponds to Table 1 in the paper. Simulation ticks differ from FPGA ticks but the overhead ratio is comparable.

---

## Running MiBench Benchmarks (Simulation)

After starting the Docker container, you can run the MiBench benchmark suite to compare the baseline and PICASSO simulators.

### Quick Start

```sh
# Inside the Docker container
cd /home/ubuntu/bench

# Run all MiBench benchmarks for both simulators and print the comparison
./run_mibench.sh
```


`run_mibench.sh` accepts `--baseline-only` or `--picasso-only` to run a single
configuration; in that case it skips the automatic comparison and prints a
reminder to run `./compare_benchmarks.sh` once both logs are available.

### Comparing Results

When both the baseline and PICASSO runs complete, `run_mibench.sh`
automatically invokes `compare_benchmarks.sh` and prints a per-benchmark
cycle/instruction overhead table plus totals. You can re-run the comparison
manually at any time:

```sh
./compare_benchmarks.sh
```

This generates:
- `bench_log/mibench_comparison.txt`
- `bench_log/mibench_comparison.tex`

### Expected Results

Across the MiBench suite, PICASSO's colored capabilities should add only a
small cycle-count overhead over the baseline; instruction counts
should be identical or nearly identical between configurations, since the
extra cycles come from pipeline/memory effects rather than additional
instructions.

A full run of all 15 benchmarks for both configurations can take a
non-trivial amount of time (some benchmarks, e.g. `adpcm_decode` /
`adpcm_encode`, may run considerably longer than the others).
