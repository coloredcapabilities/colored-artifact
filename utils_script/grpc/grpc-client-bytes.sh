#!/bin/sh -xe

# gRPC QPS Client + Driver - Run this on the HOST
# Controls both local client and remote FPGA server
# This version runs different byte size scenarios (0, 16, 64, 256, 1024 bytes)

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

FPGA_IP="${FPGA_IP:-169.254.125.247}"
FPGA_USER="${FPGA_USER:-root}"

# Native gRPC binaries (built with cheribuild.py grpc-native)
GRPC_BUILD="${GRPC_BUILD:-$HOME/cheri/build/grpc-native-build}"

# Point driver to: FPGA server + local client
export QPS_WORKERS="${FPGA_IP}:10000,localhost:20000"

BYTE_SIZES="0 16 64 256 1024"

echo "=============================================="
echo "gRPC QPS Client Configuration:"
echo "  FPGA Server: ${FPGA_USER}@${FPGA_IP}:10000"
echo "  Local Client: localhost:20000"
echo "  gRPC build:   ${GRPC_BUILD}"
echo "  Byte sizes:   ${BYTE_SIZES}"
echo "=============================================="

__start_fpga_server()
{
    echo "Starting server on FPGA (foreground via ssh -t)..."
    ssh -tt ${FPGA_USER}@${FPGA_IP} 'export PATH=/bench/riscv64-purecap/bin:$PATH; export LD_LIBRARY_PATH=/bench/riscv64-purecap/lib; export CC_DEBUG=""; grpc_qps_worker --driver_port 10000 --server_port=10001' > ${1}/server.log 2>&1 &
    SSH_PID=$!
    sleep 3
}

__stop_fpga_server()
{
    echo "Stopping server on FPGA (sending SIGINT to ssh)..."
    kill -INT ${SSH_PID} 2>/dev/null || true
    sleep 5
    # Force kill if still running
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
    mkdir -p ${BYTES}bytes

    echo "=== Run ${BYTES} bytes scenario ==="

    # Start fresh server on FPGA (output captured locally)
    __start_fpga_server ${BYTES}bytes

    # Start local client
    __client_exec
    sleep 2

    __driver_exec \
        --scenarios_file ${SCRIPT_DIR}/benchmark_${BYTES}bytes.json \
        --scenario_result_file ${BYTES}bytes/qps-result.json \
        --json_file_out ${BYTES}bytes/qps-result.json.log

    __driver_exec --quit
    wait ${CLIENT_PID}

    # Stop server on FPGA
    __stop_fpga_server

    # Display server log
    echo "=== Server output (allocation/revocation stats) ==="
    cat ${BYTES}bytes/server.log
    echo "==================================================="

    echo "=== ${BYTES} bytes scenario complete ==="
done

echo ""
echo "=============================================="
echo "Benchmark complete!"
echo "=============================================="
