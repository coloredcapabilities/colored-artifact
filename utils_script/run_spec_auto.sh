#!/usr/bin/env bash
# =============================================================================
# run_spec_auto.sh — End-to-end SPEC CPU2006 automation for FPGA
#
# What it does (in order):
#   1. Flash FPGA bitstream + boot CheriBSD kernel via vcu118-run.py
#      (runs as the 'fpga' account via sudo su fpga)
#   2. Configure host-side network interface
#   3. Poll SSH until FPGA is reachable
#   4. Reduce SPEC folder (strip ref data) on host
#   5. Instrument .test.sh scripts with time/minimal_count_stats
#   6. Mount tmpfs on FPGA and transfer SPEC folder via SCP
#   7. Run all benchmarks on FPGA via SSH
#   8. Collect _OUTPUT result dirs back to host
#   9. Run analyze_spec_overhead.py
#
# Prerequisites:
#   - SPEC CPU2006 already built on host:
#       cd $CHERIBUILD && ./cheribuild.py spec2006-riscv64-purecap \
#           --spec2006/iso-path /path/to/cpu2006-1.2.iso
#   - sudo access to run commands as the 'fpga' user
#   - riscv64-unknown-elf-gdb and openocd available (see GDB/OPENOCD paths below)
#
# Usage:
#   ./run_spec_auto.sh --config baseline|colored_paper [OPTIONS]
#
# Options:
#   --config CONFIG       baseline or colored_paper (required)
#   --fpga-ip IP          IP to assign to FPGA xae0 interface (default: 192.168.0.1)
#   --host-ip IP          IP to assign to host interface (default: 192.168.0.100)
#   --host-dev DEV        Host network interface connected to FPGA (default: eth0)
#   --bench-dir DIR       tmpfs mount point on FPGA (default: /bench)
#   --time-cmd CMD        Time binary on FPGA (default: time)
#   --ssh-timeout SEC     Seconds to wait for SSH after boot (default: 300)
#   --skip-flash          Skip flash+boot step (FPGA already booted)
#   --skip-hostnet        Skip host-side network interface setup
#   --skip-reduce         Skip spec_folder_reduce_folder.sh step
#   --skip-instrument     Skip automate.py instrumentation step
#   --skip-transfer       Skip SCP transfer (SPEC already on FPGA)
#   --skip-run            Skip running benchmarks on FPGA
#   --skip-collect        Skip collecting results back to host
#   --skip-analyze        Skip analyze_spec_overhead.py
#   -h, --help            Show this help
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# >>>  CONFIGURATION — edit these to match your setup  <<<
# ---------------------------------------------------------------------------

# Repository / build paths
ARTIFACT_DIR="${HOME}/cheri/Colored_Usenix"
CHERIBUILD="${HOME}/cheribuild"
SPEC_BUILD_DIR="${HOME}/cheri/build/spec2006-riscv64-purecap-build"
RESULTS_BASE="${ARTIFACT_DIR}/utils_script/spec"

# vcu118-run.py paths
VCU118_SCRIPT="${CHERIBUILD}/vcu118-run.py"
BIOS="${HOME}/cheri/output/sdk/bbl-gfe/riscv64-purecap/bbl"
GDB="${HOME}/opt/riscv/bin/riscv64-unknown-elf-gdb"
OPENOCD="${HOME}/opt/bin/openocd"

# FPGA account (used as: sudo su fpga -c "...")
FPGA_ACCOUNT="fpga"

# Prebuilt bitstreams and kernels
# Adjust PREBUILT_DIR if your bitstreams live elsewhere
PREBUILT_DIR="${ARTIFACT_DIR}/prebuilt"

declare -A BITFILE=(
    [baseline]="${PREBUILT_DIR}/bitstreams/cheri_baseline/design_1.bit"
    [colored_paper]="${PREBUILT_DIR}/bitstreams/colored_paper/design_1.bit"
)
declare -A LTXFILE=(
    [baseline]="${PREBUILT_DIR}/bitstreams/cheri_baseline/design_1.ltx"
    [colored_paper]="${PREBUILT_DIR}/bitstreams/colored_paper/design_1.ltx"
)
declare -A KERNEL=(
    [baseline]="${PREBUILT_DIR}/kernel/baseline_prebuild_kernel/kernel-riscv64-purecap.CHERI-PURECAP-GFE-NODEBUG"
    [colored_paper]="${PREBUILT_DIR}/kernel/colored_preprebuilt/kernel-riscv64-purecap.CHERI-PURECAP-GFE-NODEBUG"
)

# Network defaults (overrideable via flags)
FPGA_IP="192.168.0.1"
HOST_IP="192.168.0.100"
HOST_DEV="eth0"
FPGA_NETMASK="255.255.0.0"

# Other defaults
BENCH_DIR="/bench"
TIME_CMD="time"
SSH_TIMEOUT=300   # seconds to wait for FPGA SSH after boot

# SSH / SCP options
FPGA_USER="root"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
SCP_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Benchmarks (must match directory names under CINT2006)
BENCHMARKS="401.bzip2 445.gobmk 456.hmmer 458.sjeng 462.libquantum 464.h264ref 471.omnetpp 483.xalancbmk"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[$(date '+%H:%M:%S')] $*${NC}"; }
ok()   { echo -e "${GREEN}[OK] $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }
die()  { echo -e "${RED}[ERROR] $*${NC}" >&2; exit 1; }

fpga_ssh()      { ssh ${SSH_OPTS} "${FPGA_USER}@${FPGA_IP}" "$@"; }
fpga_scp_to()   { scp ${SCP_OPTS} -r "$1" "${FPGA_USER}@${FPGA_IP}:$2"; }
fpga_scp_from() { scp ${SCP_OPTS} -r "${FPGA_USER}@${FPGA_IP}:$1" "$2"; }

usage() {
    sed -n '/^# Usage:/,/^# ===*/p' "$0" | grep -v '^# ===' | sed 's/^# \?//'
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CONFIG=""
SKIP_FLASH=0; SKIP_HOSTNET=0; SKIP_REDUCE=0; SKIP_INSTRUMENT=0
SKIP_TRANSFER=0; SKIP_RUN=0; SKIP_COLLECT=0; SKIP_ANALYZE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)           CONFIG="$2";      shift 2 ;;
        --fpga-ip)          FPGA_IP="$2";     shift 2 ;;
        --host-ip)          HOST_IP="$2";     shift 2 ;;
        --host-dev)         HOST_DEV="$2";    shift 2 ;;
        --bench-dir)        BENCH_DIR="$2";   shift 2 ;;
        --time-cmd)         TIME_CMD="$2";    shift 2 ;;
        --ssh-timeout)      SSH_TIMEOUT="$2"; shift 2 ;;
        --skip-flash)       SKIP_FLASH=1;       shift ;;
        --skip-hostnet)     SKIP_HOSTNET=1;     shift ;;
        --skip-reduce)      SKIP_REDUCE=1;      shift ;;
        --skip-instrument)  SKIP_INSTRUMENT=1;  shift ;;
        --skip-transfer)    SKIP_TRANSFER=1;    shift ;;
        --skip-run)         SKIP_RUN=1;         shift ;;
        --skip-collect)     SKIP_COLLECT=1;     shift ;;
        --skip-analyze)     SKIP_ANALYZE=1;     shift ;;
        -h|--help)          usage ;;
        *) die "Unknown argument: $1. Run with --help." ;;
    esac
done

[[ -z "${CONFIG}" ]] && die "--config is required (baseline or colored_paper)"
[[ "${CONFIG}" != "baseline" && "${CONFIG}" != "colored_paper" ]] \
    && die "--config must be 'baseline' or 'colored_paper', got '${CONFIG}'"

# Derived paths
SPEC_EXTERNAL="${SPEC_BUILD_DIR}/External"
SPEC_FPGA_DIR="${SPEC_BUILD_DIR}/External_fpga"
SPEC_CINT="${SPEC_FPGA_DIR}/SPEC/CINT2006"
REMOTE_SPEC="${BENCH_DIR}/SPEC/CINT2006"
RESULTS_DIR="${RESULTS_BASE}/${CONFIG}"

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  SPEC CPU2006 FPGA Automation"
echo "  Config    : ${CONFIG}"
echo "  Bitfile   : ${BITFILE[${CONFIG}]}"
echo "  Kernel    : ${KERNEL[${CONFIG}]}"
echo "  FPGA      : ${FPGA_USER}@${FPGA_IP}  (xae0)"
echo "  Host dev  : ${HOST_DEV} → ${HOST_IP}"
echo "  Bench dir : ${BENCH_DIR} (tmpfs on FPGA)"
echo "  Results   : ${RESULTS_DIR}/"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# STEP 0: Sanity checks
# ---------------------------------------------------------------------------
log "Step 0: Sanity checks"

[[ -d "${ARTIFACT_DIR}" ]]   || die "ARTIFACT_DIR not found: ${ARTIFACT_DIR}"
[[ -f "${VCU118_SCRIPT}" ]]  || die "vcu118-run.py not found: ${VCU118_SCRIPT}"

if [[ ${SKIP_FLASH} -eq 0 ]]; then
    [[ -f "${BITFILE[${CONFIG}]}" ]] || die "Bitfile not found: ${BITFILE[${CONFIG}]}"
    [[ -f "${LTXFILE[${CONFIG}]}" ]] || die "LTX file not found: ${LTXFILE[${CONFIG}]}"
    [[ -f "${KERNEL[${CONFIG}]}" ]]  || die "Kernel not found: ${KERNEL[${CONFIG}]}"
    [[ -f "${BIOS}" ]]               || die "BIOS not found: ${BIOS}"
    [[ -f "${GDB}" ]]                || die "GDB not found: ${GDB}"
fi

if [[ ${SKIP_TRANSFER} -eq 0 ]]; then
    [[ -d "${SPEC_EXTERNAL}" ]] || die "SPEC External dir not found: ${SPEC_EXTERNAL}\n  Build SPEC first:\n    cd ${CHERIBUILD} && ./cheribuild.py spec2006-riscv64-purecap --spec2006/iso-path /path/to/cpu2006-1.2.iso"
fi

ok "Sanity checks passed"

# ---------------------------------------------------------------------------
# STEP 1: Flash FPGA and boot CheriBSD
# ---------------------------------------------------------------------------
if [[ ${SKIP_FLASH} -eq 0 ]]; then
    log "Step 1: Flashing ${CONFIG} bitstream and booting CheriBSD ..."
    log "  Bitfile : ${BITFILE[${CONFIG}]}"
    log "  Kernel  : ${KERNEL[${CONFIG}]}"
    log "  Running as: sudo su ${FPGA_ACCOUNT}"

    # vcu118-run.py 'all' action:
    #   - Flashes the bitfile via Vivado
    #   - Loads bios + kernel via OpenOCD + GDB
    #   - Runs --test-command(s) on the serial console
    #   - Exits automatically because this script is not a TTY (line 548 in vcu118-run.py)
    #
    # We use --test-command to configure FPGA networking and mount tmpfs,
    # so the FPGA is ready for SSH/SCP immediately after this step.
    sudo su "${FPGA_ACCOUNT}" -c "
        cd '${CHERIBUILD}' && \
        python3 '${VCU118_SCRIPT}' all \
            --bitfile  '${BITFILE[${CONFIG}]}' \
            --ltxfile  '${LTXFILE[${CONFIG}]}' \
            --bios     '${BIOS}' \
            --kernel   '${KERNEL[${CONFIG}]}' \
            --gdb      '${GDB}' \
            --openocd  '${OPENOCD}' \
            --benchmark-config \
            --test-command 'ifconfig xae0 inet ${FPGA_IP} netmask ${FPGA_NETMASK}' \
            --test-command 'mkdir -p ${BENCH_DIR}' \
            --test-command 'mount -t tmpfs -o size=1000m tmpfs ${BENCH_DIR}' \
            --test-command 'mkdir -p ${REMOTE_SPEC}'
    "
    ok "Flash + boot complete"
else
    warn "Step 1: Skipping flash (--skip-flash)"
fi

# ---------------------------------------------------------------------------
# STEP 2: Configure host-side network interface
# ---------------------------------------------------------------------------
if [[ ${SKIP_HOSTNET} -eq 0 ]]; then
    log "Step 2: Configuring host interface ${HOST_DEV} → ${HOST_IP} ..."
    sudo ifconfig "${HOST_DEV}" "${HOST_IP}"
    ok "Host interface configured"
else
    warn "Step 2: Skipping host network setup (--skip-hostnet)"
fi

# ---------------------------------------------------------------------------
# STEP 3: Wait for FPGA to be reachable via SSH
# ---------------------------------------------------------------------------
log "Step 3: Waiting for FPGA SSH at ${FPGA_USER}@${FPGA_IP} (timeout ${SSH_TIMEOUT}s) ..."
ELAPSED=0
INTERVAL=10
while true; do
    if fpga_ssh "echo 'SSH OK'" 2>/dev/null | grep -q 'SSH OK'; then
        ok "FPGA reachable via SSH"
        break
    fi
    if [[ ${ELAPSED} -ge ${SSH_TIMEOUT} ]]; then
        die "FPGA SSH not reachable after ${SSH_TIMEOUT}s. Check networking:\n  FPGA: ifconfig xae0 inet ${FPGA_IP} netmask ${FPGA_NETMASK}\n  Host: sudo ifconfig ${HOST_DEV} ${HOST_IP}"
    fi
    log "  Not yet reachable, retrying in ${INTERVAL}s ... (${ELAPSED}/${SSH_TIMEOUT}s)"
    sleep "${INTERVAL}"
    ELAPSED=$(( ELAPSED + INTERVAL ))
done

# ---------------------------------------------------------------------------
# STEP 4: Reduce SPEC folder on host (strip ref data and CMakeFiles)
# ---------------------------------------------------------------------------
if [[ ${SKIP_REDUCE} -eq 0 ]]; then
    log "Step 4: Reducing SPEC folder for FPGA transfer ..."
    "${ARTIFACT_DIR}/utils_script/spec/spec_folder_reduce_folder.sh"
    ok "SPEC folder reduced → ${SPEC_FPGA_DIR}"
else
    warn "Step 4: Skipping spec folder reduction (--skip-reduce)"
    [[ -d "${SPEC_FPGA_DIR}" ]] || die "SPEC_FPGA_DIR not found: ${SPEC_FPGA_DIR}"
fi

# ---------------------------------------------------------------------------
# STEP 5: Instrument .test.sh scripts with time + minimal_count_stats
# ---------------------------------------------------------------------------
if [[ ${SKIP_INSTRUMENT} -eq 0 ]]; then
    log "Step 5: Instrumenting SPEC scripts (automate.py) ..."
    python3 "${ARTIFACT_DIR}/utils_script/spec/automate.py" "${SPEC_CINT}" "${TIME_CMD}"
    ok "Scripts instrumented"
else
    warn "Step 5: Skipping instrumentation (--skip-instrument)"
fi

# ---------------------------------------------------------------------------
# STEP 6: Transfer SPEC folder to FPGA via SCP
# ---------------------------------------------------------------------------
if [[ ${SKIP_TRANSFER} -eq 0 ]]; then
    log "Step 6: Transferring SPEC folder to FPGA ..."

    for bench in ${BENCHMARKS}; do
        src="${SPEC_CINT}/${bench}"
        if [[ -d "${src}" ]]; then
            log "  → ${bench}"
            fpga_scp_to "${src}" "${REMOTE_SPEC}/"
        else
            warn "  Skipping ${bench}: not found at ${src}"
        fi
    done

    # Transfer the runner script
    fpga_scp_to "${ARTIFACT_DIR}/utils_script/spec/run_all_spec_fpga.sh" "${BENCH_DIR}/SPEC/"
    ok "Transfer complete"
else
    warn "Step 6: Skipping SPEC transfer (--skip-transfer)"
fi

# ---------------------------------------------------------------------------
# STEP 7: Run benchmarks on FPGA via SSH
# ---------------------------------------------------------------------------
if [[ ${SKIP_RUN} -eq 0 ]]; then
    log "Step 7: Running SPEC benchmarks on FPGA [${CONFIG}] ..."
    log "  Output streaming below (this will take a long time on FPGA hardware):"
    echo "------------------------------------------------------------"
    fpga_ssh "sh '${BENCH_DIR}/SPEC/run_all_spec_fpga.sh' '${REMOTE_SPEC}'"
    echo "------------------------------------------------------------"
    ok "All benchmarks finished"
else
    warn "Step 7: Skipping benchmark run (--skip-run)"
fi

# ---------------------------------------------------------------------------
# STEP 8: Collect _OUTPUT result dirs back to host
# ---------------------------------------------------------------------------
if [[ ${SKIP_COLLECT} -eq 0 ]]; then
    log "Step 8: Collecting results from FPGA → ${RESULTS_DIR}/ ..."
    mkdir -p "${RESULTS_DIR}"

    for bench in ${BENCHMARKS}; do
        remote_out="${REMOTE_SPEC}/${bench}/${bench}_OUTPUT"
        local_out="${RESULTS_DIR}/${bench}_OUTPUT"

        if fpga_ssh "test -d '${remote_out}'" 2>/dev/null; then
            log "  ← ${bench}_OUTPUT"
            mkdir -p "${local_out}"
            fpga_scp_from "${remote_out}/." "${local_out}/"
            ok "  ${bench}_OUTPUT"
        else
            warn "  No output for ${bench} at ${remote_out}"
        fi
    done

    ok "Results saved to ${RESULTS_DIR}/"
else
    warn "Step 8: Skipping result collection (--skip-collect)"
fi

# ---------------------------------------------------------------------------
# STEP 9: Analyze results
# ---------------------------------------------------------------------------
if [[ ${SKIP_ANALYZE} -eq 0 ]]; then
    log "Step 9: Analyzing SPEC overhead ..."

    HAVE_RESULTS=0
    for cfg in baseline colored_paper cornucupia; do
        if compgen -G "${RESULTS_BASE}/${cfg}/*_OUTPUT" > /dev/null 2>&1; then
            HAVE_RESULTS=1
        fi
    done

    if [[ ${HAVE_RESULTS} -eq 0 ]]; then
        warn "No _OUTPUT directories found yet — skipping analysis."
        warn "Run once you have results for all configs:"
        warn "  cd ${RESULTS_BASE} && python3 analyze_spec_overhead.py"
    else
        cd "${RESULTS_BASE}"
        python3 "${ARTIFACT_DIR}/utils_script/spec/analyze_spec_overhead.py"
        ok "Analysis complete. Figures saved alongside the script."
    fi
else
    warn "Step 9: Skipping analysis (--skip-analyze)"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
ok "DONE  [config=${CONFIG}]"
echo "  Results : ${RESULTS_DIR}/"
echo ""
echo "  To run the other config:"
if [[ "${CONFIG}" == "baseline" ]]; then
    echo "    ./run_spec_auto.sh --config colored_paper --skip-reduce --skip-instrument"
else
    echo "    ./run_spec_auto.sh --config baseline --skip-reduce --skip-instrument"
fi
echo ""
echo "  To analyze all configs together:"
echo "    cd ${RESULTS_BASE} && python3 analyze_spec_overhead.py"
echo "============================================================"
