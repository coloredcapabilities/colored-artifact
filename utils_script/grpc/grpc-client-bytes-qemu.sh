#!/bin/sh -xe

# gRPC QPS Client + Driver - Run this on the HOST (QEMU variant)
# Controls both local client and QEMU-hosted server via SSH port forwarding
# This version runs different byte size scenarios (0, 16, 64, 256, 1024 bytes)
#
#
# QEMU prints the SSH port on startup ("Listening for SSH connections on localhost:XXXXX").
# Set QEMU_SSH_PORT to match that value (default below is for UID 1000).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

QEMU_SSH_PORT="${QEMU_SSH_PORT:-10011}"
QEMU_USER="${QEMU_USER:-root}"
QEMU_IP="localhost"

# Native gRPC binaries (built with cheribuild.py grpc-native)
GRPC_BUILD="${GRPC_BUILD:-$HOME/cheri/build/grpc-native-build}"

# Paths inside QEMU to the gRPC binaries and libraries (override as needed)
QEMU_GRPC_BIN="${QEMU_GRPC_BIN:-/usr/local/riscv64-purecap/bin}"
QEMU_GRPC_LIB="${QEMU_GRPC_LIB:-/usr/local/riscv64-purecap/lib}"

# Server runs inside QEMU; its ports are forwarded to localhost via hostfwd
export QPS_WORKERS="localhost:10000,localhost:20000"

BYTE_SIZES="0 16 64 256 1024"

echo "=============================================="
echo "gRPC QPS Client Configuration (QEMU):"
echo "  QEMU Server:  ${QEMU_USER}@${QEMU_IP} (ssh port ${QEMU_SSH_PORT})"
echo "  gRPC worker:  localhost:10000 -> QEMU:10000"
echo "  Local Client: localhost:20000"
echo "  gRPC build:   ${GRPC_BUILD}"
echo "  QEMU bin:     ${QEMU_GRPC_BIN}"
echo "  QEMU lib:     ${QEMU_GRPC_LIB}"
echo "  Byte sizes:   ${BYTE_SIZES}"
echo "=============================================="

__wait_for_port()
{
    PORT=${1}
    TIMEOUT=${2:-60}
    i=0
    echo "Waiting for port ${PORT} to be ready..."
    while ! nc -z localhost ${PORT} 2>/dev/null; do
        i=$((i + 1))
        if [ ${i} -ge ${TIMEOUT} ]; then
            echo "Timeout waiting for port ${PORT} after ${TIMEOUT}s"
            return 1
        fi
        sleep 1
    done
    echo "Port ${PORT} is ready (after ${i}s)"
}

__ssh_qemu()
{
    ssh -p ${QEMU_SSH_PORT} \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        ${QEMU_USER}@${QEMU_IP} "$@"
}

__start_qemu_server()
{
    echo "Killing any leftover grpc_qps_worker inside QEMU..."
    __ssh_qemu 'pkill -9 grpc_qps_worker 2>/dev/null; true'
    sleep 3

    echo "Starting server inside QEMU (via ssh -p ${QEMU_SSH_PORT})..."
    __ssh_qemu \
        "export PATH=${QEMU_GRPC_BIN}:\$PATH; export LD_LIBRARY_PATH=${QEMU_GRPC_LIB}; export CC_DEBUG=''; grpc_qps_worker --driver_port 10000 --server_port=10001" \
        > ${1}/server.log 2>&1 &
    SSH_PID=$!
    __wait_for_port 10000 60
}

__stop_qemu_server()
{
    echo "Stopping server in QEMU..."
    __ssh_qemu 'pkill -INT grpc_qps_worker 2>/dev/null; true'
    sleep 3
    __ssh_qemu 'pkill -9 grpc_qps_worker 2>/dev/null; true'
    kill -9 ${SSH_PID} 2>/dev/null || true
    sleep 1
}

__client_exec()
{
    ${GRPC_BUILD}/qps_worker --driver_port 20000 --server_port=20001 &
    CLIENT_PID=$!
}

__driver_exec()
{
    ${GRPC_BUILD}/qps_json_driver $@
}

echo "${0}: Running benchmark for byte sizes: ${BYTE_SIZES}..."

for BYTES in ${BYTE_SIZES}; do
    mkdir -p ${SCRIPT_DIR}/${BYTES}bytes

    echo "=== Run ${BYTES} bytes scenario ==="

    __start_qemu_server ${SCRIPT_DIR}/${BYTES}bytes

    __client_exec

    __driver_exec \
        --scenarios_file ${SCRIPT_DIR}/benchmark_${BYTES}bytes.json \
        --scenario_result_file ${SCRIPT_DIR}/${BYTES}bytes/qps-result.json \
        --json_file_out ${SCRIPT_DIR}/${BYTES}bytes/qps-result.json.log

    __driver_exec --quit
    wait ${CLIENT_PID}

    __stop_qemu_server

    echo "=== Server output (allocation/revocation stats) ==="
    cat ${SCRIPT_DIR}/${BYTES}bytes/server.log
    echo "==================================================="

    echo "=== ${BYTES} bytes scenario complete ==="
done

echo ""
echo "=============================================="
echo "Benchmark complete!"
echo "=============================================="
