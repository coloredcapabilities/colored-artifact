# PICASSO Artifact 

While the CHERI instruction-set architecture extensions
for capabilities enable strong spatial memory safety, CHERI
lacks built-in temporal safety, particularly for heap allocations. Prior attempts to augment CHERI with temporal safety
fall short in terms of scalability, memory overhead, and incomplete security guarantees due to periodical sweeps of the
system’s memory to individually revoke stale capabilities.
We address these limitations by introducing colored capabilities that add a controlled form of indirection to CHERI’s
capability model. This enables provenance tracking of capabilities to their respective allocations via a hardware-managed
provenance-validity table, allowing bulk retraction of dangling pointers without needing to quarantine freed memory.
Colored capabilities significantly reduce the frequency of
capability revocation sweeps while improving security.
We realize colored capabilities in PICASSO, an extension of
the CHERI-RISC-V architecture on a speculative out-of-order
FPGA softcore (CHERI-Toooba). We also integrate colored-capability support into the CheriBSD OS and CHERI-enabled
Clang/LLVM toolchain. Our evaluation shows effective mitigation of use-after-free and double-free bugs across all heap-
based temporal memory-safety vulnerabilities in NIST Juliet test cases, real-world CVEs, only a small performance overhead on SPEC CPU benchmarks (≈ 5% g.m.), less latency,
and more consistent performance in long-running SQLite, PostgreSQL, and gRPC workloads compared to prior work.


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
  - [Juliet Test Suite (CWE-415/416)](#juliet-test-suite-cwe-415416)`[Docker]`: heap UAF/double-free detection
  - [Real-World CVE Validation](#real-world-cve-validation)`[Docker]`: 11 CVEs across 9 libraries

- [7.2 Performance Evaluations](#72-performance-evaluations) `[FPGA or Bluespec Simulator]`
  - [CoreMark](#coremark-bluespec-simulation) `[Docker]`: single-threaded overhead estimate
  - [MiBench](#mibench-bluespec-simulation) `[Docker]`: 15-benchmark suite (Table 1 / Table 3)
  - [SPEC CPU2006](#spec-cpu2006) `[VCU118 or QEMU]`: 8-benchmark integer suite (≈5% g.m. overhead)
  - [Pgbench](#pgbench) `[VCU118]`: PostgreSQL throughput
  - [SQLite](#sqlite) `[VCU118 or QEMU]`: per-operation timing
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

Build PICASSO docker images 

```sh
docker build --network=host -f Dockerfile -t picasso .
```


## Environment Setup


All benchmarks are cross-compiled for CheriBSD on the **host** (or inside the
Docker container) using the cheribuild system. See [QEMU.md](./QEMU.md) or
[FPGA.md](./FPGA.md) for instructions on getting the environment built and
running before proceeding to the evaluation sections below.

---

## 7.1 Security Evaluation

The security evaluation can be run on either QEMU or FPGA.

**Prerequisites**

- **QEMU via Docker (recommended):**

  ```sh
  # Terminal 1 — start the container and boot CheriBSD
  docker run -i -t --name picasso-run picasso
  cd ~/cheri/cheribuild
  ./cheribuild.py run-riscv64-purecap --skip-update \
      --run-riscv64-purecap/ssh-forwarding-port 10222
  ```

  QEMU takes over Terminal 1. Open a second terminal for host-side commands:

  ```sh
  # Terminal 2 — host side
  docker exec -it picasso-run bash
  export SSH_PORT=10222
  ```

  Wait for the CheriBSD login prompt in Terminal 1 before proceeding.
  Log in as **`root`** with no password.

 
  
  Both terminals attach to the **same** container (`picasso-run`) —
  Terminal 1 via `docker run`, Terminal 2 via a separate `docker exec`. 

- **QEMU (native):** Follow [QEMU.md](./QEMU.md) Manual Setup, then run
  `./cheribuild.py run-riscv64-purecap --skip-update`. SSH is reachable at
  `root@127.0.0.1 -p $SSH_PORT` once the login prompt appears.

- **FPGA:** Follow [FPGA.md](./FPGA.md) to flash the VCU118 and boot CheriBSD.
  Use the pre-built bitstreams and kernels under [`prebuilt/`](./prebuilt/) to
  skip the build. Set `SSH_PORT` to the FPGA's SSH port.

### Juliet Test Suite (CWE-415/416)

> **Docker path:** Juliet is pre-built inside the `picasso` image — skip
> this step and go straight to [Running on QEMU](#running-on-qemu) below.

For native installs, run the following on the **host** (not inside QEMU/FPGA).
This cross-compiles all CWE-415/416 binaries for riscv64-purecap using the
CHERI SDK:

```sh
${ARTIFACT_DIR}/utils_script/juliet_install.sh
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
cd ${ARTIFACT_DIR}/utils_script/transfer_juliet.sh root@127.0.0.1 -p $SSH_PORT
```

Then SSH into the guest and run the tests (a 2s per-testcase timeout prevents
test cases that wait on stdin from hanging indefinitely):

```sh
# Inside the qemu: ssh -p $SSH_PORT root@127.0.0.1
cd /root/juliet-bin
sh juliet-run.sh 415 2s < /tmp/in.txt
sh juliet-run.sh 416 2s < /tmp/in.txt
```

Results are appended to `CWE415/good.run`, `CWE415/bad.run`,
`CWE416/good.run`, and `CWE416/bad.run` as `<testcase-path> <exit-code>`
pairs.

```sh
# Run on the host / Docker container
${ARTIFACT_DIR}/utils_script/collect_juliet_results.sh root@127.0.0.1 -p $SSH_PORT
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

<details>
<summary>Expected output</summary>

```
=== PICASSO Juliet Detection Summary ===

Test set (bad.run)              Detected   Total      Rate
------------------------------------------------------------------
CWE415 double-free (exit 255)   818        818        100.0%
CWE416 use-after-free (exit 162) 175       175        100.0%
------------------------------------------------------------------
PICASSO TOTAL                   993        993        100.0%

=== False-positive check (good.run) ===
Test set (good.run)             Clean      Total      Rate
------------------------------------------------------------------
CWE415 good.run                 818        818        100.0%
CWE416 good.run                 393        393        100.0%

[OK] PICASSO detected 100% of CWE-415/416 bad-case vulnerabilities.
```

</details>

### Real-World CVE Validation

We validate PICASSO against 11 real-world UAF/Double-Free CVEs from published
benchmarks. See [`validation/README.md`](./validation/README.md) for full
details.

> **Docker path:** All 11 CVE PoCs are pre-built inside the `picasso`
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
See [Bluespec_simulation.md](./Bluespec_simulation.md) for full details.

<details>
<summary>Expected output</summary>

```
Benchmark                     Base Cycles     Base Instrs      PIC Cycles      PIC Instrs  Cyc OH(%) Inst OH(%)
------------------------- --------------- --------------- --------------- --------------- ---------- ----------
randmath.bin                        38221            5733           38601            5733        .99          0
qsort.bin                          514081          732242          513281          732242       -.15          0
aes.bin                             74548           81026           75133           81026        .78          0
dijkstra.bin                      1427512         2569261         1432030         2569261        .31          0
crc.bin                             14435           12305           14509           12305        .51          0
rc4.bin                             67938          122379           68072          122379        .19          0
bitcount.bin                      2632864         4250893         2632886         4250893          0          0
adpcm_encode.bin                  3048620         3880822         3083658         3880822       1.14          0
patricia.bin                      1610777         2467112         1632902         2467112       1.37          0
rsa.bin                             49450           60209           52004           60209       5.16          0
sha.bin                           1464582         2675784         1474223         2675784        .65          0
adpcm_decode.bin                  3325012         2909607         3380972         2909607       1.68          0
blowfish.bin                      1393763         2412853         1465512         2412853       5.14          0
limits.bin                           4434            1628            4436            1628        .04          0
picojpeg.bin                      2038299         2638124         2074049         2638124       1.75          0
------------------------- --------------- --------------- --------------- --------------- ---------- ----------
TOTAL                            17704536        24819978        17942268        24819978       1.34          0
```

</details>

---

### CoreMark (Bluespec Simulation)

CoreMark measures single-threaded CPU performance using list processing, matrix manipulation, and state-machine workloads. Running it through the Bluespec simulators quantifies the overhead of CHERI purecap and PICASSO's colored capabilities over a baseline (non-purecap) build.

**Prerequisite:** `picasso` Docker image built (see [Getting Started](#getting-started)) — it includes the CHERI SDK needed to build CoreMark ELFs, in addition to the Bluespec simulators:

```sh
docker run -i -t picasso
```

Inside the container, the CoreMark ELFs are already built during the image build. To re-run:

```sh
cd /home/ubuntu/bench/coremark
./run_coremark_for_sim.sh
```

This delegates to [blinded-cheri-sw](https://github.com/blindedcapabilities/blinded-cheri-sw)'s own `run_coremark_for_sim.sh`, which runs the baseline and purecap CoreMark ELFs once each through both simulators and prints a comparison table.

<details>
<summary>Expected output</summary>

```
=== PICASSO overhead vs CHERI-Toooba (baseline simulator) ===
Comparison                                   Delta ticks     Overhead
PICASSO purecap vs CHERI-Toooba purecap      3143            3.12%
PICASSO purecap vs CHERI-Toooba nocap        6009            6.14%

Total runtime: 7 min 38 sec
```

Exact tick counts and runtime will vary by machine; the overhead percentages are the representative figures. The last section (PICASSO vs CHERI-Toooba) isolates PICASSO's colored-capability cost specifically, separate from the generic CHERI purecap tax shown in the table above it — this is the figure that corresponds to Table 1 in the paper.

</details>

The overhead percentages in simulation may differ slightly from the FPGA results in the paper — the relative ordering (baseline < purecap < PICASSO) is consistent. Table 1 in the extended paper reports the hardware measurements.

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

#### Running SPEC CPU2006 on QEMU

**Prerequisite:** QEMU guest running CheriBSD with SSH reachable — either the
PICASSO guest (`SSH_PORT=10222`, see [Getting Started](#getting-started)) or
the baseline/Cornucopia guest (`utils_script/run_baseline_qemu.sh`,
`SSH_PORT=10223`).

After building, prepare the benchmark folder on the **host** — same steps as
the FPGA flow, unchanged:

```sh
# Optional: remove unnecessary files to reduce transfer size
$ARTIFACT_DIR/utils_script/spec/spec_folder_reduce_folder.sh

# Instrument all benchmark run scripts with timing/stat counters
python3 $ARTIFACT_DIR/utils_script/spec/automate.py
```

Transfer the SPEC folder to the guest:

```sh
$ARTIFACT_DIR/utils_script/spec/transfer_spec_qemu.sh root@127.0.0.1 -p $SSH_PORT
```

Then run **inside the QEMU guest** — `run_all_spec_fpga.sh` is plain shell
with nothing FPGA-specific in it (it just looks for
`<bench>/<bench>.test.fpga.sh` and runs them), so it's reused as-is:

```sh
# Inside the guest: ssh -p $SSH_PORT root@127.0.0.1
cd /root/SPEC/CINT2006
sh /root/SPEC/run_all_spec_fpga.sh /root/SPEC/CINT2006
```

Or run a single benchmark individually **inside the guest**:

```sh
cd /root/SPEC/CINT2006/464.h264ref
sh ./464.h264ref.test.fpga.sh
```

Results land in the same `<benchmark>/<benchmark>_OUTPUT/` layout; scp them
back to the host the same way Juliet/CVE results are collected (see
`utils_script/collect_juliet_results.sh` for the pattern).

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

#### Running SQLite on FPGA

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

#### Running SQLite on QEMU (revocation-count comparison)

This path measures PICASSO's revocation behavior directly against Cornucopia
(standard CHERI purecap + MRS software quarantine/revocation) by running
`speedtest1` against two QEMU guests side by side. `speedtest1` is already
pre-built inside the `picasso` image — no separate cross-compile step needed.

**Prerequisite:** boot both QEMU guests (each in its own terminal):

```sh
# Terminal 1 — PICASSO guest (colored capabilities)
cd ~/cheri/cheribuild
./cheribuild.py run-riscv64-purecap --skip-update \
    --run-riscv64-purecap/ssh-forwarding-port 10222
```

```sh
# Terminal 2 — baseline/Cornucopia guest (separate kernel, separate port)
~/cheri/utils_script/run_baseline_qemu.sh
```

Then, from a **third terminal** (`docker exec -it picasso-run bash`):

```sh
cd ~/cheri/utils_script/sqlite

# Against PICASSO (port 10222)
./run_speedtest1.sh root@127.0.0.1 -p 10222

# Against baseline/Cornucopia (port 10223)
./run_speedtest1.sh root@127.0.0.1 -p 10223
```

Each run transfers `speedtest1`, runs it with `CC_DEBUG=1 /usr/bin/time -l`,
and prints the parsed revoke counter, alloc counter, total time, and max RSS.
Full logs are saved under `speedtest1_logs/speedtest1_<timestamp>.log` if you
want to inspect the raw output (e.g. the `mrs[<pid>]: revoke counter: ...`
line directly):

```sh
cat ./speedtest1_logs/speedtest1_<timestamp>.log
```

**Expected results:** PICASSO's revoke counter should be **0**, versus
Cornucopia's revocation (**272** in our reference run). PICASSO
should also show a substantially lower max RSS (ours: **13,268** vs
Cornucopia's **30,708**), since it doesn't need to quarantine freed memory
pending a sweep.

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



