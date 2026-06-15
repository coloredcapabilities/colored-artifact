# QEMU Evaluation

QEMU emulation allows you to verify the security evaluation without requiring FPGA hardware.
It can be set up natively on the host (Quick Start / Manual Setup below) or
inside Docker (see [Running Inside Docker](#running-inside-docker)) if you'd
rather not install the cheribuild toolchain dependencies directly.

## Quick Start

Run the automated setup script:

```sh
./utils_script/colored_qemu_install.sh
```

This script will:
1. Clone and patch cheribuild, QEMU, LLVM, and CheriBSD with Colored Capabilities support
2. Build all components
3. Launch QEMU running CheriBSD with the RISC-V pure capability ABI

## Running Inside Docker

**Prerequisite:** Docker installed and the `picasso-qemu` image built — see
[README.md Getting Started](./README.md#getting-started) if you haven't done
this yet (`docker build --network=host -f Dockerfile.qemu -t picasso-qemu .`).

The image uses `clang-18` as the host C/C++ compiler instead of gcc — gcc on
Focal miscompiles CHERI-QEMU's capability emulation, causing a spurious
`In-address space security exception` (SIGPROT) on `/sbin/init` at boot.
It also pre-bakes an SSH keypair into the disk image overlay (see
[Reproducible SSH access](#reproducible-ssh-access)), so no manual key setup
is needed.

Start the container with the SSH port published:

```sh
docker run -i -t -p 10222:10222 picasso-qemu
```

Inside the container, build and boot CheriBSD as in [Manual Setup](#manual-setup):

```sh
cd ~/cheri/cheribuild
./cheribuild.py run-riscv64-purecap -d
```

The first run builds QEMU, LLVM, and the CheriBSD rootfs/kernel under
`~/cheri/output/` (`~/cheri/output/sdk` for the SDK, including
`qemu-system-riscv64cheri`); subsequent runs can pass `--skip-update` to avoid
re-fetching sources.

### Reproducible SSH access

To script interactions with the guest (e.g. the Juliet test suite or the
CVE validation suite, see below), QEMU needs to be launched with a
`virtio-net-device` and an SSH port forward (rather than cheribuild's default
SMB-share networking), and the guest needs your public key in
`/root/.ssh/authorized_keys` so login is non-interactive. To make this
reproducible across rebuilds, bake the key into the disk image via
cheribuild's `extra-files` overlay **before** building the disk image:

```sh
# Generate a dedicated key if you don't already have one
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

mkdir -p ~/cheri/extra-files/root/.ssh
cp ~/.ssh/id_ed25519.pub ~/cheri/extra-files/root/.ssh/authorized_keys
chmod 700 ~/cheri/extra-files/root ~/cheri/extra-files/root/.ssh
chmod 600 ~/cheri/extra-files/root/.ssh/authorized_keys

cd ~/cheri/cheribuild
./cheribuild.py disk-image-riscv64-purecap -d --skip-update
```

`disk-image-riscv64-purecap` is a fast (~30s) repackaging step that doesn't
rebuild the rootfs, so it's safe to re-run after changing `extra-files/`.
Everything under `~/cheri/extra-files/` is copied verbatim into the image
(cheribuild also defaults `sshd_enable="YES"` and
`PermitRootLogin without-password`, so no further `sshd_config` changes are
needed).

### Booting and running commands non-interactively

`utils_script/qemu_ssh_boot.py` automates "boot QEMU, wait for the login
prompt, log in as root, start `sshd`, wait for SSH" using the SDK's
`qemu-system-riscv64cheri` with the networking setup above:

```sh
# Boot and leave QEMU running, printing QEMU_READY once SSH is up
CHERI_ROOT=~/cheri python3 utils_script/qemu_ssh_boot.py

# Boot, run a command over SSH, print its output, then shut down
CHERI_ROOT=~/cheri python3 utils_script/qemu_ssh_boot.py -- sh -c 'uname -a'
```

By default it forwards the guest's SSH to host port 10222 and uses
`~/.ssh/id_ed25519` (or `~/cheri/extra-files/root/.ssh/id_ed25519` if
present) as the login key — see `--help` for the full set of options. With
the container's port 10222 published via `-p 10222:10222`, you can also
`ssh -p 10222 root@localhost` from the host directly.

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
