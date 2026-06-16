# PICASSO Artifact 

While the CHERI instruction-set architecture extensions
for capabilities enable strong spatial memory safety, CHERI
lacks built-in temporal safety, particularly for heap alloca-
tions. Prior attempts to augment CHERI with temporal safety
fall short in terms of scalability, memory overhead, and in-
complete security guarantees due to periodical sweeps of the
system’s memory to individually revoke stale capabilities.
We address these limitations by introducing colored capa-
bilities that add a controlled form of indirection to CHERI’s
capability model. This enables provenance tracking of capa-
bilities to their respective allocations via a hardware-managed
provenance-validity table, allowing bulk retraction of dan-
gling pointers without needing to quarantine freed memory.
Colored capabilities significantly reduce the frequency of
capability revocation sweeps while improving security.
We realize colored capabilities in PICASSO, an extension of
the CHERI-RISC-V architecture on a speculative out-of-order
FPGA softcore (CHERI-Toooba). We also integrate colored-
capability support into the CheriBSD OS and CHERI-enabled
Clang/LLVM toolchain. Our evaluation shows effective miti-
gation of use-after-free and double-free bugs across all heap-
based temporal memory-safety vulnerabilities in NIST Juliet
test cases, real-world CVEs, only a small performance over-
head on SPEC CPU benchmarks (≈ 5% g.m.), less latency,
and more consistent performance in long-running SQLite,
PostgreSQL, and gRPC workloads compared to prior work.


## More Information

- PICASSO: Scaling CHERI Use-After-Free Protection to Millions of Allocations using Colored Capabilities 
  https://arxiv.org/abs/2602.09131


```bibtex
@misc{Gulmez26, 
  author = {Gülmez, Merve and Sturm, Ruben and ElAtali, Hossam and Englund, Håkan and 
            Woodruff, Jonathan and Asokan, N. and Nyman, Thomas}, 
  title = {PICASSO: Scaling CHERI Use-After-Free Protection to 
           Millions of Allocations using Colored Capabilities}, 
  year = {2026},
  doi = {10.48550/ARXIV.2602.09131},
  howpublished = {{\tt arXiv:2602.09131 [cs.CR]}},
  url = {https://arxiv.org/abs/2602.09131}
}
```

## Artifact

## Structure

- [7.1 Security Evaluation](#71-security-evaluation) `[QEMU or FPGA]`
  - [Juliet Test Suite (CWE-415/416)](#juliet-test-suite-cwe-415416): heap UAF/double-free detection
  - [Real-World CVE Validation](#real-world-cve-validation): 11 CVEs across 9 libraries

- [7.2 Performance Evaluations](#72-performance-evaluations) `[FPGA or Bluespec Simulator]`
  - [CoreMark](#coremark-bluespec-simulation) `[Docker]`: single-threaded overhead estimate
  - [MiBench](#mibench-bluespec-simulation) `[Docker]`: 15-benchmark suite (Table 1 / Table 3)
  - [SPEC CPU2006](#spec-cpu2006) `[VCU118]`: 8-benchmark integer suite (≈5% g.m. overhead)
  - [Pgbench](#pgbench) `[VCU118]`: PostgreSQL throughput
  - [SQLite](#sqlite) `[VCU118]`: per-operation timing
  - [gRPC](#grpc) `[VCU118]`: RPC latency/throughput

---

## Getting Started

### Docker (recommended — no toolchain installation needed)

Both the Bluespec and QEMU evaluation paths can run entirely inside Docker.
Install Docker first if you don't have it:

```sh
./utils_script/docker_install.sh
# If this is your first Docker install, log out and back in to activate the docker group.
# Verify with: docker run --rm hello-world
```

Then build the image for your chosen evaluation path:

| Evaluation path | Command |
|-----------------|---------|
| Bluespec Simulator (MiBench) | `docker build --network=host -t picasso .` |
| QEMU Emulation (Security evaluation) | `docker build --network=host -f Dockerfile.qemu -t picasso-qemu .` |

The Bluespec image takes **1–2 hours** to build (two full Bluespec elaborations,
~15 GB intermediate artifacts). The QEMU image is faster but still clones and
patches several large repos. 

Once the image is built, proceed to [Bluespec_simulation.md](./Bluespec_simulation.md)
or [QEMU.md](./QEMU.md) for evaluation instructions.


## Environment Setup

Set these variables once in your shell (host or Docker container) before
running any commands in this README:

```sh
export ARTIFACT_DIR=~/cheri/Colored_Usenix   # path to this repo
export CHERI_ROOT=~/cheri                      # cheribuild source/output root
export CHERIBUILD=~/cheri/cheribuild           # cheribuild checkout
export SSH_PORT=10222   # guest SSH port: 10222 for qemu_ssh_boot.py (Docker path),
                        # or adjust if using cheribuild's run-riscv64-purecap directly
```

All benchmarks are cross-compiled for CheriBSD on the **host** (or inside the
Docker container) using the cheribuild system. See [QEMU.md](./QEMU.md) or
[FPGA.md](./FPGA.md) for instructions on getting the environment built and
running before proceeding to the evaluation sections below.

---

## 7.1 Security Evaluation

The security evaluation can be run on either QEMU or FPGA.

**Prerequisites — choose one:**

- **QEMU via Docker (recommended):**

  ```sh
  # Terminal 1 — start the container and boot CheriBSD
  docker run -i -t -p 10222:10222 --name picasso-qemu-run picasso-qemu
  cd ~/cheri/cheribuild
  ./cheribuild.py run-riscv64-purecap --skip-update \
      --run-riscv64-purecap/ssh-forwarding-port 10222
  ```

  QEMU takes over Terminal 1. Open a second terminal for host-side commands:

  ```sh
  # Terminal 2 — host side
  docker exec -it picasso-qemu-run bash
  export SSH_PORT=10222
  ```

  Wait for the CheriBSD login prompt in Terminal 1 before proceeding.

  > **Tip:** To confirm which port QEMU is using, run in Terminal 2:
  > `ps aux | grep qemu | grep -o 'hostfwd=[^ ]*'`
  > You will see `hostfwd=tcp::10222-:22`.

- **QEMU (native):** Follow [QEMU.md](./QEMU.md) Manual Setup, then run
  `./cheribuild.py run-riscv64-purecap -d`. SSH is reachable at
  `root@127.0.0.1 -p $SSH_PORT` once the login prompt appears.

- **FPGA:** Follow [FPGA.md](./FPGA.md) to flash the VCU118 and boot CheriBSD.
  Use the pre-built bitstreams and kernels under [`prebuilt/`](./prebuilt/) to
  skip the build. Set `SSH_PORT` to the FPGA's SSH port.

### Juliet Test Suite (CWE-415/416)

> **Docker path:** Juliet is pre-built inside the `picasso-qemu` image — skip
> this step and go straight to [Running on QEMU](#running-on-qemu) below.

For native installs, run the following on the **host** (not inside QEMU/FPGA).
This cross-compiles all CWE-415/416 binaries for riscv64-purecap using the
CHERI SDK:

```sh
utils_script/juliet_install.sh
```

This clones `juliet-test-suite` into `$CHERI_ROOT` (default `~/cheri`) and
produces `$CHERI_ROOT/juliet-test-suite/bin/CWE415`,
`$CHERI_ROOT/juliet-test-suite/bin/CWE416`, and
`$CHERI_ROOT/juliet-test-suite/juliet-run.sh`.

#### Running on QEMU

Transfer the binaries and create the stdin fixture in one step from the **host**
(or Docker Terminal 2):

```sh
# Run on the host / Docker container
utils_script/transfer_juliet.sh root@127.0.0.1 -p $SSH_PORT
```

Then SSH into the guest and run the tests (a 1s per-testcase timeout prevents
test cases that wait on stdin from hanging indefinitely):

```sh
# Inside the guest: ssh -p $SSH_PORT root@127.0.0.1
cd /root/juliet-bin
sh juliet-run.sh 415 1s
sh juliet-run.sh 416 1s
```

Results are appended to `CWE415/good.run`, `CWE415/bad.run`,
`CWE416/good.run`, and `CWE416/bad.run` as `<testcase-path> <exit-code>`
pairs.

#### Running on FPGA

```sh
utils_script/transfer_juliet.sh root@<fpga-ip>
```

Then SSH in and run as above from `/root/juliet-bin`:

```sh
cd /root/juliet-bin
sh juliet-run.sh 415 1s
sh juliet-run.sh 416 1s
```

**Expected results** (per the `<TESTCASE_PATH> <exit-code>` lines in
`*.run`):
- **Double Free (CWE-415), `bad.run`:** Programs are expected to exit with
  code 255 (PICASSO's Colored Capabilities revocation detecting the
  double-free).
- **Use-After-Free (CWE-416), `bad.run`:** Programs are expected to terminate
  with signal 34 (SIGPROT, an in-address-space security exception), which
  `sh`/`timeout` reports as exit code 128+34=162.
- **`good.run` (both CWEs):** Programs are expected to exit with code 0
  (occasional exit code 124 from the 1s `timeout` is harmless for test cases
  that wait on additional input).

### Real-World CVE Validation

We validate PICASSO against 11 real-world UAF/Double-Free CVEs from published
benchmarks. See [`validation/README.md`](./validation/README.md) for full
details.

> **Docker path:** All 11 CVE PoCs are pre-built inside the `picasso-qemu`
> image — skip `build_all.sh` and go straight to `transfer.sh`.

For native installs, build the PoCs first on the **host** (not inside QEMU/FPGA):

```sh
cd $ARTIFACT_DIR/validation
./build_all.sh
```

Then transfer to the running guest (Docker or native):

```sh
cd $ARTIFACT_DIR/validation
./transfer.sh root@127.0.0.1 -p $SSH_PORT
```

Then run the tests from the **host**:

```sh
cd $ARTIFACT_DIR/validation
./run_all_remote.sh root@127.0.0.1 -p $SSH_PORT
```

**Expected results:** All 11 CVEs should be detected — each PoC triggers
either signal 34 (SIGPROT, UAF detected) or exit code 255 (double-free
detected). `run_all_remote.sh` prints a per-CVE pass/fail summary.

The validated CVEs include BZip2 (CVE-2016-3189), libiberty (CVE-2016-4487),
nasm (CVE-2017-10686, CVE-2019-8343), libzip (CVE-2019-17582),
NGINX njs (CVE-2020-24346), LibreDWG (CVE-2022-35164), Lua (CVE-2019-6706),
mjs (issues 73, 78), and yasm (issue 91).

---

## 7.2 Performance Evaluations

### MiBench (Bluespec Simulation)

MiBench results are reproduced using the Bluespec simulator — no FPGA
hardware needed, only Docker.

**Prerequisite:** `picasso` Docker image built (see
[Getting Started](#getting-started)).

```sh
docker run -i -t picasso
```

Inside the container:

```sh
cd /home/ubuntu/bench
./run_mibench.sh
```

This runs all 15 MiBench benchmarks against both the baseline and PICASSO
simulators and prints a per-benchmark cycle/instruction overhead table.
See [Bluespec_simulation.md](./Bluespec_simulation.md) for full details and
expected results.

---

### CoreMark (Bluespec Simulation)

CoreMark measures single-threaded CPU performance using list processing, matrix manipulation, and state-machine workloads. Running it through the Bluespec simulators quantifies the overhead of CHERI purecap and PICASSO's colored capabilities over a baseline (non-purecap) build.

**Prerequisite:** `picasso` Docker image built (see [Getting Started](#getting-started)).

```sh
docker run -i -t picasso
```

Inside the container:

```sh
cd /home/ubuntu/bench/coremark
./run_coremark_for_sim.sh
```

This runs the pre-built baseline and purecap CoreMark ELFs through both simulators (3 runs each, averaged) and prints a comparison table.

<details>
<summary>Expected output</summary>

```
=== CoreMark Performance Summary (Bluespec simulation) ===

[*] Running baseline/nocap ... done (avg over 3 runs)
[*] Running baseline/purecap ... done (avg over 3 runs)
[*] Running picasso/purecap ... done (avg over 3 runs)

Simulator                    Config           Total ticks      Delta        Overhead
----------------------------------------------------------------------------------------
CHERI-Toooba (baseline)      nocap            <baseline_ticks> -            -
                             purecap          <purecap_ticks>  <delta>      ~2.6%
CHERI-Toooba (PICASSO)       purecap          <picasso_ticks>  <delta>      ~5%

Note: Simulation ticks differ from FPGA ticks (25 MHz clock). The overhead
percentage is what corresponds to Table 1 in the paper.
```

</details>

The overhead percentages in simulation may differ slightly from the FPGA results in the paper — the relative ordering (baseline < purecap < PICASSO) is consistent. Table 1 in the extended paper reports the hardware measurements.

**Building ELFs from source (optional):** Pre-built ELFs are included at `benchmarks/coremark/`. If you want to rebuild them using the CHERI SDK (requires `Dockerfile.qemu` environment with newlib baremetal):

```sh
# Inside the picasso-qemu container — SDK already built there
cd /home/ubuntu/cheri/Colored_Usenix/utils_script/coremark
./build_coremark_for_sim.sh
```

---

### SPEC CPU2006

> **Note:** Due to licensing restrictions, we do not provide the SPEC CPU2006 source code. Evaluators must have their own valid SPEC CPU2006 license to reproduce these results.

To build SPEC CPU2006 for CheriBSD:

```sh
cd $CHERIBUILD
./cheribuild.py spec2006-riscv64-purecap --spec2006/iso-path /path/to/cpu2006-1.2.iso
```

Replace `/path/to/cpu2006-1.2.iso` with the path to your SPEC CPU2006 ISO image.

The built SPEC folder is placed at:

```
$CHERI_ROOT/build/spec2006-riscv64-purecap-build
```

#### Running SPEC CPU2006 on FPGA

**Prerequisite:** FPGA running CheriBSD with SSH reachable (see [FPGA.md](./FPGA.md)).

After building, prepare the benchmark folder on the **host**:

```sh
# Optional: remove unnecessary files to reduce transfer size
$ARTIFACT_DIR/utils_script/spec/spec_folder_reduce_folder.sh

# Instrument all benchmark run scripts with timing/stat counters
python3 $ARTIFACT_DIR/utils_script/spec/automate.py
```

Copy the SPEC folder to the FPGA (see [FPGA.md](./FPGA.md#how-to-transfer-file-to-fpga)
for scp instructions), then run **inside the FPGA guest**:

```sh
# Inside the FPGA guest, from the directory where SPEC was copied
cd /bench/SPEC/CINT2006
sh $ARTIFACT_DIR/utils_script/spec/run_all_spec_fpga.sh /bench/SPEC/CINT2006
```

Or run a single benchmark individually **inside the FPGA guest**:

```sh
cd /bench/SPEC/CINT2006/464.h264ref
sh ./464.h264ref.test.fpga.sh
```

The benchmarks run are: 401.bzip2, 445.gobmk, 456.hmmer, 458.sjeng,
462.libquantum, 464.h264ref, 471.omnetpp, and 483.xalancbmk.

The results for each benchmark will be output to:

```
<benchmark>/<benchmark>_OUTPUT/
```

#### Analyzing SPEC CPU2006 Results

After collecting results for all configurations (baseline, colored_paper, cornucupia),
place the `_OUTPUT` directories under `utils_script/spec/`:

```
utils_script/spec/baseline/<benchmark>_OUTPUT/
utils_script/spec/colored_paper/<benchmark>_OUTPUT/
utils_script/spec/cornucupia/<benchmark>_OUTPUT/
```

Then run the analysis script to generate overhead tables and figures:

```sh
python3 $ARTIFACT_DIR/utils_script/spec/analyze_spec_overhead.py
```

This produces:
- Per-benchmark cycle, memory, tagcache, and DRAM traffic overhead tables
- Geometric mean summaries across all benchmarks
- Overhead figures saved as PDF and PNG alongside the script

---

### Pgbench

**Prerequisite:** FPGA running CheriBSD with SSH reachable (see [FPGA.md](./FPGA.md)).

On the **host**, clone, patch, and cross-compile PostgreSQL:

```sh
cd $CHERI_ROOT
git clone https://github.com/CTSRD-CHERI/postgres.git
cd postgres
git apply $ARTIFACT_DIR/patches/postgress.diff
cd $CHERIBUILD
./cheribuild.py postgres-riscv64-purecap -d
```

Copy PostgreSQL to the FPGA (see [FPGA.md](./FPGA.md#how-to-transfer-file-to-fpga)
for scp instructions).

**Inside the FPGA guest**, start the database and run the server-side benchmark:

```sh
sh ./postgres-bench-stats.sh  # creates the database and runs pgbench — takes a while
```

**On the host**, run the client-side benchmark driver:

```sh
sh $ARTIFACT_DIR/utils_script/postgress/pgbench-client.sh
```

---

### SQLite

**Prerequisite:** FPGA running CheriBSD with SSH reachable (see [FPGA.md](./FPGA.md)).

On the **host**, cross-compile SQLite:

```sh
cd $CHERIBUILD
./cheribuild.py sqlite-riscv64-purecap -d
```

Copy the `speedtest1` binary to the FPGA (see
[FPGA.md](./FPGA.md#how-to-transfer-file-to-fpga) for scp instructions).

**Inside the FPGA guest**, run the benchmark:

```sh
sh ./speedtest1
```

The benchmark prints per-operation timing lines. Collect results for baseline,
colored, and Cornucopia configurations and compare using:

```sh
python3 $ARTIFACT_DIR/utils_script/sqlite/analyze_sqlite.py
```
---

### gRPC

**Prerequisite:** QEMU or FPGA running CheriBSD with SSH reachable.

On the **host**, cross-compile gRPC and all dependencies:

```sh
cd $CHERIBUILD
./cheribuild.py grpc-native -d
./cheribuild.py grpc-riscv64-purecap -d
```

If that does not work, build each dependency individually:

```sh
cd $CHERIBUILD
./cheribuild.py abseil-riscv64-purecap
./cheribuild.py c-ares-riscv64-purecap
./cheribuild.py googlebenchmark-riscv64-purecap
./cheribuild.py googletest-riscv64-purecap
./cheribuild.py protobuf-riscv64-purecap
./cheribuild.py re2-riscv64-purecap
./cheribuild.py grpc-riscv64-purecap
```

The gRPC binaries are installed by cheribuild into the QEMU disk image at
`/usr/local/riscv64-purecap/bin`. For FPGA, copy them to the board first (see
[FPGA.md](./FPGA.md#how-to-transfer-file-to-fpga) for scp instructions).

#### Running on QEMU

Launch QEMU with extra port forwarding for the gRPC worker ports:

```sh
cd $CHERIBUILD
./cheribuild.py run-riscv64-purecap --run-riscv64-purecap/extra-tcp-forwarding "10000=10000 10001=10001"
```

Then run the benchmark driver **on the host**:

```sh
$ARTIFACT_DIR/utils_script/grpc/grpc-client-bytes-qemu.sh
```

#### Running on FPGA

Run the benchmark driver **on the host** (connects to the FPGA):

```sh
$ARTIFACT_DIR/utils_script/grpc/grpc-client-bytes.sh
```



