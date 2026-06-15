#!/bin/bash

set -e

# Get the directory where this script is located (artifact root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHES_DIR="$SCRIPT_DIR/patches"

CHERI_ROOT=${CHERI_ROOT:-$HOME/cheri}
mkdir -p $CHERI_ROOT
cd $CHERI_ROOT

# Clone cheribuild
git clone https://github.com/CTSRD-CHERI/cheribuild
cd cheribuild
git apply $PATCHES_DIR/cheribuild_colored.diff
cd $CHERI_ROOT

# Clone and patch QEMU
git clone https://github.com/CTSRD-CHERI/qemu.git
cd qemu
git checkout 967e7a86d8d7d1b0a730640354269afebaa0c3ed
git apply $PATCHES_DIR/qemu_colored.diff
cd $CHERI_ROOT

# Clone LLVM (no patch needed)
git clone https://github.com/CTSRD-CHERI/llvm-project.git
cd $CHERI_ROOT

# Clone and patch CheriBSD
git clone https://github.com/CTSRD-CHERI/cheribsd.git
cd cheribsd
git checkout 485c1c8195563d2be65ed2eb1bf7d8bc06eb1a64
git apply $PATCHES_DIR/cheribsd_colored.diff
cd $CHERI_ROOT

# Build and run
cd cheribuild
./cheribuild.py run-riscv64-purecap -d
