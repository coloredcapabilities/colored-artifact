# QEMU Evaluation

QEMU emulation allows you to verify the security evaluation without requiring FPGA hardware.

## Quick Start

Run the automated setup script:

```sh
./utils_script/colored_qemu_install.sh
```

This script will:
1. Clone and patch cheribuild, QEMU, LLVM, and CheriBSD with Colored Capabilities support
2. Build all components
3. Launch QEMU running CheriBSD with the RISC-V pure capability ABI

## Manual Setup


All source code and tools should be organized under `$HOME/cheri/`. The main components are:
- QEMU
- CheriBSD
- LLVM (under `llvm-project` folder)
- cheribuild

To manually set up and launch the environment, run from within the `cheribuild` directory:

```sh
./cheribuild.py run-riscv64-purecap -d
```

This command will automatically download, build, and install all required components and then start QEMU running CheriBSD.

## Using QEMU

Log in as `root` (no password required).

### Mounting Files from Host

```sh
mount_smbfs -I 10.0.2.4 -N //10.0.2.4/source_root /mnt
```

The mounted folder can be slow, so we recommend copying files into QEMU:

```sh
cp /mnt/cheribsd/tests_programs/test_bitmap ./
```

### Cross-Compiling for CheriBSD

We provide helper scripts under `/cheribsd/tests_programs/`:

```sh
ccc riscv64-purecap test_bitmap.c -o test_bitmap
```

## Running Security Tests

Once QEMU is running, you can run the security evaluation tests. See the [Security Evaluation](./README.md#security-evaluation) section in the main README for details on running the Juliet test suite.
