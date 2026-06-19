#!/bin/sh
# Boot the baseline (Cornucopia) CheriBSD QEMU guest -- built by
# Dockerfile.qemu / Dockerfile.combined into separate cheribsd-baseline-*
# paths, alongside the main PICASSO image (see the "Baseline (Cornucopia)
# CheriBSD kernel" section in those Dockerfiles).
#
# This guest is standard CHERI purecap + Cornucopia software revocation
# (patches/mrs_base_revoke_count.patch applied, not cheribsd_colored.diff),
# so it's the comparison point for utils_script/sqlite/run_speedtest1.sh's
# revoke/alloc counters -- PICASSO doesn't go through MRS's quarantine/revoke
# path at all, so it never prints those counters.
#
# Usage: run_baseline_qemu.sh [extra cheribuild args...]
#
# Environment:
#   CHERIBUILD   path to cheribuild checkout (default: $HOME/cheri/cheribuild)
#   CHERI_ROOT    path to cheribuild source/output root (default: $HOME/cheri)
#   SSH_PORT      guest SSH forwarding port (default: 10223 -- distinct from
#                  the PICASSO guest's default 10222, so both can run at once)

set -e

CHERIBUILD="${CHERIBUILD:-$HOME/cheri/cheribuild}"
CHERI_ROOT="${CHERI_ROOT:-$HOME/cheri}"
SSH_PORT="${SSH_PORT:-10223}"

cd "$CHERIBUILD"
exec ./cheribuild.py run-riscv64-purecap --skip-update \
    --cheribsd-riscv64-purecap/source-directory="$CHERI_ROOT/cheribsd-baseline" \
    --cheribsd-riscv64-purecap/build-directory="$CHERI_ROOT/build/cheribsd-baseline-riscv64-purecap-build" \
    --cheribsd-riscv64-purecap/install-directory="$CHERI_ROOT/output/rootfs-baseline-riscv64-purecap" \
    --cheribsd-mfs-root-kernel-riscv64-purecap/build-directory="$CHERI_ROOT/build/cheribsd-baseline-riscv64-purecap-build" \
    --cheribsd-mfs-root-kernel-riscv64-purecap/install-directory="$CHERI_ROOT/output/rootfs-baseline-riscv64-purecap" \
    --disk-image-riscv64-purecap/path="$CHERI_ROOT/output/cheribsd-baseline-riscv64-purecap.img" \
    --run-riscv64-purecap/ssh-forwarding-port="$SSH_PORT" \
    "$@"
