# Colored Capabilities Artifact

Our artifact can be evaluated at three levels:

| Evaluation Level | Hardware Required | What It Reproduces |
|------------------|-------------------|-------------------|
| [Bluespec Simulator](./Bluespec_simulation.md) | None (Docker) | MiBench results (Table 1) |
| [QEMU Emulation](./QEMU.md) | None | Security evaluation |
| [FPGA](./FPGA.md) | Xilinx VCU118 | Performance results |

We provide pre-built bitstreams and binaries under the [`prebuilt`](./prebuilt/) directory.
If you prefer not to build everything manually, you can skip ahead to the relevant evaluation section.

---

## Building for RISC-V 64-bit Purecap

All benchmarks are cross-compiled for CheriBSD using the cheribuild system.

Set the artifact directory (this repository) so paths resolve correctly:

```sh
export ARTIFACT_DIR=~/cheri/Colored_Usenix
```


---

## Security Evaluation

The security evaluation can be run on either QEMU or FPGA.

### Juliet Test Suite (CWE-415/416)

Install and run the Juliet test suite:

```sh
$ARTIFACT_DIR/utils_script/juliet_install.sh
```

Copy test binaries to the FPGA (see [FPGA.md](./FPGA.md) for scp instructions).

Inside the FPGA, run the tests:

```sh
cd /tmp/juliet-test-suite/bin
sh juliet-run.sh 415
sh juliet-run.sh 416
```

**Expected results:**
- **Double Free (CWE-415):** The program gracefully exits with exit code -1 (255).
- **Use-After-Free (CWE-416):** You should see an In-address Space exception signal 34, resulting in exit code 162.

### Real-World CVE Validation

We validate PICASSO against 11 real-world UAF/Double-Free CVEs from published benchmarks.
See [`validation/README.md`](./validation/README.md) for full details.

```sh
cd $ARTIFACT_DIR/validation
./build_all.sh
./transfer.sh root@127.0.0.1 -p 10003
```

Then run the tests from the host:
```sh
cd $ARTIFACT_DIR/validation
./run_all_remote.sh root@127.0.0.1 -p 10003
```

The validated CVEs include BZip2 (CVE-2016-3189), libiberty (CVE-2016-4487),
nasm (CVE-2017-10686, CVE-2019-8343), libzip (CVE-2019-17582),
NGINX njs (CVE-2020-24346), LibreDWG (CVE-2022-35164), Lua (CVE-2019-6706),
mjs (issues 73, 78), and yasm (issue 91).

---

## SPEC CPU2006

> **Note:** Due to licensing restrictions, we do not provide the SPEC CPU2006 source code. Evaluators must have their own valid SPEC CPU2006 license to reproduce these results.

To build SPEC CPU2006 for CheriBSD:

```sh
cd $CHERIBUILD
./cheribuild.py spec2006-riscv64-purecap --spec2006/iso-path /path/to/cpu2006-1.2.iso
```

Replace `/path/to/cpu2006-1.2.iso` with the path to your SPEC CPU2006 ISO image.

The output for the spec folder.. 
$HOME_DIR/cheri/build/spec2006-riscv64-purecap-build

### Running SPEC CPU2006 on FPGA

After building, prepare the benchmark folder:

```sh
# Optional: Remove unnecessary files to reduce folder size
$ARTIFACT_DIR/utils_script/spec/spec_folder_reduce_folder.sh

# Instrument all scripts with time and minimal_stats_counts
$ARTIFACT_DIR/utils_script/spec/automate.py
```

After copying the SPEC folder to the FPGA, run all benchmarks at once:

```sh
sh run_all_spec_fpga.sh /bench/SPEC/CINT2006
```

Or run a single benchmark individually:

```sh
sh ./464.h264ref/464.h264ref.test.fpga.sh
```

The benchmarks run are: 401.bzip2, 445.gobmk, 456.hmmer, 458.sjeng,
462.libquantum, 464.h264ref, 471.omnetpp, and 483.xalancbmk.

The results for each benchmark will be output to:

```
<benchmark>/<benchmark>_OUTPUT/
```

### Analyzing SPEC CPU2006 Results

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

## Pgbench

Build PostgreSQL:

Clone the repo manually under `$HOME/cheri/`:

```sh
git clone https://github.com/CTSRD-CHERI/postgres.git
cd postgres
git apply patches/postgress.diff
```

Then build with cheribuild:

```sh
cd $CHERIBUILD
./cheribuild.py postgres-riscv64-purecap -d
```

Copy PostgreSQL to the FPGA (see [FPGA.md](./FPGA.md) for scp instructions).

On the FPGA, run the benchmark:

```sh
sh ./postgres-bench-stats.sh  # This will take a while to create the full database
```

On the host, run the benchmark:

```sh
sh $ARTIFACT_DIR/utils_script/postgress/pgbench-client.sh
```

---

## SQLite

```sh
cd $CHERIBUILD
./cheribuild.py sqlite-riscv64-purecap -d
```

On the FPGA, run the benchmark:

```sh
sh ./speedtest1
```
---

## gRPC

Cross-compile all dependencies and gRPC:

```sh
cd $CHERIBUILD
./cheribuild.py grpc-native -d
./cheribuild.py grpc-riscv64-purecap -d
```

If that does not work, manually build each dependency:

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

Launch QEMU with port forwarding for the gRPC worker ports:

```sh
cd $CHERIBUILD
./cheribuild.py run-riscv64-purecap --run-riscv64-purecap/extra-tcp-forwarding "10000=10000 10001=10001"
```

By default, the gRPC binaries are installed inside QEMU at:

```
/usr/local/riscv64-purecap/bin
```

To run the gRPC benchmark on QEMU, run the following script on your host machine:

```sh
$ARTIFACT_DIR/utils_script/grpc/grpc-client-bytes-qemu.sh
```

To run the gRPC benchmark on FPGA, run the following script on your host machine:

```sh
$ARTIFACT_DIR/utils_script/grpc/grpc-client-bytes.sh
```



