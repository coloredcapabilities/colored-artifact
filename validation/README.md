# CVE Validation Suite

This directory contains reproducible test cases for real-world Use-After-Free (UAF) and Double-Free (DF) vulnerabilities. Each test case cross-compiles a vulnerable program for CheriBSD purecap (RISC-V 64-bit) and runs a proof-of-concept input that triggers the bug.

## CVEs Included

| CVE / Issue | Program |
|-------------|---------|
| CVE-2016-3189 | bzip2 (bzip2recover) |
| CVE-2016-4487 | libiberty (cxxfilt) |
| CVE-2017-10686 | nasm |
| CVE-2019-8343 | nasm |
| CVE-2019-17582 | libzip (ziptool) |
| CVE-2020-24346 | NGINX njs |
| CVE-2022-35164 | LibreDWG (dwgrewrite) |
| CVE-2019-6706 | Lua |
| mjs issue-73 | mjs |
| mjs issue-78 | mjs |
| yasm issue-91 | yasm |

## Prerequisites

- CHERI SDK built via cheribuild at `~/cheri/output/sdk`
- CheriBSD sysroot at `~/cheri/output/sdk/sysroot-riscv64-purecap`
- The `ccc` cross-compilation wrapper at the path referenced in each `build.sh`
- CheriBSD QEMU instance running with SSH access (default: `root@127.0.0.1 -p 10003`)

## Building

Build all test cases from source:

```sh
cd validation/
./build_all.sh
```

Build a specific subset:

```sh
./build_all.sh nasm lua
```

Each `build.sh` downloads the vulnerable source, cross-compiles for purecap, and places the binary under the CVE directory.

## Transferring to CheriBSD

Transfer all built binaries and PoC files to the QEMU instance:

```sh
./transfer.sh root@127.0.0.1 -p 10003
```

This packages binaries and PoC inputs into a tarball, transfers via scp, and extracts to `/root/validation/` on CheriBSD.

## Running on CheriBSD

After transfer, run all tests from the host:

```sh
./run_all_remote.sh root@127.0.0.1 -p 10003
```

Or SSH in and run manually:

```sh
ssh root@127.0.0.1 -p 10003
cd /root/validation

# Run individual test
cd nasm-cve2017-10686 && sh run.sh

# Run all tests
for d in /root/validation/*/; do
    echo "--- $(basename $d) ---"
    cd $d && sh run.sh
    echo
done
```

## Expected Results

PICASSO's colored capabilities detect UAF violations at runtime:

- **UAF (Use-After-Free):** The program receives signal 34 (SIGPROT) or signal 10 (SIGBUS), resulting in exit code 162 or 138. This indicates a CHERI capability violation when the program dereferences a pointer to freed/reallocated memory.

- **Double-Free:** The allocator detects the invalid free and exits with code 255 (`exit(-1)`).

- **VULNERABLE:** Exit code 0 means the bug was not detected (the program completed without crashing).

Example output:
```
=== nasm-cve2017-10686 ===
Running: ./nasm -f bin ./POC1 -o /dev/null

RESULT: DETECTED (signal 34)
  -> SIGPROT: CHERI capability fault
```

## Directory Structure

```
validation/
├── build_all.sh          # Build all test cases
├── transfer.sh           # Transfer to CheriBSD QEMU
├── run_all_remote.sh     # Run all tests from host via SSH
├── ccc                   # Cross-compilation wrapper for CHERI purecap
├── README.md             # This file
└── <cve-name>/
    ├── build.sh          # Download source + cross-compile
    ├── run_poc.sh        # Run on CheriBSD
    ├── poc / poc.js / ... # Proof-of-concept input file(s)
    └── *.patch           # CHERI compatibility patches (if needed)
```
